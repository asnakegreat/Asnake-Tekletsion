# Signal Scanner Pro V60 — Example & Local Demo

This repository contains a sample signal JSON and a small FastAPI demo app to validate and process signals for the Signal Scanner Pro V60 project.

Files added:

- `signal.json` — example signal with timestamps, execution metadata, and explanation.
- `signal.schema.json` — JSON Schema for validating signals.
- `app/main.py` — FastAPI application: /api/signals endpoint that validates, calculates position size, and optionally sends a Telegram alert.
- `app/position_sizing.py` — simple position sizing algorithm (unit tests included).
- `app/alerting.py` — Telegram/webhook alert helper (demo).
- `requirements.txt` — Python dependencies.
- `tests/test_position_sizing.py` — unit tests for sizing logic.
- `calibration_profit_factor.py` — reads `PAICT_Calibration.csv` (written by `PAICT_ChartMarkup.mq5`'s `CalibrationUpdate()`) and reports a per-symbol, R-multiple profit-factor summary of the EA's suggested plans vs. what price actually did. Run `python3 calibration_profit_factor.py /path/to/PAICT_Calibration.csv --help` for options.

Quick start (local)

1. Clone your repo and create a virtual environment:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Set environment variables (optional for Telegram alerts):

```bash
export TG_BOT_TOKEN="<your_bot_token>"
export TG_CHAT_ID="<your_chat_id>"
```

3. Run the FastAPI app:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

4. Validate the example signal and trigger demo processing:

```bash
curl -X POST http://localhost:8000/api/signals \
  -H "Content-Type: application/json" \
  --data-binary @signal.json
```

You should receive a JSON response with validation status and a calculated position size.

Running tests

```bash
pytest -q
```

Usage tracking (Amplitude)

`app/analytics.py` sends usage events to Amplitude. It is off unless `AMPLITUDE_API_KEY` is set, and a failed send never affects the API response.

```bash
export AMPLITUDE_API_KEY="<your_project_api_key>"   # never commit it
# optional, EU data residency:
# export AMPLITUDE_SERVER_URL="https://api.eu.amplitude.com/2/httpapi"
```

| Event | Sent from | Properties |
|---|---|---|
| Signal Received | `POST /api/signals` (valid) | engine, pair, timeframe, direction, confidence, position_sized, notified_subscribers, action, strategy, late |
| Signal Rejected | `POST /api/signals` (schema error) | engine, pair, timeframe, reason |
| Subscription Created | `POST /api/subscribe` | channel, has_pair_filter, has_confidence_filter |

User ids are hashed before sending, and property names containing password, token, secret, balance, account, login or email are dropped.

Notion logging

`app/notion_sink.py` writes every received signal as a row in the Notion "Live Signals" database (TRADING / Trading System / Tools & Automation / Signal Scanner). It is off unless both variables are set:

```bash
export NOTION_TOKEN="<internal integration secret>"   # never commit it
export NOTION_SIGNALS_DB="45fdcea0ca0a48c0b2126f2dc2b8a0aa"
```

Create the integration at notion.so/my-integrations, then open the Live Signals database in Notion → ••• → Connections → add that integration.

MT5 signal source: `mql5/ZEC_SignalHub_EA.mq5`

Signal-only EA (places no trades) for the two strategies that passed testing, using the frozen rules from ZEC_Portfolio_EA:

- **G4** index RSI(2) pullback: D1 close > SMA200 and RSI(2) < 5 → entry; exit after RSI(2) > 70 or a 3×ATR20 stop.
- **B1** trend momentum: 63- and 126-day returns both turn positive → entry; 3×ATR20 stop, chandelier = highest high since entry − 7×ATR20.

It reads the broker's real D1 bars, rebuilds open positions from history on start, and posts each entry/exit to `POST /api/signals` (→ Amplitude, Notion, subscriber alerts). It also logs to `Common\Files\ZEC_SignalHub_log.csv`. Prices are signal-close references; real fills are the next open.

Setup: copy to `MQL5\Experts`, compile (F7), add `http://127.0.0.1:8000` under Tools → Options → Expert Advisors → Allow WebRequest, attach to any one chart, and set the symbol inputs to your broker's names.

Notes

- This is a demo scaffold to illustrate validation, sizing, and alerting. Replace the sizing algorithm and alerting with production-grade implementations before using with real capital.
- For containerized local development, consider adding a docker-compose with FastAPI + Redis + Postgres as in the design docs.

Authored for: Asnake Tekletsion
