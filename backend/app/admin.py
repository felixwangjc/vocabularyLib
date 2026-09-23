import hashlib
import hmac
import os
from pathlib import Path
import uuid

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

from app.admin_auth import COOKIE, SESSION_SECONDS, csrf_token, issue_session, key, password_matches, require_admin, require_origin
from app.admin_models import ContentInput, DeleteInput, LoginInput
from app.admin_store import get_store

app = FastAPI(title='Daily Slang Admin', docs_url=None, redoc_url=None, openapi_url=None)
STATIC = Path(__file__).parent / 'static'

@app.middleware('http')
async def security(request, call_next):
    if request.method in ('POST', 'PUT', 'DELETE'):
        chunks, size = [], 0
        async for chunk in request.stream():
            size += len(chunk)
            if size > 6 * 1024 * 1024:
                return JSONResponse(status_code=413, content={'detail': '请求过大，图片最大 5 MB'})
            chunks.append(chunk)
        request._body = b''.join(chunks)
    try:
        response = await call_next(request)
    except Exception:
        import logging
        logging.exception('Admin request failed')
        response = JSONResponse(status_code=500, content={'detail': '操作失败，请稍后重试；已保存的数据不会被清空'})
    response.headers.update({
        'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY', 'Referrer-Policy': 'same-origin',
        'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
    })
    return response

@app.get('/health')
def health():
    return {'status': 'ok'}

@app.get('/')
@app.get('/admin')
def index():
    return FileResponse(STATIC / 'admin.html')

app.mount('/static', StaticFiles(directory=STATIC), name='static')

@app.post('/api/login')
def login(data: LoginInput, request: Request, store=Depends(get_store)):
    require_origin(request)
    identity = hmac.new(key(), (request.client.host if request.client else 'unknown').encode(), hashlib.sha256).hexdigest()
    store.login_attempt(identity)
    if not password_matches(data.password):
        raise HTTPException(401, '管理密码不正确')
    session = issue_session()
    response = JSONResponse({'csrfToken': csrf_token(session)})
    response.set_cookie(COOKIE, session, max_age=SESSION_SECONDS, secure=True, httponly=True, samesite='strict', path='/')
    return response

@app.get('/api/session')
def session(token=Depends(require_admin)):
    return {'csrfToken': csrf_token(token)}

@app.post('/api/logout', dependencies=[Depends(require_admin)])
def logout():
    response = JSONResponse({'ok': True})
    response.delete_cookie(COOKIE, secure=True, httponly=True, samesite='strict', path='/')
    return response

@app.get('/api/contents', dependencies=[Depends(require_admin)])
def contents(store=Depends(get_store)):
    return {'items': store.list_content()}

@app.get('/api/contents/{content_id}', dependencies=[Depends(require_admin)])
def detail(content_id: str, store=Depends(get_store)):
    check_id(content_id)
    return store.detail(content_id)

@app.post('/api/contents', dependencies=[Depends(require_admin)])
def create(data: ContentInput, store=Depends(get_store)):
    if data.baseRevision is not None:
        raise HTTPException(422, '新内容不能包含已有版本')
    return store.save(uuid.uuid4().hex, data)

@app.put('/api/contents/{content_id}', dependencies=[Depends(require_admin)])
def update(content_id: str, data: ContentInput, store=Depends(get_store)):
    check_id(content_id)
    if data.baseRevision is None:
        raise HTTPException(422, '缺少版本信息，请重新打开内容')
    return store.save(content_id, data)

@app.delete('/api/contents/{content_id}', dependencies=[Depends(require_admin)])
def delete(content_id: str, data: DeleteInput, store=Depends(get_store)):
    check_id(content_id)
    assets = store.delete_content(content_id, data.baseRevision)
    return {'ok': True, 'unlinkedAssets': assets}

@app.get('/api/assets', dependencies=[Depends(require_admin)])
def assets(store=Depends(get_store)):
    return {'items': store.list_assets()}

@app.post('/api/assets', dependencies=[Depends(require_admin)])
async def upload(request: Request, store=Depends(get_store)):
    from starlette.concurrency import run_in_threadpool
    data = await request.body()
    return await run_in_threadpool(store.upload, data)

@app.get('/api/assets/{asset_id}/image', dependencies=[Depends(require_admin)])
def image(asset_id: str, store=Depends(get_store)):
    check_id(asset_id)
    data, mime = store.preview(asset_id)
    return Response(data, media_type=mime)

@app.delete('/api/assets/{asset_id}', dependencies=[Depends(require_admin)])
def delete_asset(asset_id: str, store=Depends(get_store)):
    check_id(asset_id)
    store.delete_asset(asset_id)
    return {'ok': True}

def check_id(value):
    import re
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,79}', value):
        raise HTTPException(422, '无效 ID')
