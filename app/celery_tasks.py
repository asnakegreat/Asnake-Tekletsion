import os
import requests
from datetime import datetime
from .engines.smc_ict import generate_signal
from .celery_app import celery

API_BASE = os.getenv('API_BASE_URL', 'http://api:8000')

@celery.task(bind=True, max_retries=3)
def run_smc_engine(self, market_snapshot: dict):
    """Run SMC/ICT engine on a market snapshot and post normalized signal to API."""
    try:
        signal = generate_signal(market_snapshot)
        url = f"{API_BASE}/api/signals"
        r = requests.post(url, json=signal, timeout=5)
        r.raise_for_status()
        return {'status': 'posted', 'signal_id': signal.get('signal_id')}
    except requests.RequestException as exc:
        try:
            self.retry(exc=exc, countdown=5)
        except Exception:
            raise

@celery.task(bind=True)
def process_alert_retry(self):
    """Worker task to pop messages from Redis retry queue and resend them."""
    import redis
    REDIS_URL = os.getenv('REDIS_URL', 'redis://redis:6379/0')
    r = redis.from_url(REDIS_URL)
    queue = 'alert:retry_queue'
    while True:
        item = r.lpop(queue)
        if not item:
            break
        try:
            # Try to resend via webhook (simple fallback)
            WEBHOOK = os.getenv('ALERT_WEBHOOK_URL')
            if WEBHOOK:
                requests.post(WEBHOOK, json={'text': item.decode('utf-8')}, timeout=5)
        except Exception:
            # if resend fails, push it back
            r.rpush(queue, item)
            break
    return {'status': 'drained'}
