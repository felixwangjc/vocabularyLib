"""Live smoke test, including concurrent first requests. Prints no credentials."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import urllib.error
import urllib.request


def fetch(url, headers=None):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers or {}), timeout=60) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('base_url')
    args = parser.parse_args()
    base = args.base_url.rstrip('/')
    health = fetch(base + '/health')
    assert health[0] == 200, (health[0], health[2][:500])
    with ThreadPoolExecutor(max_workers=12) as pool:
        responses = list(pool.map(lambda _: fetch(base + '/v1/slang/daily'), range(12)))
    assert all(x[0] == 200 for x in responses), [(x[0], x[2][:300]) for x in responses]
    assert len({x[2] for x in responses}) == 1, 'Concurrent responses differ'
    payload = json.loads(responses[0][2])
    headers = {k.lower(): v for k, v in responses[0][1].items()}
    assert fetch(base + '/v1/slang/daily', {'If-None-Match': headers['etag']})[0] == 304
    assert fetch(base + '/v1/slang/daily?date=2020-01-01')[0] == 400
    image_status, image_headers, image = fetch(payload['scenario']['illustration']['url'])
    assert image_status == 200
    assert any(k.lower() == 'content-type' and v.startswith('image/') for k, v in image_headers.items())
    print(json.dumps({
        'result': 'passed', 'concurrentRequests': 12, 'date': payload['date'],
        'slangId': payload['slang']['id'], 'scenarioId': payload['scenario']['id'],
        'conditionalGet': 304, 'imageBytes': len(image), 'imageURL': payload['scenario']['illustration']['url'],
    }, ensure_ascii=False, indent=2))
