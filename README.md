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

Notes

- This is a demo scaffold to illustrate validation, sizing, and alerting. Replace the sizing algorithm and alerting with production-grade implementations before using with real capital.
- For containerized local development, consider adding a docker-compose with FastAPI + Redis + Postgres as in the design docs.

Authored for: Asnake Tekletsion
