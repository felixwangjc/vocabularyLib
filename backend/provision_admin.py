"""Deploy password-protected administration separately from the public daily API."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent

def main(args):
    project = args.project
    service = 'daily-slang-admin'
    origin = f'https://{service}-{args.project_number}.{args.region}.run.app'
    account = f'{service}@{project}.iam.gserviceaccount.com'
    def run(*cmd, data=False):
        command = [args.gcloud, *cmd, f'--project={project}', '--quiet']
        if data:
            return json.loads(subprocess.check_output([*command, '--format=json'], text=True))
        for attempt in range(5):
            if 'add-iam-policy-binding' not in cmd:
                subprocess.run(command, check=True)
                return
            result = subprocess.run(command, text=True, capture_output=True)
            if result.returncode == 0:
                return
            if 'does not exist' in result.stderr and attempt < 4:
                time.sleep(5 * (attempt + 1))
            else:
                print(result.stderr)
                result.check_returncode()
    run('services', 'enable', 'secretmanager.googleapis.com')
    accounts = run('iam', 'service-accounts', 'list', data=True)
    if account not in {item['email'] for item in accounts}:
        run('iam', 'service-accounts', 'create', service, '--display-name=Daily Slang Admin')
    run('projects', 'add-iam-policy-binding', project, f'--member=serviceAccount:{account}',
        '--role=roles/datastore.user', f'--condition=expression=resource.name=="projects/{project}/databases/daily-slang",title=daily-slang-admin-only', '--format=none')
    for suffix in ('published', 'drafts'):
        run('storage', 'buckets', 'add-iam-policy-binding', f'gs://{project}-daily-slang-{suffix}',
            f'--member=serviceAccount:{account}', '--role=roles/storage.objectAdmin', '--format=none')
    names = {item['name'].rsplit('/', 1)[-1] for item in run('secrets', 'list', data=True)}
    secret_names = ('daily-slang-admin-password-hash', 'daily-slang-admin-session-key')
    exists = [name in names for name in secret_names]
    if any(exists) and not all(exists):
        raise RuntimeError('Partial secret setup; inspect before continuing')
    if not any(exists):
        password, salt = secrets.token_urlsafe(24), secrets.token_bytes(16)
        digest = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1).hex()
        values = (salt.hex() + ':' + digest, secrets.token_urlsafe(48))
        # The password is delivered locally, not committed or printed into deployment logs.
        path = ROOT / '.admin-access.txt'
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as file:
            file.write(f'管理后台：{origin}\n管理密码：{password}\n\n请保存在密码管理器中。此文件已被 Git 忽略。\n')
        for name, value in zip(secret_names, values):
            with tempfile.NamedTemporaryFile(mode='w', prefix='slang-admin-secret-') as temp:
                temp.write(value); temp.flush()
                run('secrets', 'create', name, '--replication-policy=automatic', f'--data-file={temp.name}')
    for name in secret_names:
        run('secrets', 'add-iam-policy-binding', name, f'--member=serviceAccount:{account}',
            '--role=roles/secretmanager.secretAccessor', '--format=none')
    for group, field in [('slangs','editor'),('adminAssets','references'),('adminAssets','leases')]:
        run('firestore','indexes','fields','update',field,'--database=daily-slang',f'--collection-group={group}','--disable-indexes','--async','--format=none')
    run('run', 'deploy', service, f'--region={args.region}', f'--source={ROOT}',
        f'--service-account={account}',
        f'--build-service-account=projects/{project}/serviceAccounts/daily-slang-build@{project}.iam.gserviceaccount.com',
        '--allow-unauthenticated', '--min=0', '--max=2', '--concurrency=20', '--cpu=1', '--memory=512Mi', '--timeout=60',
        f'--set-env-vars=APP_MODULE=app.admin:app,GOOGLE_CLOUD_PROJECT={project},FIRESTORE_DATABASE=daily-slang,PUBLISHED_BUCKET={project}-daily-slang-published,DRAFT_BUCKET={project}-daily-slang-drafts,DAILY_TIMEZONE=Asia/Shanghai,ADMIN_ORIGIN={origin}',
        '--set-secrets=ADMIN_PASSWORD_HASH=daily-slang-admin-password-hash:latest,ADMIN_SESSION_KEY=daily-slang-admin-session-key:latest')
    print(f'Admin URL: {origin}')
    print(f'Local login file: {ROOT / ".admin-access.txt"}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', required=True)
    parser.add_argument('--project-number', required=True)
    parser.add_argument('--region', default='asia-southeast1')
    parser.add_argument('--gcloud', default='gcloud')
    main(parser.parse_args())
