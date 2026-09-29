#!/usr/bin/env python3
"""
paict_news.py — PAICT local news-sentiment engine (roadmap V17.00, stdlib only)

Turns headlines that YOU paste into a local inbox folder into per-symbol bias
events on the local bridge. 100% offline: Python standard library only
(urllib.request, json, argparse, pathlib, hashlib + csv/re/os/sys/time).
NO RSS fetching, NO scraping, NO cloud, NO auto-trading — you curate the
headlines, this script only scores them and posts the bias to 127.0.0.1.

Inbox (default ./newsinbox — auto-created with a README.txt on first run):
  *.txt  one item per line:
             YYYY.MM.DD HH:MM | USD | Fed delivers surprise rate hike
             YYYY.MM.DD HH:MM | ECB trims growth forecast
         (currency column optional; when missing it is detected from the
         title: USD EUR GBP JPY AUD NZD CAD CHF XAU/GOLD OIL/WTI/BRENT
         SP500/SPX US10Y/TREASURY; if still none, the line is skipped)
  *.csv  header line "time,currency,title", then one row per headline
  Malformed lines are skipped and counted — never fatal.

Scoring (built-in lexicons below — edit them freely, weights 10-25):
  HAWKISH  +   rate hike, hawkish, raise rates, tighten, hotter inflation,
               beats expectations, strong jobs, wage growth, ...
  DOVISH   -   rate cut, dovish, ease, stimulus, recession, misses
               expectations, weak jobs, softer inflation, ...
  RISK-OFF -   war, invasion, crisis, default, contagion, panic, crash,
               safe haven, ...
  RISK-ON  +   rally, optimism, record high, risk appetite, boom, ...
  score = signed sum, clamped to +/-100. Matching is case-insensitive with
  word boundaries; a phrase fully contained in a longer matched phrase is
  counted once (so "rate hike" does not also add "hike"). |score| < 20 is
  treated as noise -> no event.

Bias direction (score > 0 = the currency in question STRENGTHENS):
  events are emitted per the symbol map, e.g. USD-hawkish ->
  EURUSD/GBPUSD/AUDUSD/XAUUSD biasDir -1, USDJPY/USDCHF biasDir +1.
  USD-dovish flips every sign (XAUUSD turns +1: weak USD lifts gold).
  The default map covers USD EUR GBP JPY AUD CAD XAU OIL; CHF/NZD are
  tagged but unmapped until you pass --map (JSON, replaces the table).

Closed loop with the EA + bridge (everything stays on your machine):
  this script POSTs /v1/news -> the EA (V17+) polls it like /v1/poll,
  correlates the headline with how price actually reacted in its own
  journal, and the chart HUD flashes e.g. "HIGH PROBABILITY SHORT BIAS"
  while a fresh USD-hawkish event is live on that symbol|timeframe slot.
  Nothing is ever executed automatically — EA/dashboard surface it, the
  human decides.

State: <inbox>/.paict_news_seen.json stores the sha1 of every processed
(file, line-index) so re-runs never double-send; delete the file to
reprocess everything. Each event carries a content id (sha1 of the line,
12 hex chars) so the bridge can dedupe re-deliveries too. If a POST fails
the line is left un-marked and retried next cycle.

Usage:
    python paict_news.py                          # watch ./newsinbox every 30 s
    python paict_news.py --once --dry-run         # preview everything it would send
    python paict_news.py --inbox "C:\\MT5\\newsinbox" --tf M15
    python paict_news.py --map "{\"USD\": [[\"EURUSD\", -1], [\"USDJPY\", 1]]}"
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

# ---------------------------------------------------------------------------
# tunables
# ---------------------------------------------------------------------------
NOISE_FLOOR = 20          # |score| below this = headline noise, no event
SCORE_CLAMP = 100         # headline score clamped to +/-SCORE_CLAMP
HEADLINE_MAX = 140        # headline truncation inside the event payload
HTTP_TIMEOUT = 5          # seconds for the bridge POST
STATE_NAME = ".paict_news_seen.json"
README_NAME = "README.txt"

# ---------------------------------------------------------------------------
# built-in lexicon — edit freely; weights 10..25, sign = direction
# ---------------------------------------------------------------------------
LEXICONS: dict[str, list[tuple[str, int]]] = {
    "HAWKISH": [
        ("rate hike", 22), ("rate hikes", 22), ("hike", 12), ("hikes", 14),
        ("hawkish", 20), ("raise rates", 20), ("raises rates", 20),
        ("rate rise", 18), ("tighten", 18), ("tightening", 15),
        ("hotter inflation", 25), ("hot inflation", 22), ("inflation beats", 20),
        ("beats expectations", 18), ("strong jobs", 22), ("wage growth", 18),
        ("above forecast", 15), ("higher for longer", 20),
    ],
    "DOVISH": [
        ("rate cut", 22), ("rate cuts", 22), ("cut", 12), ("cuts", 14),
        ("cuts rates", 20), ("dovish", 20), ("ease", 15), ("eases", 15),
        ("stimulus", 15), ("recession", 22), ("misses expectations", 18),
        ("weak jobs", 22), ("softer inflation", 18), ("below forecast", 15),
        ("slowdown", 15),
    ],
    "RISK_OFF": [
        ("war", 20), ("invasion", 25), ("crisis", 22), ("default", 18),
        ("contagion", 22), ("panic", 20), ("crash", 22), ("safe haven", 15),
        ("plunge", 15), ("slump", 12), ("tumble", 12),
    ],
    "RISK_ON": [
        ("rally", 15), ("rallies", 15), ("optimism", 15), ("record high", 20),
        ("risk appetite", 18), ("boom", 15), ("surge", 15), ("surges", 15),
        ("soars", 18), ("rebound", 12),
    ],
}

# sign applied per category — LEXICONS above stores every weight as a
# positive magnitude; DOVISH/RISK_OFF matches must SUBTRACT from the score.
LEXICON_SIGN: dict[str, int] = {"HAWKISH": 1, "DOVISH": -1, "RISK_OFF": -1, "RISK_ON": 1}

# ---------------------------------------------------------------------------
# currency tagging + default symbol map (--map replaces the WHOLE table)
# ---------------------------------------------------------------------------
CANON_CURRENCY = {"GOLD": "XAU", "WTI": "OIL", "BRENT": "OIL", "OIL": "OIL",
                  "SP500": "SP500", "SPX": "SP500", "US10Y": "US10Y",
                  "TREASURY": "US10Y"}
CURRENCY_RE = re.compile(
    r"\b(USD|EUR|GBP|JPY|AUD|NZD|CAD|CHF|XAU|GOLD|OIL|WTI|BRENT|SP500|SPX|US10Y|TREASURY)\b")

DEFAULT_SYMBOL_MAP: dict[str, list[tuple[str, int]]] = {
    "USD": [("EURUSD", -1), ("GBPUSD", -1), ("AUDUSD", -1),
            ("USDJPY", +1), ("USDCHF", +1), ("XAUUSD", -1)],
    "EUR": [("EURUSD", +1), ("EURJPY", +1)],
    "GBP": [("GBPUSD", +1), ("EURGBP", -1)],
    "JPY": [("USDJPY", -1), ("EURJPY", -1)],
    "AUD": [("AUDUSD", +1)],
    "CAD": [("USDCAD", -1)],
    "XAU": [("XAUUSD", +1)],
    "OIL": [("USDCAD", -1)],
}

TIME_RE = re.compile(r"^\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}$")


# ---------------------------------------------------------------------------
# scoring + tagging (pure functions, no I/O — easy to test)
# ---------------------------------------------------------------------------
def tag_currencies(title: str) -> list[str]:
    """All canonical currencies mentioned in the title, in order of appearance."""
    found: list[str] = []
    for m in CURRENCY_RE.finditer(title.upper()):
        cur = CANON_CURRENCY.get(m.group(1), m.group(1))
        if cur not in found:
            found.append(cur)
    return found


def score_headline(title: str) -> tuple[int, list[str]]:
    """Signed lexicon score for one headline, clamped to +/-SCORE_CLAMP.
    Returns (score, matched phrases). Word-boundary matching; phrases fully
    contained in another matched phrase are dropped so 'rate hike' does not
    also add 'hike'."""
    low = title.lower()
    hits: list[tuple[str, int]] = []
    for category, terms in LEXICONS.items():
        sign = LEXICON_SIGN[category]
        for phrase, weight in terms:
            if re.search(rf"\b{re.escape(phrase)}\b", low):
                hits.append((phrase, sign * weight))
    final = [h for h in hits
             if not any(h[0] != other[0] and h[0] in other[0] for other in hits)]
    score = max(-SCORE_CLAMP, min(SCORE_CLAMP, sum(w for _, w in final)))
    return score, [p for p, _ in final]


def build_events(rec: dict, score: int, symbol_map: dict[str, list[tuple[str, int]]],
                 tf: str) -> list[dict]:
    """One line -> the POST payloads for every mapped symbol (may be empty:
    noise floor, unknown currency, or no map entry)."""
    if abs(score) < NOISE_FLOOR:
        return []
    currency = rec["currency"] or (rec["tags"][0] if rec["tags"] else "")
    pairs = symbol_map.get(currency)
    if not currency or not pairs:
        return []
    direction = 1 if score > 0 else -1
    payloads: list[dict] = []
    for symbol, sign in pairs:
        payloads.append({
            "slot": f"{symbol}|{tf}".upper(),
            "event": {
                "id": rec["sha"][:12],          # sha1 of the raw line = stable id
                "biasDir": sign * direction,    # sign * (hawkish=+1/dovish=-1)
                "score": score,
                "headline": rec["title"][:HEADLINE_MAX],
                "tags": rec["tags"],
                "at": rec["at"],
            },
        })
    return payloads


# ---------------------------------------------------------------------------
# inbox parsing
# ---------------------------------------------------------------------------
def parse_txt_line(line: str) -> dict | None:
    """'YYYY.MM.DD HH:MM | CURRENCY | Title' (currency optional) -> record."""
    parts = [p.strip() for p in line.split("|")]
    if len(parts) == 3:
        when, currency, title = parts
    elif len(parts) == 2:
        when, currency, title = parts[0], "", parts[1]
    else:
        return None
    if not TIME_RE.match(when) or not title:
        return None
    return {"at": when, "currency": currency.upper(), "title": title}


def read_records(inbox: Path) -> tuple[list[dict], int]:
    """Parse every *.txt / *.csv in the inbox. Returns (records, malformed).
    Each record: key (file#line), sha (of the raw line), at, currency, title,
    tags."""
    records: list[dict] = []
    malformed = 0
    paths = sorted(list(inbox.glob("*.txt")) + list(inbox.glob("*.csv")))
    for path in paths:
        try:
            if path.suffix.lower() == ".csv":
                with path.open(newline="", encoding="utf-8", errors="replace") as fh:
                    for i, row in enumerate(csv.DictReader(fh), start=1):
                        when = (row.get("time") or "").strip()
                        currency = (row.get("currency") or "").strip().upper()
                        title = (row.get("title") or "").strip()
                        if not TIME_RE.match(when) or not title:
                            malformed += 1
                            continue
                        raw = f"{when}|{currency}|{title}"
                        records.append({"key": f"{path.name}#{i}", "sha": _sha1(raw),
                                        "at": when, "currency": currency,
                                        "title": title, "tags": []})
            else:
                lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
                for i, line in enumerate(lines, start=1):
                    stripped = line.strip()
                    if not stripped:
                        continue
                    rec = parse_txt_line(stripped)
                    if rec is None:
                        malformed += 1
                        continue
                    rec["key"] = f"{path.name}#{i}"
                    rec["sha"] = _sha1(stripped)
                    rec["tags"] = []
                    records.append(rec)
        except OSError as exc:
            print(f"[news] WARN cannot read {path}: {exc}")
    for rec in records:
        if not rec["tags"]:
            rec["tags"] = tag_currencies(rec["title"])
        if rec["currency"] and rec["currency"] not in rec["tags"]:
            rec["tags"] = [rec["currency"]] + rec["tags"]
    return records, malformed


def _sha1(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8", errors="replace")).hexdigest()


# ---------------------------------------------------------------------------
# state + bridge POST
# ---------------------------------------------------------------------------
def load_state(path: Path) -> dict:
    try:
        with path.open(encoding="utf-8") as fh:
            st = json.load(fh)
        if isinstance(st, dict) and isinstance(st.get("seen"), dict):
            return st
    except (OSError, json.JSONDecodeError):
        pass
    return {"version": 1, "seen": {}}


def save_state(path: Path, state: dict) -> None:
    try:
        path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
    except OSError as exc:
        print(f"[news] WARN cannot write state {path}: {exc}")


def post_event(bridge: str, payload: dict, dry: bool) -> bool:
    """One POST via urllib (stdlib). Returns True on success / dry-run;
    failures print ONE warning line and never raise."""
    if dry:
        print("[news:dry] " + json.dumps(payload, ensure_ascii=False))
        return True
    try:
        req = urllib.request.Request(
            f"{bridge.rstrip('/')}/v1/news",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST")
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            ok = 200 <= resp.status < 300
    except OSError as exc:                # URLError/HTTPError/socket timeout
        print(f"[news] WARN bridge unreachable ({bridge}): {exc}")
        return False
    if ok:
        ev = payload["event"]
        print(f"[news] {payload['slot']} <- bias {ev['biasDir']:+d} "
              f"score {ev['score']:+d} id={ev['id']}")
        return True
    print(f"[news] WARN bridge rejected the event (non-2xx)")
    return False


# ---------------------------------------------------------------------------
# one pass over the inbox
# ---------------------------------------------------------------------------
def run_pass(inbox: Path, bridge: str, tf: str, symbol_map: dict,
             state_path: Path, dry: bool, verbose: bool) -> None:
    records, malformed = read_records(inbox)
    state = load_state(state_path)
    new = events = sent = failed = 0
    for rec in records:
        if state["seen"].get(rec["key"]) == rec["sha"]:
            continue                       # (file, line) already processed
        state["seen"][rec["key"]] = rec["sha"]   # provisional; reverted on failure
        new += 1
        score, hits = score_headline(rec["title"])
        if verbose:
            print(f"[news] {rec['key']}: score {score:+d} {hits or '-'} "
                  f"| {rec['title'][:60]}")
        payloads = build_events(rec, score, symbol_map, tf)
        if not payloads:
            if verbose:
                why = (f"|score| < {NOISE_FLOOR}" if abs(score) < NOISE_FLOOR
                       else "no currency / no symbol-map entry")
                print(f"[news] {rec['key']}: no event ({why})")
            continue
        line_failed = False
        for payload in payloads:
            if post_event(bridge, payload, dry):
                events += 1
                sent += 1
            else:
                failed += 1
                line_failed = True
        if line_failed:
            state["seen"].pop(rec["key"], None)   # retry the whole line next pass
    save_state(state_path, state)
    print(f"[news] pass: lines={len(records)} malformed={malformed} "
          f"already-seen={len(records) - new} new={new} events={events} "
          f"sent={sent} failed={failed}")


def ensure_inbox(inbox: Path) -> None:
    """Create the inbox + a README.txt explaining the format on first run."""
    if inbox.is_dir():
        return
    inbox.mkdir(parents=True, exist_ok=True)
    print(f"[news] created inbox: {inbox}")
    (inbox / README_NAME).write_text(
        "PAICT news inbox — drop headlines here as *.txt or *.csv.\n"
        "\n"
        "*.txt, one item per line:\n"
        "    YYYY.MM.DD HH:MM | USD | Fed delivers surprise rate hike\n"
        "    YYYY.MM.DD HH:MM | ECB trims growth forecast\n"
        "(currency column optional — when missing it is detected from the title:\n"
        "USD EUR GBP JPY AUD NZD CAD CHF XAU/GOLD OIL/WTI/BRENT SP500/SPX US10Y/TREASURY)\n"
        "\n"
        "*.csv: header line 'time,currency,title', then one row per headline.\n"
        "\n"
        "Everything stays LOCAL: paict_news.py scores each headline with its\n"
        "built-in lexicon and POSTs bias events to your local bridge\n"
        "(127.0.0.1:8891) for the EA's HUD. No RSS, no scraping, no cloud —\n"
        "YOU pick the headlines, the script only scores them.\n"
        "\n"
        "Delete .paict_news_seen.json in this folder to reprocess everything.\n",
        encoding="utf-8")


def parse_map(text: str) -> dict[str, list[tuple[str, int]]]:
    """--map JSON string -> {CURRENCY: [(SYMBOL, +/-1), ...]} (replaces the
    whole default table). Exits 2 with a clear message when invalid."""
    try:
        raw = json.loads(text)
    except json.JSONDecodeError as exc:
        print(f"[news] --map is not valid JSON: {exc}")
        sys.exit(2)
    if not isinstance(raw, dict) or not raw:
        print("[news] --map must be a JSON object like "
              '{"USD": [["EURUSD", -1], ["USDJPY", 1]]}')
        sys.exit(2)
    out: dict[str, list[tuple[str, int]]] = {}
    for currency, pairs in raw.items():
        entries: list[tuple[str, int]] = []
        for pair in pairs:
            try:
                symbol, sign = str(pair[0]).upper(), int(pair[1])
            except (TypeError, ValueError, IndexError):
                print(f"[news] --map entry {pair!r} is not [SYMBOL, +/-1]")
                sys.exit(2)
            if sign not in (-1, 1):
                print(f"[news] --map sign for {symbol} must be -1 or +1")
                sys.exit(2)
            entries.append((symbol, sign))
        out[str(currency).upper()] = entries
    return out


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        prog="paict_news.py",
        description="PAICT V17 local news-sentiment engine — scores headlines you "
                    "paste into an inbox folder and POSTs per-symbol bias events to "
                    "the local bridge. Stdlib only, zero cloud, zero auto-trading.")
    ap.add_argument("--inbox", default="./newsinbox",
                    help="headline inbox folder (default %(default)s, auto-created)")
    ap.add_argument("--bridge", default="http://127.0.0.1:8891",
                    help="local bridge base URL (default %(default)s)")
    ap.add_argument("--tf", default="M15",
                    help="timeframe used in every slot (default %(default)s)")
    ap.add_argument("--once", action="store_true",
                    help="run one pass over the inbox and exit")
    ap.add_argument("--interval", type=int, default=30,
                    help="watch-loop sleep in seconds (default %(default)s)")
    ap.add_argument("--map", default=None,
                    help='currency->symbol map as JSON, e.g. '
                         '\'{"USD": [["EURUSD", -1], ["USDJPY", 1]]}\' '
                         "(replaces the built-in table)")
    ap.add_argument("--dry-run", action="store_true",
                    help="print every JSON that would be POSTed, send nothing "
                         "(still marks lines seen — delete the state file to redo)")
    ap.add_argument("--verbose", action="store_true",
                    help="per-headline scores and skip reasons")
    ap.add_argument("--state", default=None,
                    help="seen-state file (default <inbox>/.paict_news_seen.json)")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    if args.interval < 1:
        print("[news] --interval must be >= 1 second")
        return 2
    symbol_map = parse_map(args.map) if args.map else DEFAULT_SYMBOL_MAP
    inbox = Path(args.inbox).expanduser()
    ensure_inbox(inbox)
    state_path = (Path(args.state).expanduser() if args.state
                  else inbox / STATE_NAME)
    bridge = args.bridge.rstrip("/")
    print(f"[news] inbox {inbox} -> {bridge}/v1/news slot tf={args.tf} every "
          f"{args.interval}s{' (DRY-RUN)' if args.dry_run else ''} — ctrl-C to stop")
    if args.once:
        run_pass(inbox, bridge, args.tf, symbol_map, state_path,
                 args.dry_run, args.verbose)
        return 0
    try:
        while True:
            run_pass(inbox, bridge, args.tf, symbol_map, state_path,
                     args.dry_run, args.verbose)
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("[news] stopped (ctrl-C)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
