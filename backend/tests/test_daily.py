from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path
import random

from fastapi.testclient import TestClient
import pytest

from app import main
from app.domain import ContentUnavailable, day_window, make_payload, next_selection
from publish import validate


def test_shuffle_cycle_and_boundary():
    entries = [{'slangId': str(i), 'revision': 'r1'} for i in range(10)]
    state, picks = {}, []
    for _ in range(30):
        selected, revision, state = next_selection(entries, state, random.Random(19))
        picks.append(selected)
        assert revision == 'r1'
    for i in (0, 10, 20):
        assert len(set(picks[i:i+10])) == 10
    assert picks[9] != picks[10] and picks[19] != picks[20]


def test_catalog_changes_empty_and_singleton():
    with pytest.raises(ContentUnavailable):
        next_selection([], {})
    entries = [{'slangId': 'a', 'revision': 'r2'}]
    selected, revision, state = next_selection(entries, {'remainingIds': ['removed', 'a'], 'lastSlangId': 'a'})
    assert (selected, revision, state['remainingIds']) == ('a', 'r2', [])
    assert next_selection(entries, state)[0] == 'a'
    selected, _, state = next_selection(entries + [{'slangId': 'new', 'revision': 'r1'}], {'remainingIds': ['a']})
    assert selected == 'a' and state['remainingIds'] == []


def test_midnight():
    before = datetime(2026, 9, 21, 15, 59, 59, tzinfo=timezone.utc)
    after = datetime(2026, 9, 21, 16, 0, 0, tzinfo=timezone.utc)
    assert day_window(before, 'Asia/Shanghai') == ('2026-09-21', after)
    assert day_window(after, 'Asia/Shanghai')[0] == '2026-09-22'


def test_sixty_day_exclusions_override_rotation_and_exhaustion():
    entries = [{'slangId': str(i), 'revision': 'r1'} for i in range(61)]
    state, history = {}, []
    for _ in range(150):
        selected, _, state = next_selection(entries, state, random.Random(19), excluded_ids=history[-60:])
        assert selected not in history[-60:]
        history.append(selected)
    with pytest.raises(ContentUnavailable):
        next_selection(entries[:2], {}, excluded_ids=['0', '1'])
    assert next_selection(entries[:2], {}, excluded_ids=['0'])[0] == '1'


@pytest.fixture
def content():
    root = Path(__file__).parents[1] / 'content'
    item = validate(json.loads((root / 'seed.json').read_text())[0], root)
    for scenario in item['scenarios']:
        scenario['illustration'].pop('localFile')
    return item


@pytest.fixture
def client(monkeypatch, content):
    monkeypatch.setenv('PUBLISHED_BUCKET', 'test-bucket')
    monkeypatch.setenv('DAILY_TIMEZONE', 'Asia/Shanghai')
    class Repository:
        def get_daily(self, date, end, zone):
            return make_payload(date, end, zone, content['id'], content['revision'], content)
        def get_batch(self, date, end, zone, excluded, known):
            if content['id'] in excluded:
                return []
            return [make_payload(date, end, zone, content['id'], content['revision'], content)]
    main.app.dependency_overrides[main.get_repository] = Repository
    yield TestClient(main.app)
    main.app.dependency_overrides.clear()


def test_http_cache_and_midnight(client, monkeypatch):
    monkeypatch.setattr(main, 'utc_now', lambda: datetime(2026, 9, 21, 15, 59, 59, tzinfo=timezone.utc))
    response = client.get('/v1/slang/daily')
    assert response.status_code == 200
    payload = response.json()
    assert payload['scenario']['illustration']['url'].startswith('https://storage.googleapis.com/test-bucket/')
    assert 'objectPath' not in payload['scenario']['illustration']
    assert 'localFile' not in payload['scenario']['illustration']
    assert 'max-age=1,' in response.headers['cache-control']
    etag = response.headers['etag']
    assert client.get('/v1/slang/daily', headers={'If-None-Match': f'W/{etag}'}).status_code == 304
    monkeypatch.setattr(main, 'utc_now', lambda: datetime(2026, 9, 21, 16, tzinfo=timezone.utc))
    response = client.get('/v1/slang/daily', headers={'If-None-Match': etag})
    assert response.status_code == 200 and response.json()['date'] == '2026-09-22'
    assert client.get('/v1/slang/daily?date=2020-01-01').status_code == 400


def test_unavailable(client):
    class Empty:
        def get_daily(self, *args):
            raise ContentUnavailable('private internals')
    main.app.dependency_overrides[main.get_repository] = Empty
    response = client.get('/v1/slang/daily')
    assert response.status_code == 503
    assert response.headers['retry-after'] == '30'
    assert 'private internals' not in response.text
    assert response.json()['error']['requestId'] == response.headers['x-request-id']


def test_batch_prefetch_and_exclusion(client, content):
    response = client.get('/v1/slang/batch')
    assert response.status_code == 200
    assert len(response.json()) == 1
    assert response.json()[0]['scenario']['illustration']['url'].startswith('https://')
    assert response.headers['cache-control'] == 'no-store'
    assert client.get('/v1/slang/batch', params={'exclude': content['id']}).json() == []
    assert client.get('/v1/slang/batch?exclude=a,b').status_code == 400
    assert client.get('/v1/slang/batch?unexpected=1').status_code == 400


def test_import_rejects_missing_image_and_target():
    root = Path(__file__).parents[1] / 'content'
    item = json.loads((root / 'seed.json').read_text())[0]
    missing = deepcopy(item)
    missing['scenarios'][0]['illustration']['localFile'] = 'assets/missing.png'
    with pytest.raises(ValueError):
        validate(missing, root)
    for line in item['scenarios'][0]['lines']:
        line['isTarget'] = False
    with pytest.raises(ValueError):
        validate(item, root)
