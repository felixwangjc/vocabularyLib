from copy import deepcopy
import hashlib
import io
import time
from unittest.mock import Mock

from fastapi.testclient import TestClient
from PIL import Image
import pytest
from pydantic import ValidationError

from app.admin import app
from app.admin_auth import issue_session, valid_session
from app.admin_models import ContentInput
from app.admin_store import get_store, inspect_image

@pytest.fixture
def client(monkeypatch):
    salt = '01' * 16
    password = 'testing-only-strong-password'
    digest = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1).hex()
    monkeypatch.setenv('ADMIN_SESSION_KEY', 'test-key-' * 8)
    monkeypatch.setenv('ADMIN_PASSWORD_HASH', salt + ':' + digest)
    monkeypatch.setenv('ADMIN_ORIGIN', 'https://admin.test')
    store = Mock()
    store.list_content.return_value = []
    app.dependency_overrides[get_store] = lambda: store
    yield TestClient(app, base_url='https://admin.test'), store
    app.dependency_overrides.clear()


def login(client):
    result = client.post('/api/login', json={'password': 'testing-only-strong-password'}, headers={'Origin': 'https://admin.test'})
    assert result.status_code == 200
    cookie = result.headers['set-cookie']
    assert 'HttpOnly' in cookie and 'Secure' in cookie and 'SameSite=strict' in cookie
    return {'Origin':'https://admin.test', 'X-CSRF-Token':result.json()['csrfToken']}


def test_auth_and_csrf(client):
    web, store = client
    assert web.get('/api/contents').status_code == 401
    assert web.post('/api/login', json={'password': 'x'}, headers={'Origin':'https://evil.test'}).status_code == 403
    assert not store.login_attempt.called
    assert web.post('/api/login', json={'password':'incorrect'}, headers={'Origin':'https://admin.test'}).status_code == 401
    headers = login(web)
    assert web.get('/api/contents').status_code == 200
    assert web.post('/api/logout', headers={'Origin':'https://admin.test'}).status_code == 403
    assert web.post('/api/logout', headers={**headers, 'Origin':'https://evil.test'}).status_code == 403
    assert web.post('/api/logout', headers=headers).status_code == 200
    assert web.get('/api/contents').status_code == 401


def test_session_tampering_and_expiry(client, monkeypatch):
    token = issue_session()
    assert valid_session(token)
    assert not valid_session(token[:-8] + 'abcdefgh')
    assert not valid_session('invalid-cookie')
    now = time.time()
    monkeypatch.setattr(time, 'time', lambda: now + 9 * 3600)
    assert not valid_session(token)


def test_upload_and_request_limits(client):
    web, store = client
    headers = login(web)
    assert web.post('/api/assets', content=b'a' * (6 * 1024 * 1024 + 1), headers=headers).status_code == 413
    assert not store.upload.called
    result = web.get('/')
    assert result.status_code == 200 and "frame-ancestors 'none'" in result.headers['content-security-policy']
    assert web.get('/api/contents/invalid_id').status_code == 422


def test_public_app_has_no_admin_routes():
    from app.main import app as public
    web = TestClient(public)
    assert web.get('/api/contents').status_code == 404
    assert web.post('/api/login', json={'password':'anything'}).status_code == 404


def test_published_requires_image_and_target():
    data = {'phrase':'Hello','meaningZh':'你好','category':'test','usageNoteZh':'test','status':'draft',
            'scenarios':[{'id':'scene','titleZh':'场景','lines':[{'id':'line','speaker':'A','en':'Hello','zh':'你好','isTarget':False}]}]}
    assert ContentInput(**data).status == 'draft'
    data['status'] = 'published'
    with pytest.raises(ValidationError): ContentInput(**data)
    data['scenarios'][0].update(assetId='asset', altZh='插图说明')
    with pytest.raises(ValidationError): ContentInput(**data)
    data['scenarios'][0]['lines'][0]['isTarget'] = True
    assert ContentInput(**data).status == 'published'
    data['scenarios'][0]['lines'] *= 2
    with pytest.raises(ValidationError): ContentInput(**data)


def test_image_validation():
    data = io.BytesIO()
    Image.new('RGB', (16, 20)).save(data, format='PNG')
    meta = inspect_image(data.getvalue())
    assert meta['width'] == 16 and meta['height'] == 20 and meta['contentType'] == 'image/png'
    from fastapi import HTTPException
    with pytest.raises(HTTPException): inspect_image(b'<svg onload=alert(1)>')
    with pytest.raises(HTTPException): inspect_image(b'\xff\xd8corrupt-image')
