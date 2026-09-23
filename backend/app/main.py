from copy import deepcopy
from datetime import datetime, timezone
from functools import lru_cache
import hashlib
import json
import logging
import os
from urllib.parse import quote
from uuid import uuid4

from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse, Response
from google.api_core.exceptions import GoogleAPICallError, RetryError
from google.cloud import firestore

from app.domain import ContentUnavailable, day_window
from app.repository import DailyRepository

app = FastAPI(title='Daily Slang API', version='1.0.0', docs_url=None, redoc_url=None)
log = logging.getLogger('daily-slang')


@lru_cache
def get_repository():
    return DailyRepository(firestore.Client(
        project=os.environ['GOOGLE_CLOUD_PROJECT'],
        database=os.getenv('FIRESTORE_DATABASE', 'daily-slang'),
    ))


def utc_now():
    return datetime.now(timezone.utc)


@app.middleware('http')
async def errors(request: Request, call_next):
    request_id = str(uuid4())
    try:
        response = await call_next(request)
    except Exception as exc:
        unavailable = isinstance(exc, (ContentUnavailable, GoogleAPICallError, RetryError))
        log.exception('Request failed requestId=%s path=%s', request_id, request.url.path)
        response = JSONResponse(status_code=503 if unavailable else 500, content={
            'error': {
                'code': 'CONTENT_UNAVAILABLE' if unavailable else 'INTERNAL_ERROR',
                'message': '今日内容暂不可用' if unavailable else '服务暂时不可用',
                'requestId': request_id,
            }
        }, headers={'Cache-Control': 'no-store', **({'Retry-After': '30'} if unavailable else {})})
    response.headers['X-Request-ID'] = request_id
    response.headers['X-Content-Type-Options'] = 'nosniff'
    return response


@app.get('/health')
def health():
    return {'status': 'ok'}


@app.get('/v1/slang/daily')
def daily(request: Request, repository=Depends(get_repository)):
    if request.query_params:
        return JSONResponse(status_code=400, content={
            'error': {'code': 'INVALID_QUERY', 'message': '此接口不接受查询参数'}
        }, headers={'Cache-Control': 'no-store'})
    timezone_name = os.getenv('DAILY_TIMEZONE', 'Asia/Shanghai')
    now = utc_now()
    date, end = day_window(now, timezone_name)
    payload = deepcopy(repository.get_daily(date, end, timezone_name))
    illustration = payload['scenario']['illustration']
    object_path = illustration.pop('objectPath')
    illustration['url'] = (
        f"https://storage.googleapis.com/{os.environ['PUBLISHED_BUCKET']}/{quote(object_path, safe='/')}"
    )
    body = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    etag = '"' + hashlib.sha256(body).hexdigest() + '"'
    # Calculate after the database operation so slow initialization cannot cache past midnight.
    ttl = max(0, min(300, int((end - utc_now()).total_seconds())))
    headers = {'ETag': etag, 'Cache-Control': f'public, max-age={ttl}, must-revalidate'}
    validators = [tag.strip().removeprefix('W/') for tag in request.headers.get('if-none-match', '').split(',')]
    if etag in validators or '*' in validators:
        return Response(status_code=304, headers=headers)
    return Response(body, media_type='application/json', headers=headers)


@app.get('/v1/slang/batch')
def batch(request: Request, repository=Depends(get_repository)):
    # Read-only prefetch: never reserves tomorrow's global daily selection.
    if set(request.query_params) - {'exclude', 'known'} or any(len(value) > 16000 for value in request.query_params.values()):
        return JSONResponse(status_code=400, content={'error': {'code': 'INVALID_QUERY'}}, headers={'Cache-Control': 'no-store'})
    excluded = set(filter(None, request.query_params.get('exclude', '').split(',')))
    known = set(filter(None, request.query_params.get('known', '').split(',')))
    if len(excluded) > 1 or len(known) > 120:
        return JSONResponse(status_code=400, content={'error': {'code': 'INVALID_QUERY'}}, headers={'Cache-Control': 'no-store'})
    zone = os.getenv('DAILY_TIMEZONE', 'Asia/Shanghai')
    date, end = day_window(utc_now(), zone)
    payloads = deepcopy(repository.get_batch(date, end, zone, excluded, known))
    for payload in payloads:
        illustration = payload['scenario']['illustration']
        path = illustration.pop('objectPath')
        illustration['url'] = f"https://storage.googleapis.com/{os.environ['PUBLISHED_BUCKET']}/{quote(path, safe='/')}"
    return JSONResponse(payloads, headers={'Cache-Control': 'no-store'})
