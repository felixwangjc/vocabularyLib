"""Validate and publish immutable content. Uses ADC or a local gcloud session."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from google.api_core.exceptions import PreconditionFailed
from google.cloud import firestore, storage
from google.oauth2.credentials import Credentials
from PIL import Image


def validate(item, root):
    for key in ('id', 'revision'):
        if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,79}', item[key]):
            raise ValueError(f'Invalid {key}')
    for key in ('phrase', 'meaningZh', 'category', 'usageNoteZh'):
        if not isinstance(item[key], str) or not item[key].strip() or len(item[key]) > 2000:
            raise ValueError(f'Invalid {key}')
    scenarios = item['scenarios']
    if not 1 <= len(scenarios) <= 10:
        raise ValueError('Expected 1–10 scenarios')
    ids = set()
    for scenario in scenarios:
        sid = scenario['id']
        if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,79}', sid) or sid in ids:
            raise ValueError('Invalid or duplicate scenario ID')
        ids.add(sid)
        if not isinstance(scenario['titleZh'], str) or not scenario['titleZh'].strip():
            raise ValueError('Missing scenario title')
        lines = scenario['lines']
        if not 1 <= len(lines) <= 12 or not any(x.get('isTarget') is True for x in lines):
            raise ValueError('Expected 1–12 lines and a target sentence')
        line_ids = set()
        for line in lines:
            for key in ('id', 'speaker', 'en', 'zh'):
                if not isinstance(line.get(key), str) or not line[key].strip() or len(line[key]) > 2000:
                    raise ValueError(f'Invalid line {key}')
            if line['id'] in line_ids or not isinstance(line.get('isTarget'), bool):
                raise ValueError('Invalid line ID or isTarget')
            line_ids.add(line['id'])
        image = scenario['illustration']
        path = (root / image['localFile']).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError('Image must exist within the content directory')
        if path.stat().st_size > 5 * 1024 * 1024:
            raise ValueError('Image exceeds 5 MiB')
        with Image.open(path) as picture:
            picture.verify()
        with Image.open(path) as picture:
            if picture.format not in ('PNG', 'WEBP', 'JPEG') or max(picture.size) > 4096:
                raise ValueError('Unsupported image')
            image['width'], image['height'] = picture.size
            image['contentType'] = Image.MIME[picture.format]
        if not isinstance(image.get('altZh'), str) or not image['altZh'].strip():
            raise ValueError('Missing image description')
        image['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        image['objectPath'] = f"slangs/{item['id']}/{item['revision']}/{sid}/illustration{path.suffix.lower()}"
    if len(json.dumps(item, ensure_ascii=False).encode()) > 256 * 1024:
        raise ValueError('Content exceeds 256 KiB')
    return item


def publish(db, bucket, item, root):
    content = {k: v for k, v in item.items() if k not in ('id', 'revision')}
    uploads = []
    for scenario in content['scenarios']:
        image = scenario['illustration']
        uploads.append((root / image.pop('localFile'), dict(image)))
    fingerprint = hashlib.sha256(json.dumps(content, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    version_ref = db.document(f"slangs/{item['id']}/revisions/{item['revision']}")
    existing = version_ref.get()
    if existing.exists:
        if existing.to_dict().get('fingerprint') != fingerprint:
            raise ValueError('Revision already exists with different content; use a new revision')
        print(f"Already published: {item['id']} {item['revision']}")
        return
    current = db.document(f"slangs/{item['id']}").get().to_dict() or {}
    if current.get('editor') or current.get('status') == 'deleted':
        raise ValueError('This item is managed by the admin UI; edit it there or import a new ID')
    for path, image in uploads:
        blob = bucket.blob(image['objectPath'])
        blob.cache_control = 'public, max-age=31536000, immutable'
        blob.metadata = {'sha256': image['sha256']}
        try:
            blob.upload_from_filename(str(path), content_type=image['contentType'], if_generation_match=0)
        except PreconditionFailed:
            blob.reload()
            if (blob.metadata or {}).get('sha256') != image['sha256']:
                raise ValueError('Image path already contains different bytes')

    @firestore.transactional
    def commit(transaction):
        existing = version_ref.get(transaction=transaction)
        catalog_ref = db.document('catalogs/daily')
        catalog = catalog_ref.get(transaction=transaction).to_dict() or {'revision': 0, 'entries': []}
        if existing.exists:
            if existing.to_dict().get('fingerprint') != fingerprint:
                raise ValueError('Concurrent conflicting publication')
            return
        entries = [e for e in catalog['entries'] if e['slangId'] != item['id']]
        entries.append({'slangId': item['id'], 'revision': item['revision']})
        if len(entries) > 500:
            raise ValueError('Catalog limit 500: shard the catalog before adding more')
        transaction.create(version_ref, {**content, 'fingerprint': fingerprint, 'publishedAt': firestore.SERVER_TIMESTAMP})
        transaction.set(db.document(f"slangs/{item['id']}"), {
            **{k: content[k] for k in ('phrase', 'meaningZh', 'category', 'usageNoteZh')},
            'status': 'published', 'currentRevision': item['revision'],
            'updatedAt': firestore.SERVER_TIMESTAMP,
        }, merge=True)
        transaction.set(catalog_ref, {'revision': catalog['revision'] + 1, 'entries': entries})
    commit(db.transaction())
    print(f"Published: {item['id']} {item['revision']}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('file', type=Path)
    parser.add_argument('--project', required=True)
    parser.add_argument('--database', default='daily-slang')
    parser.add_argument('--bucket', required=True)
    parser.add_argument('--gcloud', help='Optional gcloud executable; otherwise ADC')
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    items = json.loads(args.file.read_text())
    for item in items:
        validate(item, args.file.parent)
    if args.validate_only:
        print(f'Validated {len(items)} items')
    else:
        credentials = Credentials(token=subprocess.check_output(
            [args.gcloud, 'auth', 'print-access-token'], text=True).strip()) if args.gcloud else None
        db = firestore.Client(project=args.project, database=args.database, credentials=credentials)
        bucket = storage.Client(project=args.project, credentials=credentials).bucket(args.bucket)
        for item in items:
            publish(db, bucket, item, args.file.parent)
