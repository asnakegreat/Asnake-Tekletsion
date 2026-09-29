import json

import pytest
from fastapi.testclient import TestClient

from app import main as app_main
from app import notion_sink


class _Resp:
    def __init__(self, status_code=200, text=""):
        self.status_code = status_code
        self.text = text


# A signal shaped exactly like ZEC_SignalHub_EA posts it
HUB_SIGNAL = {
    "signal_id": "G4-US500z-20260929-entry",
    "engine": "ZEC_G4",
    "engine_version": "SignalHub 1.00",
    "pair": "US500z",
    "timeframe": "D1",
    "timestamp": "2026-09-29T21:00:05Z",
    "sent_at": "2026-09-29T21:00:05Z",
    "direction": "long",
    "confidence": 0.5,
    "execution_price": 6512.4,
    "execution_status": "signal_only",
    "sl": 6380.1,
    "tp": 0,
    "explanation": {"rule": "close > SMA200 and RSI(2) < 5 - buy next open"},
    "payload": {
        "action": "entry", "strategy": "G4",
        "reason": "close > SMA200 and RSI(2) < 5 - buy next open",
        "bar_date": "2026.09.29", "late": False,
        "snapshot": {"price": 6512.4}, "close": 6512.4, "high": 6540.0, "low": 6490.2,
        "atr20": 44.1, "sma200": 6100.0, "rsi2": 3.12,
    },
}


@pytest.fixture
def notion_calls(monkeypatch):
    calls = []

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append({"url": url, "body": json, "headers": headers})
        return _Resp(200)

    monkeypatch.setattr(notion_sink.requests, "post", fake_post)
    return calls


def test_disabled_without_env(monkeypatch, notion_calls):
    monkeypatch.delenv("NOTION_TOKEN", raising=False)
    monkeypatch.delenv("NOTION_SIGNALS_DB", raising=False)
    assert notion_sink.enabled() is False
    assert notion_sink.log_signal(HUB_SIGNAL) is False
    assert notion_calls == []


def test_properties_match_live_signals_db():
    props = notion_sink.build_properties(HUB_SIGNAL)
    assert props["Signal"]["title"][0]["text"]["content"] == "G4-US500z-20260929-entry"
    assert props["Strategy"] == {"select": {"name": "G4"}}
    assert props["Action"] == {"select": {"name": "entry"}}
    assert props["Direction"] == {"select": {"name": "long"}}
    assert props["Symbol"]["rich_text"][0]["text"]["content"] == "US500z"
    assert props["Bar date"] == {"date": {"start": "2026-09-29"}}
    assert props["Price"] == {"number": 6512.4}
    assert props["Stop"] == {"number": 6380.1}
    assert props["Late"] == {"checkbox": False}
    assert "RSI(2) < 5" in props["Reason"]["rich_text"][0]["text"]["content"]


def test_generic_signal_without_hub_payload():
    sig = json.loads(json.dumps(HUB_SIGNAL))
    sig["payload"] = {"raw": "x"}
    props = notion_sink.build_properties(sig)
    assert props["Strategy"] == {"select": {"name": "ZEC_G4"}}
    assert "Action" not in props and "Bar date" not in props


def test_log_signal_posts_to_database(monkeypatch, notion_calls):
    monkeypatch.setenv("NOTION_TOKEN", "secret-test")
    monkeypatch.setenv("NOTION_SIGNALS_DB", "db123")
    assert notion_sink.log_signal(HUB_SIGNAL) is True
    call = notion_calls[0]
    assert call["url"] == notion_sink.NOTION_URL
    assert call["body"]["parent"] == {"database_id": "db123"}
    assert call["headers"]["Authorization"] == "Bearer secret-test"
    assert call["headers"]["Notion-Version"] == notion_sink.NOTION_VERSION


def test_notion_error_is_swallowed(monkeypatch):
    monkeypatch.setenv("NOTION_TOKEN", "secret-test")
    monkeypatch.setenv("NOTION_SIGNALS_DB", "db123")
    monkeypatch.setattr(notion_sink.requests, "post", lambda *a, **k: _Resp(400, "bad"))
    assert notion_sink.log_signal(HUB_SIGNAL) is False


def test_endpoint_accepts_hub_signal_and_writes_notion(monkeypatch, notion_calls, tmp_path):
    monkeypatch.setenv("NOTION_TOKEN", "secret-test")
    monkeypatch.setenv("NOTION_SIGNALS_DB", "db123")
    monkeypatch.delenv("AMPLITUDE_API_KEY", raising=False)
    monkeypatch.setattr(app_main, "SIGNALS_DIR", tmp_path)
    subs = tmp_path / "subs.json"
    subs.write_text("[]")
    monkeypatch.setattr(app_main, "SUBS_FILE", subs)

    r = TestClient(app_main.app).post("/api/signals", json=HUB_SIGNAL)
    assert r.status_code == 200, r.text
    assert len(notion_calls) == 1
    assert notion_calls[0]["body"]["properties"]["Action"] == {"select": {"name": "entry"}}
    saved = json.loads((tmp_path / "G4-US500z-20260929-entry.json").read_text())
    assert saved["payload"]["strategy"] == "G4"
