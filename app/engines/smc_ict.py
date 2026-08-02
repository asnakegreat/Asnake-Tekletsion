import uuid
from datetime import datetime

def generate_signal(snapshot: dict) -> dict:
    """Very simple demo SMC/ICT signal generator.
    snapshot expected keys: pair, timeframe, price, recent_structure_score (0-1)
    Returns a normalized signal dict compatible with signal.schema.json.
    """
    pair = snapshot.get('pair', 'EURUSD')
    timeframe = snapshot.get('timeframe', '1H')
    price = float(snapshot.get('price', 1.0))
    structure = float(snapshot.get('recent_structure_score', 0.5))

    # crude rule: if structure > 0.6 we bias long, <0.4 bias short
    if structure > 0.6:
        direction = 'long'
        confidence = min(0.9, 0.5 + (structure - 0.6))
    elif structure < 0.4:
        direction = 'short'
        confidence = min(0.9, 0.5 + (0.4 - structure))
    else:
        direction = 'long'
        confidence = 0.45

    # suggested SL/TP at demo offsets
    sl = round(price - 0.0025 if direction == 'long' else price + 0.0025, 5)
    tp = round(price + 0.0050 if direction == 'long' else price - 0.0050, 5)

    signal = {
        'signal_id': str(uuid.uuid4()),
        'engine': 'SMC-ICT',
        'engine_version': 'v1.0',
        'pair': pair,
        'timeframe': timeframe,
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'sent_at': datetime.utcnow().isoformat() + 'Z',
        'direction': direction,
        'confidence': round(confidence, 3),
        'suggested_size': None,
        'execution_price': price,
        'execution_status': 'pending',
        'sl': sl,
        'tp': tp,
        'explanation': {
            'components': [
                {'name': 'HTFStructure', 'weight': 0.6, 'note': 'Demo structure strength'},
                {'name': 'SMCPattern', 'weight': 0.3, 'note': 'Order block detected'}
            ],
            'ml_shap_summary': 'N/A for rule-based demo'
        },
        'payload': {
            'snapshot': snapshot
        }
    }
    return signal
