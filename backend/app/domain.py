"""Daily selection policy, independent of Firestore and HTTP."""
from copy import deepcopy
from datetime import datetime, time, timedelta, timezone
from random import SystemRandom
from zoneinfo import ZoneInfo


class ContentUnavailable(Exception):
    pass


def day_window(now: datetime, timezone_name: str):
    zone = ZoneInfo(timezone_name)
    local = now.astimezone(zone)
    end = datetime.combine(local.date() + timedelta(days=1), time(), zone)
    return local.date().isoformat(), end.astimezone(timezone.utc)


def next_selection(entries, state, rng=None, excluded_ids=()):
    rng = rng or SystemRandom()
    excluded = set(excluded_ids)
    available = {entry['slangId']: entry['revision'] for entry in entries if entry['slangId'] not in excluded}
    if not available:
        raise ContentUnavailable('No published content')
    remaining = list(dict.fromkeys(x for x in state.get('remainingIds', []) if x in available))
    cycle = state.get('cycle', 0)
    if not remaining:
        remaining = list(available)
        rng.shuffle(remaining)
        cycle += 1
        if len(remaining) > 1 and remaining[0] == state.get('lastSlangId'):
            swap = rng.randrange(1, len(remaining))
            remaining[0], remaining[swap] = remaining[swap], remaining[0]
    selected = remaining.pop(0)
    return selected, available[selected], {
        'remainingIds': remaining, 'lastSlangId': selected, 'cycle': cycle,
    }


def make_payload(date, end, timezone_name, slang_id, revision, content, rng=None):
    scenarios = content.get('scenarios', [])
    if not scenarios:
        raise ContentUnavailable('Published content has no scenarios')
    scenario = deepcopy((rng or SystemRandom()).choice(scenarios))
    return {
        'schemaVersion': 1, 'dailyId': date, 'date': date,
        'timezone': timezone_name,
        'nextRefreshAt': end.isoformat().replace('+00:00', 'Z'),
        'contentRevision': 1,
        'slang': {
            'id': slang_id, 'revision': revision,
            **{key: content[key] for key in ('phrase', 'meaningZh', 'category', 'usageNoteZh')},
        },
        'scenario': scenario,
    }
