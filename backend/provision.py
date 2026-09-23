"""Idempotent provisioning for dedicated Daily Slang resources; never deletes data."""
import argparse
import json
from pathlib import Path
import subprocess
import time
import requests

ROOT = Path(__file__).resolve().parent


def provision(args):
    project, region = args.project, args.region
    def gcloud(*command, data=False):
        cmd = [args.gcloud, *command, f'--project={project}', '--quiet']
        if data:
            return json.loads(subprocess.check_output([*cmd, '--format=json'], text=True))
        if command[:2] == ('run', 'deploy'):
            subprocess.run(cmd, check=True)
            return
        for attempt in range(5):
            result = subprocess.run(cmd, text=True, capture_output=True)
            if result.returncode == 0:
                print(result.stdout + result.stderr, end='', flush=True)
                return
            if 'add-iam-policy-binding' in command and 'does not exist' in result.stderr and attempt < 4:
                print('Waiting for new service account propagation...', flush=True)
                time.sleep(5 * (attempt + 1))
                continue
            print(result.stdout + result.stderr, end='', flush=True)
            result.check_returncode()

    billing = gcloud('billing', 'projects', 'describe', project, data=True)
    if not billing.get('billingEnabled'):
        raise RuntimeError('Billing must already be enabled for the target project')
    gcloud('services', 'enable', 'run.googleapis.com', 'firestore.googleapis.com',
           'cloudbuild.googleapis.com', 'artifactregistry.googleapis.com',
           'storage.googleapis.com', 'iam.googleapis.com', 'firebaserules.googleapis.com')

    databases = gcloud('firestore', 'databases', 'list', data=True)
    if not any(x['name'].endswith('/daily-slang') for x in databases):
        gcloud('firestore', 'databases', 'create', '--database=daily-slang',
               f'--location={region}', '--type=firestore-native', '--delete-protection')

    accounts = {x['email'] for x in gcloud('iam', 'service-accounts', 'list', data=True)}
    for name in ('daily-slang-api', 'daily-slang-build'):
        if f'{name}@{project}.iam.gserviceaccount.com' not in accounts:
            gcloud('iam', 'service-accounts', 'create', name, f'--display-name={name}')
    runtime = f'daily-slang-api@{project}.iam.gserviceaccount.com'
    builder = f'daily-slang-build@{project}.iam.gserviceaccount.com'
    gcloud('projects', 'add-iam-policy-binding', project,
           f'--member=serviceAccount:{runtime}', '--role=roles/datastore.user',
           f'--condition=expression=resource.name=="projects/{project}/databases/daily-slang",title=daily-slang-only',
           '--format=none')
    gcloud('projects', 'add-iam-policy-binding', project,
           f'--member=serviceAccount:{builder}', '--role=roles/run.builder',
           '--condition=None', '--format=none')

    buckets = {x['name'] for x in gcloud('storage', 'buckets', 'list', data=True)}
    for suffix in ('published', 'drafts'):
        name = f'{project}-daily-slang-{suffix}'
        if name not in buckets:
            gcloud('storage', 'buckets', 'create', f'gs://{name}',
                   f'--location={region}', '--uniform-bucket-level-access',
                   *(['--public-access-prevention'] if suffix == 'drafts' else []))
    bucket = f'{project}-daily-slang-published'
    gcloud('storage', 'buckets', 'add-iam-policy-binding', f'gs://{bucket}',
           '--member=allUsers', '--role=roles/storage.objectViewer', '--format=none')

    for collection, field in [('revisions', 'scenarios'), ('dailyPicks', 'payload'),
                              ('catalogs', 'entries'), ('rotationStates', 'remainingIds')]:
        gcloud('firestore', 'indexes', 'fields', 'update', field,
               f'--collection-group={collection}', '--database=daily-slang', '--disable-indexes', '--async')

    # Deny direct mobile/web Firestore access. Server IAM is separate.
    token = subprocess.check_output([args.gcloud, 'auth', 'print-access-token'], text=True).strip()
    session = requests.Session()
    session.headers['Authorization'] = f'Bearer {token}'
    session.headers['X-Goog-User-Project'] = project
    base = f'https://firebaserules.googleapis.com/v1/projects/{project}'
    result = session.post(base + '/rulesets', json={'source': {'files': [{
        'name': 'firestore.rules', 'content': (ROOT / 'firestore.rules').read_text(),
    }]}}, timeout=30)
    result.raise_for_status()
    ruleset = result.json()['name']
    release_name = f'projects/{project}/releases/cloud.firestore/daily-slang'
    release_url = f'https://firebaserules.googleapis.com/v1/{release_name}'
    existing = session.get(release_url, timeout=30)
    if existing.status_code == 404:
        result = session.post(base + '/releases', json={'name': release_name, 'rulesetName': ruleset}, timeout=30)
    else:
        existing.raise_for_status()
        result = session.patch(release_url, json={
            'release': {'name': release_name, 'rulesetName': ruleset}, 'updateMask': 'rulesetName',
        }, timeout=30)
    result.raise_for_status()
    print('Firestore rules deployed', flush=True)
    if args.deploy:
        gcloud('run', 'deploy', 'daily-slang-api', f'--region={region}', f'--source={ROOT}',
               f'--service-account={runtime}',
               f'--build-service-account=projects/{project}/serviceAccounts/{builder}',
               '--allow-unauthenticated', '--min=0', '--max=2', '--concurrency=40',
               '--cpu=1', '--memory=512Mi', '--timeout=30',
               f'--set-env-vars=GOOGLE_CLOUD_PROJECT={project},FIRESTORE_DATABASE=daily-slang,PUBLISHED_BUCKET={bucket},DAILY_TIMEZONE=Asia/Shanghai')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', required=True)
    parser.add_argument('--region', default='asia-southeast1')
    parser.add_argument('--gcloud', default='gcloud')
    parser.add_argument('--deploy', action='store_true')
    provision(parser.parse_args())
