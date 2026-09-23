import base64
import hashlib
import hmac
import os
import secrets
import time
from fastapi import HTTPException, Request

COOKIE = 'slang_admin_session'
SESSION_SECONDS = 8 * 3600

def key():
    value = os.environ.get('ADMIN_SESSION_KEY', '')
    if len(value) < 32:
        raise RuntimeError('Admin session secret not configured')
    return value.encode()

def password_matches(password):
    try:
        salt, expected = os.environ['ADMIN_PASSWORD_HASH'].split(':')
        actual = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1).hex()
        return hmac.compare_digest(actual, expected)
    except (KeyError, ValueError):
        return False

def issue_session():
    payload = f'{int(time.time())}:{secrets.token_hex(24)}'
    signature = hmac.new(key(), payload.encode(), hashlib.sha256).hexdigest()
    return base64.urlsafe_b64encode(f'{payload}:{signature}'.encode()).decode()

def valid_session(token):
    try:
        raw = base64.urlsafe_b64decode(token).decode()
        issued, nonce, signature = raw.split(':')
        payload = f'{issued}:{nonce}'
        age = time.time() - int(issued)
        return (0 <= age <= SESSION_SECONDS and len(nonce) == 48 and
                hmac.compare_digest(signature, hmac.new(key(), payload.encode(), hashlib.sha256).hexdigest()))
    except (ValueError, UnicodeDecodeError, TypeError):
        return False

def csrf_token(token):
    return hmac.new(key(), ('csrf:' + token).encode(), hashlib.sha256).hexdigest()

def require_origin(request):
    if request.headers.get('origin') != os.environ['ADMIN_ORIGIN']:
        raise HTTPException(403, '请求来源不匹配，请从正式后台地址访问')

def require_admin(request: Request):
    token = request.cookies.get(COOKIE, '')
    if not valid_session(token):
        raise HTTPException(401, '请先登录管理后台')
    if request.method not in ('GET', 'HEAD', 'OPTIONS'):
        require_origin(request)
        if not hmac.compare_digest(request.headers.get('x-csrf-token', ''), csrf_token(token)):
            raise HTTPException(403, '安全校验失败，请刷新页面')
    return token
