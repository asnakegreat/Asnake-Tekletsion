import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import analytics
from app import main as app_main


class _Resp:
    def __init__(self, status_code=200):
        self.status_code = status_code


@pytest.fixture
def sent(monkeypatch):
    """Capture Amplitude POSTs instead of hitting the network."""
    calls = []

    def fake_post(url, json=None, timeout=None):
        calls.append({"url": url, "body": json})
        return _Resp(200)

    monkeypatch.setattr(analytics.requests, "post", fake_post)
    return calls


def test_disabled_without_api_key(monkeypatch, sent):
    monkeypatch.delenv("AMPLITUDE_API_KEY", raising=False)
    assert analytics.enabled() is False
    assert analytics.track("Signal Received", {"pair": "XAUUSD"}) is False
    assert sent == []


def test_track_sends_event(monkeypatch, sent):
    monkeypatch.setenv("AMPLITUDE_API_KEY", "test-key")
    assert analytics.track("Signal Received", {"pair": "XAUUSD", "confidence": 0.7}) is True
    body = sent[0]["body"]
    assert sent[0]["url"] == analytics.DEFAULT_URL
    assert body["api_key"] == "test-key"
    ev = body["events"][0]
    assert ev["event_type"] == "Signal Received"
    assert ev["device_id"] == analytics.DEVICE_ID
    assert ev["event_properties"] == {"pair": "XAUUSD", "confidence": 0.7}


def test_sensitive_props_and_raw_user_id_never_sent(monkeypatch, sent):
    monkeypatch.setenv("AMPLITUDE_API_KEY", "test-key")
    analytics.track("X", {"pair": "EURUSD", "account_balance": 5000, "bot_token": "t",
                          "user_email": "a@b.c", "empty": None}, user_id="user-42")
    ev = sent[0]["body"]["events"][0]
    assert ev["event_properties"] == {"pair": "EURUSD"}
    assert ev["user_id"] != "user-42" and len(ev["user_id"]) == 32


def test_network_error_is_swallowed(monkeypatch):
    monkeypatch.setenv("AMPLITUDE_API_KEY", "test-key")

    def boom(*a, **k):
        raise ConnectionError("offline")

    monkeypatch.setattr(analytics.requests, "post", boom)
    assert analytics.track("Signal Received") is False


def test_endpoints_emit_events(monkeypatch, sent, tmp_path):
    monkeypatch.setenv("AMPLITUDE_API_KEY", "test-key")
    monkeypatch.setattr(app_main, "SIGNALS_DIR", tmp_path)
    subs = tmp_path / "subs.json"
    subs.write_text("[]")
    monkeypatch.setattr(app_main, "SUBS_FILE", subs)
    monkeypatch.setattr(app_main, "send_alert", lambda *a, **k: True)
    client = TestClient(app_main.app)

    r = client.post("/api/subscribe", json={"user_id": "u1", "channel": "telegram",
                                            "filters": {"pair": "XAUUSD"}})
    assert r.status_code == 200

    signal = json.loads((Path(__file__).resolve().parents[1] / "signal.json").read_text())
    r = client.post("/api/signals", json=signal)
    assert r.status_code == 200

    names = [c["body"]["events"][0]["event_type"] for c in sent]
    assert names == ["Subscription Created", "Signal Received"]
    sub_ev = sent[0]["body"]["events"][0]
    assert sub_ev["event_properties"] == {"channel": "telegram", "has_pair_filter": True,
                                          "has_confidence_filter": False}
    assert sub_ev["user_id"] != "u1"
