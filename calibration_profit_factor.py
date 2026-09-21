#!/usr/bin/env python3
"""
PAICT_Calibration.csv -> profit-factor-style report, per symbol.

IMPORTANT — what this is and isn't:
  PAICT_ChartMarkup.mq5 never places real trades. This script does NOT
  compute a trading profit factor from executed positions. It replays the
  EA's own *suggested* plans (the entry/stop/target it displayed) against
  what price actually did afterward, using the same WIN/LOSS/TIMEOUT
  outcome PAICT_ChartMarkup already recorded in CalibrationUpdate().

  Outcomes are binary — CalibrationUpdate() in PAICT_ChartMarkup.mq5 only
  ever records a full TP hit or a full SL hit, never a partial exit — so
  each resolved plan instance is normalized to ITS OWN risk before being
  summed, which is what makes "R" comparable across symbols with very
  different price scales (e.g. a USDJPYz stop-to-entry gap is ~100x the
  size of a EURUSDz one in raw price terms):
    risk   = |entry - stop|
    reward = |target - entry|
    WIN     -> adds (reward / risk) to "gross profit" — the full planned
               reward, in units of that trade's own risk
    LOSS    -> adds exactly 1.0 to "gross loss" — full stop hit = 1R lost,
               by definition
    TIMEOUT -> excluded from profit factor (neither level was hit), but
               shown as its own column so it isn't silently hidden

  profit_factor = gross_profit / gross_loss   (R-multiple basis, not $ —
  no lot size, spread, commission or slippage is modeled, since none of
  that exists without a real trade)

Usage:
    python3 calibration_profit_factor.py /path/to/PAICT_Calibration.csv
    python3 calibration_profit_factor.py /path/to/PAICT_Calibration.csv --band GO
    python3 calibration_profit_factor.py /path/to/PAICT_Calibration.csv --csv out.csv

Where to find PAICT_Calibration.csv on your machine:
    <MT5 data folder>\\MQL5\\Files\\PAICT_Calibration.csv
  (File -> Open Data Folder inside MT5, then MQL5\\Files). It's per-terminal,
  not shared across terminals, so if you run PAICT_ChartMarkup on more than
  one terminal instance, each has its own file.
"""
import argparse
import csv
import sys
from collections import defaultdict

EXPECTED_HEADER = ["time", "symbol", "timeframe", "band", "masterScore", "side",
                    "entry", "stop", "target", "outcome", "ageBars", "regime",
                    "alignScore", "session", "volBand"]


def load_rows(path):
    with open(path, newline="", encoding="cp1252", errors="replace") as f:
        reader = csv.reader(f)
        rows = list(reader)
    if not rows:
        return []
    header = rows[0]
    if header[:len(EXPECTED_HEADER)] != EXPECTED_HEADER:
        print(f"warning: header does not match expected PAICT_Calibration.csv "
              f"layout (got {header[:4]}...); attempting positional parse anyway",
              file=sys.stderr)
    data = []
    for r in rows[1:]:
        if len(r) < 10:
            continue
        data.append(dict(zip(EXPECTED_HEADER, r)))
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv_path", help="path to PAICT_Calibration.csv")
    ap.add_argument("--band", default=None,
                     help="restrict to one verdict band, e.g. GO, WAIT, or \"NO TRADE\"")
    ap.add_argument("--tf", default=None,
                     help="restrict to one timeframe, e.g. M1, M5, M30, H1 "
                          "(M1 plans on tight pairs often have stop distances "
                          "smaller than live spread -- see the printed caveat)")
    ap.add_argument("--min-stop-pips", dest="min_stop_pips", type=float, default=None,
                     help="drop rows whose stop distance is below this many pips "
                          "(rough filter: JPY/metal pairs use 0.01 as a pip, "
                          "everything else 0.0001 -- good enough to flag "
                          "sub-spread stops, not a precise pip converter)")
    ap.add_argument("--csv", dest="out_csv", default=None,
                     help="also write the per-symbol summary to this CSV path")
    args = ap.parse_args()

    rows = load_rows(args.csv_path)
    if not rows:
        print("No rows found (file empty or not yet created — "
              "PAICT_ChartMarkup writes it only after the first plan resolves).")
        return

    if args.band:
        rows = [r for r in rows if r["band"].strip().upper() == args.band.strip().upper()]
    if args.tf:
        rows = [r for r in rows if r["timeframe"].strip().upper() == args.tf.strip().upper()]
    if args.min_stop_pips is not None:
        def _pip(sym):
            return 0.01 if ("JPY" in sym.upper() or sym.upper().startswith(("XAU", "XAG"))) else 0.0001
        kept = []
        for r in rows:
            try:
                entry = float(r["entry"]); stop = float(r["stop"])
            except ValueError:
                continue
            pips = abs(entry - stop) / _pip(r["symbol"])
            if pips >= args.min_stop_pips:
                kept.append(r)
        rows = kept

    per_symbol = defaultdict(lambda: {"gross_profit": 0.0, "gross_loss": 0.0,
                                       "wins": 0, "losses": 0, "timeouts": 0,
                                       "other": 0})

    for r in rows:
        sym = r["symbol"].strip()
        try:
            entry = float(r["entry"])
            stop = float(r["stop"])
            target = float(r["target"])
        except ValueError:
            continue
        risk = abs(entry - stop)
        reward = abs(target - entry)
        outcome = r["outcome"].strip().upper()
        s = per_symbol[sym]
        if outcome == "WIN":
            # Outcomes here are binary (full TP or full SL, never a partial
            # exit — see CalibrationUpdate() in PAICT_ChartMarkup.mq5), so
            # a WIN is exactly +reward/risk R for THAT trade. Normalizing
            # to each trade's own risk before summing is what makes "R"
            # comparable across symbols with very different price scales
            # (e.g. USDJPYz vs EURUSDz) — summing raw price differences
            # instead (the v1 bug) mixed unlike units and silently rounded
            # small-pip pairs to 0.00 on display.
            if risk > 0:
                s["gross_profit"] += reward / risk
            s["wins"] += 1
        elif outcome == "LOSS":
            # A LOSS is by definition the full stop hit -> exactly 1R lost.
            s["gross_loss"] += 1.0
            s["losses"] += 1
        elif outcome == "TIMEOUT":
            s["timeouts"] += 1
        else:
            s["other"] += 1

    fmt_row = "{:<10} {:>6} {:>6} {:>8} {:>7} {:>7} {:>13} {:>12} {:>10}"
    print(fmt_row.format("SYMBOL", "WINS", "LOSSES", "TIMEOUT", "SAMPLES",
                          "WINRATE", "GROSS_PROFIT", "GROSS_LOSS", "PROF_FACT"))

    out_rows = []
    for sym in sorted(per_symbol):
        s = per_symbol[sym]
        n = s["wins"] + s["losses"] + s["timeouts"] + s["other"]
        judged = s["wins"] + s["losses"]  # timeouts excluded from PF, shown separately
        winrate = f"{(s['wins'] / judged * 100):.0f}%" if judged else "n/a"
        if s["gross_loss"] > 0:
            pf = s["gross_profit"] / s["gross_loss"]
            pf_str = f"{pf:.2f}"
        elif s["gross_profit"] > 0:
            pf_str = "inf (no losses yet)"
        else:
            pf_str = "n/a"
        print(fmt_row.format(sym, s["wins"], s["losses"], s["timeouts"], n, winrate,
                              f"{s['gross_profit']:.2f}R", f"{s['gross_loss']:.2f}R", pf_str))
        out_rows.append([sym, s["wins"], s["losses"], s["timeouts"], n, winrate,
                          round(s["gross_profit"], 4), round(s["gross_loss"], 4), pf_str])

    if args.out_csv:
        with open(args.out_csv, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["symbol", "wins", "losses", "timeouts", "samples", "winrate",
                        "gross_profit_R", "gross_loss_R", "profit_factor"])
            w.writerows(out_rows)
        print(f"\nwrote {args.out_csv}")

    print("\nNote: figures are in R-multiples of the EA's own planned risk/reward, "
          "not currency — no lot size, spread, commission, or slippage is modeled, "
          "since no real trade was placed. TIMEOUT rows are excluded from the "
          "profit-factor ratio (shown separately) since neither TP nor SL was hit.")


if __name__ == "__main__":
    main()
