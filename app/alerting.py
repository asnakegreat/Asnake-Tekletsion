from typing import Optional
import os
import requests
import hashlib

try:
    import redis
    REDIS = redis.from_url(os.getenv('REDIS_URL', 'redis://redis:6379/0'))
except Exception:
    REDIS = None

TG_BOT_TOKEN = os.getenv('TG_BOT_TOKEN')
TG_CHAT_ID = os.getenv('TG_CHAT_ID')
WEBHOOK_URL = os.getenv('ALERT_WEBHOOK_URL')

DEDUP_TTL = int(os.getenv('ALERT_DEDUP_TTL_SEC', '60'))
RATE_LIMIT_WINDOW = int(os.getenv('ALERT_RATE_WINDOW_SEC', '60'))
RATE_LIMIT_MAX = int(os.getenv('ALERT_RATE_MAX', '10'))

def _hash_message(message: str) -> str:
    return hashlib.sha256(message.encode('utf-8')).hexdigest()

def _dedupe_check(message: str) -> bool:
    if not REDIS:
        return False
    key = 'alert:dedup:' + _hash_message(message)
    if REDIS.get(key):
        return True
    REDIS.set(key, '1', ex=DEDUP_TTL)
    return False

def _rate_limited(user_key: str = 'global') -> bool:
    if not REDIS:
        return False
    rl_key = f'alert:rate:{user_key}'
    count = REDIS.incr(rl_key)
    if count == 1:
        REDIS.expire(rl_key, RATE_LIMIT_WINDOW)
    return count > RATE_LIMIT_MAX

def _queue_retry(message: str):
    if not REDIS:
        return
    try:
        REDIS.rpush('alert:retry_queue', message)
    except Exception:
        pass

def send_alert(message: str, user_key: Optional[str] = 'global') -> bool:
    """Sends an alert with dedupe, rate-limit and retry queue."""
    # dedupe
    if _dedupe_check(message):
        # deduped
        return True

    # rate limit
    if _rate_limited(user_key):
        # queue for later
        _queue_retry(message)
        return True

    # send
    sent = False
    if TG_BOT_TOKEN and TG_CHAT_ID:
        url = f"https://api.telegram.org/bot{TG_BOT_TOKEN}/sendMessage"
        try:
            r = requests.post(url, json={"chat_id": TG_CHAT_ID, "text": message}, timeout=5)
            sent = r.ok
        except Exception:
            sent = False
    elif WEBHOOK_URL:
        try:
            r = requests.post(WEBHOOK_URL, json={"text": message}, timeout=5)
            sent = r.ok
        except Exception:
            sent = False
    else:
        # nothing configured; for demo log and return True
        print('ALERT:', message)
        sent = True

    if not sent:
        _queue_retry(message)

    return sent
