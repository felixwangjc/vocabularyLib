from copy import deepcopy
from datetime import datetime, timezone, timedelta
from functools import lru_cache
import hashlib
import io
import json
import os
import uuid

from fastapi import HTTPException
from google.api_core.exceptions import AlreadyExists, NotFound, PreconditionFailed
from google.cloud import firestore, storage
from PIL import Image, UnidentifiedImageError

from app.domain import day_window

MAX_IMAGE_BYTES = 5 * 1024 * 1024


def inspect_image(data):
    if not data or len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(413, '图片大小需在 1 字节至 5 MB 之间')
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.format not in ('JPEG', 'PNG', 'WEBP') or max(image.size) > 4096:
                raise HTTPException(422, '仅支持最长边不超过 4096px 的 JPEG、PNG、WebP 图片')
            if getattr(image, 'n_frames', 1) != 1:
                raise HTTPException(422, '请上传静态图片')
            width, height, kind = *image.size, image.format
            image.verify()
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError, SyntaxError, ValueError):
        raise HTTPException(422, '图片损坏或格式不支持')
    return {'width': width, 'height': height, 'contentType': Image.MIME[kind],
            'extension': {'JPEG': 'jpg', 'PNG': 'png', 'WEBP': 'webp'}[kind],
            'sha256': hashlib.sha256(data).hexdigest()}


@lru_cache
def get_store():
    project = os.environ['GOOGLE_CLOUD_PROJECT']
    db = firestore.Client(project=project, database=os.getenv('FIRESTORE_DATABASE', 'daily-slang'))
    client = storage.Client(project=project)
    return AdminStore(db, client.bucket(os.environ['PUBLISHED_BUCKET']), client.bucket(os.environ['DRAFT_BUCKET']))


class AdminStore:
    def __init__(self, db, published, drafts):
        self.db, self.published, self.drafts = db, published, drafts

    def login_attempt(self, identity):
        ref = self.db.document(f'adminLoginAttempts/{identity}')
        now = datetime.now(timezone.utc).timestamp()
        @firestore.transactional
        def attempt(tx):
            item = ref.get(transaction=tx).to_dict() or {}
            count = item.get('count', 0) if now - item.get('window', 0) < 900 else 0
            if count >= 10:
                raise HTTPException(429, '登录尝试过多，请 15 分钟后再试', headers={'Retry-After': '900'})
            tx.set(ref, {'count': count + 1, 'window': item.get('window', now) if count else now})
        attempt(self.db.transaction())

    def list_content(self):
        result = []
        for snap in self.db.collection('slangs').stream():
            item = snap.to_dict()
            if item.get('status') == 'deleted':
                continue
            result.append({'id': snap.id, **{k: item.get(k) for k in
                ('phrase', 'meaningZh', 'category', 'status', 'currentRevision', 'updatedAt')}})
        return sorted(result, key=lambda x: str(x.get('updatedAt') or ''), reverse=True)

    def register_legacy(self, content_id, image):
        asset_id = image.get('assetId') or 'legacy-' + hashlib.sha256(image['objectPath'].encode()).hexdigest()[:32]
        ref = self.db.document(f'adminAssets/{asset_id}')
        if not ref.get().exists:
            try:
                ref.create({**image, 'state': 'published', 'references': [content_id],
                            'createdAt': firestore.SERVER_TIMESTAMP})
            except AlreadyExists:
                pass
        return asset_id

    def detail(self, content_id):
        root = self.db.document(f'slangs/{content_id}').get().to_dict()
        if not root or root.get('status') == 'deleted':
            raise HTTPException(404, '内容不存在或已删除')
        if root.get('editor'):
            editor = deepcopy(root['editor'])
        else:
            version = self.db.document(f"slangs/{content_id}/revisions/{root['currentRevision']}").get().to_dict()
            editor = {k: version[k] for k in ('phrase', 'meaningZh', 'category', 'usageNoteZh')}
            editor['scenarios'] = []
            for scenario in version['scenarios']:
                image = scenario.get('illustration')
                editor['scenarios'].append({
                    'id': scenario['id'], 'titleZh': scenario['titleZh'], 'lines': scenario['lines'],
                    'assetId': self.register_legacy(content_id, image) if image else None,
                    'altZh': image.get('altZh', '') if image else '',
                })
        return {'id': content_id, **editor, 'baseRevision': root['currentRevision'], 'status': root.get('status', 'published')}

    def upload(self, data):
        metadata = inspect_image(data)
        asset_id = uuid.uuid4().hex
        draft_path = f'admin-uploads/{asset_id}.{metadata.pop("extension")}'
        blob = self.drafts.blob(draft_path)
        blob.upload_from_string(data, content_type=metadata['contentType'], if_generation_match=0)
        item = {**metadata, 'draftPath': draft_path, 'objectPath': f'admin-assets/{asset_id}.{draft_path.rsplit(".", 1)[1]}',
                'state': 'staged', 'references': [], 'createdAt': firestore.SERVER_TIMESTAMP}
        self.db.document(f'adminAssets/{asset_id}').create(item)
        return {'id': asset_id, **metadata}

    def asset(self, asset_id):
        item = self.db.document(f'adminAssets/{asset_id}').get().to_dict()
        if not item or item.get('state') in ('deleted', 'deleting'):
            raise HTTPException(404, '图片不存在或已删除')
        return item

    def preview(self, asset_id):
        item = self.asset(asset_id)
        blob = self.drafts.blob(item['draftPath']) if item.get('draftPath') else self.published.blob(item['objectPath'])
        try:
            return blob.download_as_bytes(), item['contentType']
        except NotFound:
            raise HTTPException(404, '图片文件不存在')

    def list_assets(self):
        return [{'id': snap.id, **snap.to_dict()} for snap in self.db.collection('adminAssets').stream()
                if snap.to_dict().get('state') != 'deleted']

    def promote(self, item):
        if item['state'] == 'published':
            return
        source = self.drafts.blob(item['draftPath'])
        try:
            self.drafts.copy_blob(source, self.published, item['objectPath'], if_generation_match=0)
        except PreconditionFailed:
            pass  # Retry of the same immutable asset ID.
        blob = self.published.blob(item['objectPath'])
        blob.cache_control = 'public, max-age=31536000, immutable'
        blob.patch()

    def save(self, content_id, data):
        current = self.db.document(f'slangs/{content_id}').get().to_dict()
        if (current or {}).get('currentRevision') != data.baseRevision or (current or {}).get('status') == 'deleted':
            raise HTTPException(409, '内容已更新或删除，请重新打开后再编辑')
        editor = data.model_dump(exclude={'baseRevision'})
        if len(json.dumps(editor, ensure_ascii=False).encode()) > 220 * 1024:
            raise HTTPException(413, '内容过长，请拆成多条')
        asset_ids = sorted({s.assetId for s in data.scenarios if s.assetId})
        revision = 'r-' + uuid.uuid4().hex
        for asset_id in asset_ids:
            asset_ref = self.db.document(f'adminAssets/{asset_id}')
            @firestore.transactional
            def reserve(tx):
                asset = asset_ref.get(transaction=tx).to_dict()
                if not asset or asset.get('state') in ('deleted', 'deleting'):
                    raise HTTPException(409, '图片已被删除，请重新上传')
                now = datetime.now(timezone.utc)
                leases = {k: v for k, v in asset.get('leases', {}).items() if v > now}
                leases[revision] = now + timedelta(minutes=2)
                tx.update(asset_ref, {'leases': leases})
                return asset
            asset = reserve(self.db.transaction())
            if data.status == 'published':
                self.promote(asset)
        root_ref = self.db.document(f'slangs/{content_id}')
        catalog_ref = self.db.document('catalogs/daily')
        date, _ = day_window(datetime.now(timezone.utc), os.getenv('DAILY_TIMEZONE', 'Asia/Shanghai'))
        today_ref = self.db.document(f'dailyPicks/{date}')

        @firestore.transactional
        def commit(tx):
            root = root_ref.get(transaction=tx).to_dict()
            if root and root.get('status') == 'deleted':
                raise HTTPException(409, '内容已删除，请新建内容')
            if (root or {}).get('currentRevision') != data.baseRevision:
                raise HTTPException(409, '内容已在其他窗口更新，请重新打开后再编辑')
            catalog = catalog_ref.get(transaction=tx).to_dict() or {'entries': [], 'revision': 0}
            today = today_ref.get(transaction=tx).to_dict()
            old_ids = set((root or {}).get('assetIds', []))
            if root and not root.get('editor'):
                old_version = self.db.document(f"slangs/{content_id}/revisions/{root['currentRevision']}").get(transaction=tx).to_dict()
                old_ids.update('legacy-' + hashlib.sha256(s['illustration']['objectPath'].encode()).hexdigest()[:32]
                               for s in old_version['scenarios'] if s.get('illustration'))
            assets = {i: self.db.document(f'adminAssets/{i}').get(transaction=tx).to_dict() for i in old_ids | set(asset_ids)}
            for i in asset_ids:
                if not assets[i] or assets[i]['state'] in ('deleted', 'deleting'):
                    raise HTTPException(409, '图片已被删除，请重新上传')
            entries = [x for x in catalog['entries'] if x['slangId'] != content_id]
            if data.status == 'published':
                entries.append({'slangId': content_id, 'revision': revision})
            if len(entries) > 500:
                raise HTTPException(409, '最多发布 500 条内容')
            canonical = {k: editor[k] for k in ('phrase', 'meaningZh', 'category', 'usageNoteZh')}
            canonical['scenarios'] = []
            for scenario in editor['scenarios']:
                asset = assets.get(scenario['assetId'])
                illustration = {k: asset[k] for k in ('objectPath', 'width', 'height', 'contentType', 'sha256') if k in asset} if asset else None
                if illustration:
                    illustration.update(altZh=scenario['altZh'], assetId=scenario['assetId'])
                canonical['scenarios'].append({k: scenario[k] for k in ('id', 'titleZh', 'lines')} | {'illustration': illustration})
            tx.create(self.db.document(f'slangs/{content_id}/revisions/{revision}'),
                      {**canonical, 'status': data.status, 'publishedAt': firestore.SERVER_TIMESTAMP})
            tx.set(root_ref, {**{k: editor[k] for k in ('phrase', 'meaningZh', 'category', 'usageNoteZh')},
                             'status': data.status, 'currentRevision': revision, 'editor': editor,
                             'assetIds': asset_ids, 'updatedAt': firestore.SERVER_TIMESTAMP}, merge=True)
            tx.set(catalog_ref, {'entries': entries, 'revision': catalog['revision'] + 1})
            for i, item in assets.items():
                if item:
                    refs = set(item.get('references', [])) - {content_id}
                    if i in asset_ids:
                        refs.add(content_id)
                    update = {'references': sorted(refs), 'leases': {k: v for k, v in item.get('leases', {}).items() if k != revision}}
                    if i in asset_ids and data.status == 'published':
                        update['state'] = 'published'
                    tx.update(self.db.document(f'adminAssets/{i}'), update)
            if today and today['slangId'] == content_id:
                tx.delete(today_ref)
        commit(self.db.transaction())
        return {'id': content_id, 'revision': revision}

    def delete_content(self, content_id, base_revision):
        # Also indexes legacy picture references before the transactional edit.
        self.detail(content_id)
        root_ref = self.db.document(f'slangs/{content_id}')
        catalog_ref = self.db.document('catalogs/daily')
        date, _ = day_window(datetime.now(timezone.utc), os.getenv('DAILY_TIMEZONE', 'Asia/Shanghai'))
        daily_ref = self.db.document(f'dailyPicks/{date}')
        @firestore.transactional
        def commit(tx):
            root = root_ref.get(transaction=tx).to_dict()
            if not root or root.get('status') == 'deleted':
                raise HTTPException(404, '内容已删除')
            if root['currentRevision'] != base_revision:
                raise HTTPException(409, '内容已更新，请刷新后再删除')
            catalog = catalog_ref.get(transaction=tx).to_dict() or {'entries': [], 'revision': 0}
            today = daily_ref.get(transaction=tx).to_dict()
            version = self.db.document(f"slangs/{content_id}/revisions/{root['currentRevision']}").get(transaction=tx).to_dict()
            ids = set(root.get('assetIds', []))
            if not root.get('editor'):
                ids.update('legacy-' + hashlib.sha256(s['illustration']['objectPath'].encode()).hexdigest()[:32]
                           for s in version['scenarios'] if s.get('illustration'))
            assets = {i: self.db.document(f'adminAssets/{i}').get(transaction=tx).to_dict() for i in ids}
            tx.update(root_ref, {'status': 'deleted', 'deletedAt': firestore.SERVER_TIMESTAMP})
            tx.set(catalog_ref, {'entries': [e for e in catalog['entries'] if e['slangId'] != content_id], 'revision': catalog['revision'] + 1})
            for i, asset in assets.items():
                if asset:
                    tx.update(self.db.document(f'adminAssets/{i}'), {'references': [x for x in asset.get('references', []) if x != content_id]})
            if today and today['slangId'] == content_id:
                tx.delete(daily_ref)
            return sorted(ids)
        return commit(self.db.transaction())

    def delete_asset(self, asset_id):
        ref = self.db.document(f'adminAssets/{asset_id}')
        @firestore.transactional
        def reserve(tx):
            asset = ref.get(transaction=tx).to_dict()
            if not asset or asset['state'] == 'deleted':
                return None
            if asset.get('references'):
                raise HTTPException(409, '图片仍被内容引用，请先移除配图并保存内容')
            if any(v > datetime.now(timezone.utc) for v in asset.get('leases', {}).values()):
                raise HTTPException(409, '图片正在保存中，请稍后再试')
            tx.update(ref, {'state': 'deleting'})
            return asset
        asset = reserve(self.db.transaction())
        if not asset:
            return
        for bucket, path in [(self.published, asset['objectPath']), (self.drafts, asset.get('draftPath'))]:
            if path:
                try:
                    bucket.blob(path).delete()
                except NotFound:
                    pass
        ref.update({'state': 'deleted', 'deletedAt': firestore.SERVER_TIMESTAMP})
