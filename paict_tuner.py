#!/usr/bin/env python3
"""
paict_tuner.py — PAICT local tuner (roadmap V5.00 "Local AI Analysis Desk")

Reads, entirely LOCALLY (no network, no cloud):
  1. MQL5\\Files\\PAICT_TradeJournal_<SYMBOL>.csv   written by the EA's
     OnTrade auto-journal (one row per manual close, with the plan context
     entry/stop/target/RR that was live at close time)
  2. the newest MQL5\\Files\\PAICT_<symbol>_<tf>.json snapshot(s),
     if InpExportJSON is enabled

...and writes:
  MQL5\\Files\\PAICT_TunerSuggestion.txt

The EA (v5.00+) reads that file (whitelisted KEY=VALUE lines), shows the
suggestions on its chart HUD and pushes them in the matrix payload. APPLYING
them stays a human decision: type the values into the EA input dialog, or
queue a SET_RISK command from the dashboard. Nothing is applied automatically.

Usage (run inside the terminal's MQL5\\Files folder, or pass --files DIR):
    python paict_tuner.py
    python paict_tuner.py --files "C:\\...\\MQL5\\Files" --symbol XAUUSDz

Suggestion logic (deliberately simple, explainable statistics — not magic):
  * RISK_PERCENT
      - win rate < 40% over the last 20 closed trades  -> suggest 0.5
      - win rate > 55% and avg profit > 0              -> suggest 1.5
      - otherwise echo the EA's current risk input if found in a snapshot
  * ZONE_TOLERANCE / PLAN_ZONE_HEIGHT / STOP_BUFFER
      - correlate stop-outs with the plan geometry recorded at close time:
        if most losers had RR < 1, suggest a wider stop buffer; if most
        winners had RR >= 2, keep the geometry and just say so in NOTE.
The tuner NEVER suggests leverage, martingale or automation — the EA stays
zero-auto-trading by design.
"""

from __future__ import annotations

import argparse
import csv
import glob
import json
import os
import sys
from collections import deque

JOURNAL_GLOB = "PAICT_TradeJournal_*.csv"
SNAPSHOT_GLOB = "PAICT_*_*.json"
SUGGESTION_NAME = "PAICT_TunerSuggestion.txt"
WINDOW = 20  # trades considered (most recent)


def load_trades(files_dir: str, symbol: str | None) -> list[dict]:
    rows: list[dict] = []
    for path in sorted(glob.glob(os.path.join(files_dir, JOURNAL_GLOB))):
        sym = os.path.basename(path)[len("PAICT_TradeJournal_"):-len(".csv")]
        if symbol and sym.upper() != symbol.upper():
            continue
        try:
            with open(path, newline="", encoding="utf-8", errors="replace") as fh:
                for row in csv.DictReader(fh):
                    try:
                        rows.append({
                            "time": row.get("time", ""),
                            "symbol": row.get("symbol", sym),
                            "side": row.get("side", ""),
                            "profit": float(row.get("profit", "0") or 0),
                            "rr": float(row.get("planRR", "0") or 0),
                            "had_plan": float(row.get("planEntry", "0") or 0) > 0,
                        })
                    except ValueError:
                        continue  # header or partial row
        except OSError as exc:
            print(f"[tuner] cannot read {path}: {exc}", file=sys.stderr)
    rows.sort(key=lambda r: r["time"])
    return rows


def latest_snapshot(files_dir: str) -> dict:
    snaps = sorted(glob.glob(os.path.join(files_dir, SNAPSHOT_GLOB)),
                   key=os.path.getmtime)
    for path in reversed(snaps):
        if "TradeJournal" in path or "TunerSuggestion" in path:
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                return json.load(fh)
        except (OSError, json.JSONDecodeError):
            continue
    return {}


def suggest(trades: list[dict], snapshot: dict) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    recent = trades[-WINDOW:]

    # --- RISK_PERCENT ---------------------------------------------------
    current_risk = ""
    try:
        # the EA journal rows do not carry the risk input; the dashboard's
        # last matrix push (mirrored into snapshots) does
        current_risk = str(snapshot.get("riskPct", ""))
    except Exception:
        current_risk = ""
    if len(recent) >= 10:
        wins = sum(1 for t in recent if t["profit"] > 0)
        win_rate = wins / len(recent)
        avg = sum(t["profit"] for t in recent) / len(recent)
        if win_rate < 0.40 and avg < 0:
            out.append(("RISK_PERCENT", "0.5"))
            out.append(("NOTE", f"win {win_rate:.0%} over {len(recent)} — risk halved"))
        elif win_rate > 0.55 and avg > 0:
            out.append(("RISK_PERCENT", "1.5"))
            out.append(("NOTE", f"win {win_rate:.0%} over {len(recent)} — risk up"))
        else:
            if current_risk:
                out.append(("RISK_PERCENT", current_risk))
            out.append(("NOTE", f"win {win_rate:.0%} — keep risk"))

    # --- geometry: stop-outs vs planned R:R -----------------------------
    with_plan = [t for t in recent if t["had_plan"]]
    if len(with_plan) >= 6:
        losers = [t for t in with_plan if t["profit"] < 0]
        if len(losers) >= max(3, len(with_plan) // 2):
            low_rr_losers = sum(1 for t in losers if t["rr"] > 0 and t["rr"] < 1.5)
            if low_rr_losers >= len(losers) // 2:
                out.append(("PLAN_ZONE_HEIGHT", "0.30"))
                out.append(("NOTE", "losers planned < 1.5R — widen bands/stop"))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="PAICT local tuner (V5.00)")
    ap.add_argument("--files", default=".", help="MQL5\\Files directory")
    ap.add_argument("--symbol", default=None, help="restrict to one symbol")
    args = ap.parse_args()

    files_dir = os.path.abspath(args.files)
    if not os.path.isdir(files_dir):
        print(f"[tuner] not a directory: {files_dir}", file=sys.stderr)
        return 2

    trades = load_trades(files_dir, args.symbol)
    snapshot = latest_snapshot(files_dir)
    pairs = suggest(trades, snapshot)

    out_path = os.path.join(files_dir, SUGGESTION_NAME)
    with open(out_path, "w", encoding="utf-8") as fh:
        if pairs:
            for key, val in pairs:
                fh.write(f"{key}={val}\n")
        else:
            fh.write("")  # empty file = no suggestions; the EA clears its HUD line

    print(f"[tuner] journals: {len(trades)} trades · suggestions: {len(pairs)}")
    for key, val in pairs:
        print(f"[tuner]   {key}={val}")
    print(f"[tuner] wrote {out_path}")
    print("[tuner] the EA shows these on its HUD — you decide whether to apply them.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
