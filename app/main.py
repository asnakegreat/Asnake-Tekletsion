from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Optional
import json
import os
from jsonschema import validate, ValidationError
from datetime import datetime
from pathlib import Path
from .position_sizing import calculate_position_size
from .alerting import send_alert

app = FastAPI(title="Signal Scanner Pro V60 - Subscriptions and Signals")
DATA_DIR = Path(__file__).resolve().parents[1] / 'data'
SIGNALS_DIR = DATA_DIR / 'signals'
SUBS_FILE = DATA_DIR / 'subscriptions.json'
SIGNALS_DIR.mkdir(parents=True, exist_ok=True)
DATA_DIR.mkdir(parents=True, exist_ok=True)
if not SUBS_FILE.exists():
    SUBS_FILE.write_text('[]')

SCHEMA_PATH = Path(__file__).resolve().parents[1] / 'signal.schema.json'
with open(SCHEMA_PATH, 'r') as f:
    SIGNAL_SCHEMA = json.load(f)

class SignalIn(BaseModel):
    signal_id: str
    engine: str
    pair: str
    timeframe: str
    timestamp: str
    direction: str
    confidence: float
    sl: float
    tp: float
    suggested_size: Optional[float] = None
    execution_price: Optional[float] = None
    execution_status: Optional[str] = None
    payload: Optional[dict] = None

class Subscription(BaseModel):
    user_id: str
    channel: str  # telegram | webhook | email
    filters: dict = {}

@app.post('/api/signals')
async def ingest_signal(signal: SignalIn, background_tasks: BackgroundTasks):
    data = signal.dict()
    try:
        validate(instance=data, schema=SIGNAL_SCHEMA)
    except ValidationError as e:
        raise HTTPException(status_code=422, detail=f"Schema validation error: {e.message}")

    # persist signal
    sig_path = SIGNALS_DIR / f"{data['signal_id']}.json"
    with open(sig_path, 'w') as f:
        json.dump(data, f, indent=2)

    # calculate position size
    account_balance = float(os.getenv('ACCOUNT_BALANCE', '10000'))
    risk_percent = float(os.getenv('RISK_PERCENT', '0.01'))
    entry_price = float(data.get('execution_price') or (data.get('payload', {}).get('snapshot', {}).get('price') or 0))
    try:
        size = calculate_position_size(account_balance, risk_percent, entry_price, float(data['sl']))
    except Exception:
        size = None

    # load subscriptions and notify matching subscribers
    subs = json.loads(SUBS_FILE.read_text())
    notified = 0
    for s in subs:
        try:
            filters = s.get('filters', {})
            # very simple matching: check pair and min_confidence if present
            if filters.get('pair') and filters.get('pair') != data['pair']:
                continue
            min_conf = filters.get('min_confidence')
            if min_conf and data.get('confidence', 0) < float(min_conf):
                continue
            # build message and send via alerting helper (background)
            msg = f"Signal {data['signal_id']} {data['pair']} {data['direction']} conf={data['confidence']:.2f} size={size if size else 'n/a'}"
            background_tasks.add_task(send_alert, msg, s.get('user_id', 'global'))
            notified += 1
        except Exception:
            continue

    return {"signal_id": data['signal_id'], "received_at": datetime.utcnow().isoformat() + 'Z', "position_size": size, 'notified_subscribers': notified}

@app.post('/api/subscribe')
def subscribe(sub: Subscription):
    subs = json.loads(SUBS_FILE.read_text())
    subs.append(sub.dict())
    SUBS_FILE.write_text(json.dumps(subs, indent=2))
    return {'status': 'subscribed', 'subscription': sub.dict()}

@app.get('/api/subscriptions')
def list_subs():
    return json.loads(SUBS_FILE.read_text())

@app.get('/api/signals')
def list_signals(limit: int = 100):
    files = sorted(SIGNALS_DIR.glob('*.json'), key=lambda p: p.stat().st_mtime, reverse=True)[:limit]
    result = []
    for f in files:
        try:
            with open(f, 'r') as fh:
                data = json.load(fh)
                result.append({'signal_id': data.get('signal_id'), 'pair': data.get('pair'), 'timeframe': data.get('timeframe'), 'confidence': data.get('confidence'), 'timestamp': data.get('timestamp')})
        except Exception:
            continue
    return result

@app.get('/api/signals/{signal_id}')
def get_signal(signal_id: str):
    p = SIGNALS_DIR / f"{signal_id}.json"
    if not p.exists():
        raise HTTPException(status_code=404, detail='signal not found')
    with open(p, 'r') as f:
        return json.load(f)

@app.get('/')
def index():
    return { 'endpoints': ['/api/signals (POST, GET)', '/api/signals/{id} (GET)', '/api/subscribe (POST)', '/api/subscriptions (GET)'] }
