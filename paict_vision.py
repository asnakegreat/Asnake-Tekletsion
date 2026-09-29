#!/usr/bin/env python3
"""
paict_vision.py — PAICT local chart-vision engine (roadmap V16.00, OpenCV)

Watches MQL5\\Files for the EA's chart screenshots (PAICT_VISION_<SYMBOL>_<TF>.png,
e.g. PAICT_VISION_EURUSD_H1.png — the EA saves them via ChartScreenShot on each
new bar while InpVisionShot is enabled), rebuilds a coarse candle series from
pure pixels and POSTs the detected chart patterns + wick-rejection reads to the
LOCAL bridge only:

    POST http://127.0.0.1:8891/v1/vision
         {"slot": "EURUSD|H1", "source": "paict-vision",
          "patterns": [{"name": "HEAD_AND_SHOULDERS", "conf": 89,
                        "barsAgo": 9, "dir": -1}, ...],
          "wicks":    [{"barsAgo": 0, "side": "upper", "strength": 100}, ...]}

The bridge stores the payload per slot and the EA / dashboard read it like any
other matrix-side signal. NOTHING here ever places an order — this file is a
decision-SUPPORT sensor for a human sitting at the terminal.

HONEST SCOPE — read before trusting a number:
  * Pixel-level pattern recognition is a HEURISTIC RESEARCH TOOL, not a
    textbook-certified detector. Candle geometry is reconstructed from
    foreground pixel runs; markup objects, gridlines, zoom levels, chart
    themes and nonstandard color schemes all perturb the reconstruction.
  * Peaks/troughs come from candle mid points (wick midline), not real OHLC,
    so "conf" (60-95) is a graded symmetry score, not a probability.
  * Wicks cannot know the candle color, so the close is approximated by the
    body edge FARTHEST from the wick under test — the most demanding pixel
    read (fewer, stronger signals).
  * Zero cloud, zero telemetry, zero downloads: the ONLY network call is a
    POST to your own local bridge (default 127.0.0.1:8891). If the bridge is
    down the script warns once per cycle and keeps watching. No order is
    ever placed by this script, directly or indirectly.

Pipeline (image -> candle metadata -> patterns):
  1. gray -> background estimate = median of the four 16 px corner patches
  2. foreground mask = |gray - bg| > 40; horizontal runs longer than w/50 px
     (gridlines, zone-box edges) are removed with a morphological opening
  3. foreground columns are grouped into candle bands (gap < 2 px merges);
     per band: rows >= 3 px wide = body, 1-2 px = wick
  4. filters: drop bands centered in the rightmost 3% (price-label gutter),
     noise bands < 1.5% of image height, near-full-height bands (markup /
     zone edges), thin-and-tall bands (vertical trend lines); fewer than 12
     candles -> the frame is reported as unusable and skipped
  5. candle mid = (wickTop + wickBottom) / 2, normalized so 0 = lowest price
     on the image and 1 = highest -> peaks/troughs with window k = max(3, n//12)
  6. pattern detectors (pure geometry, unit-testable WITHOUT cv2 — see
     detect_patterns): HEAD_AND_SHOULDERS (dir -1), ASCENDING_TRIANGLE
     (dir 0, breakout direction unknown), CUP_AND_HANDLE (dir +1)
  7. wick rejection: body >= 2 px and upper wick >= 2x body with the close
     proxy inside the top 30% of the last 40 candles' range -> upper-reject
     entry (strength = min(100, round(wick/body*40))); lower side mirrored

Usage (Windows, run from anywhere — paths with spaces need quotes):
    python paict_vision.py
    python paict_vision.py --dir "C:\\Users\\you\\AppData\\Roaming\\MetaQuotes\\Terminal\\<ID>\\MQL5\\Files"
    python paict_vision.py --once --dry-run --verbose
    python paict_vision.py --bridge http://127.0.0.1:8891 --interval 30

--dir probing order when omitted: every %APPDATA%\\MetaQuotes\\Terminal\\*\\MQL5\\Files
(newest first), "C:\\Program Files\\MetaTrader 5\\MQL5\\Files" (portable installs),
.\\MQL5\\Files, then the current directory. If none exists the script asks for
an explicit --dir and exits 2.

Dependencies are OPTIONAL and checked after argparse (so --help always works):
opencv-python, numpy, requests. Missing -> one-line hint -> exit code 2.
"""

from __future__ import annotations

import argparse
import glob
import os
import pprint
import re
import sys
import time

# ---------------------------------------------------------------------------
# geometry / detection constants — pixels unless noted, all in one place
# ---------------------------------------------------------------------------
FG_THRESH = 40             # |gray - bg| above this counts as foreground
CORNER_PATCH = 16          # corner patch size (px) for the background estimate
HLINE_RUN_DIV = 50         # horizontal runs > w/HLINE_RUN_DIV = gridline/box edge
GAP_MERGE_PX = 2           # foreground columns with a gap < 2 px = one candle band
BODY_W_MIN = 3             # row width > 2 px = body; 1-2 px = wick
MIN_CANDLES = 12           # fewer reconstructed candles -> frame unusable
EDGE_TRIM_FRAC = 0.03      # drop bands centered in the rightmost 3% (price labels)
MIN_BAND_H_FRAC = 0.015    # drop bands shorter than 1.5% of image height
MAX_BAND_H_FRAC = 0.92     # drop near-full-height bands (markup, zone edges)
TALL_THIN_H_FRAC = 0.50    # drop thin (<=2 px) bands taller than half the image
BAND_SPAN_MIN = 40         # max candle-band width = max(BAND_SPAN_MIN, w/BAND_SPAN_DIV)
BAND_SPAN_DIV = 30
PIVOT_WIN_MIN = 3          # peak/trough window k = max(PIVOT_WIN_MIN, n/PIVOT_WIN_DIV)
PIVOT_WIN_DIV = 12
MAX_WICK_REPORTS = 12      # cap on wick-rejection entries per POST
LOOKBACK_HI = 40           # wick-reject range window (candles)
RANGE_ZONE_FRAC = 0.30     # close proxy must sit in top/bottom 30% of that range
WICK_BODY_RATIO = 2.0      # wick must be >= 2x body
WICK_STRENGTH_K = 40       # strength = min(100, round(wick/body * K))
MIN_BODY_PX = 2            # candles with a smaller body are never wick-rejects

# pattern thresholds — fractions of the normalized full range (1.0 = the total
# visible mid-line span on the image)
HS_MIN_HEAD = 0.02         # head must rise at least 2% above the neckline
HS_SHOULDER_TOL = 0.12     # |left shoulder - right shoulder| <= 12% of head height
HS_NECK_SLOPE = 0.25       # neckline slope <= 25% of head height per bar
ASC_FLAT_TOL = 0.06        # last swing-high spread <= 6% of full range (flat top)
ASC_RISE_MIN = 0.03        # new low > previous low + 3% of full range
ASC_APEX_GAP = 0.08        # lows must sit >= 8% below the flat top (anti-apex guard)
CUP_POS_LO = 0.35          # bowl bottom must sit between 35% ...
CUP_POS_HI = 0.65          # ... and 65% of the analyzed window
CUP_RIM_TOL = 0.08         # |left rim - right rim| <= 8% of full range
CUP_DEPTH_MIN = 0.25       # rim-to-bottom depth >= 25% of full range
CUP_HANDLE_MIN = 0.05      # handle pullback >= 5% of full range in the last n/4 bars

VISION_GLOB = "PAICT_VISION_*.png"
VISION_RE = re.compile(r"^PAICT_VISION_(?P<sym>.+)_(?P<tf>[A-Za-z0-9]+)\.png$", re.IGNORECASE)
PIP_HINT = "pip install opencv-python numpy requests"

# heavy optional deps — imported AFTER argparse in ensure_deps() so --help
# always works, even on a bare Python without a single extra package
cv2 = None
np = None
requests = None


def ensure_deps() -> None:
    """Import cv2/numpy/requests or print one install hint line and exit 2."""
    global cv2, np, requests
    missing: list[str] = []
    try:
        import cv2 as _cv2
        cv2 = _cv2
    except ImportError:
        missing.append("opencv-python (cv2)")
    try:
        import numpy as _np
        np = _np
    except ImportError:
        missing.append("numpy")
    try:
        import requests as _rq
        requests = _rq
    except ImportError:
        missing.append("requests")
    if missing:
        print(f"[vision] missing dependencies: {', '.join(missing)}")
        print(f"[vision] install with: {PIP_HINT}")
        sys.exit(2)


# ---------------------------------------------------------------------------
# pure geometry (NO cv2/numpy here) — everything below is unit-testable with
# plain candle dicts: {"x", "bodyTop", "bodyBottom", "wickTop", "wickBottom"}
# (pixel y grows DOWN, so a smaller y = a higher price)
# ---------------------------------------------------------------------------
def norm_mids(candles: list[dict]) -> list[float] | None:
    """Candle wick-mid points -> price proxies normalized to 0..1 where
    0 = lowest price on the image, 1 = highest (full range = 1.0)."""
    mids = [(c["wickTop"] + c["wickBottom"]) / 2.0 for c in candles]
    lo, hi = min(mids), max(mids)
    if hi - lo < 1e-9:
        return None
    return [1.0 - (m - lo) / (hi - lo) for m in mids]


def find_pivots(vals: list[float], k: int) -> list[tuple[int, bool, float]]:
    """Peaks/troughs with a +-k window; returns a strictly ALTERNATING
    chronological list of (index, is_high, value). When two same-type pivots
    touch, the more extreme one wins (same rule as the EA's BuildPivots)."""
    n = len(vals)
    raw: list[tuple[int, bool, float]] = []
    for i in range(n):
        lo_i, hi_i = max(0, i - k), min(n - 1, i + k)
        neigh = [vals[j] for j in range(lo_i, hi_i + 1) if j != i]
        if not neigh:
            continue
        if vals[i] > max(neigh):
            raw.append((i, True, vals[i]))
        elif vals[i] < min(neigh):
            raw.append((i, False, vals[i]))
    alt: list[tuple[int, bool, float]] = []
    for idx, is_high, val in raw:
        if alt and alt[-1][1] == is_high:
            if (is_high and val >= alt[-1][2]) or (not is_high and val <= alt[-1][2]):
                alt[-1] = (idx, is_high, val)
        else:
            alt.append((idx, is_high, val))
    return alt


def _detect_hs(pivots: list[tuple[int, bool, float]], n: int) -> dict | None:
    """HEAD_AND_SHOULDERS (top) — the spec's P1<P2>P3<P4>P5 chain read in
    image-y space maps to a chronological high,low,high,low,high pivot run:
    P1=left shoulder, P3=head (highest), P5=right shoulder; the two lows are
    the neckline anchors. dir=-1 (bearish)."""
    if len(pivots) < 5:
        return None
    p = pivots[-5:]
    if [q[1] for q in p] != [True, False, True, False, True]:
        return None
    ls_i, ls = p[0][0], p[0][2]
    t1_i, t1 = p[1][0], p[1][2]
    hd_i, hd = p[2][0], p[2][2]
    t2_i, t2 = p[3][0], p[3][2]
    rs_i, rs = p[4][0], p[4][2]
    head_h = hd - max(t1, t2)
    if head_h < HS_MIN_HEAD:
        return None                       # no meaningful head above the neckline
    if not (hd > ls and hd > rs):
        return None                       # head must dominate both shoulders
    shoulder_gap = abs(ls - rs)           # "two shoulders roughly equal" <= 12%
    if shoulder_gap > HS_SHOULDER_TOL * head_h:
        return None
    if t2_i <= t1_i:
        return None
    neck_slope = abs(t2 - t1) / (t2_i - t1_i)   # per-bar slope in range units
    if neck_slope > HS_NECK_SLOPE * head_h:
        return None
    conf = 60 + int(20 * (1.0 - shoulder_gap / (HS_SHOULDER_TOL * head_h))) \
            + int(15 * (1.0 - neck_slope / (HS_NECK_SLOPE * head_h)))
    return {"name": "HEAD_AND_SHOULDERS", "conf": min(95, conf),
            "barsAgo": n - 1 - rs_i, "dir": -1}


def _detect_asc(pivots: list[tuple[int, bool, float]], n: int) -> dict | None:
    """ASCENDING_TRIANGLE — flat top (last >=2 swing highs within 6% of the
    full range) + strictly rising lows (new low > old low + 3%). The breakout
    direction is unknown from pixels alone -> dir=0. The apex guard (lows
    must still sit >= ASC_APEX_GAP below the top) keeps cups/late-stage
    wedges from masquerading as triangles."""
    highs = [(i, v) for i, h, v in pivots if h]
    lows = [(i, v) for i, h, v in pivots if not h]
    if len(highs) < 2 or len(lows) < 2:
        return None
    top = [v for _, v in highs[-3:]]      # last 3 swing highs (or 2 if only 2)
    if max(top) - min(top) > ASC_FLAT_TOL:
        return None
    (l1i, l1), (l2i, l2) = lows[-2], lows[-1]
    if not (l2 > l1 + ASC_RISE_MIN):
        return None
    if min(top) - l2 < ASC_APEX_GAP:
        return None                       # price already at the apex -> not a triangle
    conf = 60 + int(20 * (1.0 - (max(top) - min(top)) / ASC_FLAT_TOL)) \
            + int(15 * min(1.0, (l2 - l1) / (4 * ASC_RISE_MIN)))
    done_i = max(highs[-1][0], l2i)       # pattern completes at its last pivot
    return {"name": "ASCENDING_TRIANGLE", "conf": min(95, conf),
            "barsAgo": n - 1 - done_i, "dir": 0}


def _detect_cup(prices: list[float], n: int) -> dict | None:
    """CUP_AND_HANDLE — bowl bottom centered (35-65% of the window), rims
    within 8%, rim-to-bottom depth >= 25%, and a shallow (>= 5% of range)
    pullback inside the last n/4 candles = the handle. dir=+1 (bullish)."""
    if n < 20:
        return None
    lo = min(prices)
    bot_i = prices.index(lo)
    pos = bot_i / (n - 1)
    if not (CUP_POS_LO <= pos <= CUP_POS_HI):
        return None
    rim_w = max(2, n // 5)                # outer 20% windows hold the rims
    rim_l = max(prices[:rim_w])
    rim_r = max(prices[n - rim_w:])
    if abs(rim_l - rim_r) > CUP_RIM_TOL:
        return None
    depth = min(rim_l, rim_r) - lo
    if depth < CUP_DEPTH_MIN:
        return None
    hw = max(4, n // 4)                   # handle lives in the last n/4 candles
    seg = prices[n - hw:]
    peak_j = seg.index(max(seg))
    if n - hw + peak_j <= bot_i:
        return None                       # handle high must come after the bowl bottom
    if peak_j >= len(seg) - 1:
        return None                       # no room left for a pullback
    tail = seg[peak_j:]
    pull = max(tail) - min(tail)
    if pull < CUP_HANDLE_MIN:
        return None
    handle_i = n - hw + peak_j + tail.index(min(tail))
    conf = 60 + int(20 * (1.0 - abs(rim_l - rim_r) / CUP_RIM_TOL)) \
            + int(15 * min(1.0, depth / (2 * CUP_DEPTH_MIN)))
    return {"name": "CUP_AND_HANDLE", "conf": min(95, conf),
            "barsAgo": n - 1 - handle_i, "dir": +1}


def detect_patterns(candles: list[dict], img_h: int) -> list[dict]:
    """Pure pattern detection over candle metadata (no cv2). `img_h` is only
    a sanity guard (kept in the signature so the cv2 stage and this stage
    stay cleanly separated). Returns [{name, conf, barsAgo, dir}, ...]
    sorted by conf descending."""
    if img_h <= 0 or len(candles) < MIN_CANDLES:
        return []
    prices = norm_mids(candles)
    if prices is None:
        return []
    n = len(prices)
    k = max(PIVOT_WIN_MIN, n // PIVOT_WIN_DIV)
    pivots = find_pivots(prices, k)
    found: list[dict] = []
    for det in (_detect_hs(pivots, n), _detect_asc(pivots, n), _detect_cup(prices, n)):
        if det:
            found.append(det)
    found.sort(key=lambda d: -d["conf"])
    return found


def detect_wick_rejects(candles: list[dict], lookback: int = LOOKBACK_HI,
                        zone_frac: float = RANGE_ZONE_FRAC) -> list[dict]:
    """Wick-rejection reads, newest first, capped at MAX_WICK_REPORTS.
    Upper: body >= MIN_BODY_PX, upper wick >= 2x body AND the close proxy
    (body bottom — the body edge farthest from the wick, i.e. the strictest
    read since pixel data cannot tell candle color) inside the top
    `zone_frac` of the last `lookback` candles' range. Lower side mirrored.
    strength = min(100, round(wick/body * WICK_STRENGTH_K))."""
    n = len(candles)
    out: list[dict] = []
    for i in range(n - 1, -1, -1):
        if len(out) >= MAX_WICK_REPORTS:
            break
        c = candles[i]
        body = c["bodyBottom"] - c["bodyTop"]
        if body < MIN_BODY_PX:
            continue
        win = candles[max(0, i - lookback + 1):i + 1]
        ytop = min(x["wickTop"] for x in win)
        ybot = max(x["wickBottom"] for x in win)
        rng = ybot - ytop
        if rng <= 0:
            continue
        uw = c["bodyTop"] - c["wickTop"]
        lw = c["wickBottom"] - c["bodyBottom"]
        if uw >= WICK_BODY_RATIO * body and c["bodyBottom"] <= ytop + zone_frac * rng:
            out.append({"barsAgo": n - 1 - i, "side": "upper",
                        "strength": min(100, round(uw / body * WICK_STRENGTH_K))})
            if len(out) >= MAX_WICK_REPORTS:
                break
        if lw >= WICK_BODY_RATIO * body and c["bodyTop"] >= ybot - zone_frac * rng:
            out.append({"barsAgo": n - 1 - i, "side": "lower",
                        "strength": min(100, round(lw / body * WICK_STRENGTH_K))})
    return out


# ---------------------------------------------------------------------------
# cv2 stage: image -> candle metadata (the ONLY part that needs OpenCV)
# ---------------------------------------------------------------------------
def reconstruct_candles(img) -> tuple[list[dict] | None, int, int]:
    """BGR image -> (candles, img_h, img_w); candles is None when the frame
    does not contain a usable candle field (too few bands, markup-only, ...)."""
    h, w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    cs = max(2, min(CORNER_PATCH, h // 4, w // 4))
    corners = np.concatenate([
        gray[:cs, :cs].ravel(), gray[:cs, w - cs:].ravel(),
        gray[h - cs:, :cs].ravel(), gray[h - cs:, w - cs:].ravel()])
    bg = int(float(np.median(corners)))
    fg = (np.abs(gray.astype(np.int16) - bg) > FG_THRESH).astype(np.uint8)

    # remove long horizontal structures (gridlines, zone-box top/bottom edges):
    # a morphological opening with a 1xK kernel keeps exactly those runs
    krun = max(25, w // HLINE_RUN_DIV)
    hkernel = cv2.getStructuringElement(cv2.MORPH_RECT, (krun, 1))
    hlines = cv2.morphologyEx(fg, cv2.MORPH_OPEN, hkernel)
    fg = cv2.bitwise_and(fg, cv2.bitwise_not(hlines))

    cols = np.nonzero(fg.any(axis=0))[0]
    if cols.size == 0:
        return None, h, w
    bands: list[tuple[int, int]] = []
    s = p = int(cols[0])
    for x in cols[1:]:
        x = int(x)
        if x - p - 1 < GAP_MERGE_PX:      # gap < 2 px -> same candle
            p = x
        else:
            bands.append((s, p))
            s = p = x
    bands.append((s, p))

    max_span = max(BAND_SPAN_MIN, w // BAND_SPAN_DIV)
    candles: list[dict] = []
    for x0, x1 in bands:
        span = x1 - x0 + 1
        row_w = fg[:, x0:x1 + 1].sum(axis=1)
        rows = np.nonzero(row_w)[0]
        if rows.size == 0:
            continue
        wtop, wbot = int(rows[0]), int(rows[-1])
        height = wbot - wtop
        if span > max_span:               # markup blob / merged debris
            continue
        if height < MIN_BAND_H_FRAC * h:  # noise speckle
            continue
        if height > MAX_BAND_H_FRAC * h:  # near-full-height structure
            continue
        if span <= 2 and height > TALL_THIN_H_FRAC * h:  # vertical markup line
            continue
        if (x0 + x1) / 2.0 > w * (1.0 - EDGE_TRIM_FRAC):  # price-label gutter
            continue
        body_rows = np.nonzero(row_w >= BODY_W_MIN)[0]
        if body_rows.size:
            btop, bbot = int(body_rows[0]), int(body_rows[-1])
        else:
            btop = bbot = (wtop + wbot) // 2   # doji: no row reached BODY_W_MIN
        candles.append({"x": int((x0 + x1) // 2), "x0": int(x0), "x1": int(x1),
                        "bodyTop": btop, "bodyBottom": bbot,
                        "wickTop": wtop, "wickBottom": wbot})
    if len(candles) < MIN_CANDLES:
        return None, h, w
    return candles, h, w


# ---------------------------------------------------------------------------
# plumbing: filename -> slot, directory probing, POST, watch loop
# ---------------------------------------------------------------------------
def slot_of(path: str) -> str | None:
    """PAICT_VISION_<SYMBOL>_<TF>.png -> '<SYMBOL>|<TF>' (e.g. EURUSD|H1).
    The symbol keeps every dot/suffix; the TF is the token after the last '_'."""
    m = VISION_RE.match(os.path.basename(path))
    if not m:
        return None
    return f"{m.group('sym')}|{m.group('tf')}".upper()


def probe_dirs() -> list[str]:
    """Candidate screenshot dirs, best first (Windows MQL5\\Files paths, then
    portable install, then ./MQL5/Files, then the current directory)."""
    cands: list[str] = []
    appdata = os.environ.get("APPDATA")
    if appdata:
        found = glob.glob(os.path.join(appdata, "MetaQuotes", "Terminal",
                                       "*", "MQL5", "Files"))
        try:
            found.sort(key=os.path.getmtime, reverse=True)
        except OSError:
            pass
        cands.extend(found)
    cands.append(os.path.join(os.environ.get("PROGRAMFILES", r"C:\Program Files"),
                              "MetaTrader 5", "MQL5", "Files"))
    cands.append(os.path.join(os.getcwd(), "MQL5", "Files"))
    cands.append(os.getcwd())
    out: list[str] = []
    for c in cands:
        if os.path.isdir(c) and c not in out:
            out.append(c)
    return out


def post_vision(bridge: str, slot: str, patterns: list[dict], wicks: list[dict],
                dry: bool) -> bool:
    """One POST per processed screenshot. Returns True when handled (sent or
    dry-run); bridge failures print ONE warning line and never raise."""
    payload = {"slot": slot, "source": "paict-vision",
               "patterns": patterns, "wicks": wicks}
    if dry:
        print(f"[vision] dry-run payload for {slot}:")
        pprint.pprint(payload)
        return True
    try:
        r = requests.post(f"{bridge.rstrip('/')}/v1/vision", json=payload, timeout=5)
    except Exception as exc:              # requests.RequestException + odd OS errors
        print(f"[vision] WARN bridge unreachable ({bridge}): {exc}")
        return False
    if r.status_code == 200:
        print(f"[vision] {slot}: {len(patterns)} patterns, {len(wicks)} wick rejects")
        return True
    print(f"[vision] WARN bridge HTTP {r.status_code}: {r.text[:120]}")
    return False


def process_file(path: str, bridge: str, dry: bool, verbose: bool) -> bool:
    """Returns True when the file's mtime may be recorded (i.e. do not retry
    it until MT5 rewrites it). False = still being written / decode failed."""
    slot = slot_of(path)
    if slot is None:
        if verbose:
            print(f"[vision] skip (name does not match PAICT_VISION_<SYM>_<TF>.png): "
                  f"{os.path.basename(path)}")
        return True
    img = cv2.imread(path)
    if img is None:
        print(f"[vision] WARN cannot decode {os.path.basename(path)} yet "
              f"(MT5 may still be writing it) — retrying next cycle")
        return False
    candles, ih, iw = reconstruct_candles(img)
    if candles is None:
        if verbose:
            print(f"[vision] {slot}: no usable candle field in {iw}x{ih} frame")
        return True
    patterns = detect_patterns(candles, ih)
    wicks = detect_wick_rejects(candles)
    if verbose:
        print(f"[vision] {slot}: {len(candles)} candles @ {iw}x{ih} -> "
              f"{len(patterns)} pattern(s), {len(wicks)} wick reject(s)")
    return post_vision(bridge, slot, patterns, wicks, dry)


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        prog="paict_vision.py",
        description="PAICT V16 local chart-vision engine — OpenCV reads the EA's "
                    "PAICT_VISION_*.png screenshots and POSTs patterns/wick reads "
                    "to the local bridge. Zero cloud, zero auto-trading.")
    ap.add_argument("--dir", default=None,
                    help=r"screenshot directory (default: probe MQL5\Files, then CWD)")
    ap.add_argument("--bridge", default="http://127.0.0.1:8891",
                    help="local bridge base URL (default %(default)s)")
    ap.add_argument("--once", action="store_true",
                    help="run one sweep over the directory and exit")
    ap.add_argument("--interval", type=int, default=15,
                    help="watch-loop sleep in seconds (default %(default)s)")
    ap.add_argument("--dry-run", action="store_true",
                    help="print the JSON that would be POSTed, send nothing")
    ap.add_argument("--verbose", action="store_true",
                    help="per-file reconstruction diagnostics")
    return ap.parse_args()


def main() -> int:
    args = parse_args()                   # --help answers before any dep check
    ensure_deps()                         # may exit 2 with the pip hint

    if args.interval < 1:
        print("[vision] --interval must be >= 1 second")
        return 2

    watch_dir = args.dir
    if watch_dir:
        watch_dir = os.path.abspath(watch_dir)
        if not os.path.isdir(watch_dir):
            print(f"[vision] not a directory: {watch_dir}")
            return 2
    else:
        probes = probe_dirs()
        if not probes:
            print("[vision] no screenshot directory found — pass --dir explicitly, e.g.")
            print(r'[vision]   --dir "C:\Users\you\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Files"')
            return 2
        watch_dir = next((d for d in probes
                          if glob.glob(os.path.join(d, VISION_GLOB))), probes[0])
        print(f"[vision] auto-probed screenshot dir: {watch_dir}")

    if not glob.glob(os.path.join(watch_dir, VISION_GLOB)):
        print(f"[vision] note: no {VISION_GLOB} files yet in {watch_dir} — waiting")

    bridge = args.bridge.rstrip("/")
    print(f"[vision] watching {watch_dir} -> {bridge}/v1/vision every {args.interval}s"
          f"{' (DRY-RUN)' if args.dry_run else ''} — ctrl-C to stop")

    mtimes: dict[str, float] = {}

    def sweep() -> list[tuple[str, float]]:
        changed: list[tuple[str, float]] = []
        for path in sorted(glob.glob(os.path.join(watch_dir, VISION_GLOB))):
            try:
                m = os.path.getmtime(path)
            except OSError:
                continue
            if mtimes.get(path) != m:
                changed.append((path, m))
        return changed

    if args.once:
        for path, m in sweep():
            if process_file(path, bridge, args.dry_run, args.verbose):
                mtimes[path] = m
        return 0

    try:
        while True:
            for path, m in sweep():
                if process_file(path, bridge, args.dry_run, args.verbose):
                    mtimes[path] = m      # only mtime-changed files are reprocessed
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("[vision] stopped (ctrl-C)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
