from celery import Celery
import os

REDIS_URL = os.getenv('REDIS_URL', 'redis://redis:6379/0')
celery = Celery('app', broker=REDIS_URL)
celery.conf.task_routes = {
    'app.celery_tasks.run_smc_engine': {'queue': 'engines'},
    'app.celery_tasks.process_alert_retry': {'queue': 'alerts'}
}
