"""Write each received signal to a Notion database (optional).

Off unless both env vars are set:
  NOTION_TOKEN        internal integration secret (notion.so/my-integrations);
                      the database must be shared with that integration
  NOTION_SIGNALS_DB   id of the "Live Signals" database

A failed write never affects the API response. Uses `requests`.
"""
from __future__ import annotations

import logging
import os
from typing import Any

import requests

log = logging.getLogger(__name__)

NOTION_URL = "https://api.notion.com/v1/pages"
NOTION_VERSION = "2022-06-28"
TIMEOUT_SEC = 10


def enabled() -> bool:
    return bool(os.getenv("NOTION_TOKEN") and os.getenv("NOTION_SIGNALS_DB"))


def _text(value: Any) -> list[dict[str, Any]]:
    return [{"type": "text", "text": {"content": str(value)[:2000]}}]


def build_properties(signal: dict[str, Any]) -> dict[str, Any]:
    payload = signal.get("payload") or {}
    props: dict[str, Any] = {
        "Signal": {"title": _text(signal["signal_id"])},
        "Symbol": {"rich_text": _text(signal.get("pair", ""))},
        "Direction": {"select": {"name": signal.get("direction", "long")}},
        "Strategy": {"select": {"name": str(payload.get("strategy") or signal.get("engine", "other"))[:100]}},
        "Late": {"checkbox": bool(payload.get("late", False))},
    }
    if payload.get("action"):
        props["Action"] = {"select": {"name": str(payload["action"])}}
    if payload.get("reason"):
        props["Reason"] = {"rich_text": _text(payload["reason"])}
    bar_date = str(payload.get("bar_date") or "").replace(".", "-")
    if len(bar_date) == 10:
        props["Bar date"] = {"date": {"start": bar_date}}
    if signal.get("execution_price") is not None:
        props["Price"] = {"number": float(signal["execution_price"])}
    if signal.get("sl") is not None:
        props["Stop"] = {"number": float(signal["sl"])}
    return props


def log_signal(signal: dict[str, Any]) -> bool:
    """Create one page in the Live Signals database. Returns True on success; never raises."""
    token = os.getenv("NOTION_TOKEN")
    db = os.getenv("NOTION_SIGNALS_DB")
    if not (token and db):
        return False
    headers = {
        "Authorization": f"Bearer {token}",
        "Notion-Version": NOTION_VERSION,
        "Content-Type": "application/json",
    }
    body = {"parent": {"database_id": db}, "properties": build_properties(signal)}
    try:
        resp = requests.post(NOTION_URL, json=body, headers=headers, timeout=TIMEOUT_SEC)
        if resp.status_code != 200:
            log.warning("notion: %s rejected with HTTP %s: %s",
                        signal.get("signal_id"), resp.status_code, resp.text[:300])
            return False
        return True
    except Exception as exc:
        log.warning("notion: %s not written (%s)", signal.get("signal_id"), exc)
        return False
