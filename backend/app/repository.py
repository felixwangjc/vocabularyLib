from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from datetime import date as calendar_date, timedelta
from random import SystemRandom
from app.domain import ContentUnavailable, make_payload, next_selection


class DailyRepository:
    def __init__(self, client):
        self.db = client

    def get_batch(self, date, end, timezone_name, excluded, known):
        catalog = self.db.document('catalogs/daily').get(timeout=10).to_dict() or {}
        available = [entry for entry in catalog.get('entries', []) if entry['slangId'] not in excluded]
        rng = SystemRandom()
        fresh = [entry for entry in available if entry['slangId'] not in known]
        old = [entry for entry in available if entry['slangId'] in known]
        rng.shuffle(fresh)
        rng.shuffle(old)
        result = []
        for entry in (fresh + old)[:2]:
            content = self.db.document(f"slangs/{entry['slangId']}/revisions/{entry['revision']}").get(timeout=10).to_dict()
            if content:
                result.append(make_payload(date, end, timezone_name, entry['slangId'], entry['revision'], content))
        return result

    def get_daily(self, date, end, timezone_name):
        daily_ref = self.db.collection('dailyPicks').document(date)
        existing = daily_ref.get(timeout=10)
        if existing.exists:
            return existing.to_dict()['payload']

        @firestore.transactional
        def select(transaction):
            snapshot = daily_ref.get(transaction=transaction)
            if snapshot.exists:
                return snapshot.to_dict()['payload']
            catalog = self.db.document('catalogs/daily').get(transaction=transaction).to_dict() or {}
            state_ref = self.db.document('rotationStates/global')
            state = state_ref.get(transaction=transaction).to_dict() or {}
            cutoff = (calendar_date.fromisoformat(date) - timedelta(days=60)).isoformat()
            recent = self.db.collection('dailyPicks').where(filter=FieldFilter('date', '>=', cutoff)).where(filter=FieldFilter('date', '<', date))
            excluded = {snapshot.to_dict()['slangId'] for snapshot in recent.stream(transaction=transaction)}
            slang_id, revision, updated = next_selection(catalog.get('entries', []), state, excluded_ids=excluded)
            content = self.db.document(f'slangs/{slang_id}/revisions/{revision}').get(
                transaction=transaction
            ).to_dict()
            if not content:
                raise ContentUnavailable('Published revision is missing')
            payload = make_payload(date, end, timezone_name, slang_id, revision, content)
            transaction.create(daily_ref, {
                'date': date, 'timezone': timezone_name, 'slangId': slang_id,
                'revision': revision, 'scenarioId': payload['scenario']['id'],
                'payload': payload, 'createdAt': firestore.SERVER_TIMESTAMP,
            })
            transaction.set(state_ref, {**updated, 'catalogRevision': catalog.get('revision', 0)})
            return payload

        return select(self.db.transaction(max_attempts=5))
