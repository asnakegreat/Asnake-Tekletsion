"""Amplitude usage tracking for Signal Scanner Pro (server side).

Sends events to Amplitude's HTTP V2 API using `requests` (already a dependency).
Tracking is OFF unless AMPLITUDE_API_KEY is set, and a failed send never breaks
the request that triggered it.

Env:
  AMPLITUDE_API_KEY     project API key (never commit it)
  AMPLITUDE_SERVER_URL  optional, defaults to the US endpoint; use
                        https://api.eu.amplitude.com/2/httpapi for EU data residency

Privacy: never pass passwords, broker logins, account numbers, balances,
tokens or emails as properties. User ids are hashed before sending.
"""
from __future__ import annotations

import hashlib
import logging
import os
import threading
import time
from typing import Any, Optional

import requests

log = logging.getLogger(__name__)

DEFAULT_URL = "https://api2.amplitude.com/2/httpapi"
DEVICE_ID = "signal-scanner-server"
TIMEOUT_SEC = 5

# Property names that must never leave the server.
_BLOCKED_KEYS = {"password", "token", "api_key", "secret", "balance", "account", "login", "email"}


def enabled() -> bool:
    return bool(os.getenv("AMPLITUDE_API_KEY"))


def _hash_id(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:32]


def _clean(props: dict[str, Any]) -> dict[str, Any]:
    return {
        k: v
        for k, v in props.items()
        if v is not None and not any(b in k.lower() for b in _BLOCKED_KEYS)
    }


def build_event(event_type: str, props: Optional[dict[str, Any]] = None,
                user_id: Optional[str] = None) -> dict[str, Any]:
    event: dict[str, Any] = {
        "event_type": event_type,
        "device_id": DEVICE_ID,
        "time": int(time.time() * 1000),
        "event_properties": _clean(props or {}),
    }
    if user_id:
        event["user_id"] = _hash_id(user_id)
    return event


def track(event_type: str, props: Optional[dict[str, Any]] = None,
          user_id: Optional[str] = None) -> bool:
    """Send one event. Returns True if Amplitude accepted it; never raises."""
    api_key = os.getenv("AMPLITUDE_API_KEY")
    if not api_key:
        return False
    url = os.getenv("AMPLITUDE_SERVER_URL", DEFAULT_URL)
    body = {"api_key": api_key, "events": [build_event(event_type, props, user_id)]}
    try:
        resp = requests.post(url, json=body, timeout=TIMEOUT_SEC)
        if resp.status_code != 200:
            log.warning("amplitude: %s rejected with HTTP %s", event_type, resp.status_code)
            return False
        return True
    except Exception as exc:  # network errors must not affect the API
        log.warning("amplitude: %s not sent (%s)", event_type, exc)
        return False


def track_async(event_type: str, props: Optional[dict[str, Any]] = None,
                user_id: Optional[str] = None) -> None:
    """Fire-and-forget on a daemon thread; use where FastAPI BackgroundTasks won't run
    (e.g. just before raising HTTPException)."""
    if not enabled():
        return
    threading.Thread(target=track, args=(event_type, props, user_id), daemon=True).start()
