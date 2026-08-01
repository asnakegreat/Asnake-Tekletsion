from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
import uuid
import json
import os
from jsonschema import validate, ValidationError
from .position_sizing import calculate_position_size
from .alerting import send_telegram_alert
from datetime import datetime

app = FastAPI(title="Signal Scanner Pro V60 Demo")

# Load schema
SCHEMA_PATH = os.path.join(os.path.dirname(__file__), '..', 'signal.schema.json')
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
    suggested_size: float = None
    execution_price: float = None
    execution_status: str = None
    payload: dict = None

@app.post('/api/signals')
async def ingest_signal(signal: SignalIn, background_tasks: BackgroundTasks):
    data = signal.dict()
    # Validate against JSON Schema
    try:
        validate(instance=data, schema=SIGNAL_SCHEMA)
    except ValidationError as e:
        raise HTTPException(status_code=422, detail=f"Schema validation error: {e.message}")

    # Calculate position size (demo): require ACCOUNT_BALANCE and RISK_PERCENT env vars or defaults
    try:
        account_balance = float(os.getenv('ACCOUNT_BALANCE', '10000'))
        risk_percent = float(os.getenv('RISK_PERCENT', '0.01'))  # 1% default
        size = calculate_position_size(account_balance, risk_percent, float(data['execution_price']) if data.get('execution_price') else (float(data.get('suggested_size') or 0)), float(data['sl']))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Position sizing error: {str(e)}")

    # Enqueue alert in background
    msg = f"Signal {data['signal_id']} {data['pair']} {data['direction']} conf={data['confidence']:.2f} size={size:.6f}"
    background_tasks.add_task(send_telegram_alert, msg)

    return {"signal_id": data['signal_id'], "received_at": datetime.utcnow().isoformat() + 'Z', "position_size": size}
