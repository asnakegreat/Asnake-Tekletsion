//+------------------------------------------------------------------+
//|                                            PAICT_ChartMarkup.mq5 |
//|                Chart Markup Key — multi-chart annotation expert  |
//|                                                                  |
//|  Attach this EA to ONE chart only. It discovers every other      |
//|  open chart automatically (ChartFirst / ChartNext), including    |
//|  charts opened afterwards on its refresh cycle, and draws the    |
//|  markup layers on all of them for every pair it is allowed to    |
//|  cover (whitelist empty = all symbols).                          |
//|                                                                  |
//|  Markup spec — thin lines and thin outline boxes ONLY (session   |
//|  shading and zone fills are opt-in extras behind OFF inputs):     |
//|   Price Action                                                   |
//|     • Support zones        thin green outline box   (clustered   |
//|                              swing lows inside an ATR tolerance)  |
//|     • Resistance zones     thin red outline box                  |
//|     • Trend line           solid blue through the two latest     |
//|                              swings of the prevailing direction  |
//|     • Fast / slow MAs      native yellow / violet plots added    |
//|                              via the PAICT_DualMA companion      |
//|   ICT / SMC                                                      |
//|     • Order blocks         teal (bullish) / orange (bearish)     |
//|                              outline boxes — last opposite       |
//|                              candle before an ATR-scaled         |
//|                              displacement move, dropped once     |
//|                              mitigated                           |
//|     • Fair value gaps      dashed yellow outline boxes —         |
//|                              three-candle imbalance, dropped     |
//|                              once fully filled                   |
//|     • CHoCH                tight magenta dashes on the nearest   |
//|                              counter-trend swing break           |
//|     • MSS / BOS            wide blue dashes on the larger        |
//|                              structural swing break              |
//|   Extended layers (v2.00)                                        |
//|     • Liquidity pools      dashed slate BSL / SSL lines from     |
//|                              equal highs / equal lows (>= 2      |
//|                              confirmed touches, nearest first)    |
//|     • Premium / discount   dotted violet 50% equilibrium of the  |
//|                              dealing range + premium/discount tag |
//|     • Killzones            dim Asia / London / NY session shading |
//|                              BEHIND candles (opt-in, OFF default) |
//|     • HTF overlay          higher-timeframe OB + FVG, dimmed and |
//|                              labelled ("H4 …"), auto-skipped when |
//|                              the chosen TF <= the chart timeframe |
//|     • JSON export          per-symbol/tf snapshot written to      |
//|                              MQL5\Files\PAICT_<symbol>_<tf>.json  |
//|     • Trade plan           filled ENTRY (gold) / STOP (red) /    |
//|                              TARGET (green) BANDS — identical      |
//|                              rectangles, only the color differs —  |
//|                              + level lines, priced labels, R:R,    |
//|                              ICT-first                             |
//|   Zenith Terminal (v10.00)                                       |
//|     • Mailbox IPC         every push rewrites the local snapshot  |
//|                             JSON — zero HTTP for local readers    |
//|     • Trade sandbox       draggable ENTRY/STOP/TARGET lines; R:R, |
//|                             lots + MC recompute live (v10)        |
//|     • Master Score        0-100 fusion of every V4-V9 metric →   |
//|                             big GO / WAIT / NO TRADE read         |
//|   AI Desk / Microstructure / Simulation (v5.00-v7.00)             |
//|     • Trade journal       CSV row per manual close (OnTrade)      |
//|     • Self-heal           setup mutes after N stop-outs, re-arms  |
//|     • Tuner bridge        paict_tuner.py suggestions on the HUD   |
//|     • Volume profile      tick-volume POC / VAH / VAL histogram   |
//|     • Fractal matrix      M1-H4 alignment score (HUD + payload)   |
//|     • Cone / MC / DOM     probability cone, Monte Carlo TP/SL,    |
//|                             Depth-of-Market ladder strip          |
//|   Order Flow / Intermarket (v8.00-v9.00)                          |
//|     • CVD + divergences   tick-volume delta curve in the low band |
//|     • Sweep tags          TRUE SWEEP vs FAKEOUT on BSL/SSL raids  |
//|     • Absorption / disp   ABS+ dots, 1-10 displacement grade      |
//|     • Correlation watch   Pearson r vs every covered chart        |
//|     • ICT patterns        TURTLE SOUP · AMD phase · Power-of-3    |
//|   Analytical Co-Pilot (v4.00)                                    |
//|     • Risk HUD            "RISK 1.0% = 0.25 lots" — balance ×    |
//|                              risk% ÷ (entry→stop distance priced |
//|                              via tick size / tick value), volume-|
//|                              step floored, per covered chart     |
//|     • Portfolio heat      total open risk of ALL manual trades   |
//|                              (magic 0, any symbol) as % of the   |
//|                              balance; flashing "MAX PORTFOLIO    |
//|                              HEAT" warning at InpMaxHeatPct      |
//|     • News blackout       MT5 economic calendar: a red column    |
//|                              spans InpNewsPreMin before →        |
//|                              InpNewsPostMin after every          |
//|                              high-impact event of the symbol's   |
//|                              currencies; plan bands wash out     |
//|     • Remote control      after each accepted push the EA polls  |
//|                              /v1/poll and applies whitelisted     |
//|                              commands (SET_RISK / TOGGLE_ZONES / |
//|                              SET_RENDER / PING) from the bridge  |
//|   Analytical Foundation (v3.00)                                  |
//|     • MVC split           CalculateMarketState() fills one       |
//|                              SMarketState; RenderMarketState()   |
//|                              draws it; bridge/export read state  |
//|     • Pause render        InpPauseRender stops drawing while the |
//|                              state + bridge push keep running    |
//|     • Zero-flicker        upsert-in-place object engine + stale  |
//|                              sweep (no per-bar ObjectsDeleteAll) |
//|                                                                  |
//|  Only the most recent element of each ICT kind is drawn so the   |
//|  chart never fills up with history. All objects are grouped      |
//|  under the "PAICT_" prefix and are removed cleanly on exit.      |
//|                                                                  |
//|  NOTE — deliberately simplified, non-repainting heuristics built |
//|  from confirmed bars only, intended as visual markup study, NOT  |
//|  a certified signal engine. Place no trades from the drawings    |
//|  without your own backtest.                                      |
//+------------------------------------------------------------------+
#property copyright "Chart Markup Key"
#property link      ""
#property version   "24.00"
#property description "Draws Price Action + ICT/SMC markup (thin lines / thin outline boxes) on every open chart."
// v24.00 — OPTIONS GREEKS & IMPLIED VOLATILITY (roadmap V24.00 — map option
//         market structure onto the underlying, when the broker lists it):
//         1. Local Black-Scholes pricer + a Newton-Raphson/bisection implied-
//            volatility solver over a call and a put symbol you name
//            (InpOptCallSymbol/InpOptPutSymbol, InpOptStrike, InpOptExpiry,
//            InpOptRiskFreeRate) — HONEST SCOPE: most retail forex/CFD
//            brokers do not list option instruments on majors/XAUUSD at
//            all; this reads real quotes when they exist and stays
//            silent (ivCall/ivPut absent) otherwise. Toggle: InpOptionsGreeks.
//         2. Gamma barrier: the strike whose computed gamma is highest of
//            the two contracts is flagged as a magnet/repulsion level on
//            the HUD and pushed as gammaLevel.
// v23.00 — INTERMARKET COINTEGRATION (roadmap V23.00 — upgrade the v9
//         Pearson correlation read into a mean-reversion signal):
//         1. Z-score spread: tracks the rolling spread between this
//            chart's closes and its strongest correlated covered symbol's
//            closes (index-aligned by bar, InpStatArbBars window), and its
//            Z-score against that spread's own mean/stdev. |Z| >=
//            InpStatArbZ flashes "STAT ARB OPPORTUNITY" — the two legs
//            have drifted apart further than their historical equilibrium
//            supports. Toggle: InpStatArb. Payload: statArbZ, statArbFlag,
//            statArbSym.
// v22.00 — WALK-FORWARD MATRIX (roadmap V22.00 — a historical expectancy
//         read for the EXACT setup forming right now, not just the
//         theoretical Master Score):
//         1. Signature backtest: replays the same bullish/bearish
//            displacement-and-retracement heuristic FindOrderBlockCandidates
//            already uses over the last InpWalkForwardBars closed bars,
//            matching the CURRENT plan's direction, then forward-simulates
//            each historical match with the plan's own R:R ratio to see
//            whether target or stop would have been hit first. Reports
//            win% + expectancy-in-R + sample count on the HUD — "62% WR ·
//            +0.8R · n=14" — so a fresh setup carries its own historical
//            track record instead of a generic score. Toggle:
//            InpWalkForward. Payload: wfWinPct, wfExpectancyR, wfTrades.
// v21.00 — LOCAL MARKET PROFILE (roadmap V21.00 — session TPO, alongside
//         the existing v6 Volume Profile):
//         1. Time-Price-Opportunity profile over the current session:
//            buckets each InpTpoPeriodMin-minute period into a letter and
//            tallies which price rows it touched, from confirmed bars
//            only. Derives TPO Point of Control, a 70% Value Area
//            (High/Low), Single Prints (rows touched by exactly one
//            period — thin, un-auctioned price) and a Poor High/Low flag
//            (the session extreme was touched by 2+ periods, i.e. never
//            firmly rejected). Drawn as a compact box + HUD line, reusing
//            the existing zone-box primitives. Toggle: InpTpoProfile.
//            Payload: tpoPoc, tpoVah, tpoVal, tpoSinglePrints, tpoPoorHigh,
//            tpoPoorLow.
// v20.00 — THE ORACLE (roadmap V20.00 — fuse every independent read this EA
//         produces into one number, and let the trader mark up the chart
//         with their own read alongside it):
//         1. Oracle Score: master 45% + confluence 25% + flow sentiment 15%
//            + regime alignment 15% (0-100). >= InpOracleGoAt (default 85)
//            flashes "PERFECT SETUP" on the HUD. Toggle: InpOracleScore.
//         2. On-chart journal: double-click any chart to drop a numbered
//            note pinned at that exact price/time (OBJ_TEXT + OBJ_EDIT
//            popup for the note body), persisted to
//            MQL5\Files\PAICT_Notes.csv and pushed as notes[] in the
//            bridge payload so the dashboard's Journal monitor can render
//            it. Toggle: InpJournal.
// v19.00 — MACRO CROSSCURRENTS (roadmap V19.00 — what is the wider market
//         doing while this chart's setup builds):
//         1. Yield curve monitor: reads InpYieldShort / InpYieldLong bond
//            CFD symbols, computes their spread and flags an inversion —
//            "2s10s -0.42 INVERTED". Skips silently when the symbols
//            aren't available from the broker. Toggle: InpYieldCurve.
//         2. Intermarket lead/lag: watches InpLeadSymbol for a move past
//            InpLeadAtrMult x its own ATR and flags leadFlash + direction
//            so a correlated chart can react early. Toggle: InpLeadLag.
// v18.00 — PATTERN GEOMETRY (roadmap V18.00 — the two classic manual-chartist
//         reads, done heuristically off confirmed swings):
//         1. Harmonic XABCD scan (Gartley / Bat / Butterfly / Crab) over the
//            last five confirmed swing points, tolerance-banded against each
//            pattern's canonical Fibonacci ratios; a match draws the PRZ
//            (potential reversal zone) box and reports harmonic/harmDir.
//            Toggle: InpHarmonics.
//         2. Simplified Elliott Wave count over the same swing series
//            (impulse 1-5 / corrective ABC heuristic), reported as
//            elliott/ewDir. Toggle: InpElliottWave.
// v17.00 — CONFLUENCE FUSION (roadmap V17.00 — stack every independent
//         signal this EA already computes into one agreement score):
//         1. Confluence Fusion: counts how many of the existing independent
//            reads (OB/FVG bias, structure break, liquidity sweep, OTE
//            zone, session killzone, correlation alignment, CVD, Monte
//            Carlo TP%, volatility regime) agree with the plan's direction,
//            turns the count into confluence (0-100) + confCount +
//            confTags ("OB+FVG+CVD"). Toggle: InpConfluence.
// v16.00 — REGIME & VOLATILITY READ (roadmap V16.00 — classify what kind of
//         market this is before trusting any directional plan):
//         1. Market regime: Hurst exponent (R/S analysis) + Kaufman
//            Efficiency Ratio over InpRegimeBars bars classify the chart as
//            TRENDING / RANGING / TRANSITION, shown on the HUD and folded
//            into Master Score (-15 when an ICT trend-continuation plan
//            fights a RANGING regime, +5 when it rides a TRENDING one).
//            Toggle: InpRegime.
//         2. Volatility contraction (VCV): Bollinger-inside-Keltner squeeze
//            detection with a "cone" flag when the squeeze is actively
//            narrowing bar over bar. Toggle: InpVcv.
// v15.00 — THE COCKPIT SUMMARY (roadmap V15.00 — a top-down view across
//         every covered chart, and a sense of session time remaining):
//         1. Cross-chart leaderboard: as each covered chart renders, its
//            Master Score + verdict + symbol are written into a shared
//            registry (g_leader[]); the ATTACH chart draws a compact HUD
//            block ranking the top InpLeaderboardRows charts by score —
//            "1. XAUUSD GO 82  2. EURUSD WAIT 51  ...". Lets one attached
//            EA answer "which of my open pairs looks best right now?"
//            without switching charts. Toggle: InpLeaderboard.
//         2. Session countdown: a HUD line naming the CLOSEST killzone
//            transition (next open or the active session's close) and the
//            remaining time, e.g. "NEXT: LONDON opens in 41m" or
//            "NEXT: NY closes in 1h12m" — computed from server time
//            against the existing Asia/London/NY hour inputs, independent
//            of whether killzone shading itself is enabled. Toggle:
//            InpSessionCountdown. Additive payload: leaderboard[], nextSession.
// v14.00 — ADAPTIVE RISK (roadmap V14.00 — sizing and entry selection get
//         smarter without any new auto-trading):
//         1. Volatility regime read: current ATR vs. its own trailing
//            InpVolRegimeBars-bar average classifies HIGH / NORMAL / LOW;
//            HIGH scales a SUGGESTED risk % (InpVolHighCutMult× the
//            current ATR ratio against InpRiskPercent, floored at
//            InpVolMinRiskPercent) shown on the HUD next to the existing
//            RISK line — "VOL HIGH (1.8x) - suggested risk 0.5%". Applying
//            it stays manual (SET_RISK from the dashboard, same as v4.00)
//            so a read-only suggestion never silently changes exposure.
//            Toggle: InpVolRegime. Payload: volRegime, suggestedRiskPct.
//         2. Best-of-N order-block selection: ComputeTradePlan no longer
//            settles for the single newest unmitigated order block on
//            each side — it scores up to InpPlanCandidates recent
//            unmitigated OBs by ATR-normalized R:R to the nearest
//            external-liquidity target and keeps the best, so a closer
//            but poor-R:R OB no longer silently wins over a slightly
//            older, better-aimed one. No behavior change when only one
//            candidate exists.
// v13.00 — PERFORMANCE ANALYTICS (roadmap V13.00 — the v5.00 trade journal
//         finally gets read back, not just written):
//         1. Win-rate / expectancy HUD: rescans each symbol's
//            PAICT_TradeJournal_<symbol>.csv (InpStatsScanSec throttle,
//            capped at InpStatsMaxRows most-recent rows) and shows
//            "STATS 55% WIN - 0.32R EXP (42)" — win % and expectancy in
//            R-multiples (profit / |entry-stop| priced via the row's own
//            planEntry/planStop/planTarget columns), or stays silent with
//            zero trades. Toggle: InpTradeStats. Payload: statsWinPct,
//            statsExpectancyR, statsTrades.
//         2. Equity mini-sparkline: a small normalized polyline of the
//            journal's cumulative balanceAfter column, drawn top-right of
//            the attach chart in a fixed pixel-mapped price band (reuses
//            the v8.00 CVD polyline technique) — a running shape of
//            "am I currently up or down" without opening the CSV.
//            Toggle: InpEquitySpark.
// v12.00 — SMART MONEY EXECUTION LAYER (roadmap V12.00 — two ICT
//         refinements that read the state that already exists, no new
//         detection primitives):
//         1. Breaker blocks: an order block that gets mitigated (price
//            trades through it) is checked for a hard displacement in the
//            OPPOSITE direction on the very bar that broke it — if found,
//            the box is redrawn as a dashed "breaker" in the flipped
//            polarity color (a broken bullish OB that reverses hard
//            becomes bearish resistance, and mirrored) instead of simply
//            vanishing, tracking the classic ICT role-flip. Toggle:
//            InpBreakerBlocks.
//         2. Structure-shift warning: if a CHoCH against the ACTIVE
//            plan's direction prints while price has not yet reached
//            ENTRY, the plan's labels gain a "STRUCTURE SHIFT" tag instead
//            of silently waiting to be hit or invalidated — the setup
//            stays drawn (still a human call) but is flagged as
//            contradicted by the newest structure. Toggle:
//            InpStructureShiftTag. Payload: planShiftWarn.
// v11.00 — THE 10x FEATURE DROP (three practical, low-risk additions on
//         top of the v10.01 Zenith Terminal — all read-only markup, still
//         zero auto-trading):
//         1. OTE (Optimal Trade Entry) zone: a dotted violet outline box
//            over the 62%-79% Fibonacci retracement of the latest swing
//            leg (the two most recent opposite-side confirmed swings),
//            drawn in the direction of the prevailing leg — the classic
//            ICT "sniper entry" pocket. Toggle: InpDrawOTE; retracement
//            bounds: InpOTEFibLow / InpOTEFibHigh. Additive JSON field
//            "ote": {"low":...,"high":...,"bullish":true/false}.
//         2. Daily / Weekly open lines: thin dotted lines at today's D1
//            open and this week's W1 open, labelled "D-OPEN <price>" /
//            "W-OPEN <price>" — the reference levels ICT setups measure
//            premium/discount and AMD phases against. Toggle:
//            InpDrawDayWeekOpens. Additive JSON fields "dOpen"/"wOpen".
//         3. Price-in-zone push alerts: when the live Bid on the attach
//            chart enters the plan's ENTRY band, or touches STOP/TARGET,
//            the EA fires SendNotification (mobile push, if a MetaQuotes
//            ID is configured) plus a chart Alert()/Print() fallback —
//            so a trader watching several pairs does not have to stare
//            at the screen for the setup to arrive. Toggle:
//            InpPriceAlerts; throttle: InpAlertCooldownMin (minutes
//            between repeat alerts of the SAME kind on the SAME plan).
//         No existing drawing, payload key, or cadence was removed or
//         renamed — every addition is opt-in and additive.
// v10.01 — HOTFIX (first MetaEditor F7 pass of v10.00 — 19 errors, 2 roots):
//         1. Type-before-use: SMarketState was defined at ~line 2100 but
//            SelfHealUpdate() already took one at ~line 1108 — MQL5 needs
//            the type declared first, so the whole parameter list failed
//            ("declaration without type") and every 'st.' member inside
//            cascaded (15 errors + the 2482 call-site mismatch). The
//            struct now sits with the other state structs just before
//            OnInit; the old ~2100 definition site is gone.
//         2. MqlBookInfo has NO volume_dbl member (only type / price /
//            volume: long) — DrawDOMStrip()'s book[i].volume_dbl raised
//            4 "undeclared identifier" errors. Both lines now read
//            (double)book[i].volume — the long volume, cast.
//         No behavior, payload or input change — pure compile fix.
// v10.00 — THE ZENITH TERMINAL (roadmap V10.00 — the cockpit comes
//         together; still zero auto-trading):
//         1. Local Mailbox IPC: every accepted bridge push also rewrites
//            MQL5\Files\PAICT_matrix_snapshot.json (FILE_SHARE_READ) —
//            local readers get the live matrix with ZERO HTTP round-trips.
//            The HTTP bridge stays as-is for LAN/dashboard use.
//         2. Interactive Trade Sandbox: the plan levels become draggable
//            OBJ_TREND lines (PAICT_SB_E/S/T, SELECTABLE). CHARTEVENT_
//            OBJECT_DRAG reads the new levels back into g_sb; the HUD and
//            the payload (sbEntry/sbStop/sbTP) recompute R:R-based reads
//            live. A fresh plan (or RESET_SANDBOX) re-anchors; a held drag
//            is never fought by the renderer (OBJPROP_SELECTED guard).
//            Remote: TOGGLE_SANDBOX 0/1, RESET_SANDBOX.
//         3. Master Score 0-100 — every metric fused into one verdict:
//            R:R (25) + fractal alignment vs the plan side (15) + Monte
//            Carlo TP% (20) + agreeing displacement grade (10) + CVD
//            agreement (10), minus correlation divergence (5) and heat
//            alert (15); a news blackout scales the total to 20%. Drawn
//            as a big top-center GO / WAIT / NO TRADE label (thresholds
//            are inputs InpMasterGoAt/InpMasterWaitAt) and pushed as
//            masterScore/masterVerdict.
// v9.00 — INTERMARKET SENTIMENT (roadmap V9.00):
//         1. Correlation engine: Pearson r of bar returns vs every OTHER
//            covered chart symbol (window InpCorrBars). HUD "CORR SYM
//            r=0.87"; when the attach symbol moved >= 2 ATR over the
//            window while |r| stayed below InpCorrWarn the line turns
//            amber with "DIVERGING" ("Gold diverging from USD Index").
//            Payload: corrSym/corrR/corrWarn.
//         2. Named ICT patterns: TURTLE SOUP tags when a wick raids the
//            prior 20-bar extreme by <= 0.10 ATR and closes back inside;
//            Power-of-3 day-open dotted line + AMD phase read (AMD ACCUM /
//            P3 EXPAND UP/DN) from the first ~3h range vs the day open.
// v8.00 — ORDER FLOW & DELTA (roadmap V8.00, all from free tick-volume):
//         1. CVD curve: delta ≈ tickVol × sign(close-open), cumulative
//            over InpCVDLength bars, drawn as a normalized polyline in
//            the bottom band of the dealing range + divergence labels
//            (price HH / CVD LH = "CVD DIV-", mirror "CVD DIV+").
//            Payload: cvdDir, cvdDiv.
//         2. TRUE SWEEP vs FAKEOUT tags on BSL/SSL raids: wick through +
//            close back inside = TRUE SWEEP (reversal expected); close
//            beyond = FAKEOUT (the level gave way). Nearest raid per pool.
//         3. Absorption tags: an OB candle with a small body (<= 0.30 ATR)
//            but >= 1.8× the average tick volume gets ABS+/ABS- (the
//            opposing side was absorbed there).
//         4. Displacement grade 1-10 after every CHoCH/MSS: break-bar body
//            in 0.20 ATR steps, labelled "D7" at the dash. Payload:
//            displacement.
// v7.00 — SIMULATION & LIQUIDITY (roadmap V7.00):
//         1. Monte Carlo: zero-drift random walk (per-bar sigma = ATR,
//            Box-Muller gaussians, seeded from the plan so a plan always
//            yields the same read) — InpMCRuns first-touch outcomes over
//            InpMCBars bars. HUD "MC TP 68% · SL 27% (10000)"; payload
//            mcTP/mcSL. ATR sigma is an upper bound — comparison metric.
//         2. DOM ladder strip (opt-in, InpDrawDOM): MarketBookGet levels
//            drawn as bid/ask volume bars reaching back from the forming
//            bar; degrades warn-once when the broker serves no book.
// v6.00 — MICROSTRUCTURE & FRACTAL ALIGNMENT (roadmap V6.00):
//         1. Session volume profile: tick-volume histogram over the last
//            InpVPDays sessions in InpVPRows price buckets, drawn from the
//            session open rightward; POC (gold) + 70% value area VAH/VAL
//            (dotted slate). Payload: poc/vah/val.
//         2. Fractal alignment matrix M1-H4: +1 HH&HL, -1 LL&LH per TF
//            (same swing detector as the markup). HUD "ALIGN 3/5 · M1+ M5+
//            M15- H1+ H4-"; payload alignScore.
//         3. Probability cone (opt-in): ±2σ random-walk projection of the
//            next InpConeBars bars from the |Δclose| statistics (sqrt-time
//            scaling), dotted violet from the last closed bar.
// v5.00 — LOCAL AI ANALYSIS DESK (roadmap V5.00 — self-healing &
//         auto-journaling; the "AI" stays honest local statistics):
//         1. OnTrade auto-journal: every MANUAL deal close (magic 0)
//            appends one CSV row to MQL5\Files\PAICT_TradeJournal_<symbol>.csv
//            with profit, balance and the attach chart's plan context at
//            close time (entry/stop/target/RR).
//         2. Self-healing setups: a plan whose STOP is hit before its
//            TARGET counts one fail per plan instance; InpSelfHealFails
//            consecutive stop-outs MUT the setup — the plan stops
//            rendering and is pulled from the bridge (status flips to
//            awaiting_plan + setupMuted) until it re-arms after
//            SELF_HEAL_REARM_BARS closed bars. A TARGET hit resets the
//            counter. HUD "SETUP MUTED (self-heal)".
//         3. Tuner bridge: the kit's paict_tuner.py reads the CSV journals
//            + JSON snapshots and writes PAICT_TunerSuggestion.txt
//            (KEY=VALUE whitelist: RISK_PERCENT, ZONE_TOLERANCE,
//            PLAN_ZONE_HEIGHT, STOP_BUFFER, NOTE). The EA shows the lines
//            on the HUD ("TUNER ...") and pushes them in the payload —
//            applying stays a human decision (input dialog or SET_RISK).
// v4.01 — Hotfix (first MetaEditor F7 compile of v4.00 failed):
//         OBJ_VRECTANGLE does not exist in MQL5 ("undeclared identifier /
//         cannot convert enum" at the UpsertVRect ObjectCreate call — the
//         name exists on other trading platforms, not in MQL5). The news
//         blackout column is now a regular OBJ_RECTANGLE whose price span
//         overshoots the viewport by ~3 decades of the chart symbol's bid
//         (bid × 0.001 → bid × 1000, ±1e9 fallback when the bid is not
//         available): MT5 auto-scales ONLY to bars — never to chart
//         objects — so the rectangle is clipped at the viewport top and
//         bottom and renders as a true full-height vertical band at any
//         zoom level, WITHOUT viewport re-pinning (it stays correct even
//         while rendering is paused via InpPauseRender). Both time AND
//         price anchors are now updated on every upsert pass. No other
//         drawing, payload, input or cadence change.
// v4.00 — THE ANALYTICAL CO-PILOT (roadmap V4.00 — risk math & remote
//         control, all local, zero auto-trading):
//         1. Simulated Risk Sizing HUD: reads the account balance and the
//            plan's entry→stop distance, prices it via tick size / tick
//            value and shows "RISK 1.0% = 0.25 lots" as a pixel HUD line
//            (volume-step floored, broker-minimum aware). Inputs:
//            InpRiskHUD / InpRiskPercent — runtime-overridable remotely.
//         2. Portfolio Heat Tracker: sums the open risk of ALL manual
//            positions (magic 0, every symbol) as % of balance and
//            flashes a red "MAX PORTFOLIO HEAT" HUD warning at
//            InpMaxHeatPct (default 3%). Positions without a stop are
//            counted separately ("N no-SL") since they cannot be sized.
//         3. News & Event Blackout: scans the MT5 economic calendar (both
//            currencies of the attach symbol) every 10 min for
//            high-impact events. Inside the blackout window
//            (InpNewsPreMin before → InpNewsPostMin after the release) a
//            red full-height column + "NEWS <event>" label appear and the
//            plan BANDS wash out toward the background (level lines and
//            labels stay readable). Brokers without a calendar degrade
//            to "no blackout" with a single journal line.
//         4. Local Two-Way Bridge: after every accepted push the EA GETs
//            /v1/poll?slot=SYMBOL|TF and applies whitelisted commands the
//            Node bridge hands back (SET_RISK / TOGGLE_ZONES / SET_RENDER
//            / PING) — the local dashboard can toggle EA behavior from
//            the browser. MQL5 inputs are read-only at runtime, so
//            commands write runtime mirrors (g_ov) initialized from the
//            inputs on attach.
//         5. Matrix payload additions (additive — dashboards ignore
//            unknown keys): riskPct, riskLots, heatPct, heatAlert,
//            newsBlackout, newsEvent.
// v3.00 — THE ANALYTICAL FOUNDATION (roadmap V3.00 — state & perf;
//         re-versioned from 2.07, which shipped the full engineering
//         pass: CalculateMarketState()/RenderMarketState() MVC split
//         over one SMarketState struct, the zero-flicker upsert object
//         engine with SweepUndrawn stale GC, ArrayResize reserve
//         chunks, CopyRates/ATR hardening and the embedded CJsonWriter).
//         NEW in 3.00: InpPauseRender — rendering can be paused while
//         the state keeps calculating and the bridge keeps pushing
//         ("calculates levels instantly, even if drawing is paused").
// v2.07 — Engineering pass — calculation decoupled from rendering (MVC),
//         plus four reliability/performance upgrades:
//         1. MVC: the old monolithic DrawOnChart() is split into
//            CalculateMarketState() (pure detection, fills one SMarketState
//            struct: swings, zones, OBs, FVGs, liquidity, EQ, structure
//            breaks, trade plan) and RenderMarketState() (draws it). The
//            Web Bridge and the JSON export now read the STATE directly —
//            the bridge no longer scrapes OBJPROP_PRICE off chart objects
//            (g_plan cache) — which also prepares the ground for automated
//            execution without any chart open.
//         2. Performance: every grow-in-a-loop ArrayResize (FindSwings,
//            ClusterSide, SideOf, FVG/liquidity collectors) now passes a
//            reserve_size (ARRAY_RESERVE_CHUNK = 64), so MQL5 reallocates
//            in chunks instead of on every append — removes the CPU spikes
//            on deep lookbacks.
//         3. Performance: the per-bar ObjectsDeleteAll(PAICT_*) is GONE.
//            Every drawer now goes through UpsertRect / UpsertSegment /
//            UpsertText — existing objects get their TIME/PRICE/color
//            updated in place; only genuinely new objects are created.
//            A per-cycle registry (g_drawn) + SweepUndrawn() deletes exactly
//            the objects that stopped being valid, nothing else. This ends
//            the 50+-object GDI churn (micro-stutter) on every closed bar.
//         4. Reliability: CopyRates failures now ResetLastError() first and
//            journal the EXACT MT5 error (ERR_HISTORY_NOT_FOUND etc.,
//            human-mapped, throttled per chart to one line per new error).
//            GetAtr() falls back to a manual true-range average over raw
//            CopyHigh/CopyLow/CopyClose bars when the iATR cache fails, so
//            zone math never silently divides by zero / blanks the chart.
//         5. Quality: all scattered heuristics are named constants now
//            (ZONE_LASTRESORT_ATR 0.15, ZONE_MAX_SPAN_MULT 2.5, FVG_BODY_ATR
//            0.8, PLAN_STOP_BUF_ATR 0.10, BRIDGE_HEARTBEAT_SEC 30, ...).
//         6. Network: the bridge payload is built by an embedded zero-
//            dependency CJsonWriter (per-field escaping, explicit digits,
//            single Build() that closes the object) instead of hand-
//            concatenated strings. JAson.mqh was deliberately NOT pulled
//            in: it would turn this single-file EA into a two-file install
//            with an Include-folder dependency — the embedded writer gives
//            the same guarantees and keeps the kit self-contained. The
//            byte-exact StringToCharArray(-1) conversion stays (the v2.02
//            truncation fix).
// v2.06 — Plan ZONES. Even at v2.05's strong colors and width 2 the user still
//         could not read ENTRY / SL / TP on a live chart: three thin lines
//         threaded through candles are easy to lose. Each plan level is now
//         ALSO drawn as a FILLED RECTANGLE band — one at ENTRY, one below at
//         STOP, one above at TARGET (a short plan mirrors automatically) —
//         all three IDENTICAL in size and x-range so the only difference is
//         the color: gold ENTRY / red STOP / green TARGET. Band height =
//         InpPlanZoneHeightATR × ATR (default 0.20 → a slim strip that stays
//         readable on every timeframe). New Trade Plan inputs: InpPlanZones
//         (master, default true), InpPlanZoneHeightATR, InpPlanZoneBack
//         (false = solid band in FRONT of candles for maximum visibility,
//         true = tint behind candles like the killzones). The width-2 level
//         lines and priced labels stay and render on top of the bands; the
//         bands carry the PAICT_ prefix so cleanup stays one call. Web
//         Bridge payload and cadence unchanged.
// v2.05 — Trade-plan visibility. The user could not read the plan levels
//         clearly: amber / rose / cyan at width 1 washed out over candles,
//         and the labels carried no price. The three plan colors are now
//         INPUTS in the Trade Plan group — InpEntryColor / InpStopColor /
//         InpTargetColor, defaults strong gold C'255,191,0' / vivid red
//         C'255,59,48' / vivid green C'0,220,130' (chosen to hold contrast
//         on both dark and light chart backgrounds) — plus InpPlanWidth
//         (default 2; set 1 for the old thin look) and InpPlanLabelPrice
//         (default true: labels now read "ENTRY 2345.67" instead of bare
//         "ENTRY", font bumped to size 9). DrawPlanLine and the R:R label
//         pick the colors up through the existing COL_* aliases, so the
//         PA and ICT plan variants all follow the same inputs. JSON
//         export and the Web Bridge payload are unchanged.
// v2.04 — Bridge forensics. The first v2.03 field report showed the
//         worst-case combo: "pushed 157 bytes, reply 1001 bytes <- no
//         status line" with an EMPTY body. That proves the wire is UP
//         (no -1, constant 1001-byte reply every push) but whatever
//         answers does not behave like a normal HTTP/1.1 JSON endpoint
//         — an Express error page would carry an "HTTP/1.1 500 ..."
//         status line and printable HTML text; this has neither. The
//         non-2xx branch now additionally prints raw forensics: exact
//         body-array size, the first 80 chars of the header buffer,
//         and a hex dump of the first 32 body bytes — enough to
//         identify ANY responder (binary protocol, compressed page,
//         or a port squatter on 8891) in a single journal line. No
//         transport, payload or cadence changes.
// v2.03 — Bridge log diagnostics. The v2.02 journal line "pushed N bytes ->
//         HTTP res" was misleading: MQL5's WebRequest does NOT return the
//         HTTP status code — it returns the number of BODY BYTES received
//         (an HTTP status is always exactly 3 digits, so a logged value like
//         1001 can only be a byte count). A healthy bridge replies with a
//         tiny JSON (~40 bytes); a reply of ~500–1000 bytes is the
//         fingerprint of an Express default HTML error page (DOCTYPE +
//         stack trace with long Windows paths). The push handler now parses
//         the real status line out of resultHeaders and logs
//         "pushed N bytes, reply M bytes <- HTTP/1.1 200 OK"; on any
//         non-2xx answer it additionally prints the first ~200 characters
//         of the reply body (newlines collapsed), so the next push names
//         the exact server-side error in the journal. No transport,
//         payload, cadence or drawing behavior changed.
// v2.02 — Bridge hotfix — two wire-level bugs, both exposed by the user's
//         bridge logs:
//         1. StringToCharArray(json, post, 0, StringLen(json)) treats the
//            count as ARRAY ELEMENTS INCLUDING the terminal 0 — it copied
//            StringLen-1 characters, so the JSON arrived WITHOUT its closing
//            brace and body-parser rejected every push (entity.parse.failed,
//            HTTP 500/400 from the Node bridge). Now converts with the
//            default count (-1) and strips only the terminator: the full
//            document ships byte-exact, closing brace included.
//         2. The payload's wall-clock "time" field made every build differ,
//            so the dedupe never matched and the EA POSTed on every refresh
//            tick (2 s spam). The dedupe key now carries plan values only;
//            "time" is injected at push moment. Cadence back to spec: plan
//            changes, every closed bar of the attach chart, plus a 30 s
//            heartbeat. Failures still retry at most every 30 s.
// v2.01 — Web Bridge / Matrix Push: the EA POSTs the attach chart's live
//         trade plan (ENTRY / STOP / TARGET read back from the drawn plan
//         lines — confirmed bars only, still non-repainting) as JSON to a
//         local HTTP bridge, default http://127.0.0.1:8891/v1/matrix, so a
//         React dashboard can render it. New inputs: InpBridgeEnabled /
//         InpBridgeURL / InpBridgeTimeoutMs / InpBridgeVerbose. The push is
//         deduped (fires on plan changes, on every closed bar of the attach
//         chart, plus a 30 s heartbeat) and runs from OnInit and the
//         refresh timer. The endpoint URL must be
//         whitelisted under Tools → Options → Expert Advisors → "Allow
//         WebRequest for listed URL". No drawing or markup behavior changed.
// v2.00 — consolidated release. The optional zone-fill toggle (v1.09) is
//         merged back onto the corrected v1.08 base (capped cluster spans,
//         shared-zone trade plan) and SIX markup layers ship on top:
//           1. Zone fills        InpZoneFilled — dim tint behind candles (OFF)
//           2. Liquidity pools   BSL / SSL equal-high / equal-low clusters
//           3. Premium/discount  dotted 50% equilibrium of the dealing range
//           4. Killzones         Asia / London / NY session shading (OFF)
//           5. HTF overlay       higher-timeframe OB + FVG, dimmed & labelled
//           6. JSON export       MQL5\Files\PAICT_<symbol>_<tf>.json snapshot
//         The input dialog mirrors the page reference 1:1 — General →
//         Price Action → Moving Averages (companion) → ICT/SMC → Liquidity →
//         HTF Overlay → Trade Plan → Killzones → Export → Style.
//         Adopted from an external review pass: the PAICT_VERSION macro and
//         a startup journal line that verifies the attach chart's symbol
//         digits. Everything else in that review (indicator-style
//         OnCalculate, alpha-channel "opacity", averaging cluster levels,
//         visible-range session anchors, timestamped JSON files) was
//         deliberately rejected — it conflicts with the multi-chart EA
//         architecture, MQL5's no-alpha objects, or the redraw-on-closed-bar
//         gate. No drawing or input behavior changed.
// v1.11 — input-dialog mirror patch (no drawing/runtime behavior changed):
//         the EA dialog now matches the page's "Input reference" 1:1.
//         InpFastMAPeriod / InpSlowMAPeriod move into their own
//         "Moving Averages (companion)" group (they previously sat inside
//         Price Action), the Style group moves last — after Export — so the
//         dialog reads General → Price Action → Moving Averages → ICT/SMC →
//         Liquidity → HTF Overlay → Trade Plan → Killzones → Export → Style,
//         and every input comment is aligned word-for-word with the
//         reference table on the web page.
// v1.10 — "10x" feature drop — the five carried-over requests land:
//         • Liquidity pools: equal highs / equal lows (BSL / SSL) detected by
//           small-tolerance clustering of confirmed swings (>= 2 touches);
//           dashed slate line at the pool level, labelled, nearest first,
//           InpMaxLiqPerSide per side. Inputs: InpDrawLiquidity / InpLiqTolATR.
//         • Premium / discount: 50% equilibrium of the current dealing range
//           (highest swing high vs lowest swing low) as a dotted violet line
//           with EQ 50% / premium / discount text. Input: InpDrawPremiumDiscount.
//         • Killzones: Asia / London / New York session shading (SERVER time,
//           configurable open hours, last InpKZDays days) as dim background
//           fills BEHIND candles — default OFF like InpZoneFilled, since fills
//           sit outside the "thin lines and thin boxes" spec.
//         • HTF overlay: order blocks + FVGs from a higher timeframe (input,
//           default H4) drawn dimmed with "H4 …" labels so they never collide
//           with chart-timeframe objects; auto-skipped when InpHTF <= chart TF.
//         • JSON export hook: with InpExportJSON on, every closed bar writes
//           MQL5\Files\PAICT_<symbol>_<tf>.json holding zones, order blocks,
//           FVGs, liquidity pools, equilibrium and the active trade plan —
//           ready for external dashboards (e.g. Signal Scanner Pro).
//         DrawOrderBlock / DrawFairValueGaps gained name/label prefixes, an
//         optional end-time override and a color-dim factor for the HTF reuse;
//         DrawTradePlan now reports the entry/stop/target it drew for export.
// v1.09 — the optional zone-fill toggle is back, merged onto the v1.08 base:
//         new InpZoneFilled input (default OFF, so the spec stays "thin lines
//         and thin outline boxes ONLY"). When enabled, each supply/demand
//         outline gains a background fill rectangle tinted by DimColor() —
//         the zone color blended toward the chart background because chart
//         objects have no alpha channel — placed BEHIND the candles, while
//         the thin outline itself stays foreground. Also documents the
//         deliberate v1.08 behavior change: the price-action trade-plan
//         fallback runs only when the Price Action layer is on (no zones
//         drawn -> no zone-anchored plan); the ICT order-block plan is
//         unaffected.
// v1.08 — consistency patch: supply/demand zone labels are now numbered
//         ("supply zone 1", "supply zone 2", ...) whenever several zones are
//         drawn per side — same fix pattern the FVG boxes got in v1.07.
//         ClusterSide() caps a cluster's TOTAL span at 2.5× the tolerance, so
//         a staircase of swing lows each within tolerance of the previous one
//         can no longer chain into a single zone far wider than any real zone
//         (the flush now fires when curMax - cluster's original min exceeds
//         the cap, even while each individual step stays inside tolerance).
//         The trade plan's price-action fallback no longer re-clusters swings
//         privately: DrawOnChart computes the zones once in BuildAndDrawZones
//         and hands the exact drawn boxes to DrawTradePlan, so ENTRY/STOP and
//         TARGET can only reference a supply/demand box visible on the chart.
// v1.07 — review patch: redraw only on closed bars (no per-cycle ObjectsDeleteAll
//         churn — flicker and idle CPU gone), DualMA handles of closed charts are
//         released every pass (was: leaked until exit), attaching to a second
//         chart is refused via an owner lock with stale-claim takeover, whitelist
//         matches broker suffixes ("EURUSD" also covers EURUSDz), DualMA failure
//         logs once per chart instead of every cycle, zone widening only
//         re-clusters the empty side, trend-line projection clamped to 60
//         average bar ranges, all markup drawn foreground (OBJPROP_BACK=false
//         everywhere for consistent stacking), FVG boxes numbered FVG 1/2/3,
//         OB/FVG labels anchored away from price, CHoCH dashes switched to
//         STYLE_DOT, one unified InpVerboseLog diagnostic line, and the Trade
//         Plan gained a STOP level (order-block/zone far edge + 0.10×ATR buffer)
//         plus an R:R text label between ENTRY and TARGET.
// v1.06 — supply/demand zone fix: clusters are now SIDE-AWARE (supply strictly
//         above price, demand strictly below) with adaptive tolerance widening
//         and a dominant-extreme fallback, so a support AND a resistance zone
//         always get marked whenever swings exist. Zone outlines moved in front
//         of candles so the thin borders stay readable; label text is passed
//         explicitly (fixes every label previously reading "resistance zone").
//         Chart discovery is announced in the journal, and the DualMA companion
//         no longer gates drawing — one attached EA covers every open pair even
//         if the indicator layer hiccups. New input: InpVerboseLog.
// v1.05 — new Trade Plan layer: an expected ENTRY line (amber) next to the TARGET
//         point (cyan). ICT-first: order-block proximal edge -> nearest swing
//         extreme beyond it (external liquidity). Falls back to a zone-edge ->
//         opposite-zone price-action plan. Inputs: InpDrawPlan / InpPlanBars.
// v1.04 — runtime fix: DrawBreakDash() could index rates[lastClosed+2] (one past the
//         forming bar) whenever the latest CHoCH/MSS break was within 5 bars of now.
//         Critical 'array out of range' on the first tick unloads the EA immediately
//         (indicator loads, expert removed). Dash end is now clamped to lastClosed+1.
// v1.03 — fixed MetaEditor compile errors: OBJ_TRENDLINE -> OBJ_TREND (MQL5 name),
//         DrawFairValueGaps() now receives the timeframe used by PeriodSeconds().

/* ------------------------------------------------------------------ */
/* Palette (matches the reference page)                                */
/* ------------------------------------------------------------------ */
#define COL_SUPPORT   C'16,185,129'   // emerald
#define COL_RESIST    C'239,68,68'    // red
#define COL_TREND     C'37,99,235'    // blue
#define COL_OB_BULL   C'20,184,166'   // teal
#define COL_OB_BEAR   C'249,115,22'   // orange
#define COL_FVG       C'250,204,21'   // yellow
#define COL_CHOCH     C'236,72,153'   // magenta
#define COL_STRUCT    C'59,130,246'   // blue (wide)
#define COL_ENTRY     InpEntryColor   // v2.05: user-adjustable input (strong gold default)
#define COL_TARGET    InpTargetColor  // v2.05: user-adjustable input (vivid green default)
#define COL_STOP      InpStopColor    // v2.05: user-adjustable input (vivid red default)
#define COL_LIQ       C'148,163,184'  // slate — liquidity pools (BSL / SSL)
#define COL_EQ        C'167,139,250'  // violet — premium / discount equilibrium
#define COL_KZ_ASIA   C'100,116,139'  // slate — Asia killzone tint
#define COL_KZ_LON    C'245,158,11'   // amber — London killzone tint
#define COL_KZ_NY     C'6,182,212'    // cyan — New York killzone tint
#define COL_OTE       C'196,181,253'  // v11.00: light violet — OTE Fibonacci pocket
#define COL_DOPEN     C'226,232,240'  // v11.00: pale slate — daily / weekly open lines
#define COL_BREAKER   C'244,63,94'    // v12.00: rose — breaker block (role-flipped OB)
#define COL_SPARK     C'34,197,94'    // v13.00: green — equity sparkline (red when net down)

#define OBJ_PREFIX    "PAICT_"
#define IND_SHORTNAME "PAICT DualMA"
#define GV_OWNER      "PAICT_ChartMarkup_Owner"
#define PAICT_VERSION "24.00"  // single source of truth for journal output

/* ------------------------------------------------------------------ */
/* v2.07 tuning constants — every formerly-hardcoded heuristic, named. */
/* Tune here without digging through the logic that uses them.          */
/* ------------------------------------------------------------------ */
#define ARRAY_RESERVE_CHUNK  64     // ArrayResize reserve_size for grow-in-loop arrays
#define ZONE_MIN_HALF_ATR    0.18   // zone box: min half-height × ATR (thin but visible)
#define ZONE_FILL_TINT       0.18   // zone fill blend strength toward background (0..1)
#define ZONE_RESCAN_WIDEN    3.0    // empty-side re-cluster: tolerance × per pass
#define ZONE_LASTRESORT_ATR  0.15   // dominant-extreme fallback zone height × ATR
#define ZONE_MAX_SPAN_MULT   2.5    // ClusterSide: max cluster span × tolerance
#define KZ_TINT_STRENGTH     0.10   // killzone session fill blend toward background
#define KZ_LOOKBACK_BARS     40     // killzone ceiling scan depth (bars)
#define KZ_TOP_ATR           8.0    // killzone ceiling above range high × ATR
#define KZ_LBL_ATR           1.2    // killzone label offset above range high × ATR
#define HTF_DIM_STRENGTH     0.55   // HTF overlay color dim (0..1 = color kept)
#define HTF_MIN_BARS         40     // HTF overlay: minimum usable bars
#define HTF_NEED_BARS        120    // HTF overlay: CopyRates request size
#define TREND_MAX_EXT_RANGES 60.0   // trend projection cap (× average bar range)
#define TREND_EXT_MULT       3      // trend line right extension × InpExtendRightBars
#define EQ_EXT_MULT          2      // EQ line right extension × InpExtendRightBars
#define STRUCT_DASH_CTX      6      // CHoCH / MSS dash context bars on each side
#define FVG_BODY_ATR         0.8    // FVG mid-candle body threshold × displacement
#define PLAN_STOP_BUF_ATR    0.10   // trade plan stop buffer beyond the far edge × ATR
#define BRIDGE_HEARTBEAT_SEC 30     // bridge heartbeat / failure retry throttle (s)
#define BRIDGE_BODY_SNIP     200    // bridge: reply-body snippet length in the journal
#define BRIDGE_HDR_SNIP      80     // bridge: forensics header-buffer snippet length
#define BRIDGE_HEX_SNIP      32     // bridge: forensics hex-dump byte count

/* ------------------------------------------------------------------ */
/* v4.00 co-pilot constants                                            */
/* ------------------------------------------------------------------ */
#define HUD_X                10     // HUD left inset (pixels)
#define HUD_Y                20     // HUD top inset (pixels)
#define HUD_LINE_H           15     // HUD line spacing (pixels)
#define HUD_FONT             9      // HUD main line font size
#define HUD_FONT_ALERT       11     // HUD alert line font size
#define NEWS_SCAN_SEC        600    // economic calendar rescan interval (s)
#define NEWS_LOOKAHEAD_SEC   86400  // high-impact event cache horizon (s)
#define NEWS_WASH_STRENGTH   0.30   // plan-band color kept during a blackout (0..1)
#define REMOTE_MAX_VALUE     10.0   // SET_RISK sanity clamp (max risk %)
#define REMOTE_MIN_VALUE     0.05   // SET_RISK sanity clamp (min risk %)

/* ------------------------------------------------------------------ */
/* v5.00 AI desk constants                                             */
/* ------------------------------------------------------------------ */
#define SELF_HEAL_REARM_BARS  50     // muted setup re-arms after N closed bars
#define TUNER_SCAN_SEC        60     // tuner suggestion file rescan interval (s)
#define TUNER_MAX_LINES       8      // tuner: max KEY=VALUE lines read per file
#define TUNER_VALUE_MAXLEN    24     // tuner: max chars per value (sanity clamp)

/* ------------------------------------------------------------------ */
/* v6.00 microstructure constants                                      */
/* ------------------------------------------------------------------ */
#define VP_MAX_ROWS           40     // volume profile: hard cap on price buckets
#define VP_VALUE_AREA_PCT     0.70   // VAH/VAL: volume share inside the value area
#define VP_ROW_COLOR          C'100,116,139'  // slate profile row fill
#define CONE_LOOKBACK_BARS    200    // probability cone: |Δclose| statistics window
#define CONE_SIGMAS           2.0    // probability cone: band width (std devs)
#define ALIGN_TFS_TOTAL       5      // fractal matrix: M1 M5 M15 H1 H4

/* ------------------------------------------------------------------ */
/* v7.00 simulation constants                                          */
/* ------------------------------------------------------------------ */
#define MC_MAX_RUNS           50000  // Monte Carlo hard cap per evaluation
#define MC_MAX_BARS           200    // Monte Carlo horizon cap (bars)
#define DOM_WIDTH_BARS        14     // DOM ladder strip: max length (bars)
#define DOM_MAX_LEVELS        10     // DOM ladder strip: levels per side (cap)

/* ------------------------------------------------------------------ */
/* v8.00 order flow constants                                          */
/* ------------------------------------------------------------------ */
#define CVD_MAX_SEGMENTS      32     // CVD curve polyline segments (cap)
#define CVD_BAND_FRAC         0.16   // CVD curve occupies the bottom 16% of the range
#define ABSORB_VOL_MULT       1.80   // absorption: tick volume ≥ mean × this multiplier
#define ABSORB_BODY_ATR       0.30   // absorption: max body size × ATR ("small body")
#define SWEEP_SCAN_BARS       10     // sweep/fakeout: raid search depth (closed bars)
#define DISP_GRADE_ATR_STEP   0.20   // displacement grade: +1 per 0.20 ATR of break body

/* ------------------------------------------------------------------ */
/* v9.00 intermarket constants                                         */
/* ------------------------------------------------------------------ */
#define TSoup_LOOKBACK        20     // Turtle Soup: prior-extreme window (bars)
#define TSoup_TOL_ATR         0.10   // Turtle Soup: max raid distance beyond the extreme
#define DAY_OPEN_MAX_BARS     200    // Power of 3: search depth for today's opening bar

/* ------------------------------------------------------------------ */
/* v10.00 zenith constants                                             */
/* ------------------------------------------------------------------ */
#define MASTER_FONT           15     // Master Score verdict font size
#define MASTER_HALF_W         62     // Master Score label half-width estimate (px)
#define MASTER_Y              4      // Master Score label y inset (px)
#define ORACLE_FONT           11     // Oracle Score label font size
#define ORACLE_HALF_W         70     // Oracle Score label half-width estimate (px)
#define ORACLE_Y              (MASTER_Y + 22) // below the Master Score verdict
#define ZEN_HUD_Y_OFF         84     // zenith HUD block starts below the v4 HUD lines

/* ------------------------------------------------------------------ */
/* v11.00 upgrade constants                                            */
/* ------------------------------------------------------------------ */
#define ALERT_TOL_ATR         0.10   // price-in-zone alert: ENTRY band tolerance × ATR
#define ALERT_COOLDOWN_MIN_DEF 15    // default minutes between repeat alerts of one kind

/* ------------------------------------------------------------------ */
/* v12.00 execution-layer constants                                    */
/* ------------------------------------------------------------------ */
#define BREAKER_DISP_ATR      1.0    // breaker: opposite-direction body × ATR on the break bar

/* ------------------------------------------------------------------ */
/* v13.00 performance-analytics constants                              */
/* ------------------------------------------------------------------ */
#define STATS_SCAN_SEC_DEF    120    // trade-journal rescan interval (s)
#define STATS_MAX_ROWS_DEF    500    // trade-journal: max recent rows read per scan
#define SPARK_MAX_SEGMENTS    24     // equity sparkline polyline segments (cap)
#define SPARK_WIDTH_BARS      20     // equity sparkline: pixel-mapped width (bars)
#define SPARK_BAND_ATR        3.0    // equity sparkline: vertical band height × ATR

/* ------------------------------------------------------------------ */
/* v14.00 adaptive-risk constants                                      */
/* ------------------------------------------------------------------ */
#define VOL_REGIME_BARS_DEF   60     // ATR-vs-average window (bars)
#define VOL_HIGH_RATIO        1.5    // ATR / avgATR ratio that reads as "HIGH" regime
#define VOL_LOW_RATIO         0.7    // ATR / avgATR ratio that reads as "LOW" regime
#define PLAN_CANDIDATES_DEF   3      // best-of-N unmitigated order blocks scored per side

/* ------------------------------------------------------------------ */
/* v15.00 cockpit-summary constants                                    */
/* ------------------------------------------------------------------ */
#define LEADERBOARD_ROWS_DEF  3      // leaderboard: rows shown on the HUD
#define LEADERBOARD_FONT      9      // leaderboard: HUD font size

/* ------------------------------------------------------------------ */
/* Inputs                                                              */
/* ------------------------------------------------------------------ */
input group "General"
input bool   InpDrawPriceAction = true;          // Master toggle for zones / trend line (also gates the PA plan fallback)
input bool   InpDrawICT         = true;          // Master toggle for OB / FVG / CHoCH / MSS
input int    InpRefreshSeconds  = 2;             // Redraw cycle across discovered charts
input string InpSymbolWhitelist = "";            // CSV of symbols; empty = all open charts
input bool   InpVerboseLog      = false;         // Journal diagnostics: covered charts + swing/zone counts
input bool   InpPauseRender     = false;         // v3.00: pause DRAWING only — state calc + bridge keep running

input group "Price Action"
input int    InpLookbackBars    = 160;           // How far back swing detection scans
input int    InpSwingStrength   = 3;             // Fractal strength (bars on each side)
input double InpZoneATRTolerance= 0.35;          // Cluster tolerance × ATR before merging touches
input int    InpZonesPerSide    = 2;             // Zones drawn above and below price
input bool   InpDrawTrendLine   = true;          // Rising/falling line through last two swings

input group "Moving Averages (companion)"
input int    InpFastMAPeriod    = 5;             // Passed to PAICT_DualMA when attaching
input int    InpSlowMAPeriod    = 15;            // Must exceed fast period at runtime

input group "ICT / SMC"
input int    InpICTLookback     = 180;           // Scan depth for order blocks & FVGs
input double InpDisplacementATR = 1.10;          // Body threshold × ATR qualifying displacement
input int    InpMaxFVG          = 3;             // Maximum open FVG boxes displayed
input bool   InpDrawOB          = true;          // Per-layer toggle: order blocks
input bool   InpDrawFVG         = true;          // Per-layer toggle: fair value gaps
input bool   InpDrawStructure   = true;          // Per-layer toggle: CHoCH & MSS/BOS dashes
input bool   InpDrawPremiumDiscount = true;      // Dotted 50% EQ of the dealing range

input group "Liquidity"
input bool   InpDrawLiquidity   = true;          // BSL / SSL pools from equal highs & lows
input double InpLiqTolATR       = 0.15;          // Pool equality tolerance × ATR
input int    InpMaxLiqPerSide   = 1;             // Pools drawn per side (nearest first)

input group "HTF Overlay"
input bool   InpDrawHTF         = true;          // Higher-timeframe OB + FVG, dimmed & labelled
input ENUM_TIMEFRAMES InpHTF    = PERIOD_H4;     // Skipped automatically when ≤ the chart timeframe

input group "Trade Plan"
input bool   InpDrawPlan        = true;          // ENTRY / TARGET / STOP level lines + R:R label
input int    InpPlanBars        = 10;            // Plan segment length back from the current bar
input color  InpEntryColor      = C'255,191,0';  // ENTRY line color — strong gold
input color  InpStopColor       = C'255,59,48';  // STOP line color — vivid red
input color  InpTargetColor     = C'0,220,130';  // TARGET line color — vivid green
input int    InpPlanWidth       = 2;             // Plan line thickness (1 = old thin style)
input bool   InpPlanLabelPrice  = true;          // Append the level price to plan labels
input bool   InpPlanZones       = true;          // v2.06: filled ENTRY / STOP / TARGET zone rectangles
input double InpPlanZoneHeightATR = 0.20;        // v2.06: zone band height × ATR (slim strip)
input bool   InpPlanZoneBack    = false;         // v2.06: true = tint behind candles, false = solid band in front

input group "Killzones (server time)"
input bool   InpDrawKillzones   = false;         // Dim Asia / London / NY session shading
input int    InpKZAsiaStart     = 0;             // Asia session open hour (broker time)
input int    InpKZLondonStart   = 8;             // London session open hour (broker time)
input int    InpKZNewYorkStart  = 13;            // New York session open hour (broker time)
input int    InpKZLengthHours   = 3;             // Session length (Asia draws double)
input int    InpKZDays          = 2;             // Days of history to shade

input group "Export"
input bool   InpExportJSON      = false;         // Rewrite MQL5\Files\PAICT_<symbol>_<tf>.json every closed bar

input group "Web Bridge (matrix push)"
input bool   InpBridgeEnabled   = true;              // POST the live trade plan to a local HTTP bridge
input string InpBridgeURL       = "http://127.0.0.1:8891/v1/matrix"; // Endpoint (whitelist host in MT5 options!)
input int    InpBridgeTimeoutMs = 3000;              // WebRequest timeout (ms)
input bool   InpBridgeVerbose   = true;              // Journal every push result
input bool   InpRemoteControl   = true;              // v4.00: apply whitelisted commands the bridge hands back

input group "Risk Copilot (v4.00)"
input bool   InpRiskHUD        = true;           // Simulated risk sizing on the chart HUD
input double InpRiskPercent    = 1.0;            // Risk per trade (% of account balance)
input bool   InpHeatTracker    = true;           // Portfolio heat across open MANUAL trades
input double InpMaxHeatPct     = 3.0;            // "MAX PORTFOLIO HEAT" flash threshold (%)

input group "News Blackout (v4.00)"
input bool   InpNewsBlackout   = true;           // Red column + washed plan bands around high-impact news
input int    InpNewsPreMin     = 15;             // Blackout starts N minutes BEFORE the release
input int    InpNewsPostMin    = 5;              // Blackout ends N minutes AFTER the release

input group "AI Desk (v5.00)"
input bool   InpTradeJournal     = true;        // OnTrade auto-journal: CSV row per manual close
input bool   InpSelfHeal         = true;        // mute a setup after N consecutive stop-outs
input int    InpSelfHealFails    = 5;           // consecutive STOP hits before the setup mutes
input bool   InpTunerFile        = true;        // show MQL5\Files\PAICT_TunerSuggestion.txt on the HUD

input group "Microstructure (v6.00)"
input bool   InpVolumeProfile    = true;        // session volume profile + POC / VAH / VAL
input int    InpVPRows           = 24;          // profile price buckets (4..40)
input int    InpVPDays           = 3;           // sessions aggregated (bounded by the lookback)
input int    InpVPWidthBars      = 18;          // histogram length from the session open (bars)
input bool   InpFractalAlign     = true;        // M1-H4 trend alignment matrix (HUD + payload)
input bool   InpProbabilityCone  = false;       // statistical projection right of the last bar
input int    InpConeBars         = 12;          // cone horizon (bars)

input group "Simulation (v7.00)"
input bool   InpMonteCarlo       = true;        // random-walk TP/SL probability for the plan
input int    InpMCRuns           = 10000;       // runs per evaluation (100..50000)
input int    InpMCBars           = 40;          // horizon before a run scores as timeout
input bool   InpDrawDOM          = false;       // Depth of Market ladder strip (broker DOM needed)
input int    InpDOMLevels        = 6;           // ladder rows rendered per side (1..10)

input group "Order Flow (v8.00)"
input bool   InpCVD              = true;        // tick-volume CVD curve + divergence labels
input int    InpCVDLength        = 80;          // CVD lookback (bars, 24..300)
input bool   InpSweepTags        = true;        // TRUE SWEEP vs FAKEOUT tags on BSL/SSL raids
input bool   InpAbsorption       = true;        // absorption dots on small-body high-volume OBs
input bool   InpDisplacementGrade = true;       // 1-10 displacement grade after every CHoCH/MSS

input group "Intermarket (v9.00)"
input bool   InpCorrelation      = true;        // cross-chart correlation watch (HUD + payload)
input int    InpCorrBars         = 60;          // Pearson window (bars)
input double InpCorrWarn         = 0.30;        // |r| below this while trending = diverging
input bool   InpICTPatterns      = true;        // Turtle Soup / AMD phase / Power-of-3 day open

input group "Zenith Terminal (v10.00)"
input bool   InpSandbox          = true;        // draggable ENTRY / STOP / TARGET sandbox lines
input bool   InpMasterScore      = true;        // 0-100 GO / WAIT / NO TRADE fusion read
input int    InpMasterGoAt       = 70;          // score >= this reads GO
input int    InpMasterWaitAt     = 45;          // score >= this reads WAIT, below = NO TRADE
input bool   InpMailboxIPC       = true;        // zero-HTTP mailbox: MQL5\Files\PAICT_matrix_snapshot.json

input group "10x Upgrade (v11.00)"
input bool   InpDrawOTE           = true;       // dotted OTE (62%-79% retracement) Fibonacci pocket
input double InpOTEFibLow         = 0.62;       // OTE zone near edge (fraction of the swing leg)
input double InpOTEFibHigh        = 0.79;       // OTE zone far edge (fraction of the swing leg)
input bool   InpDrawDayWeekOpens  = true;       // dotted daily / weekly open reference lines
input bool   InpPriceAlerts       = true;       // SendNotification/Alert when price enters ENTRY/STOP/TARGET
input int    InpAlertCooldownMin  = 15;         // minutes between repeat alerts of the same kind

input group "Execution Layer (v12.00)"
input bool   InpBreakerBlocks     = true;       // redraw a mitigated OB as a role-flipped breaker block
input bool   InpStructureShiftTag = true;       // tag the plan "STRUCTURE SHIFT" on a counter-trend CHoCH

input group "Performance Analytics (v13.00)"
input bool   InpTradeStats        = true;       // win% / expectancy HUD from the trade journal CSV
input int    InpStatsScanSec      = 120;        // journal rescan interval (s)
input int    InpStatsMaxRows      = 500;        // max recent journal rows read per scan
input bool   InpEquitySpark       = true;       // equity mini-sparkline from the journal balance column

input group "Adaptive Risk (v14.00)"
input bool   InpVolRegime         = true;       // ATR-vs-average volatility regime + suggested risk %
input int    InpVolRegimeBars     = 60;         // trailing window for the ATR average (bars)
input double InpVolMinRiskPercent = 0.25;       // floor for the suggested risk % in a HIGH regime
input int    InpPlanCandidates    = 3;          // best-of-N unmitigated order blocks scored per side

input group "Cockpit Summary (v15.00)"
input bool   InpLeaderboard       = true;       // cross-chart Master Score leaderboard on the HUD
input int    InpLeaderboardRows   = 3;          // leaderboard rows shown
input bool   InpSessionCountdown  = true;       // "NEXT: LONDON opens in 41m" HUD line

input group "Regime & Volatility (v16.00)"
input bool   InpRegime           = true;        // Hurst + Kaufman ER regime classification (TRENDING/RANGING/TRANSITION)
input int    InpRegimeBars       = 100;         // lookback window for Hurst / KER
input bool   InpVcv              = true;        // Bollinger-inside-Keltner volatility contraction (squeeze/cone)

input group "Confluence Fusion (v17.00)"
input bool   InpConfluence       = true;        // stack independent signals into a 0-100 agreement score

input group "Pattern Geometry (v18.00)"
input bool   InpHarmonics        = true;        // XABCD harmonic pattern scan (Gartley/Bat/Butterfly/Crab)
input double InpHarmonicTolPct   = 6.0;         // tolerance band (% of leg) around each canonical ratio
input bool   InpElliottWave      = true;        // simplified Elliott Wave count over confirmed swings

input group "Macro Crosscurrents (v19.00)"
input bool   InpYieldCurve       = false;       // yield curve spread + inversion flag (needs bond CFD symbols)
input string InpYieldShort       = "";          // short-end bond CFD symbol, e.g. "US2Y"
input string InpYieldLong        = "";          // long-end bond CFD symbol, e.g. "US10Y"
input bool   InpLeadLag          = false;       // intermarket lead/lag flash
input string InpLeadSymbol       = "";          // correlated leading symbol to watch
input double InpLeadAtrMult      = 0.8;         // flash when the lead symbol moves >= this x its own ATR

input group "The Oracle (v20.00)"
input bool   InpOracleScore      = true;        // master 45% + confluence 25% + flow 15% + regime 15% fusion
input int    InpOracleGoAt       = 85;          // Oracle Score >= this flashes PERFECT SETUP
input bool   InpJournal          = true;        // double-click chart to pin a price/time note
input string InpJournalFile      = "PAICT_Notes.csv"; // journal file under MQL5\Files\

input group "Local Market Profile (v21.00)"
input bool   InpTpoProfile      = true;         // session TPO profile (POC/Value Area/single prints)
input int    InpTpoPeriodMin    = 30;           // minutes per TPO letter period

input group "Walk-Forward Matrix (v22.00)"
input bool   InpWalkForward     = true;         // historical win%/expectancy for the CURRENT setup
input int    InpWalkForwardBars = 1000;         // lookback window (bars)

input group "Statistical Arbitrage (v23.00)"
input bool   InpStatArb         = false;        // Z-score spread vs. the strongest correlated symbol
input int    InpStatArbBars     = 100;          // spread lookback window (bars)
input double InpStatArbZ        = 2.0;          // |Z| >= this flashes STAT ARB OPPORTUNITY

input group "Options Greeks (v24.00)"
input bool   InpOptionsGreeks   = false;        // local Black-Scholes IV/gamma (needs broker option symbols)
input string InpOptCallSymbol   = "";           // call option symbol, e.g. broker-specific
input string InpOptPutSymbol    = "";           // put option symbol
input double InpOptStrike       = 0.0;          // strike price shared by both legs
input datetime InpOptExpiry     = 0;            // expiry (server time); 0 = read SYMBOL_EXPIRATION_TIME
input double InpOptRiskFreeRate = 0.05;         // annualized risk-free rate used in the BS model

input group "Style"
input int    InpExtendRightBars = 8;             // Right-edge extension of boxes
input bool   InpShowLabels      = true;          // Small text labels beside objects
input bool   InpZoneFilled      = false;         // Dim tint inside zones, behind candles (off = outline only)
input int    InpATRPeriod       = 14;            // ATR period driving tolerances

/* ------------------------------------------------------------------ */
/* State                                                               */
/* ------------------------------------------------------------------ */
struct SZoneBox
  {
   double   p_low;
   double   p_high;
   datetime t_start;
   int      touches;
  };

struct SAtrCache
  {
   string           symbol;
   ENUM_TIMEFRAMES  tf;
   int              handle;
  };

struct SIndPair
  {
   long             chart_id;
   int              handle;
   int              attempts;   // failed DualMA attach tries (log-once sentinel)
  };

struct SChartState
  {
   long             chart_id;
   datetime         last_bar;   // last CLOSED bar this chart was drawn for
   int              last_data_err;   // v2.07 throttle: last CopyRates error journaled (-1 = none)
   string           symbol;     // v15.02: symbol this chart was covering last pass
   ENUM_TIMEFRAMES  tf;         // v15.02: timeframe this chart was covering last pass
  };

SAtrCache   g_atr[];        // cached ATR handles per symbol/tf
SIndPair    g_ind[];        // DualMA instances per chart id (incl. failed tries)
SChartState g_charts[];     // per-chart journal + new-bar redraw gate
datetime    g_lastRun   = 0;
int         g_fastMaP   = 5;
int         g_slowMaP   = 15;
int         g_refreshS  = 2;
long        g_ownChart  = 0;   // chart that owns the single-instance lock
bool        g_claimed   = false; // true only for the instance that actually claimed GV_OWNER
bool        g_drawSuppressed = false; // v15.02: InpPauseRender/SET_RENDER=0 — Upsert* no-ops, calc keeps running
string      g_bridgeLastJSON = "";   // web bridge: last payload pushed (dedupe)
datetime    g_bridgeLastTry  = 0;    // web bridge: last push attempt (throttle)
datetime    g_bridgeLastBar  = 0;    // web bridge: attach-chart bar at last push
bool        g_manualAtrWarned = false;  // v2.07: ATR fallback journaled once per session

/* ------------------------------------------------------------------ */
/* v4.00 co-pilot state                                                */
/* ------------------------------------------------------------------ */
// Runtime mirrors of user inputs. MQL5 inputs are read-only while the EA
// runs, so remote-control commands write THESE; they are (re)initialized
// from the inputs on every attach / recompile / input change.
struct SOverrides
  {
   double riskPct;     // active risk % per trade (mirror of InpRiskPercent)
   bool   planZones;   // plan bands enabled (mirror of InpPlanZones)
   bool   render;      // markup rendering enabled (SET_RENDER command)
   bool   sandbox;     // v10.00: draggable sandbox lines enabled (TOGGLE_SANDBOX)
  };
SOverrides g_ov;

// Economic-calendar cache: high-impact events for the attach symbol's
// two currencies, rescanned every NEWS_SCAN_SEC.
struct SNewsEvent
  {
   datetime time;
   string   name;
   string   currency;
  };
SNewsEvent g_news[];
datetime    g_newsScan        = 0;     // last calendar scan (throttle)
bool        g_newsUnavailable = false; // broker without a calendar — warn once
bool        g_heatBlink       = false; // MAX HEAT flash alternator

/* ------------------------------------------------------------------ */
/* v5.00 AI desk state                                                 */
/* ------------------------------------------------------------------ */
struct SSetupHeal
  {
   string   key;        // "SYMBOL|TF"
   int      fails;      // consecutive plans whose STOP was hit before TARGET
   datetime mutedFrom;  // closed-bar time the mute engaged (0 = not muted)
   double   planE;      // last plan instance seen (entry) — verdicts are one-per-plan
   double   planS;      // ... (stop)
   double   planT;      // ... (target)
   bool     judged;      // this plan instance already produced a stop/target verdict
  };
SSetupHeal g_heal[];                 // self-heal state per symbol|TF
bool       g_journalWarned = false;  // journal file-open failure — warn once
datetime   g_tunerScan     = 0;      // tuner file last scan (throttle)
string     g_tunerKeys[];            // whitelisted tuner suggestion keys ...
string     g_tunerVals[];            // ... and their values (display-only)
bool       g_domWarned     = false;  // broker without Depth of Market — warn once
string     g_domSubs[];              // symbols currently subscribed via MarketBookAdd

/* ------------------------------------------------------------------ */
/* v6.00-v9.00 metric bus — every analyzer stashes its latest numbers  */
/* here; the Zenith Master Score and the matrix payload read them.     */
/* ------------------------------------------------------------------ */
int      g_alignScore  = 0;    // -5..+5 (M1..H4 bull count minus bear count)
string   g_alignDetail = "";   // "M1+ M5- M15+ H1+ H4-"
double   g_mcTP        = 0.0;  // Monte Carlo P(touch TP first) in %
double   g_mcSL        = 0.0;  // Monte Carlo P(touch SL first) in %
int      g_cvdDir      = 0;    // CVD slope sign: 1 up / -1 down / 0 flat
bool     g_cvdDiv      = false;// CVD/price divergence present
bool     g_dispLong    = false;// last CHoCH/MSS broke upward (displacement direction)
int      g_dispGrade   = 0;    // 1..10 displacement grade at the last CHoCH/MSS
string   g_corrSym     = "";   // strongest correlated covered symbol
double   g_corrR       = 0.0;  // Pearson r of returns vs that symbol
bool     g_corrWarn    = false;// diverging warning active
double   g_vpPoc       = 0.0;  // volume profile levels (payload)
double   g_vpVah       = 0.0;
double   g_vpVal       = 0.0;
bool     g_tsoupBull   = false;// Turtle Soup tags fired on the current bar
bool     g_tsoupBear   = false;

/* ------------------------------------------------------------------ */
/* v10.00 zenith state                                                 */
/* ------------------------------------------------------------------ */
struct SSandbox
  {
   bool   active;      // lines anchored from a live plan
   double entry;       // CURRENT (possibly user-dragged) levels
   double stop;
   double tp;
   double planEntry;   // plan the sandbox was anchored to — a fresh plan re-anchors
   double planStop;
   double planTarget;
  };
SSandbox g_sb;
bool     g_sbDirty       = false; // a line was dragged — refresh HUD + payload
int      g_masterScore   = -1;    // 0..100 (-1 = not computable)
string   g_masterVerdict = "";    // GO / WAIT / NO TRADE
int      g_oracleScore   = -1;    // v20.00: fused 0..100 (-1 = not computable)
bool     g_oraclePerfect = false; // v20.00: g_oracleScore >= InpOracleGoAt
bool     g_setupMuted    = false; // attach chart's self-heal mute state (HUD + payload)

// Attach chart's zenith metric snapshot for the bridge payload — filled in
// DrawOnChart right after the attach chart's render pass (the globals hold
// whatever chart rendered LAST, so the payload must copy them per chart).
struct SZenSnap
  {
   int    align;      // -5..+5 fractal alignment
   double mcTP;       // Monte Carlo P(TP first) %
   double mcSL;       // Monte Carlo P(SL first) %
   int    cvdDir;     // CVD slope sign: 1 / -1 / 0
   bool   cvdDiv;     // CVD/price divergence present
   int    disp;       // displacement grade 1..10 (0 = none)
   string corrSym;    // strongest correlated covered symbol
   double corrR;      // Pearson r of returns
   bool   corrWarn;   // diverging flag
   double poc;        // volume profile levels
   double vah;
   double val;
   int    master;     // Master Score 0..100 (-1 = n/a)
   string verdict;    // GO / WAIT / NO TRADE
   bool   muted;      // self-heal mute active
   bool   sbActive;   // sandbox levels present
   double sbE;        // sandbox (possibly dragged) levels
   double sbS;
   double sbT;
   bool   oteOk;      // v11.00: OTE zone present
   double oteLow;     // v11.00: OTE zone edges
   double oteHigh;
   bool   oteBullish; // v11.00: OTE zone direction
   double dOpen;      // v11.00: today's D1 open
   double wOpen;       // v11.00: this week's W1 open
   bool   planShiftWarn;     // v12.00: active plan contradicted by a fresher CHoCH
   string volRegime;         // v14.00: HIGH / NORMAL / LOW
   double suggestedRiskPct;  // v14.00: scaled-down risk % suggestion
   double statsWinPct;       // v13.00: journal win rate %
   double statsExpectancyR;  // v13.00: journal expectancy in R-multiples
   int    statsTrades;       // v13.00: journal trade count used
   // v16.00-v20.00: Oracle engine
   string regime;
   double hurst;
   double ker;
   double vcvSqueeze;
   bool   vcvCone;
   int    confluence;
   int    confCount;
   string confTags;
   string harmonic;
   int    harmDir;
   double przLo;
   double przHi;
   string elliott;
   int    ewDir;
   bool   ycOk;
   double ycSpread;
   bool   ycInverted;
   string leadSym;
   double leadMove;
   int    leadDir;
   bool   leadFlash;
   int    oracleScore;
   // v21.00-v24.00
   bool   tpoOk;
   double tpoPoc;
   double tpoVah;
   double tpoVal;
   int    tpoSinglePrints;
   bool   tpoPoorHigh;
   bool   tpoPoorLow;
   double wfWinPct;
   double wfExpectancyR;
   int    wfTrades;
   double statArbZ;
   bool   statArbFlag;
   string statArbSym;
   bool   optOk;
   double ivCall;
   double ivPut;
   double gammaLevel;
  };
SZenSnap g_zen;

// v11.00 price-in-zone alerts, throttled per KIND *and* per PLAN so
// watching several pairs does not spam mobile push, and a freshly formed
// plan is never suppressed by a cooldown a DIFFERENT, older plan left
// behind. v15.03: ENTRY/STOP/TARGET each get their OWN remembered
// (planKey, time) slot — a single shared slot (v15.01) meant firing STOP
// then ENTRY seconds later overwrote ENTRY's own cooldown clock, so
// switching kinds could bypass a kind's cooldown entirely.
string   g_lastAlertKind[3]    = {"ENTRY", "STOP", "TARGET"};
string   g_lastAlertPlanKey[3] = {"", "", ""};
datetime g_lastAlertTimeAt[3]  = {0, 0, 0};

/* ------------------------------------------------------------------ */
/* v20.00 on-chart journal — double-click a chart to pin a note at the */
/* clicked price/time; persisted to MQL5\Files\InpJournalFile and      */
/* pushed as notes[] in the bridge payload.                            */
/* ------------------------------------------------------------------ */
struct SJournalNote
  {
   string   timeStr;   // ISO-ish string for the JSON payload
   datetime t;          // pinned bar time
   double   price;      // pinned price
   string   text;       // note body
  };
SJournalNote g_journalNotes[];
ulong        g_lastClickMs   = 0;      // GetTickCount() of the previous click
int          g_lastClickX    = -1000;
int          g_lastClickY    = -1000;
#define JOURNAL_DBLCLICK_MS   400      // max gap between clicks to count as a double-click
#define JOURNAL_DBLCLICK_PX   6        // max pixel drift between the two clicks

/* ------------------------------------------------------------------ */
/* v13.00 performance analytics state                                  */
/* ------------------------------------------------------------------ */
datetime g_statsScan       = 0;      // journal rescan throttle
double   g_statsWinPct     = 0.0;
double   g_statsExpR       = 0.0;
int      g_statsTrades     = 0;
double   g_statsBalances[];          // cumulative balanceAfter series for the sparkline

/* ------------------------------------------------------------------ */
/* v15.00 cross-chart leaderboard                                      */
/* ------------------------------------------------------------------ */
struct SLeaderRow
  {
   string key;        // "SYMBOL|TF" — same symbol on two timeframes gets two rows
   string label;       // "SYMBOL TF" for display
   int    score;
   string verdict;
  };
SLeaderRow g_leader[];   // one row per covered chart, refreshed as each renders

// v10.01 hotfix: SMarketState moved ABOVE its first use — SelfHealUpdate()
// takes one, and MQL5 requires a type to be declared before the first
// function signature that uses it (it used to be defined at ~line 2100).

/* ------------------------------------------------------------------ */
/* SMarketState — one struct holding EVERYTHING CalculateMarketState   */
/* detected for a chart from confirmed bars. RenderMarketState draws   */
/* it; the JSON export and the Web Bridge read it directly (no chart-  */
/* object scraping). This is the seam a future execution layer plugs   */
/* into: run CalculateMarketState() with no chart open at all.         */
/* ------------------------------------------------------------------ */
struct SMarketState
  {
   bool             ok;             // usable data (rates loaded, enough history)
   string           symbol;
   ENUM_TIMEFRAMES  tf;
   int              lastClosed;     // index of the last CLOSED bar
   datetime         closedBar;      // its open time (new-bar gate bookkeeping)
   double           atr;
   double           closeRef;
   // swing detection (shared by zones / trend / structure / plan)
   int              hiIdx[];
   double           hiVal[];
   int              loIdx[];
   double           loVal[];
   int              nHi;
   int              nLo;
   // supply / demand (side-split, nearest-first, size-capped)
   SZoneBox         supply[];
   SZoneBox         demand[];
   int              zonesDrawn;
   // ICT
   int              bullIdx;
   int              bearIdx;
   double           fvgLo[];
   double           fvgHi[];
   datetime         fvgT1[];
   int              fvgCount;
   int              chocIdx;        double chocLvl;   // CHoCH dash
   int              mssIdx;         double mssLvl;   // MSS / BOS dash
   int              structCount;
   // liquidity + premium / discount
   double           bslLv[];        datetime bslT[];
   double           sslLv[];        datetime sslT[];
   int              liqDrawn;
   double           eq;
   double           rangeHi;        double rangeLo;
   datetime         eqT0;
   // trade plan
   bool             planOk;
   double           planEntry;
   double           planStop;
   double           planTarget;
   // v11.00: OTE Fibonacci pocket of the latest swing leg
   bool             oteOk;
   double           oteLow;
   double           oteHigh;
   bool             oteBullish;
   datetime         oteT0;
   // v11.00: daily / weekly open reference lines
   double           dOpen;
   datetime         dOpenT;
   double           wOpen;
   datetime         wOpenT;
   // v12.00: breaker block (a mitigated OB that flipped polarity)
   bool             breakerOk;
   bool             breakerWasBull;   // the ORIGINAL order block's side before the flip
   double           breakerLo;
   double           breakerHi;
   datetime         breakerT1;
   // v12.00: active plan contradicted by a fresher counter-trend CHoCH
   bool             planShiftWarn;
   // v14.00: volatility regime + suggested risk
   string           volRegime;        // "HIGH" / "NORMAL" / "LOW"
   double           volRatio;         // ATR / trailing average ATR
   double           suggestedRiskPct; // scaled-down risk % suggestion (HIGH regime only)
   // v16.00: market regime + volatility contraction
   string           regime;           // "TRENDING" / "RANGING" / "TRANSITION"
   double           hurst;            // R/S Hurst exponent (0..1, ~0.5 = random walk)
   double           ker;              // Kaufman Efficiency Ratio (0..1)
   double           vcvSqueeze;       // Bollinger-inside-Keltner squeeze ratio (<1 = squeezed)
   bool             vcvCone;          // squeeze actively narrowing bar-over-bar
   // v17.00: confluence fusion
   int              confluence;       // 0-100 agreement score for the active plan direction
   int              confCount;        // number of independent signals agreeing
   string           confTags;         // "OB+FVG+CVD"
   // v18.00: harmonic pattern + Elliott wave
   string           harmonic;         // "GARTLEY" / "BAT" / "BUTTERFLY" / "CRAB" / "" (none)
   int              harmDir;          // +1 bullish PRZ, -1 bearish PRZ, 0 none
   double           przLo;
   double           przHi;
   string           elliott;          // e.g. "WAVE 3" / "WAVE C" / ""
   int              ewDir;            // +1 up, -1 down, 0 unclear
   // v19.00: yield curve + lead/lag
   double           ycSpread;
   bool             ycInverted;
   bool             ycOk;
   string           leadSym;
   double           leadMove;         // move in units of the lead symbol's own ATR
   int              leadDir;
   bool             leadFlash;
   // v20.00: oracle score
   int              oracleScore;
   // v21.00: local TPO market profile
   bool             tpoOk;
   double           tpoPoc;
   double           tpoVah;
   double           tpoVal;
   int              tpoSinglePrints;
   bool             tpoPoorHigh;
   bool             tpoPoorLow;
   // v22.00: walk-forward matrix
   double           wfWinPct;
   double           wfExpectancyR;
   int              wfTrades;
   // v23.00: statistical arbitrage
   double           statArbZ;
   bool             statArbFlag;
   string           statArbSym;
   // v24.00: options Greeks / implied volatility
   bool             optOk;
   double           ivCall;
   double           ivPut;
   double           gammaLevel;
  };

/* ------------------------------------------------------------------ */
/* Initialization                                                      */
/* ------------------------------------------------------------------ */
int OnInit()
  {
   g_fastMaP  = MathMax(2, InpFastMAPeriod);
   g_slowMaP  = MathMax(g_fastMaP + 1, InpSlowMAPeriod);
   g_refreshS = MathMax(1, InpRefreshSeconds);

   // v4.00: runtime override mirrors (remote control writes these, not inputs)
   g_ov.riskPct   = MathMax(REMOTE_MIN_VALUE, MathMin(REMOTE_MAX_VALUE, InpRiskPercent));
   g_ov.planZones = InpPlanZones;
   g_ov.render    = true;
   // v10.00: sandbox mirror + dormant start; the first live plan anchors it.
   g_ov.sandbox   = InpSandbox;
   g_sb.active    = false;
   g_sbDirty      = false;
   g_masterScore  = -1;
   g_masterVerdict = "";
   g_oracleScore  = -1;
   g_oraclePerfect = false;

   // v20.00: reload persisted journal notes and redraw their pins on the
   // attach chart so a re-init/re-compile doesn't lose them from view.
   if(InpJournal)
     {
      LoadJournalNotes();
      for(int ji = 0; ji < ArraySize(g_journalNotes); ji++)
         DrawJournalNote(ChartID(), g_journalNotes[ji], ji);
     }

   // Force a fresh redraw pass after re-compile / input change: globals
   // survive OnDeinit+OnInit on REPARAMETERS, and the new-bar gate would
   // otherwise skip charts whose last closed bar is unchanged.
   ArrayFree(g_charts);

   // Single-instance guard: one owner chart claims a terminal global.
   // A stale claim from a closed chart is taken over automatically.
   g_ownChart   = ChartID();
   bool claimed = false;
   if(!GlobalVariableCheck(GV_OWNER))
      GlobalVariableSet(GV_OWNER, 0.0);
   if(GlobalVariableSetOnCondition(GV_OWNER, (double)g_ownChart, 0.0))
      claimed = true;
   else
     {
      long owner = (long)GlobalVariableGet(GV_OWNER);
      if(owner == g_ownChart)
         claimed = true;                                  // re-init of own chart
      else if(!ChartIsValidObjectCache(owner))
        {
         GlobalVariableSet(GV_OWNER, (double)g_ownChart); // stale owner takeover
         claimed = true;
        }
      else
         Print("PAICT: refused — the markup EA is already running on chart ",
               owner, ". Keep it on ONE chart; it covers every open pair.");
     }
   if(!claimed)
      return(INIT_FAILED);
   g_claimed = true;

   EventSetTimer(g_refreshS);
   // v7.00 / v15.01: subscribe to Depth of Market for the attach symbol
   // up front (opt-in); every OTHER covered symbol gets its own
   // subscription lazily via EnsureDOMSubscription() the first time
   // DrawDOMStrip() renders it — a single MarketBookAdd(_Symbol) here left
   // every other covered chart's ladder strip permanently empty.
   if(InpDrawDOM)
      EnsureDOMSubscription(_Symbol);
   // Startup journal: version macro + attach-chart digits verified here
   // (per-symbol digits are verified again per chart inside the JSON writer).
   Print("PAICT_ChartMarkup v", PAICT_VERSION, " started on ", _Symbol,
         " (digits=", (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
         "). Refresh=", g_refreshS,
         "s · whitelist='", InpSymbolWhitelist,
         "' · attach this EA to ONE chart only.");

   // Immediate connectivity test: pushes a heartbeat until the plan forms.
   ScanNews();   // v4.00: prime the economic-calendar cache right away
   Print("PAICT co-pilot: risk HUD ", (InpRiskHUD ? "on" : "off"),
         " · heat tracker ", (InpHeatTracker ? "on" : "off"),
         " (alert at ", DoubleToString(InpMaxHeatPct, 1), "%)",
         " · news blackout ", (InpNewsBlackout ? "on" : "off"),
         " · remote control ", (InpRemoteControl ? "on" : "off"));
   Print("PAICT zenith: journal ", (InpTradeJournal ? "on" : "off"),
         " · self-heal ", (InpSelfHeal ? "on" : "off"),
         " (mute at ", MathMax(2, InpSelfHealFails), " stop-outs)",
         " · volume profile ", (InpVolumeProfile ? "on" : "off"),
         " · Monte Carlo ", (InpMonteCarlo ? "on" : "off"),
         " · sandbox ", (InpSandbox ? "on" : "off"),
         " · master score ", (InpMasterScore ? "on" : "off"),
         " · mailbox IPC ", (InpMailboxIPC ? "on" : "off"));
   Print("PAICT 10x (v11.00): OTE pocket ", (InpDrawOTE ? "on" : "off"),
         " (", DoubleToString(InpOTEFibLow, 2), "-", DoubleToString(InpOTEFibHigh, 2), ")",
         " · day/week opens ", (InpDrawDayWeekOpens ? "on" : "off"),
         " · price alerts ", (InpPriceAlerts ? "on" : "off"),
         " (cooldown ", MathMax(1, InpAlertCooldownMin), "m)");
   Print("PAICT v12-v15: breaker blocks ", (InpBreakerBlocks ? "on" : "off"),
         " · structure-shift tag ", (InpStructureShiftTag ? "on" : "off"),
         " · trade stats ", (InpTradeStats ? "on" : "off"),
         " · equity spark ", (InpEquitySpark ? "on" : "off"),
         " · vol regime ", (InpVolRegime ? "on" : "off"),
         " (plan candidates ", MathMax(1, InpPlanCandidates), ")",
         " · leaderboard ", (InpLeaderboard ? "on" : "off"),
         " · session countdown ", (InpSessionCountdown ? "on" : "off"));
   PushMatrixToBridge();
   return(INIT_SUCCEEDED);
  }

/* ------------------------------------------------------------------ */
/* Shutdown                                                            */
/* ------------------------------------------------------------------ */
void OnDeinit(const int reason)
  {
   EventKillTimer();
   // v15.01: release every symbol subscribed via EnsureDOMSubscription(),
   // not just the attach symbol.
   for(int i = 0; i < ArraySize(g_domSubs); i++)
      MarketBookRelease(g_domSubs[i]);
   ArrayFree(g_domSubs);

   // A second attach that lost the single-instance lock (OnInit returned
   // INIT_FAILED) still runs OnDeinit. Chart objects are terminal-wide, not
   // per-EA-instance, so an unconditional ObjectsDeleteAll here would wipe
   // the ACTUAL running instance's markup on every open chart. Only the
   // instance that actually claimed ownership may clean up.
   if(!g_claimed)
      return;

   long cid = ChartFirst();
   while(cid >= 0)
     {
      ObjectsDeleteAll(cid, OBJ_PREFIX, -1, -1);
      ChartRedraw(cid);
      cid = ChartNext(cid);
     }

   int pairs = ArraySize(g_ind);
   for(int p = 0; p < pairs; p++)
     {
      if(!ChartIsValidObjectCache(g_ind[p].chart_id))
         continue;
      ChartIndicatorDelete(g_ind[p].chart_id, 0, IND_SHORTNAME);
      if(g_ind[p].handle != INVALID_HANDLE)
         IndicatorRelease(g_ind[p].handle);
     }
   ArrayFree(g_ind);

   int atrs = ArraySize(g_atr);
   for(int a = 0; a < atrs; a++)
     {
      if(g_atr[a].handle != INVALID_HANDLE)
         IndicatorRelease(g_atr[a].handle);
     }
   ArrayFree(g_atr);
   ArrayFree(g_charts);
   if(g_ownChart > 0 && GlobalVariableCheck(GV_OWNER) &&
      (long)GlobalVariableGet(GV_OWNER) == g_ownChart)
      GlobalVariableDel(GV_OWNER);
   Print("PAICT_ChartMarkup removed (reason ", reason, ").");
  }

//+------------------------------------------------------------------+
//| Cached chart-id sanity helper                                    |
//+------------------------------------------------------------------+
bool ChartIsValidObjectCache(const long chart_id)
  {
   return(chart_id > 0 && ChartSymbol(chart_id) != "");
  }

/* ------------------------------------------------------------------ */
/* Timer / tick driver                                                 */
/* ------------------------------------------------------------------ */
void OnTimer()
  {
   RefreshAll();
   ScanNews();             // v4.00: economic-calendar cache (internally throttled)
   CheckNewsBlackoutTransition(); // v15.02: force a redraw the instant blackout starts/ends
   ScanTunerFile();        // v5.00: local tuner suggestions (internally throttled)
   ScanTradeStats();       // v13.00: trade-journal win%/expectancy (internally throttled)
   PushMatrixToBridge();   // re-push whenever the plan values changed (deduped)
   CheckPriceAlerts();     // v11.00: price-in-zone push alerts (internally throttled)
  }

void OnTick()
  {
   datetime now = TimeCurrent();
   if(now - g_lastRun >= g_refreshS)
      RefreshAll();
  }

/* ================================================================== */
/* v5.00 AI DESK — trade journal, self-healing setups, tuner file      */
/*                                                                     */
/*  OnTradeTransaction journals every MANUAL close (magic 0) to        */
/*  MQL5\Files\PAICT_TradeJournal_<symbol>_<tf>.csv — one row per deal */
/*  out, carrying the attach chart's plan context at close time. The   */
/*  local Python tuner (paict_tuner.py in the kit) reads those CSVs    */
/*  plus the JSON snapshots and writes PAICT_TunerSuggestion.txt; the  */
/*  EA shows the suggestions on the HUD — applying them stays a human  */
/*  decision (input dialog or a SET_RISK command from the dashboard).  */
/*                                                                     */
/*  Self-healing: a setup (symbol|TF) whose STOP was hit before its    */
/*  TARGET InpSelfHealFails times in a row is MUTED — the plan stops   */
/*  rendering and stops being pushed until it re-arms after            */
/*  SELF_HEAL_REARM_BARS more closed bars (a TARGET hit resets the     */
/*  fail counter immediately).                                         */
/* ================================================================== */
string SetupKey(const string sym, const ENUM_TIMEFRAMES tf)
  {
   string tfLabel = EnumToString(tf);
   StringReplace(tfLabel, "PERIOD_", "");
   return(sym + "|" + tfLabel);
  }

int HealIndex(const string key, const bool create)
  {
   for(int i = 0; i < ArraySize(g_heal); i++)
      if(g_heal[i].key == key)
         return(i);
   if(!create)
      return(-1);
   const int at = ArraySize(g_heal);
   ArrayResize(g_heal, at + 1, ARRAY_RESERVE_CHUNK);
   g_heal[at].key       = key;
   g_heal[at].fails     = 0;
   g_heal[at].mutedFrom = 0;
   g_heal[at].planE     = 0.0;
   g_heal[at].planS     = 0.0;
   g_heal[at].planT     = 0.0;
   g_heal[at].judged    = false;
   return(at);
  }

bool SetupIsMuted(const string sym, const ENUM_TIMEFRAMES tf, const datetime closedBar,
                  const int periodSec)
  {
   const int at = HealIndex(SetupKey(sym, tf), false);
   if(at < 0)
      return(false);
   if(g_heal[at].mutedFrom == 0)
      return(false);
   if((long)(closedBar - g_heal[at].mutedFrom) >=
      (long)SELF_HEAL_REARM_BARS * MathMax(60, periodSec))
     {
      g_heal[at].mutedFrom = 0;      // cool-down over — re-arm the setup
      Print("PAICT self-heal: ", g_heal[at].key, " re-armed after the cool-down.");
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Judge the CURRENT plan against the just-closed bar (once per plan: |
//| a stop/target touch consumes the instance by invalidating it).     |
//+------------------------------------------------------------------+
void SelfHealUpdate(const string sym, const ENUM_TIMEFRAMES tf, const MqlRates &rates[],
                    const SMarketState &st)
  {
   const int at = HealIndex(SetupKey(sym, tf), true);
   if(at < 0 || !st.planOk || st.atr <= 0.0)
      return;
   // A NEW plan instance (any level moved) resets the evaluation — and is
   // never judged on the very bar it formed.
   if(g_heal[at].planE != st.planEntry || g_heal[at].planS != st.planStop ||
      g_heal[at].planT != st.planTarget)
     {
      g_heal[at].planE  = st.planEntry;
      g_heal[at].planS  = st.planStop;
      g_heal[at].planT  = st.planTarget;
      g_heal[at].judged = false;
      return;
     }
   // Already produced a verdict for THIS plan instance — a stop hit stays
   // hit even if price lingers beyond it for several more bars, so judging
   // again here would count one real stop-out as several (tracking
   // consumption via a separate flag instead of zeroing planS/planT, which
   // used to make the unchanged plan look "new" again on the next bar).
   if(g_heal[at].judged)
      return;

   const bool   isLong = (st.planTarget > st.planEntry);
   const double lo     = rates[st.lastClosed].low;
   const double hi     = rates[st.lastClosed].high;
   const int    limit  = MathMax(2, InpSelfHealFails);
   if(isLong)
     {
      if(lo <= st.planStop)
        {
         g_heal[at].fails++;
         g_heal[at].judged = true;
         if(InpSelfHeal && g_heal[at].fails >= limit && g_heal[at].mutedFrom == 0)
           {
            g_heal[at].mutedFrom = st.closedBar;
            Print("PAICT self-heal: ", g_heal[at].key, " MUTED after ",
                  g_heal[at].fails, " consecutive stop-outs. Re-arms after ",
                  SELF_HEAL_REARM_BARS, " closed bars.");
           }
        }
      else if(hi >= st.planTarget)
        {
         g_heal[at].fails  = 0;
         g_heal[at].judged = true;
        }
     }
   else
     {
      if(hi >= st.planStop)
        {
         g_heal[at].fails++;
         g_heal[at].judged = true;
         if(InpSelfHeal && g_heal[at].fails >= limit && g_heal[at].mutedFrom == 0)
           {
            g_heal[at].mutedFrom = st.closedBar;
            Print("PAICT self-heal: ", g_heal[at].key, " MUTED after ",
                  g_heal[at].fails, " consecutive stop-outs. Re-arms after ",
                  SELF_HEAL_REARM_BARS, " closed bars.");
           }
        }
      else if(lo <= st.planTarget)
        {
         g_heal[at].fails  = 0;
         g_heal[at].judged = true;
        }
     }
  }

//+------------------------------------------------------------------+
//| v5.00 trade journal — one CSV row per MANUAL deal close (magic 0). |
//| Rows carry the attach chart's plan context at close time so the    |
//| local tuner can correlate plan geometry with outcomes.             |
//+------------------------------------------------------------------+
void JournalClosedDeal(const ulong dealTicket)
  {
   if(!InpTradeJournal)
      return;
   if(!HistoryDealSelect(dealTicket))
      return;
   if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != 0)
      return;                                     // EA/bot trades are not journaled
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;
   const string dealSym  = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   const long   dealTime = (long)HistoryDealGetInteger(dealTicket, DEAL_TIME);
   const double profit   = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                           HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                           HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   const double volume   = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
   const double price    = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   // a deal OUT of a long position books a SELL — recover the position side
   const bool wasLong = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE) == DEAL_TYPE_SELL);

   // plan context: only the attach chart's live plan is known to this EA
   double pe = 0.0, ps = 0.0, pt = 0.0, prr = 0.0;
   if(dealSym == _Symbol && g_plan.ok)
     {
      pe = g_plan.entry;
      ps = g_plan.stop;
      pt = g_plan.target;
      const double risk = MathAbs(pe - ps);
      if(risk > 0.0)
         prr = MathAbs(pt - pe) / risk;
     }

   const string name = "PAICT_TradeJournal_" + dealSym + ".csv";
   const int h = FileOpen(name, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE)
     {
      if(!g_journalWarned)
        {
         g_journalWarned = true;
         Print("PAICT journal: cannot open ", name, " (error ", GetLastError(),
               ") — trade journaling disabled this session.");
        }
      return;
     }
   if(FileSize(h) == 0)
      FileWrite(h, "time", "symbol", "side", "volume", "closePrice", "profit",
                "balanceAfter", "planEntry", "planStop", "planTarget", "planRR");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString((datetime)dealTime, TIME_DATE|TIME_SECONDS), dealSym,
             (wasLong ? "long" : "short"), DoubleToString(volume, 2),
             DoubleToString(price, 8), DoubleToString(profit, 2),
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
             DoubleToString(pe, 8), DoubleToString(ps, 8), DoubleToString(pt, 8),
             DoubleToString(prr, 2));
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Trade events: journal manual closes the moment the deal lands      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   JournalClosedDeal(trans.deal);
  }

//+------------------------------------------------------------------+
//| v5.00 local tuner bridge: paict_tuner.py writes KEY=VALUE lines to |
//| MQL5\Files\PAICT_TunerSuggestion.txt; whitelisted keys are shown   |
//| on the HUD + pushed in the payload. Applying stays manual.         |
//+------------------------------------------------------------------+
bool TunerKeyAllowed(const string k)
  {
   return(k == "RISK_PERCENT" || k == "ZONE_TOLERANCE" || k == "PLAN_ZONE_HEIGHT" ||
          k == "STOP_BUFFER" || k == "NOTE");
  }

void ScanTunerFile()
  {
   if(!InpTunerFile)
      return;
   if(g_tunerScan != 0 && TimeCurrent() - g_tunerScan < TUNER_SCAN_SEC)
      return;
   g_tunerScan = TimeCurrent();
   ResetLastError();
   const int h = FileOpen("PAICT_TunerSuggestion.txt",
                          FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
     {
      if(ArraySize(g_tunerKeys) > 0)           // file vanished — clear the HUD line
        {
         ArrayResize(g_tunerKeys, 0, ARRAY_RESERVE_CHUNK);
         ArrayResize(g_tunerVals, 0, ARRAY_RESERVE_CHUNK);
         ForceFullRedraw();
        }
      return;                                  // no suggestion file yet — silent
     }
   string keys[]; string vals[];
   while(!FileIsEnding(h) && ArraySize(keys) < TUNER_MAX_LINES)
     {
      string ln = FileReadString(h);
      StringReplace(ln, "\r", "");
      StringTrimLeft(ln);
      StringTrimRight(ln);
      const int eq = StringFind(ln, "=");
      if(eq <= 0)
         continue;
      string k = StringSubstr(ln, 0, eq);
      string v = StringSubstr(ln, eq + 1);
      StringTrimLeft(k);  StringTrimRight(k);
      StringTrimLeft(v);  StringTrimRight(v);
      if(StringLen(k) == 0 || StringLen(v) == 0 || StringLen(v) > TUNER_VALUE_MAXLEN)
         continue;
      if(!TunerKeyAllowed(k))
         continue;
      const int at = ArraySize(keys);
      ArrayResize(keys, at + 1, ARRAY_RESERVE_CHUNK);
      ArrayResize(vals, at + 1, ARRAY_RESERVE_CHUNK);
      keys[at] = k;
      vals[at] = v;
     }
   FileClose(h);
   // only touch the globals + redraw when the suggestion set actually changed
   bool same = (ArraySize(keys) == ArraySize(g_tunerKeys));
   for(int i = 0; same && i < ArraySize(keys); i++)
      if(keys[i] != g_tunerKeys[i] || vals[i] != g_tunerVals[i])
         same = false;
   if(same)
      return;
   ArrayResize(g_tunerKeys, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(g_tunerVals, 0, ARRAY_RESERVE_CHUNK);
   for(int i = 0; i < ArraySize(keys); i++)
     {
      const int at = ArraySize(g_tunerKeys);
      ArrayResize(g_tunerKeys, at + 1, ARRAY_RESERVE_CHUNK);
      ArrayResize(g_tunerVals, at + 1, ARRAY_RESERVE_CHUNK);
      g_tunerKeys[at] = keys[i];
      g_tunerVals[at] = vals[i];
     }
   if(ArraySize(g_tunerKeys) > 0)
     {
      string joined = "";
      for(int i = 0; i < ArraySize(g_tunerKeys); i++)
         joined += (i == 0 ? "" : " · ") + g_tunerKeys[i] + "=" + g_tunerVals[i];
      Print("PAICT tuner: suggestions -> ", joined);
     }
   ForceFullRedraw();
  }

/* ================================================================== */
/* v13.00 PERFORMANCE ANALYTICS — read back the v5.00 trade journal    */
/* (win rate, expectancy in R-multiples, an equity mini-sparkline).    */
/* Scoped to the ATTACH chart's own symbol journal, same as g_plan.    */
/* ================================================================== */

//+------------------------------------------------------------------+
//| Rescan MQL5\Files\PAICT_TradeJournal_<attach symbol>.csv (throttled |
//| to InpStatsScanSec) and recompute win% / expectancy(R) / the        |
//| cumulative-balance series the sparkline draws from. Expectancy      |
//| approximates each trade's risk in money from ITS OWN planEntry/     |
//| planStop columns priced at CURRENT tick size/value — a comparison   |
//| statistic, like every other simplified metric in this EA, not a     |
//| certified backtest number.                                          |
//+------------------------------------------------------------------+
void ScanTradeStats()
  {
   if(!InpTradeStats && !InpEquitySpark)
      return;
   if(g_statsScan != 0 && TimeCurrent() - g_statsScan < MathMax(10, InpStatsScanSec))
      return;
   g_statsScan = TimeCurrent();

   const string fname = "PAICT_TradeJournal_" + _Symbol + ".csv";
   ResetLastError();
   const int h = FileOpen(fname, FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE)
     {
      g_statsWinPct = 0.0;
      g_statsExpR   = 0.0;
      g_statsTrades = 0;
      ArrayResize(g_statsBalances, 0, ARRAY_RESERVE_CHUNK);
      return;                      // no journal yet — silent, no trades closed
     }

   for(int k = 0; k < 11 && !FileIsEnding(h); k++)
      FileReadString(h);          // skip the 11 header fields

   // Read every row (the journal is append-only and bounded by real manual
   // trading volume) then keep only the TRAILING InpStatsMaxRows rows below
   // — reading with an early cap would freeze the stats on the OLDEST rows
   // forever once the journal grows past the cap.
   double allProfit[];
   double allBal[];
   double allR[];
   bool   allHasR[];

   while(!FileIsEnding(h))
     {
      const string sTime = FileReadString(h);
      if(sTime == "" && FileIsEnding(h))
         break;
      const string sSym      = FileReadString(h);
      FileReadString(h);                          // side (unused here)
      const double vol       = StringToDouble(FileReadString(h));
      FileReadString(h);                          // closePrice (unused here)
      const double profit    = StringToDouble(FileReadString(h));
      const double balAfter  = StringToDouble(FileReadString(h));
      const double pe        = StringToDouble(FileReadString(h));
      const double ps        = StringToDouble(FileReadString(h));
      FileReadString(h);                          // planTarget (unused here)
      FileReadString(h);                          // planRR (unused here)

      double  r     = 0.0;
      bool    hasR  = false;
      if(pe != 0.0 && ps != 0.0 && vol > 0.0)
        {
         const double tickSize  = SymbolInfoDouble(sSym, SYMBOL_TRADE_TICK_SIZE);
         const double tickValue = SymbolInfoDouble(sSym, SYMBOL_TRADE_TICK_VALUE);
         if(tickSize > 0.0 && tickValue > 0.0)
           {
            const double riskMoney = MathAbs(pe - ps) / tickSize * tickValue * vol;
            if(riskMoney > 0.0)
              {
               r    = profit / riskMoney;
               hasR = true;
              }
           }
        }

      const int at = ArraySize(allProfit);
      ArrayResize(allProfit, at + 1, ARRAY_RESERVE_CHUNK);
      ArrayResize(allBal,    at + 1, ARRAY_RESERVE_CHUNK);
      ArrayResize(allR,      at + 1, ARRAY_RESERVE_CHUNK);
      ArrayResize(allHasR,   at + 1, ARRAY_RESERVE_CHUNK);
      allProfit[at] = profit;
      allBal[at]    = balAfter;
      allR[at]      = r;
      allHasR[at]   = hasR;
     }
   FileClose(h);

   const int total   = ArraySize(allProfit);
   const int maxRows = MathMax(1, InpStatsMaxRows);
   const int start   = MathMax(0, total - maxRows);

   int    wins   = 0;
   int    trades = 0;
   double sumR   = 0.0;
   int    rCount = 0;
   double balances[];
   ArrayResize(balances, total - start, ARRAY_RESERVE_CHUNK);
   for(int i = start; i < total; i++)
     {
      trades++;
      if(allProfit[i] > 0.0)
         wins++;
      if(allHasR[i])
        {
         sumR += allR[i];
         rCount++;
        }
      balances[i - start] = allBal[i];
     }

   // v15.01: a manual close detected between closed bars would otherwise
   // sit in these globals unseen — the HUD, sparkline and bridge payload
   // only refresh on the next closed bar's redraw. Force one now, exactly
   // like ScanTunerFile does when its own suggestions change.
   if(trades != g_statsTrades)
      ForceFullRedraw();

   g_statsTrades = trades;
   g_statsWinPct = (trades > 0) ? 100.0 * wins / trades : 0.0;
   g_statsExpR   = (rCount > 0) ? sumR / rCount : 0.0;
   ArrayResize(g_statsBalances, ArraySize(balances), ARRAY_RESERVE_CHUNK);
   for(int i = 0; i < ArraySize(balances); i++)
      g_statsBalances[i] = balances[i];
  }

//+------------------------------------------------------------------+
//| Equity mini-sparkline: a normalized polyline of the cumulative      |
//| balanceAfter series, anchored above price near the right edge —     |
//| reuses the v8.00 CVD polyline technique (price/time chart objects,  |
//| not literal screen pixels, so it scales with zoom like everything   |
//| else this EA draws).                                                |
//+------------------------------------------------------------------+
void DrawEquitySpark(const long chart_id, const MqlRates &rates[], const int lastClosed,
                     const ENUM_TIMEFRAMES tf, const double atr, const double closeRef)
  {
   const int n = ArraySize(g_statsBalances);
   if(n < 2 || atr <= 0.0)
      return;
   const int take = MathMin(n, SPARK_MAX_SEGMENTS + 1);
   const int i0   = n - take;
   double mn = DBL_MAX, mx = -DBL_MAX;
   for(int i = i0; i < n; i++)
     {
      if(g_statsBalances[i] < mn) mn = g_statsBalances[i];
      if(g_statsBalances[i] > mx) mx = g_statsBalances[i];
     }
   if(mx - mn <= 0.0)
      return;

   const double   base   = closeRef + atr * (SPARK_BAND_ATR - 1.0);
   const double   band   = atr;
   const long     barSec = MathMax(60, PeriodSeconds(tf));
   const datetime t0     = (datetime)((long)rates[lastClosed].time - (long)SPARK_WIDTH_BARS * barSec);
   const int      steps  = take - 1;
   const color    clr    = (g_statsBalances[n - 1] >= g_statsBalances[i0]) ? COL_SPARK : COL_STOP;

   for(int k = 0; k < steps; k++)
     {
      const double y0 = base + band * (g_statsBalances[i0 + k]     - mn) / (mx - mn);
      const double y1 = base + band * (g_statsBalances[i0 + k + 1] - mn) / (mx - mn);
      const datetime x0 = (datetime)((long)t0 + (long)((double)k       / steps * SPARK_WIDTH_BARS) * barSec);
      const datetime x1 = (datetime)((long)t0 + (long)((double)(k + 1) / steps * SPARK_WIDTH_BARS) * barSec);
      UpsertSegment(chart_id, OBJ_PREFIX + "SPARK_" + IntegerToString(k), x0, y0, x1, y1, clr, 1, STYLE_SOLID);
     }
   if(InpShowLabels)
      UpsertText(chart_id, OBJ_PREFIX + "SPARK_LBL", t0, base + band,
                 "EQUITY", clr, 8, "Arial", ANCHOR_LEFT_LOWER);
  }

//+------------------------------------------------------------------+
//| v10.00 sandbox: a line was dragged — read the new levels back.     |
//| Chart events only fire for the EA's OWN chart, which is exactly    |
//| the chart the sandbox lives on.                                    |
//+------------------------------------------------------------------+
void SandboxReadDragged()
  {
   const long cid = ChartID();
   g_sb.entry = ObjectGetDouble(cid, OBJ_PREFIX + "SB_E", OBJPROP_PRICE, 0);
   g_sb.stop  = ObjectGetDouble(cid, OBJ_PREFIX + "SB_S", OBJPROP_PRICE, 0);
   g_sb.tp    = ObjectGetDouble(cid, OBJ_PREFIX + "SB_T", OBJPROP_PRICE, 0);
   if(g_sb.entry > 0.0 && g_sb.stop > 0.0 && g_sb.tp > 0.0)
     {
      g_sb.active = true;
      g_sbDirty   = true;
      // The new-bar gate in DrawOnChart would otherwise leave the HUD and
      // the bridge payload showing the pre-drag sandbox levels until the
      // next closed bar. Force the next cycle to redraw and re-push now.
      ForceFullRedraw();
     }
  }

//+------------------------------------------------------------------+
//| v20.00 journal — load persisted notes from MQL5\Files\ at start.   |
//+------------------------------------------------------------------+
void LoadJournalNotes()
  {
   ArrayResize(g_journalNotes, 0);
   ResetLastError();
   const int h = FileOpen(InpJournalFile, FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE)
      return;                          // no file yet — nothing to load
   if(!FileIsEnding(h))
      FileReadString(h);               // skip header row
   while(!FileIsEnding(h))
     {
      const string t   = FileReadString(h);
      const double p   = StringToDouble(FileReadString(h));
      const string txt = FileReadString(h);
      if(t == "" && txt == "")
         continue;
      const int n = ArraySize(g_journalNotes);
      ArrayResize(g_journalNotes, n + 1);
      g_journalNotes[n].timeStr = t;
      g_journalNotes[n].t       = StringToTime(t);
      g_journalNotes[n].price   = p;
      g_journalNotes[n].text    = txt;
     }
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| v20.00 journal — append one note to the CSV (create + header on    |
//| first write, matching the trade-journal file pattern above).       |
//+------------------------------------------------------------------+
void AppendJournalNoteCSV(const SJournalNote &note)
  {
   const int h = FileOpen(InpJournalFile, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE)
     {
      Print("PAICT journal: cannot open ", InpJournalFile, " (error ", GetLastError(),
            ") — note not persisted.");
      return;
     }
   if(FileSize(h) == 0)
      FileWrite(h, "time", "price", "text");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, note.timeStr, DoubleToString(note.price, _Digits), note.text);
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| v20.00 journal — pin an OBJ_TEXT marker + arrow at the note's      |
//| price/time so it stays visible on the chart it was created on.     |
//+------------------------------------------------------------------+
void DrawJournalNote(const long chart_id, const SJournalNote &note, const int idx)
  {
   const string name = OBJ_PREFIX + "NOTE_" + IntegerToString(idx);
   ObjectCreate(chart_id, name, OBJ_TEXT, 0, note.t, note.price);
   ObjectSetString(chart_id, name, OBJPROP_TEXT, "\xF0\x9F\x93\x8C " + note.text);
   ObjectSetInteger(chart_id, name, OBJPROP_COLOR, COL_KZ_LON);
   ObjectSetInteger(chart_id, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(chart_id, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(chart_id, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| v20.00 journal — finish a pending note: read the OBJ_EDIT text,    |
//| drop the edit box, persist + draw the pin.                         |
//+------------------------------------------------------------------+
void FinishJournalEdit(const long chart_id, const string editName)
  {
   const string txt = ObjectGetString(chart_id, editName, OBJPROP_TEXT);
   const datetime t = (datetime)ObjectGetInteger(chart_id, editName, OBJPROP_TIME);
   const double   p = ObjectGetDouble(chart_id, editName, OBJPROP_PRICE);
   ObjectDelete(chart_id, editName);
   if(StringLen(txt) == 0)
      return;                          // empty note = cancelled

   const int n = ArraySize(g_journalNotes);
   ArrayResize(g_journalNotes, n + 1);
   g_journalNotes[n].t       = t;
   g_journalNotes[n].timeStr = TimeToString(t, TIME_DATE|TIME_SECONDS);
   g_journalNotes[n].price   = p;
   g_journalNotes[n].text    = txt;
   AppendJournalNoteCSV(g_journalNotes[n]);
   DrawJournalNote(chart_id, g_journalNotes[n], n);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_DRAG && InpSandbox &&
      StringFind(sparam, OBJ_PREFIX + "SB_") == 0)
      SandboxReadDragged();

   // v20.00: double-click detection (MQL5 has no native dblclick event) —
   // two CHARTEVENT_CLICKs within JOURNAL_DBLCLICK_MS ms and
   // JOURNAL_DBLCLICK_PX px of each other count as one. Opens a small
   // OBJ_EDIT box pinned at the clicked price/time for the note text;
   // CHARTEVENT_OBJECT_ENDEDIT below reads it back.
   if(id == CHARTEVENT_CLICK && InpJournal)
     {
      const long   chart_id = ChartID();
      const int    x = (int)lparam;
      const int    y = (int)dparam;
      const ulong  now = GetTickCount();
      const bool   isDouble = (now - g_lastClickMs <= JOURNAL_DBLCLICK_MS) &&
                              (MathAbs(x - g_lastClickX) <= JOURNAL_DBLCLICK_PX) &&
                              (MathAbs(y - g_lastClickY) <= JOURNAL_DBLCLICK_PX);
      g_lastClickMs = now;
      g_lastClickX  = x;
      g_lastClickY  = y;
      if(isDouble)
        {
         g_lastClickMs = 0;   // consume — a third rapid click starts fresh
         datetime t; double p;
         int sub_window;
         if(ChartXYToTimePrice(chart_id, x, y, sub_window, t, p))
           {
            const string editName = OBJ_PREFIX + "NOTE_EDIT";
            ObjectDelete(chart_id, editName);
            ObjectCreate(chart_id, editName, OBJ_EDIT, 0, 0, 0);
            ObjectSetInteger(chart_id, editName, OBJPROP_XDISTANCE, x);
            ObjectSetInteger(chart_id, editName, OBJPROP_YDISTANCE, y);
            ObjectSetInteger(chart_id, editName, OBJPROP_XSIZE, 180);
            ObjectSetInteger(chart_id, editName, OBJPROP_YSIZE, 20);
            ObjectSetInteger(chart_id, editName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(chart_id, editName, OBJPROP_TIME, t);
            ObjectSetDouble(chart_id, editName, OBJPROP_PRICE, p);
            ObjectSetString(chart_id, editName, OBJPROP_TEXT, "");
            ObjectSetString(chart_id, editName, OBJPROP_TOOLTIP, "Type a note, press Enter");
            ObjectSetInteger(chart_id, editName, OBJPROP_BGCOLOR, clrWhite);
            ObjectSetInteger(chart_id, editName, OBJPROP_SELECTABLE, true);
            ChartRedraw(chart_id);
           }
        }
     }

   if(id == CHARTEVENT_OBJECT_ENDEDIT && InpJournal &&
      sparam == OBJ_PREFIX + "NOTE_EDIT")
      FinishJournalEdit(ChartID(), sparam);
  }

/* ------------------------------------------------------------------ */
/* Discover charts and refresh every eligible one                      */
/* ------------------------------------------------------------------ */
void RefreshAll()
  {
   g_lastRun = TimeCurrent();

   long cid = ChartFirst();
   while(cid >= 0)
     {
      string sym = ChartSymbol(cid);
      ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)ChartPeriod(cid);

      if(sym != "" && IsSymbolAllowed(sym))
        {
         const int csAt = ChartStateIndex(cid);
         if(csAt < 0)
           {
            Print("PAICT: covering ", sym, "@", EnumToString(tf),
                  " (chart ", cid, ") — one attached EA marks every open pair.");
            ChartStateTouch(cid, 0, sym, tf);   // announced; first draw this pass
           }
         else if(g_charts[csAt].symbol != sym || g_charts[csAt].tf != tf)
           {
            // v15.02: the SAME chart id switched to a different symbol or
            // timeframe (a user re-used the chart window). The redraw gate
            // is keyed by chart_id + closed-bar timestamp only, so a new
            // symbol whose latest bar happens to share that timestamp
            // would otherwise keep the PREVIOUS symbol's markup on screen
            // and DualMA handle attached. Treat it as a brand-new chart.
            Print("PAICT: chart ", cid, " switched ", g_charts[csAt].symbol, "@",
                  EnumToString(g_charts[csAt].tf), " -> ", sym, "@", EnumToString(tf),
                  " — resetting.");
            ChartStateTouch(cid, 0, sym, tf);
            ReleaseIndicatorFor(cid);
           }
         EnsureIndicators(cid, sym, tf);   // advisory MA layer — never gates markup
         DrawOnChart(cid, sym, tf);
        }
      cid = ChartNext(cid);
     }
   PruneChartStates();
   PruneIndicatorPairs();
   PruneLeaderboard();      // v15.00: drop rows for charts no longer covered
  }

//+------------------------------------------------------------------+
//| Per-chart draw state (journal + new-bar redraw gate)              |
//+------------------------------------------------------------------+
int ChartStateIndex(const long chart_id)
  {
   for(int i = 0; i < ArraySize(g_charts); i++)
      if(g_charts[i].chart_id == chart_id)
         return(i);
   return(-1);
  }

void ChartStateTouch(const long chart_id, const datetime closed_bar, const string symbol,
                     const ENUM_TIMEFRAMES tf)
  {
   int at = ChartStateIndex(chart_id);
   if(at < 0)
     {
      at = ArraySize(g_charts);
      ArrayResize(g_charts, at + 1, ARRAY_RESERVE_CHUNK);
      g_charts[at].chart_id = chart_id;
      g_charts[at].last_data_err = -1;
     }
   g_charts[at].last_bar = closed_bar;
   g_charts[at].symbol   = symbol;
   g_charts[at].tf       = tf;
  }

void PruneChartStates()
  {
   int kept  = 0;
   int total = ArraySize(g_charts);
   for(int i = 0; i < total; i++)
     {
      if(ChartIsValidObjectCache(g_charts[i].chart_id))
        {
         g_charts[kept] = g_charts[i];
         kept++;
        }
     }
   if(kept != total)
      ArrayResize(g_charts, kept);
  }

//+------------------------------------------------------------------+
//| Release DualMA handles of charts closed since the last pass       |
//+------------------------------------------------------------------+
void PruneIndicatorPairs()
  {
   int kept  = 0;
   int total = ArraySize(g_ind);
   for(int i = 0; i < total; i++)
     {
      if(ChartIsValidObjectCache(g_ind[i].chart_id))
        {
         if(kept != i)
            g_ind[kept] = g_ind[i];
         kept++;
        }
      else if(g_ind[i].handle != INVALID_HANDLE)
         IndicatorRelease(g_ind[i].handle);   // chart closed: free the handle
     }
   if(kept != total)
      ArrayResize(g_ind, kept);
  }

/* ------------------------------------------------------------------ */
/* Symbol whitelist (CSV, case-insensitive; empty = allow all)         */
/* ------------------------------------------------------------------ */
bool IsSymbolAllowed(const string symbol)
  {
   string csv = InpSymbolWhitelist;
   StringTrimLeft(csv);
   StringTrimRight(csv);
   if(csv == "")
      return(true);

   string upper = symbol;
   StringToUpper(upper);

   string parts[];
   int count = StringSplit(csv, ',', parts);
   for(int i = 0; i < count; i++)
     {
      string part = parts[i];
      StringTrimLeft(part);
      StringTrimRight(part);
      StringToUpper(part);
      if(part == "")
         continue;
      if(part == "*" || part == upper)
         return(true);
      // Broker suffix tolerance (Exness "EURUSDz", "EURUSDm", IC "EURUSD.r"):
      // the shorter symbol matches the longer one when the extra tail is a
      // short broker tag (2 chars max) on either side. "EURUSD" therefore
      // covers "EURUSDz" without also matching "EURUSDJPY".
      if(StringFind(upper, part) == 0 && StringLen(upper) - StringLen(part) <= 2)
         return(true);
      if(StringFind(part, upper) == 0 && StringLen(part) - StringLen(upper) <= 2)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| v15.02: drop a chart's DualMA handle so EnsureIndicators() attaches |
//| a fresh one — used when a covered chart's symbol/timeframe changed |
//| under the same chart id (EnsureIndicators is keyed by chart_id      |
//| only, so it would otherwise keep serving the OLD symbol's handle). |
//+------------------------------------------------------------------+
void ReleaseIndicatorFor(const long chart_id)
  {
   for(int i = 0; i < ArraySize(g_ind); i++)
     {
      if(g_ind[i].chart_id != chart_id)
         continue;
      if(g_ind[i].handle != INVALID_HANDLE)
        {
         ChartIndicatorDelete(chart_id, 0, IND_SHORTNAME);
         IndicatorRelease(g_ind[i].handle);
        }
      const int last = ArraySize(g_ind) - 1;
      g_ind[i] = g_ind[last];
      ArrayResize(g_ind, last);
      return;
     }
  }

/* ------------------------------------------------------------------ */
/* Attach the DualMA companion indicator to a chart (once per chart)   */
/* ------------------------------------------------------------------ */
bool EnsureIndicators(const long chart_id, const string symbol, const ENUM_TIMEFRAMES tf)
  {
   int found = -1;
   int total = ArraySize(g_ind);
   for(int i = 0; i < total; i++)
     {
      if(g_ind[i].chart_id == chart_id)
        {
         found = i;
         break;
        }
     }

   bool retry   = (found >= 0);                    // entry exists from a failed try
   bool logOnce = true;
   if(retry)
     {
      if(g_ind[found].handle != INVALID_HANDLE)
         return(true);                             // already attached
      logOnce = (g_ind[found].attempts == 0);      // log the first failure only
      g_ind[found].attempts++;
     }

   int handle = iCustom(symbol, tf, "PAICT_DualMA", g_fastMaP, g_slowMaP);
   if(handle == INVALID_HANDLE)
     {
      if(logOnce)
         Print("PAICT: cannot create PAICT_DualMA handle for ", symbol,
               "@", EnumToString(tf), " (compile PAICT_DualMA.mq5 into Indicators)");
      if(!retry)
        {
         int atFail = ArraySize(g_ind);
         ArrayResize(g_ind, atFail + 1);
         g_ind[atFail].chart_id  = chart_id;
         g_ind[atFail].handle    = INVALID_HANDLE;
         g_ind[atFail].attempts  = 1;
        }
      return(false);
     }
   if(!ChartIndicatorAdd(chart_id, 0, handle))
     {
      if(logOnce)
         Print("PAICT: ChartIndicatorAdd failed on chart ", chart_id);
      IndicatorRelease(handle);
      if(!retry)
        {
         int atFail2 = ArraySize(g_ind);
         ArrayResize(g_ind, atFail2 + 1);
         g_ind[atFail2].chart_id  = chart_id;
         g_ind[atFail2].handle    = INVALID_HANDLE;
         g_ind[atFail2].attempts  = 1;
        }
      return(false);
     }

   if(retry)
     {
      g_ind[found].handle = handle;                // recovered on a retry
      return(true);
     }

   int atNew = ArraySize(g_ind);
   ArrayResize(g_ind, atNew + 1);
   g_ind[atNew].chart_id  = chart_id;
   g_ind[atNew].handle    = handle;
   g_ind[atNew].attempts  = 0;
   return(true);
  }

/* ------------------------------------------------------------------ */
/* ATR helper with caching                                             */
/* ------------------------------------------------------------------ */
double GetAtr(const string symbol, const ENUM_TIMEFRAMES tf)
  {
   int    found  = -1;
   int    total  = ArraySize(g_atr);
   double result = 0.0;

   for(int i = 0; i < total; i++)
     {
      if(g_atr[i].symbol == symbol && g_atr[i].tf == tf)
        {
         found = i;
         break;
        }
     }

   if(found < 0)
     {
      int h = iATR(symbol, tf, MathMax(2, InpATRPeriod));
      if(h == INVALID_HANDLE)
         return(0.0);
      int at = ArraySize(g_atr);
      ArrayResize(g_atr, at + 1);
      g_atr[at].symbol = symbol;
      g_atr[at].tf     = tf;
      g_atr[at].handle = h;
      found = at;
     }

   double buf[1];
   buf[0] = 0.0;
   ResetLastError();
   if(CopyBuffer(g_atr[found].handle, 0, 1, 1, buf) == 1) // last CLOSED bar
      result = buf[0];
   if(result <= 0.0)
     {
      // v2.07: indicator cache failed or returned nothing — a manual true-range
      // average over raw bars keeps the zone math alive instead of zeroing it
      // (a zero ATR blanks zones, liquidity and the trade plan entirely).
      result = ManualAtr(symbol, tf, MathMax(2, InpATRPeriod));
     }
   return(result);
  }

//+------------------------------------------------------------------+
//| v14.00: trailing average of the ATR indicator's own readings over   |
//| `bars` closed bars — the baseline the current ATR is compared      |
//| against for the HIGH / NORMAL / LOW volatility regime read.        |
//+------------------------------------------------------------------+
double GetAtrAverage(const string symbol, const ENUM_TIMEFRAMES tf, const int bars)
  {
   int h = iATR(symbol, tf, MathMax(2, InpATRPeriod));
   if(h == INVALID_HANDLE)
      return(0.0);
   double buf[];
   ArraySetAsSeries(buf, true);
   const int need = MathMax(5, bars);
   ResetLastError();
   if(CopyBuffer(h, 0, 1, need, buf) < need)
     {
      IndicatorRelease(h);
      return(0.0);
     }
   double sum = 0.0;
   for(int i = 0; i < need; i++)
      sum += buf[i];
   IndicatorRelease(h);
   return(sum / need);
  }

//+------------------------------------------------------------------+
//| v14.00: classify the current ATR against its trailing average into  |
//| HIGH / NORMAL / LOW, and — only in a HIGH regime — suggest a        |
//| scaled-down risk % (never applied automatically; SET_RISK from the |
//| dashboard, exactly like the v4.00 risk override, stays the only    |
//| way it actually changes sizing).                                    |
//+------------------------------------------------------------------+
void ComputeVolRegime(const double atr, const double atrAvg, const double riskPct,
                      string &regime, double &ratio, double &suggestedRiskPct)
  {
   regime = "NORMAL";
   ratio  = 0.0;
   suggestedRiskPct = 0.0;
   if(atrAvg <= 0.0 || atr <= 0.0)
      return;
   ratio = atr / atrAvg;
   if(ratio >= VOL_HIGH_RATIO)
     {
      regime = "HIGH";
      suggestedRiskPct = MathMax(InpVolMinRiskPercent, riskPct / ratio);
     }
   else if(ratio <= VOL_LOW_RATIO)
      regime = "LOW";
  }

//+------------------------------------------------------------------+
//| v16.00 — Hurst exponent via rescaled-range (R/S) analysis over the  |
//| last `bars` closed-bar log returns. H > 0.55 trending, H < 0.45    |
//| mean-reverting/ranging, else a random-walk transition band.        |
//+------------------------------------------------------------------+
double ComputeHurst(const MqlRates &rates[], const int lastClosed, const int bars)
  {
   const int n = MathMin(bars, lastClosed);
   if(n < 20)
      return(0.5);
   double ret[];
   ArrayResize(ret, n);
   for(int i = 0; i < n; i++)
     {
      const int a = lastClosed - n + i;
      const double c0 = rates[a].close;
      const double c1 = rates[a + 1].close;
      ret[i] = (c0 > 0.0) ? MathLog(c1 / c0) : 0.0;
     }
   double mean = 0.0;
   for(int i = 0; i < n; i++)
      mean += ret[i];
   mean /= n;
   double cum = 0.0, minC = 0.0, maxC = 0.0, sumSq = 0.0;
   for(int i = 0; i < n; i++)
     {
      cum   += (ret[i] - mean);
      minC   = MathMin(minC, cum);
      maxC   = MathMax(maxC, cum);
      sumSq += (ret[i] - mean) * (ret[i] - mean);
     }
   const double range = maxC - minC;
   const double sd     = MathSqrt(sumSq / n);
   if(sd <= 0.0 || range <= 0.0)
      return(0.5);
   const double rs = range / sd;
   // H = log(R/S) / log(n) — the standard single-window R/S estimator.
   const double h = MathLog(rs) / MathLog((double)n);
   return(MathMax(0.0, MathMin(1.0, h)));
  }

//+------------------------------------------------------------------+
//| v16.00 — Kaufman Efficiency Ratio: net displacement over the sum   |
//| of bar-to-bar movement, 0 (pure noise) .. 1 (pure trend).           |
//+------------------------------------------------------------------+
double ComputeKER(const MqlRates &rates[], const int lastClosed, const int bars)
  {
   const int n = MathMin(bars, lastClosed);
   if(n < 5)
      return(0.0);
   const double net = MathAbs(rates[lastClosed].close - rates[lastClosed - n].close);
   double vol = 0.0;
   for(int i = lastClosed - n + 1; i <= lastClosed; i++)
      vol += MathAbs(rates[i].close - rates[i - 1].close);
   return((vol > 0.0) ? MathMin(1.0, net / vol) : 0.0);
  }

//+------------------------------------------------------------------+
//| v16.00 — combine Hurst + KER into one regime label.                 |
//+------------------------------------------------------------------+
void ComputeRegime(const MqlRates &rates[], const int lastClosed, const int bars,
                   double &hurst, double &ker, string &regime)
  {
   hurst  = ComputeHurst(rates, lastClosed, bars);
   ker    = ComputeKER(rates, lastClosed, bars);
   if(hurst >= 0.55 && ker >= 0.30)
      regime = "TRENDING";
   else if(hurst <= 0.45 && ker < 0.30)
      regime = "RANGING";
   else
      regime = "TRANSITION";
  }

//+------------------------------------------------------------------+
//| v16.00 — Volatility Contraction (VCV): Bollinger-inside-Keltner     |
//| squeeze, expressed as (Bollinger width / Keltner width). < 1.0     |
//| means price is coiled inside the Keltner channel (a "squeeze").    |
//| `cone` flags the squeeze actively narrowing vs. the prior bar.     |
//+------------------------------------------------------------------+
double ComputeVcv(const MqlRates &rates[], const int lastClosed, const double atr,
                  const int period, bool &cone)
  {
   cone = false;
   const int n = MathMin(period, lastClosed);
   if(n < 5 || atr <= 0.0)
      return(1.0);
   double sum = 0.0;
   for(int i = lastClosed - n + 1; i <= lastClosed; i++)
      sum += rates[i].close;
   const double ma = sum / n;
   double sq = 0.0;
   for(int i = lastClosed - n + 1; i <= lastClosed; i++)
      sq += (rates[i].close - ma) * (rates[i].close - ma);
   const double sd = MathSqrt(sq / n);
   const double bbWidth = 2.0 * 2.0 * sd;      // Bollinger(2,2): +/-2 SD
   const double kcWidth = 2.0 * 1.5 * atr;     // Keltner(1.5xATR)
   const double squeeze = (kcWidth > 0.0) ? bbWidth / kcWidth : 1.0;

   // one-bar-back comparison to tell whether the squeeze is narrowing
   if(lastClosed - n >= n)
     {
      double sumPrev = 0.0;
      for(int i = lastClosed - 1 - n + 1; i <= lastClosed - 1; i++)
         sumPrev += rates[i].close;
      const double maPrev = sumPrev / n;
      double sqPrev = 0.0;
      for(int i = lastClosed - 1 - n + 1; i <= lastClosed - 1; i++)
         sqPrev += (rates[i].close - maPrev) * (rates[i].close - maPrev);
      const double sdPrev = MathSqrt(sqPrev / n);
      const double bbPrev = 2.0 * 2.0 * sdPrev;
      cone = (squeeze < 1.0 && bbWidth < bbPrev);
     }
   return(squeeze);
  }

//+------------------------------------------------------------------+
//| Manual ATR fallback — true-range average from raw bars (v2.07)     |
//| Used when the iATR handle/cache fails so the chart never blanks.   |
//+------------------------------------------------------------------+
double ManualAtr(const string symbol, const ENUM_TIMEFRAMES tf, const int period)
  {
   const int need = period + 2;              // window + prev-close bar + forming bar
   double hi[];
   double lo[];
   double cl[];
   ResetLastError();
   if(CopyHigh(symbol, tf, 0, need, hi) < need ||
      CopyLow(symbol, tf, 0, need, lo)  < need ||
      CopyClose(symbol, tf, 0, need, cl) < need)
     {
      if(!g_manualAtrWarned)
        {
         g_manualAtrWarned = true;           // journal once per session, not per call
         int err = GetLastError();
         Print("PAICT: ATR fallback — raw bar copy failed for ", symbol, "@",
               EnumToString(tf), ", error ", err, " (", DataErrText(err), ").");
        }
      return(0.0);
     }
   double sum = 0.0;
   int    n   = 0;
   for(int i = 1; i <= period; i++)          // index need-1 = forming bar: excluded
     {
      double tr = MathMax(hi[i] - lo[i],
                          MathMax(MathAbs(hi[i] - cl[i - 1]),
                                  MathAbs(lo[i] - cl[i - 1])));
      sum += tr;
      n++;
     }
   return(n > 0 ? sum / n : 0.0);
  }

/* ------------------------------------------------------------------ */
/* v2.07 data-error helper — human text for history/data error codes   */
/* ------------------------------------------------------------------ */
string DataErrText(const int err)
  {
   switch(err)
     {
      case 0:    return("history still loading (not enough bars yet)");
      case 4401: return("history not found — is the symbol subscribed?");
      case 4402: return("wrong history property request");
      case 4403: return("history request timeout — retried next cycle");
      case 4404: return("bars limit exceeded in the request");
     }
   return("see MQL5 documentation for this code");
  }

/* ================================================================== */
/*  v4.00 ANALYTICAL CO-PILOT — pure math (no drawing, no side effect) */
/*                                                                     */
/*  Everything here reads the account / positions / calendar cache and */
/*  writes into caller-owned structs — the same MVC seam as            */
/*  CalculateMarketState(). RenderRiskHUD() below is the only renderer */
/*  and the bridge serializes the same numbers into the matrix push.   */
/* ================================================================== */

//+------------------------------------------------------------------+
//| Simulated risk sizing — "Risk 1% = 0.25 lots"                      |
//| lots = (balance × risk%) / (stopDistance / tickSize × tickValue)   |
//| Volume-step FLOORED (never round up — that would risk more than    |
//| the configured %); broker minimum is the floor. 0.0 = not usable.  |
//+------------------------------------------------------------------+
double ComputeRiskLots(const string symbol, const double entry, const double stop,
                       const double riskPct)
  {
   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0 || riskPct <= 0.0)
      return(0.0);
   const double stopDist = MathAbs(entry - stop);
   if(stopDist <= 0.0)
      return(0.0);
   const double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return(0.0);
   const double lossPerLot = stopDist / tickSize * tickValue;   // account ccy per 1.0 lot
   if(lossPerLot <= 0.0)
      return(0.0);
   double lots = balance * riskPct / 100.0 / lossPerLot;
   const double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step > 0.0)
      lots = MathFloor(lots / step) * step;
   const double minV = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if(lots < minV)
      return(0.0);   // no compliant size exists — rounding UP to minV would risk more than riskPct
   const double maxV = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(maxV > 0.0 && lots > maxV)
      lots = maxV;   // a tight stop / large balance can floor-round above the broker's ceiling
   return(lots);
  }

//+------------------------------------------------------------------+
//| Portfolio heat — total open risk across ALL manual positions       |
//| (magic 0, every symbol). A position without a stop cannot be       |
//| sized, so it is counted separately for the HUD to flag.            |
//+------------------------------------------------------------------+
struct SHeat
  {
   double pct;        // total open risk as % of the balance
   int    positions;  // open manual positions (any symbol)
   int    noSl;       // of those, without a stop loss
   bool   alert;      // pct >= threshold
  };

void ComputePortfolioHeat(SHeat &h)
  {
   h.pct       = 0.0;
   h.positions = 0;
   h.noSl      = 0;
   h.alert     = false;
   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
      return;
   double riskMoney = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);      // selects the position
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != 0)     // manual trades only
         continue;
      h.positions++;
      const double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0)
        {
         h.noSl++;
         continue;
        }
      const string psym      = PositionGetString(POSITION_SYMBOL);
      const double tickSize  = SymbolInfoDouble(psym, SYMBOL_TRADE_TICK_SIZE);
      const double tickValue = SymbolInfoDouble(psym, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0 || tickValue <= 0.0)
         continue;
      const double dist = MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - sl);
      riskMoney += dist / tickSize * tickValue * PositionGetDouble(POSITION_VOLUME);
     }
   h.pct   = riskMoney / balance * 100.0;
   h.alert = (h.pct >= MathMax(0.1, InpMaxHeatPct));
  }

//+------------------------------------------------------------------+
//| Economic calendar — collect high-impact events of ONE currency     |
//| into the g_news cache. Silently degrades to "no blackout" on       |
//| brokers that do not serve a calendar (journal warns once).         |
//+------------------------------------------------------------------+
void CollectCalendarCurrency(const string currency, const datetime from,
                             const datetime to, const datetime now)
  {
   if(currency == "")
      return;
   MqlCalendarValue vals[];
   ResetLastError();
   if(!CalendarValueHistory(vals, from, to, NULL, currency))
     {
      if(!g_newsUnavailable)
        {
         g_newsUnavailable = true;    // journal once per session, not per scan
         Print("PAICT news: economic calendar unavailable (error ", GetLastError(),
               ") — blackout visual disabled for this session.");
        }
      return;
     }
   for(int i = 0; i < ArraySize(vals); i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev))
         continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      if(vals[i].time < now - 3600)   // keep ~1h of past releases for the post-window
         continue;
      const int at = ArraySize(g_news);
      ArrayResize(g_news, at + 1, ARRAY_RESERVE_CHUNK);
      g_news[at].time     = vals[i].time;
      g_news[at].name     = ev.name;
      g_news[at].currency = currency;
     }
  }

//+------------------------------------------------------------------+
//| Rescan the calendar (throttled to NEWS_SCAN_SEC) for the attach    |
//| symbol's base + profit currency.                                   |
//+------------------------------------------------------------------+
void ScanNews()
  {
   if(!InpNewsBlackout)
      return;
   const datetime now = TimeTradeServer();
   if(now <= 0 || now - g_newsScan < NEWS_SCAN_SEC)
      return;
   g_newsScan = now;
   ArrayResize(g_news, 0, ARRAY_RESERVE_CHUNK);
   const string base   = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   const string profit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   CollectCalendarCurrency(base,   now - 3600, now + NEWS_LOOKAHEAD_SEC, now);
   if(profit != base)
      CollectCalendarCurrency(profit, now - 3600, now + NEWS_LOOKAHEAD_SEC, now);
  }

//+------------------------------------------------------------------+
//| Blackout active RIGHT NOW? (pure read of the cached events)        |
//+------------------------------------------------------------------+
bool NewsBlackoutActive(datetime &eventTime, string &eventName)
  {
   eventTime = 0;
   eventName = "";
   if(!InpNewsBlackout)
      return(false);
   const datetime now = TimeTradeServer();
   for(int i = 0; i < ArraySize(g_news); i++)
     {
      if(now >= g_news[i].time - (long)MathMax(0, InpNewsPreMin) * 60 &&
         now <= g_news[i].time + (long)MathMax(0, InpNewsPostMin) * 60)
        {
         eventTime = g_news[i].time;
         eventName = g_news[i].name;
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| v15.02: NewsBlackoutActive() is time-continuous, but the red column |
//| / plan washout only actually get drawn or removed inside            |
//| RenderMarketState(), which the new-bar gate can hold off for a      |
//| whole timeframe. Called every OnTimer tick (cheap — just scans the  |
//| small cached g_news array) so a blackout starting or ending         |
//| mid-bar forces a redraw instead of waiting for the next closed bar. |
//+------------------------------------------------------------------+
bool g_newsBlackoutWas = false;
void CheckNewsBlackoutTransition()
  {
   datetime nt = 0;
   string   nn = "";
   const bool now = NewsBlackoutActive(nt, nn);
   if(now != g_newsBlackoutWas)
     {
      g_newsBlackoutWas = now;
      ForceFullRedraw();
     }
  }

//+------------------------------------------------------------------+
//| Remote control — apply ONE bridge command (whitelisted actions,    |
//| sanity-clamped values). Writes the g_ov runtime mirrors only.      |
//+------------------------------------------------------------------+
void ForceFullRedraw()
  {
   // the new-bar gate would otherwise keep stale markup until the next close
   for(int i = 0; i < ArraySize(g_charts); i++)
      g_charts[i].last_bar = 0;
   g_bridgeLastJSON = "";      // force the next push too
  }

void ApplyRemoteCommand(const int id, const string action, const string value)
  {
   bool applied = false;
   if(action == "SET_RISK")
     {
      const double v = StringToDouble(value);
      if(v >= REMOTE_MIN_VALUE && v <= REMOTE_MAX_VALUE)
        {
         g_ov.riskPct = v;
         applied = true;
        }
     }
   else if(action == "TOGGLE_ZONES")
     {
      g_ov.planZones = (value == "1");
      applied = true;
     }
   else if(action == "SET_RENDER")
     {
      g_ov.render = (value == "1");
      applied = true;
     }
   else if(action == "TOGGLE_SANDBOX")
     {
      g_ov.sandbox = (value == "1");     // v10.00: show/hide the draggable lines
      applied = true;
     }
   else if(action == "RESET_SANDBOX")
     {
      g_sb.active = false;               // v10.00: re-anchor from the next live plan
      applied = true;
     }
   else if(action == "PING")
      applied = true;
   if(!applied)
     {
      Print("PAICT remote: cmd #", id, " ", action, " ", value,
            " REJECTED (unknown action or value out of range).");
      return;
     }
   if(action != "PING")
      ForceFullRedraw();          // mirrors changed — redraw + re-push now
   Print("PAICT remote: cmd #", id, " ", action, " ", value, " applied.");
  }

//+------------------------------------------------------------------+
//| Two-way bridge — ask the Node bridge for pending commands after    |
//| every accepted push. Reply format (text/plain, one per line):      |
//|   CMD <id> <action> <value>                                        |
//+------------------------------------------------------------------+
void PollRemoteCommands()
  {
   string url = InpBridgeURL;
   StringReplace(url, "/v1/matrix", "/v1/poll");
   url += "?slot=" + _Symbol + "|" + BridgeTimeframeLabel();

   char   post[];
   char   result[];
   string headers = "";
   const int res = WebRequest("GET", url, "Content-Type: text/plain\r\n",
                              InpBridgeTimeoutMs, post, result, headers);
   if(res <= 0)
      return;                     // bridge down / empty queue — stay silent

   string body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   string lines[];
   const int n = StringSplit(body, '\n', lines);
   for(int i = 0; i < n; i++)
     {
      string ln = lines[i];
      StringReplace(ln, "\r", "");
      StringTrimLeft(ln);
      StringTrimRight(ln);
      if(StringFind(ln, "CMD ") != 0)
         continue;
      string parts[];
      if(StringSplit(ln, ' ', parts) < 4)
         continue;
      ApplyRemoteCommand((int)StringToInteger(parts[1]), parts[2], parts[3]);
     }
  }

/* ------------------------------------------------------------------ */
/* v2.07 object upsert infrastructure                                  */
/*                                                                     */
/* Drawers no longer DeleteAll + recreate. Each Upsert* updates an     */
/* existing object's anchors/colors IN PLACE (one ObjectFind + a few   */
/* property sets) and only calls ObjectCreate for genuinely new        */
/* objects. Every drawn object name is registered in g_drawn for the   */
/* current chart pass; SweepUndrawn() then deletes exactly the objects */
/* that stopped being valid (a filled FVG, a vanished zone, ...).      */
/* This replaces the old per-bar ObjectsDeleteAll(OBJ_PREFIX) that     */
/* churned 50+ GDI objects on every closed bar (micro-stutter).        */
/* ------------------------------------------------------------------ */
string g_drawn[];      // objects (re)drawn for the chart in the current pass

void DrawnReset()
  {
   ArrayResize(g_drawn, 0, ARRAY_RESERVE_CHUNK);
  }

void DrawnMark(const string name)
  {
   int n = ArraySize(g_drawn);
   ArrayResize(g_drawn, n + 1, ARRAY_RESERVE_CHUNK);
   g_drawn[n] = name;
  }

bool DrawnHas(const string name)
  {
   for(int i = 0; i < ArraySize(g_drawn); i++)
      if(g_drawn[i] == name)
         return(true);
   return(false);
  }

void SweepUndrawn(const long chart_id)
  {
   int total = ObjectsTotal(chart_id, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string nm = ObjectName(chart_id, i, -1, -1);
      if(StringFind(nm, OBJ_PREFIX) != 0)
         continue;
      if(!DrawnHas(nm))
         ObjectDelete(chart_id, nm);
     }
  }

//+------------------------------------------------------------------+
//| Rectangle: update anchors/colors in place, create only if missing  |
//+------------------------------------------------------------------+
bool UpsertRect(const long cid, const string name, const datetime t1, const double p1,
                const datetime t2, const double p2, const color clr,
                const bool fill, const bool back, const ENUM_LINE_STYLE style)
  {
   if(g_drawSuppressed)
      return(false);
   if(ObjectFind(cid, name) < 0)
     {
      if(!ObjectCreate(cid, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
         return(false);
      ObjectSetInteger(cid, name, OBJPROP_STYLE, style);     // static props: once
      ObjectSetInteger(cid, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(cid, name, OBJPROP_HIDDEN, true);
     }
   else
     {
      ObjectSetInteger(cid, name, OBJPROP_TIME,  0, (long)t1);
      ObjectSetDouble(cid, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(cid, name, OBJPROP_TIME,  1, (long)t2);
      ObjectSetDouble(cid, name, OBJPROP_PRICE, 1, p2);
     }
   ObjectSetInteger(cid, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(cid, name, OBJPROP_FILL, fill);
   ObjectSetInteger(cid, name, OBJPROP_BACK, back);
   DrawnMark(name);
   return(true);
  }

//+------------------------------------------------------------------+
//| Segment line: update anchors in place, create only if new          |
//+------------------------------------------------------------------+
bool UpsertSegment(const long cid, const string name, const datetime t1, const double p1,
                   const datetime t2, const double p2, const color clr,
                   const int width, const ENUM_LINE_STYLE style)
  {
   if(g_drawSuppressed)
      return(false);
   if(ObjectFind(cid, name) < 0)
     {
      if(!ObjectCreate(cid, name, OBJ_TREND, 0, t1, p1, t2, p2))
         return(false);
      ObjectSetInteger(cid, name, OBJPROP_RAY_RIGHT, false); // static props: once
      ObjectSetInteger(cid, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(cid, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(cid, name, OBJPROP_HIDDEN, true);
     }
   else
     {
      ObjectSetInteger(cid, name, OBJPROP_TIME,  0, (long)t1);
      ObjectSetDouble(cid, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(cid, name, OBJPROP_TIME,  1, (long)t2);
      ObjectSetDouble(cid, name, OBJPROP_PRICE, 1, p2);
     }
   ObjectSetInteger(cid, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(cid, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(cid, name, OBJPROP_STYLE, style);
   DrawnMark(name);
   return(true);
  }

//+------------------------------------------------------------------+
//| Text label: update position/text/style in place, create if new     |
//+------------------------------------------------------------------+
bool UpsertText(const long cid, const string name, const datetime t, const double p,
                const string text, const color clr, const int fontSize,
                const string font, const ENUM_ANCHOR_POINT anchor)
  {
   if(g_drawSuppressed)
      return(false);
   if(ObjectFind(cid, name) < 0)
     {
      if(!ObjectCreate(cid, name, OBJ_TEXT, 0, t, p))
         return(false);
      ObjectSetString(cid, name, OBJPROP_FONT, font);        // static prop: once
      ObjectSetInteger(cid, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(cid, name, OBJPROP_HIDDEN, true);
     }
   else
     {
      ObjectSetInteger(cid, name, OBJPROP_TIME,  0, (long)t);
      ObjectSetDouble(cid, name, OBJPROP_PRICE, 0, p);
     }
   ObjectSetString(cid, name, OBJPROP_TEXT, text);
   ObjectSetInteger(cid, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(cid, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(cid, name, OBJPROP_ANCHOR, anchor);
   DrawnMark(name);
   return(true);
  }

//+------------------------------------------------------------------+
//| Pixel label (OBJ_LABEL): HUD lines that must not drift with price  |
//+------------------------------------------------------------------+
bool UpsertLabel(const long cid, const string name, const int x, const int y,
                 const string text, const color clr, const int fontSize,
                 const string font, const ENUM_BASE_CORNER corner)
  {
   if(g_drawSuppressed)
      return(false);
   if(ObjectFind(cid, name) < 0)
     {
      if(!ObjectCreate(cid, name, OBJ_LABEL, 0, 0, 0))
         return(false);
      ObjectSetString(cid, name, OBJPROP_FONT, font);        // static prop: once
      ObjectSetInteger(cid, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(cid, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(cid, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(cid, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(cid, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(cid, name, OBJPROP_TEXT, text);
   ObjectSetInteger(cid, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(cid, name, OBJPROP_COLOR, clr);
   DrawnMark(name);
   return(true);
  }

//+------------------------------------------------------------------+
//| Vertical rectangle (full chart height) — news blackout column      |
//| MQL5 has NO OBJ_VRECTANGLE type (v4.01 hotfix: the first MetaEditor|
//| compile of v4.00 failed with "undeclared identifier"). A full-     |
//| height column is built from a regular OBJ_RECTANGLE whose price    |
//| span overshoots the viewport by ~3 decades of the chart symbol's   |
//| bid: MT5 auto-scaling only ever considers BARS — never chart       |
//| objects — so the rectangle is clipped at the viewport top/bottom   |
//| and behaves like a true vertical band at any zoom, without         |
//| re-pinning (correct even while rendering is paused).               |
//+------------------------------------------------------------------+
bool UpsertVRect(const long cid, const string name, const datetime t1, const datetime t2,
                 const color clr, const bool fill, const bool back)
  {
   if(g_drawSuppressed)
      return(false);
   const string sym = ChartSymbol(cid);
   const double bid = (StringLen(sym) > 0 ? SymbolInfoDouble(sym, SYMBOL_BID) : 0.0);
   const double lo  = (bid > 0.0 ? bid * 0.001  : -1.0e9);   // far below any zoom
   const double hi  = (bid > 0.0 ? bid * 1000.0 :  1.0e9);   // far above any zoom
   if(ObjectFind(cid, name) < 0)
     {
      if(!ObjectCreate(cid, name, OBJ_RECTANGLE, 0, t1, lo, t2, hi))
         return(false);
      ObjectSetInteger(cid, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(cid, name, OBJPROP_HIDDEN, true);
     }
   else
     {
      ObjectSetInteger(cid, name, OBJPROP_TIME,  0, (long)t1);
      ObjectSetInteger(cid, name, OBJPROP_TIME,  1, (long)t2);
      ObjectSetDouble(cid, name, OBJPROP_PRICE, 0, lo);
      ObjectSetDouble(cid, name, OBJPROP_PRICE, 1, hi);
     }
   ObjectSetInteger(cid, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(cid, name, OBJPROP_FILL, fill);
   ObjectSetInteger(cid, name, OBJPROP_BACK, back);
   DrawnMark(name);
   return(true);
  }

//+------------------------------------------------------------------+
//| Clear every field/array of the state struct                        |
//+------------------------------------------------------------------+
void MarketStateReset(SMarketState &st)
  {
   st.ok         = false;
   st.symbol     = "";
   st.tf         = PERIOD_CURRENT;
   st.lastClosed = 0;
   st.closedBar  = 0;
   st.atr        = 0.0;
   st.closeRef   = 0.0;
   ArrayResize(st.hiIdx, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(st.hiVal, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(st.loIdx, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(st.loVal, 0, ARRAY_RESERVE_CHUNK);
   st.nHi = 0;
   st.nLo = 0;
   ArrayResize(st.supply, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(st.demand, 0, ARRAY_RESERVE_CHUNK);
   st.zonesDrawn = 0;
   st.bullIdx = -1;
   st.bearIdx = -1;
   ArrayResize(st.fvgLo, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(st.fvgHi, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(st.fvgT1, 0, ARRAY_RESERVE_CHUNK);
   st.fvgCount = 0;
   st.chocIdx = -1;   st.chocLvl = 0.0;
   st.mssIdx  = -1;   st.mssLvl  = 0.0;
   st.structCount = 0;
   ArrayResize(st.bslLv, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(st.bslT,  0, ARRAY_RESERVE_CHUNK);
   ArrayResize(st.sslLv, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(st.sslT,  0, ARRAY_RESERVE_CHUNK);
   st.liqDrawn = 0;
   st.eq = 0.0;
   st.rangeHi = 0.0;
   st.rangeLo = 0.0;
   st.eqT0 = 0;
   st.planOk    = false;
   st.planEntry = 0.0;
   st.planStop  = 0.0;
   st.planTarget = 0.0;
   // v11.00
   st.oteOk      = false;
   st.oteLow     = 0.0;
   st.oteHigh    = 0.0;
   st.oteBullish = false;
   st.oteT0      = 0;
   st.dOpen      = 0.0;
   st.dOpenT     = 0;
   st.wOpen      = 0.0;
   st.wOpenT     = 0;
   st.breakerOk       = false;
   st.breakerWasBull  = false;
   st.breakerLo       = 0.0;
   st.breakerHi       = 0.0;
   st.breakerT1       = 0;
   st.planShiftWarn   = false;
   st.volRegime       = "";
   st.volRatio        = 0.0;
   st.suggestedRiskPct = 0.0;
   // v16.00-v20.00
   st.regime      = "";
   st.hurst       = 0.0;
   st.ker         = 0.0;
   st.vcvSqueeze  = 0.0;
   st.vcvCone     = false;
   st.confluence  = 0;
   st.confCount   = 0;
   st.confTags    = "";
   st.harmonic    = "";
   st.harmDir     = 0;
   st.przLo       = 0.0;
   st.przHi       = 0.0;
   st.elliott     = "";
   st.ewDir       = 0;
   st.ycSpread    = 0.0;
   st.ycInverted  = false;
   st.ycOk        = false;
   st.leadSym     = "";
   st.leadMove    = 0.0;
   st.leadDir     = 0;
   st.leadFlash   = false;
   st.oracleScore = -1;
   // v21.00-v24.00
   st.tpoOk            = false;
   st.tpoPoc           = 0.0;
   st.tpoVah           = 0.0;
   st.tpoVal           = 0.0;
   st.tpoSinglePrints  = 0;
   st.tpoPoorHigh      = false;
   st.tpoPoorLow       = false;
   st.wfWinPct         = 0.0;
   st.wfExpectancyR    = 0.0;
   st.wfTrades         = 0;
   st.statArbZ         = 0.0;
   st.statArbFlag      = false;
   st.statArbSym       = "";
   st.optOk            = false;
   st.ivCall           = 0.0;
   st.ivPut            = 0.0;
   st.gammaLevel       = 0.0;
  }

// Attach chart's latest plan — the Web Bridge reads THIS (v2.07: no more
// OBJPROP_PRICE scraping off chart objects; works while charts are hidden).
struct SAttachPlan
  {
   bool   ok;
   double entry;
   double stop;
   double target;
  };
SAttachPlan g_plan;

/* ------------------------------------------------------------------ */
/* Main drawing pipeline for one chart (v2.07 MVC)                     */
/*                                                                     */
/*   CalculateMarketState() — pure detection, NO drawing: fills one    */
/*   SMarketState from confirmed bars only (non-repainting).           */
/*                                                                     */
/*   RenderMarketState() — draws the state via the upsert helpers and  */
/*   sweeps objects that are no longer valid. Returns HTF draw count   */
/*   for the diagnostic journal line.                                  */
/*                                                                     */
/*   DrawOnChart() — new-bar gate + orchestration + journal.           */
/* ------------------------------------------------------------------ */
bool CalculateMarketState(const long chart_id, const string symbol, const ENUM_TIMEFRAMES tf,
                          MqlRates &rates[], SMarketState &st)
  {
   MarketStateReset(st);
   st.symbol = symbol;
   st.tf     = tf;

   const int need = MathMax(InpLookbackBars, InpICTLookback) + 30;
   ResetLastError();                              // v2.07: exact error, not silence
   int total = CopyRates(symbol, tf, 0, need, rates);
   if(total < 60)
     {
      int err = GetLastError();                   // 0 = request ok, history still short
      int si  = ChartStateIndex(chart_id);
      if(si >= 0 && g_charts[si].last_data_err != err)
        {
         g_charts[si].last_data_err = err;        // one journal line per NEW error
         Print("PAICT: CopyRates(", symbol, "@", EnumToString(tf), ") -> ",
               total, " bars, error ", err, " (", DataErrText(err),
               ") — markup paused for this chart until data is ready.");
        }
      return(false);
     }
   int siOk = ChartStateIndex(chart_id);
   if(siOk >= 0)
      g_charts[siOk].last_data_err = -1;          // re-arm the throttle after success

   st.lastClosed = total - 2;                     // exclude forming bar
   if(st.lastClosed < 10)
      return(false);
   st.closedBar = rates[st.lastClosed].time;
   st.atr       = GetAtr(symbol, tf);
   st.closeRef  = rates[st.lastClosed].close;

   /* -------- shared swing detection (zones, trend, structure, plan) --- */
   FindSwings(rates, st.lastClosed, InpSwingStrength,
              st.hiIdx, st.hiVal, st.nHi, st.loIdx, st.loVal, st.nLo);

   /* -------- zones (Price Action) — computed ONCE; the trade-plan     */
   /* fallback consumes the EXACT boxes the renderer draws (v1.08 rule) */
   if(InpDrawPriceAction && st.atr > 0.0)
      st.zonesDrawn = BuildZones(rates, st.atr, st.closeRef,
                                 st.hiIdx, st.hiVal, st.nHi, st.loIdx, st.loVal, st.nLo,
                                 st.supply, st.demand);

   /* --------------------- liquidity pools (BSL/SSL) ----------- */
   if(InpDrawLiquidity && st.atr > 0.0)
      st.liqDrawn = FindLiquidity(rates, st.lastClosed, st.atr, st.closeRef,
                                  st.hiIdx, st.hiVal, st.nHi, st.loIdx, st.loVal, st.nLo,
                                  st.bslLv, st.bslT, st.sslLv, st.sslT);

   /* --------------------- premium / discount EQ ------------------ */
   if(InpDrawPremiumDiscount)
      ComputeEQ(rates, st.lastClosed,
                st.hiIdx, st.hiVal, st.nHi, st.loIdx, st.loVal, st.nLo,
                st.eq, st.rangeHi, st.rangeLo, st.eqT0);

   /* ----------------------------- ICT / SMC ---------------------- */
   const double dThr = st.atr * InpDisplacementATR;
   if(InpDrawICT && dThr > 0.0)
     {
      // v14.00: best-of-N unmitigated order blocks, scored by ATR-normalized
      // R:R to the nearest external-liquidity target, instead of always the
      // single newest one — InpPlanCandidates=1 recovers the old behavior.
      int bullCands[];
      int bearCands[];
      const int maxCand = MathMax(1, InpPlanCandidates);
      FindOrderBlockCandidates(rates, st.lastClosed, dThr, true,  bullCands, maxCand);
      FindOrderBlockCandidates(rates, st.lastClosed, dThr, false, bearCands, maxCand);
      st.bullIdx = PickBestOB(rates, bullCands, ArraySize(bullCands), true,
                              st.hiIdx, st.hiVal, st.nHi, st.loIdx, st.loVal, st.nLo, st.atr);
      st.bearIdx = PickBestOB(rates, bearCands, ArraySize(bearCands), false,
                              st.hiIdx, st.hiVal, st.nHi, st.loIdx, st.loVal, st.nLo, st.atr);

      if(InpDrawFVG)
         st.fvgCount = FindFVGs(rates, st.lastClosed, dThr,
                                st.fvgLo, st.fvgHi, st.fvgT1);

      if(InpDrawStructure && st.atr > 0.0)
         st.structCount = FindStructureBreaks(rates, st.lastClosed,
                                              st.hiIdx, st.hiVal, st.nHi,
                                              st.loIdx, st.loVal, st.nLo,
                                              st.chocIdx, st.chocLvl,
                                              st.mssIdx, st.mssLvl);

      // v12.00: a mitigated OB that reversed hard becomes a breaker block.
      if(InpBreakerBlocks)
         st.breakerOk = FindBreakerBlock(rates, st.lastClosed, dThr, st.atr,
                                         st.breakerWasBull, st.breakerLo, st.breakerHi, st.breakerT1);
     }

   /* --------------------------- Trade Plan ----------------------- */
   if(InpDrawPlan && st.atr > 0.0)
     {
      st.planOk = ComputeTradePlan(rates, st.lastClosed, st.closeRef, st.atr,
                                   st.hiIdx, st.hiVal, st.nHi, st.loIdx, st.loVal, st.nLo,
                                   st.bullIdx, st.bearIdx,
                                   st.supply, ArraySize(st.supply),
                                   st.demand, ArraySize(st.demand),
                                   st.planEntry, st.planStop, st.planTarget);

      // v12.00: a fresher counter-trend CHoCH/MSS while price hasn't yet
      // reached ENTRY flags the plan instead of leaving it silently stale.
      if(st.planOk && InpStructureShiftTag)
         st.planShiftWarn = DetectStructureShift(st.lastClosed, st.chocIdx, st.mssIdx,
                                                 st.closeRef, st.planEntry, st.planTarget);
     }

   /* --------------------------- v11.00: OTE pocket ----------------- */
   if(InpDrawOTE)
      st.oteOk = ComputeOTE(rates, st.hiIdx, st.hiVal, st.nHi, st.loIdx, st.loVal, st.nLo,
                            st.oteLow, st.oteHigh, st.oteBullish, st.oteT0);

   /* --------------------- v11.00: daily / weekly opens ------------- */
   if(InpDrawDayWeekOpens)
      ComputeDayWeekOpens(symbol, st.dOpen, st.dOpenT, st.wOpen, st.wOpenT);

   /* --------------------- v14.00: volatility regime ----------------- */
   if(InpVolRegime && st.atr > 0.0)
     {
      const double atrAvg = GetAtrAverage(symbol, tf, MathMax(5, InpVolRegimeBars));
      ComputeVolRegime(st.atr, atrAvg, g_ov.riskPct, st.volRegime, st.volRatio, st.suggestedRiskPct);
     }

   /* --------------------- v16.00: regime + VCV ---------------------- */
   if(InpRegime)
      ComputeRegime(rates, st.lastClosed, MathMax(20, InpRegimeBars), st.hurst, st.ker, st.regime);
   if(InpVcv && st.atr > 0.0)
      st.vcvSqueeze = ComputeVcv(rates, st.lastClosed, st.atr, MathMax(5, InpATRPeriod), st.vcvCone);

   /* --------------------- v17.00: confluence fusion ------------------ */
   if(InpConfluence)
      st.confluence = ComputeConfluence(st, st.confCount, st.confTags);

   /* --------------------- v18.00: harmonic + Elliott ------------------ */
   if(InpHarmonics)
      ComputeHarmonic(st.hiIdx, st.hiVal, st.nHi, st.loIdx, st.loVal, st.nLo,
                      InpHarmonicTolPct, st.harmonic, st.harmDir, st.przLo, st.przHi);
   if(InpElliottWave)
      ComputeElliott(st.hiIdx, st.hiVal, st.nHi, st.loIdx, st.loVal, st.nLo, st.elliott, st.ewDir);

   /* --------------------- v19.00: macro crosscurrents ------------------ */
   if(InpYieldCurve)
      st.ycOk = ComputeYieldCurve(InpYieldShort, InpYieldLong, st.ycSpread, st.ycInverted);
   if(InpLeadLag)
     {
      st.leadSym = InpLeadSymbol;
      ComputeLeadLag(InpLeadSymbol, InpLeadAtrMult, st.leadMove, st.leadDir, st.leadFlash);
     }

   /* --------------------- v21.00: local TPO market profile ------------- */
   if(InpTpoProfile && st.atr > 0.0)
      st.tpoOk = ComputeTPOProfile(rates, st.lastClosed, st.atr, MathMax(5, InpTpoPeriodMin),
                                   st.tpoPoc, st.tpoVah, st.tpoVal, st.tpoSinglePrints,
                                   st.tpoPoorHigh, st.tpoPoorLow);

   /* --------------------- v22.00: walk-forward matrix ------------------- */
   if(InpWalkForward && st.planOk && st.atr > 0.0)
     {
      const bool wfLong       = (st.planTarget > st.planEntry);
      const double wfRiskDist = MathAbs(st.planEntry - st.planStop);
      const double wfRwdDist  = MathAbs(st.planTarget - st.planEntry);
      ComputeWalkForward(rates, st.lastClosed, st.atr, wfLong, wfRiskDist, wfRwdDist,
                         InpWalkForwardBars, st.wfWinPct, st.wfExpectancyR, st.wfTrades);
     }

   /* --------------------- v23.00: statistical arbitrage ------------------ */
   if(InpStatArb && g_corrSym != "")
     {
      st.statArbSym = g_corrSym;
      ComputeStatArb(rates, st.lastClosed, g_corrSym, tf, MathMax(20, InpStatArbBars),
                     InpStatArbZ, st.statArbZ, st.statArbFlag);
     }

   /* --------------------- v24.00: options Greeks / IV --------------------- */
   if(InpOptionsGreeks)
      st.optOk = ComputeOptionsGreeks(InpOptCallSymbol, InpOptPutSymbol, st.closeRef,
                                      InpOptStrike, InpOptExpiry, InpOptRiskFreeRate,
                                      st.ivCall, st.ivPut, st.gammaLevel);

   st.ok = true;
   return(true);
  }

//+------------------------------------------------------------------+
//| Draw one SMarketState. Everything goes through the upsert helpers, |
//| then SweepUndrawn removes exactly the objects that stopped being   |
//| valid. Returns the HTF overlay count for the diagnostic journal.   |
//+------------------------------------------------------------------+
int RenderMarketState(const long chart_id, const MqlRates &rates[], const SMarketState &st,
                      const bool setupMuted)
  {
   DrawnReset();

   /* -------- killzone shading first — background fills (opt-in) --- */
   if(InpDrawKillzones)
      DrawKillzones(chart_id, st.symbol, rates, st.lastClosed, st.closeRef, st.atr);

   /* --------------------- v11.00: daily / weekly opens ------------ */
   if(InpDrawDayWeekOpens && (st.dOpen > 0.0 || st.wOpen > 0.0))
      RenderDayWeekOpens(chart_id, rates, st.tf, st.lastClosed, st.closeRef,
                         st.dOpen, st.dOpenT, st.wOpen, st.wOpenT);

   /* ------------- news blackout column (v4.00, opt-in) ------------ */
   // A red full-height column spans the blackout window around every
   // high-impact calendar event of the symbol's currencies; the plan
   // BANDS wash out toward the background while it is active.
   // g_news is populated by ScanNews() from ONLY the ATTACH chart's
   // _Symbol currencies — applying it to every other covered chart would
   // wash out an unrelated symbol's plan (or miss its own real news).
   // Restrict the blackout read to the attach chart until a per-symbol
   // calendar cache exists.
   datetime newsT    = 0;
   string   newsName = "";
   const bool blackout = (chart_id == ChartID()) && NewsBlackoutActive(newsT, newsName);
   if(blackout)
     {
      const datetime pre  = (datetime)((long)newsT - (long)MathMax(0, InpNewsPreMin) * 60);
      const datetime post = (datetime)((long)newsT + (long)MathMax(0, InpNewsPostMin) * 60);
      UpsertVRect(chart_id, OBJ_PREFIX + "NEWS_COL", pre, post, COL_STOP, true, true);
      const double lblY = (st.atr > 0.0) ? st.closeRef + st.atr * KZ_LBL_ATR
                                         : st.closeRef;
      UpsertText(chart_id, OBJ_PREFIX + "NEWS_LBL", pre, lblY,
                 "NEWS " + newsName, COL_STOP, 8, "Arial Bold", ANCHOR_LEFT_LOWER);
     }

   /* --------------------------- Price Action -------------------- */
   const int maxZones = MathMax(1, InpZonesPerSide);
   for(int s = 0; s < ArraySize(st.supply) && s < maxZones; s++)
      DrawZoneBox(chart_id, rates, st.tf, st.lastClosed, st.supply[s], st.atr,
                  COL_RESIST, "SUPPLY_" + IntegerToString(s),
                  "supply zone " + IntegerToString(s + 1));
   for(int d = 0; d < ArraySize(st.demand) && d < maxZones; d++)
      DrawZoneBox(chart_id, rates, st.tf, st.lastClosed, st.demand[d], st.atr,
                  COL_SUPPORT, "DEMAND_" + IntegerToString(d),
                  "demand zone " + IntegerToString(d + 1));

   if(InpDrawPriceAction && InpDrawTrendLine && (st.nHi >= 2 || st.nLo >= 2))
      DrawTrendLine(chart_id, rates, st.tf, st.lastClosed,
                    st.nHi, st.hiIdx, st.hiVal, st.nLo, st.loIdx, st.loVal);

   /* --------------------------- v11.00: OTE pocket ----------------- */
   if(InpDrawOTE && st.oteOk)
      DrawOTE(chart_id, rates, st.tf, st.lastClosed, st.closeRef, st.oteT0,
             st.oteLow, st.oteHigh, st.oteBullish);

   /* ----------------------- liquidity pools (BSL/SSL) ----------- */
   const datetime liqEnd = (datetime)(rates[st.lastClosed].time +
                                      (long)PeriodSeconds(st.tf) * MathMax(1, InpExtendRightBars));
   for(int b = 0; b < ArraySize(st.bslLv); b++)
      DrawPoolLine(chart_id, st.bslT[b], liqEnd, st.bslLv[b], st.closeRef,
                   "LIQ_BSL_" + IntegerToString(b), "BSL");
   for(int q = 0; q < ArraySize(st.sslLv); q++)
      DrawPoolLine(chart_id, st.sslT[q], liqEnd, st.sslLv[q], st.closeRef,
                   "LIQ_SSL_" + IntegerToString(q), "SSL");

   /* --------------------- premium / discount EQ ------------------ */
   if(InpDrawPremiumDiscount && st.eq > 0.0)
      RenderPremiumDiscount(chart_id, rates, st.tf, st.lastClosed, st.closeRef,
                            st.eq, st.rangeHi, st.rangeLo, st.eqT0);

   /* ----------------------------- ICT / SMC ---------------------- */
   if(InpDrawOB && st.bullIdx >= 0)
      DrawOrderBlock(chart_id, rates, st.tf, st.lastClosed, st.bullIdx, true,
                     st.closeRef, "", "bullish OB", 0, 1.0);
   if(InpDrawOB && st.bearIdx >= 0)
      DrawOrderBlock(chart_id, rates, st.tf, st.lastClosed, st.bearIdx, false,
                     st.closeRef, "", "bearish OB", 0, 1.0);

   if(InpDrawFVG && st.fvgCount > 0)
      RenderFVGs(chart_id, rates, st.tf, st.lastClosed,
                 st.fvgLo, st.fvgHi, st.fvgT1, st.fvgCount, st.closeRef,
                 "", "", 0, 1.0);

   if(InpDrawStructure && st.structCount > 0)
     {
      if(st.chocIdx >= 0)
         DrawBreakDash(chart_id, rates, st.lastClosed, st.chocIdx, st.chocLvl,
                       COL_CHOCH, STYLE_DOT, 1, "CHoCH");
      if(st.mssIdx >= 0)
         DrawBreakDash(chart_id, rates, st.lastClosed, st.mssIdx, st.mssLvl,
                       COL_STRUCT, STYLE_DASH, 2, "MSS/BOS");
     }

   /* --------------------------- v12.00: breaker block --------------- */
   if(InpBreakerBlocks && st.breakerOk)
      DrawBreakerBlock(chart_id, rates, st.tf, st.lastClosed, st.closeRef,
                       st.breakerT1, st.breakerLo, st.breakerHi, st.breakerWasBull);

   /* --------------------- HTF overlay (dimmed, labelled) --------- */
   int htfDrawn = 0;
   // v15.02: HTF OB/FVG boxes are still ICT/SMC markup — the InpDrawICT
   // master toggle (and its per-layer OB/FVG toggles, honored inside
   // DrawHTFOverlay) must disable them too, not just the chart-TF ones.
   if(InpDrawHTF && InpDrawICT)
      htfDrawn = DrawHTFOverlay(chart_id, st.symbol, st.tf, rates, st.lastClosed, st.closeRef);

   /* --------------------------- Trade Plan ----------------------- */
   if(st.planOk)
      RenderTradePlan(chart_id, rates, st.tf, st.lastClosed, st.closeRef,
                      st.planEntry, st.planStop, st.planTarget, blackout,
                      InpStructureShiftTag && st.planShiftWarn);

   /* --------------------- co-pilot HUD (v4.00) -------------------- */
   if(InpRiskHUD || InpHeatTracker)
      RenderRiskHUD(chart_id, st);

   /* ------- V5-V10 zenith analyzers + HUD + sandbox + master ------- */
   const int zenHudY = RenderZenithHUD(chart_id, st.symbol, st.tf, st, setupMuted);
   if(InpVolumeProfile)
      DrawVolumeProfile(chart_id, rates, st.tf, st.lastClosed, st);
   else
     {
      // v15.02: layer off — clear the cached levels so AppendZenithJSON()
      // stops publishing a stale POC/VAH/VAL from a prior render.
      g_vpPoc = 0.0;
      g_vpVah = 0.0;
      g_vpVal = 0.0;
     }
   if(InpProbabilityCone)
      DrawProbabilityCone(chart_id, rates, st.tf, st.lastClosed, st.closeRef);
   if(InpCVD)
      DrawCVD(chart_id, rates, st.lastClosed, st);
   else
     {
      // v15.01: CVD off — clear the shared reading so ComputeMasterScore()
      // and the bridge payload don't keep scoring a stale prior signal
      // (globals survive across renders and OnInit reparameterization).
      g_cvdDir = 0;
      g_cvdDiv = false;
     }
   if(InpSweepTags)
      TagSweeps(chart_id, rates, st);
   if(InpAbsorption)
      TagAbsorption(chart_id, rates, st);
   if(InpDisplacementGrade)
      TagDisplacement(chart_id, rates, st);
   if(InpICTPatterns)
      DrawICTPatterns(chart_id, rates, st);
   if(InpDrawDOM)
      DrawDOMStrip(chart_id, st.symbol, st.tf);
   // v15.01: g_sb is one shared instance, and CHARTEVENT_OBJECT_DRAG only
   // ever fires for the EA's own (attach) chart anyway — rendering it on
   // every covered chart let each one's plan reanchor and clobber a drag
   // just made on the attach chart.
   if(InpSandbox && g_ov.sandbox && chart_id == ChartID())
      RenderSandbox(chart_id, rates, st.lastClosed, st.tf, st);
   if(InpEquitySpark && chart_id == ChartID())
      DrawEquitySpark(chart_id, rates, st.lastClosed, st.tf, st.atr, st.closeRef);
   if(InpMasterScore)
     {
      g_masterScore = ComputeMasterScore(st);
      if(g_masterScore >= 0)
         g_masterVerdict = (g_masterScore >= MathMax(50, InpMasterGoAt) ? "GO" :
                            (g_masterScore >= MathMax(1, InpMasterWaitAt) ? "WAIT" :
                             "NO TRADE"));
      else
         g_masterVerdict = "";
      RenderMasterScoreLabel(chart_id);
      // v15.00: feed this chart's read into the cross-chart leaderboard —
      // the globals above hold THIS chart's numbers right now.
      if(InpLeaderboard)
         UpdateLeaderboard(st.symbol, st.tf, g_masterScore, g_masterVerdict);
      // v20.00: the Oracle Score fuses this chart's just-computed Master
      // Score with its confluence read — must run after g_masterScore above.
      if(InpOracleScore)
        {
         g_oracleScore   = ComputeOracleScore(st, g_masterScore, st.confluence);
         g_oraclePerfect = (g_oracleScore >= MathMax(1, InpOracleGoAt));
         RenderOracleLabel(chart_id);
        }
     }
   // v15.02: rendered AFTER the update above (and after RenderZenithHUD,
   // whose fractal/MC/correlation reads the Master Score above depends
   // on) so THIS chart's own just-computed row is never one cycle stale.
   if(InpLeaderboard)
      RenderLeaderboard(chart_id, zenHudY);

   SweepUndrawn(chart_id);
   return(htfDrawn);
  }

//+------------------------------------------------------------------+
//| Orchestration: new-bar gate -> calculate -> render -> journal      |
//+------------------------------------------------------------------+
void DrawOnChart(const long chart_id, const string symbol, const ENUM_TIMEFRAMES tf)
  {
   // Redraw gate: only when a NEW bar has closed (or the chart is covered for
   // the first time). Skipping unchanged bars keeps idle charts at zero cost.
   datetime closedNow = iTime(symbol, tf, 1);
   int       stateAt  = ChartStateIndex(chart_id);
   if(stateAt >= 0 && closedNow > 0 && g_charts[stateAt].last_bar == closedNow)
      return;

   MqlRates     rates[];
   SMarketState st;
   if(!CalculateMarketState(chart_id, symbol, tf, rates, st))
      return;                       // data not ready — throttled journal inside

   // v5.00 self-heal: judge the plan against the newly closed bar; a muted
   // setup stops rendering AND stops feeding the bridge until it re-arms
   // (a TARGET hit resets the fail counter immediately).
   bool setupMuted = false;
   if(InpSelfHeal)
     {
      SelfHealUpdate(symbol, tf, rates, st);
      setupMuted = SetupIsMuted(symbol, tf, st.closedBar, PeriodSeconds(tf));
     }
   if(setupMuted && st.planOk)
      st.planOk = false;            // no plan lines, no bridge push, no sizing

   // v3.00: drawing can be paused while the state keeps calculating —
   // the bridge keeps pushing the freshest levels the whole time.
   // v15.02: RenderMarketState() is now ALWAYS called — the v6-v10
   // analyzers it drives (fractal alignment, Monte Carlo, correlation,
   // CVD, displacement grade, Master Score) live INSIDE it, so skipping
   // the whole call on pause froze them too, despite the documented
   // "state keeps calculating" promise. g_drawSuppressed instead makes
   // every Upsert* drawing primitive a no-op while paused; nothing gets
   // marked drawn, so SweepUndrawn() clears the chart, while every
   // calculation runs exactly as normal.
   const bool render = (!InpPauseRender && g_ov.render);
   g_drawSuppressed  = !render;
   const int htfDrawn = RenderMarketState(chart_id, rates, st, setupMuted);

   // v2.07: the Web Bridge reads the ATTACH chart's plan from this cache —
   // no chart-object scraping, valid even while the chart is hidden.
   if(chart_id == ChartID())
     {
      g_plan.ok     = st.planOk;
      g_plan.entry  = st.planEntry;
      g_plan.stop   = st.planStop;
      g_plan.target = st.planTarget;
      // v10.00: snapshot the zenith metric bus for the bridge payload —
      // globals hold THIS chart's numbers right after its render pass.
      g_setupMuted   = setupMuted;
      g_zen.align    = g_alignScore;
      g_zen.mcTP     = g_mcTP;
      g_zen.mcSL     = g_mcSL;
      g_zen.cvdDir   = g_cvdDir;
      g_zen.cvdDiv   = g_cvdDiv;
      g_zen.disp     = g_dispGrade;
      g_zen.corrSym  = g_corrSym;
      g_zen.corrR    = g_corrR;
      g_zen.corrWarn = g_corrWarn;
      g_zen.poc      = g_vpPoc;
      g_zen.vah      = g_vpVah;
      g_zen.val      = g_vpVal;
      g_zen.master   = g_masterScore;
      g_zen.verdict  = g_masterVerdict;
      g_zen.muted    = setupMuted;
      g_zen.sbActive = (InpSandbox && g_ov.sandbox && g_sb.active);
      g_zen.sbE      = g_sb.entry;
      g_zen.sbS      = g_sb.stop;
      g_zen.sbT      = g_sb.tp;
      // v11.00: OTE pocket + daily/weekly opens for the bridge payload
      g_zen.oteOk      = st.oteOk;
      g_zen.oteLow     = st.oteLow;
      g_zen.oteHigh    = st.oteHigh;
      g_zen.oteBullish = st.oteBullish;
      g_zen.dOpen      = st.dOpen;
      g_zen.wOpen      = st.wOpen;
      // v12.00 / v13.00 / v14.00: execution layer, journal stats, adaptive risk
      g_zen.planShiftWarn    = st.planShiftWarn;
      g_zen.volRegime        = st.volRegime;
      g_zen.suggestedRiskPct = st.suggestedRiskPct;
      g_zen.statsWinPct      = g_statsWinPct;
      g_zen.statsExpectancyR = g_statsExpR;
      g_zen.statsTrades      = g_statsTrades;
      // v16.00-v20.00: Oracle engine bridge payload
      g_zen.regime      = st.regime;
      g_zen.hurst       = st.hurst;
      g_zen.ker         = st.ker;
      g_zen.vcvSqueeze  = st.vcvSqueeze;
      g_zen.vcvCone     = st.vcvCone;
      g_zen.confluence  = st.confluence;
      g_zen.confCount   = st.confCount;
      g_zen.confTags    = st.confTags;
      g_zen.harmonic    = st.harmonic;
      g_zen.harmDir     = st.harmDir;
      g_zen.przLo       = st.przLo;
      g_zen.przHi       = st.przHi;
      g_zen.elliott     = st.elliott;
      g_zen.ewDir       = st.ewDir;
      g_zen.ycOk        = st.ycOk;
      g_zen.ycSpread    = st.ycSpread;
      g_zen.ycInverted  = st.ycInverted;
      g_zen.leadSym     = st.leadSym;
      g_zen.leadMove    = st.leadMove;
      g_zen.leadDir     = st.leadDir;
      g_zen.leadFlash   = st.leadFlash;
      g_zen.oracleScore = g_oracleScore;
      // v21.00-v24.00
      g_zen.tpoOk           = st.tpoOk;
      g_zen.tpoPoc          = st.tpoPoc;
      g_zen.tpoVah          = st.tpoVah;
      g_zen.tpoVal          = st.tpoVal;
      g_zen.tpoSinglePrints = st.tpoSinglePrints;
      g_zen.tpoPoorHigh     = st.tpoPoorHigh;
      g_zen.tpoPoorLow      = st.tpoPoorLow;
      g_zen.wfWinPct        = st.wfWinPct;
      g_zen.wfExpectancyR   = st.wfExpectancyR;
      g_zen.wfTrades        = st.wfTrades;
      g_zen.statArbZ        = st.statArbZ;
      g_zen.statArbFlag     = st.statArbFlag;
      g_zen.statArbSym      = st.statArbSym;
      g_zen.optOk           = st.optOk;
      g_zen.ivCall          = st.ivCall;
      g_zen.ivPut           = st.ivPut;
      g_zen.gammaLevel      = st.gammaLevel;
     }

   /* --------------------- JSON export hook (opt-in) --------------- */
   if(InpExportJSON)
      WriteChartJSON(st, rates);

   ChartStateTouch(chart_id, st.closedBar, symbol, tf);

   if(InpVerboseLog)
      Print("PAICT diag ", symbol, "@", EnumToString(tf),
            ": swings ", st.nHi, "/", st.nLo,
            " · zones ", st.zonesDrawn,
            " · OB ", (st.bullIdx >= 0 ? "bull" : "—"), "/", (st.bearIdx >= 0 ? "bear" : "—"),
            " · FVG ", st.fvgCount,
            " · struct ", st.structCount,
            " · liq ", st.liqDrawn,
            " · eq ", (st.eq > 0.0 ? "yes" : "no"),
            " · HTF ", htfDrawn,
            " · plan ", (st.planOk ? "yes" : "no"),
            " · ote ", (st.oteOk ? "yes" : "no"),
            (InpExportJSON ? " · json ok" : ""),
            (!render ? " · RENDER PAUSED" : ""),
            " · closed bar ", TimeToString(st.closedBar, TIME_DATE | TIME_MINUTES));

   ChartRedraw(chart_id);
  }

/* ------------------------------------------------------------------ */
/* Fractal swing detector (confirmed bars only → non-repainting)       */
/* ------------------------------------------------------------------ */
void FindSwings(const MqlRates &rates[], const int scanEnd, const int strength,
                int &hiIdx[], double &hiVal[], int &nHi,
                int &loIdx[], double &loVal[], int &nLo)
  {
   nHi = 0;
   nLo = 0;
   ArrayResize(hiIdx, 0);
   ArrayResize(hiVal, 0);
   ArrayResize(loIdx, 0);
   ArrayResize(loVal, 0);

   for(int i = strength; i <= scanEnd - strength; i++)
     {
      bool isHigh = true;
      bool isLow  = true;
      for(int k = 1; k <= strength && (isHigh || isLow); k++)
        {
         if(isHigh && (rates[i].high < rates[i - k].high || rates[i].high < rates[i + k].high))
            isHigh = false;
         if(isLow && (rates[i].low > rates[i - k].low || rates[i].low > rates[i + k].low))
            isLow = false;
        }
      if(isHigh)
        {
         ArrayResize(hiIdx, nHi + 1, ARRAY_RESERVE_CHUNK);
         ArrayResize(hiVal, nHi + 1, ARRAY_RESERVE_CHUNK);
         hiIdx[nHi] = i;
         hiVal[nHi] = rates[i].high;
         nHi++;
        }
      if(isLow)
        {
         ArrayResize(loIdx, nLo + 1, ARRAY_RESERVE_CHUNK);
         ArrayResize(loVal, nLo + 1, ARRAY_RESERVE_CHUNK);
         loIdx[nLo] = i;
         loVal[nLo] = rates[i].low;
         nLo++;
        }
     }
  }

/* ------------------------------------------------------------------ */
/* Cluster swings into support/resistance zones (PURE — v2.07 split)   */
/* Fills supplyOut / demandOut with the side-split, nearest-first,     */
/* size-capped boxes the renderer will draw — the exact boxes the      */
/* trade-plan fallback consumes (v1.08 contract preserved).            */
/* ------------------------------------------------------------------ */
int BuildZones(const MqlRates &rates[], const double atr, const double closeRef,
               const int &hiIdx[], const double &hiVal[], const int nHi,
               const int &loIdx[], const double &loVal[], const int nLo,
               SZoneBox &supplyOut[], SZoneBox &demandOut[])
  {
   int    maxZones = MathMax(1, InpZonesPerSide);
   double tol      = atr * MathMax(0.05, InpZoneATRTolerance);

   /* -------- cluster both swing series -------------------------- */
   SZoneBox hiClusters[];
   SZoneBox loClusters[];
   int nHiC = ClusterAll(hiIdx, hiVal, nHi, rates, tol, hiClusters);
   int nLoC = ClusterAll(loIdx, loVal, nLo, rates, tol, loClusters);

   /* -------- partition strictly by side of price ---------------- */
   SZoneBox supply[];
   SZoneBox demand[];
   int nSup = SideOf(hiClusters, nHiC, closeRef, true,  supply);
   int nDem = SideOf(loClusters, nLoC, closeRef, false, demand);

   /* -------- adaptive widening when one side is empty ----------- */
   // Only the EMPTY side is re-clustered at the wider tolerance; the side
   // that already found zones keeps its base-tolerance clusters.
   for(int pass = 0; pass < 2 && (nSup == 0 || nDem == 0); pass++)
     {
      tol *= ZONE_RESCAN_WIDEN;
      if(nSup == 0)
        {
         ClusterAll(hiIdx, hiVal, nHi, rates, tol, hiClusters);
         nSup = SideOf(hiClusters, ArraySize(hiClusters), closeRef, true, supply);
        }
      if(nDem == 0)
        {
         ClusterAll(loIdx, loVal, nLo, rates, tol, loClusters);
         nDem = SideOf(loClusters, ArraySize(loClusters), closeRef, false, demand);
        }
     }

   /* -------- last resort: mark the dominant raw extreme ---------- */
   if(nSup == 0 && nHi > 0)
     {
      int imax = 0;
      for(int h = 1; h < nHi; h++)
         if(hiVal[h] > hiVal[imax])
            imax = h;
      ArrayResize(supply, 1);
      supply[0].p_low   = hiVal[imax] - atr * ZONE_LASTRESORT_ATR;
      supply[0].p_high  = hiVal[imax];
      supply[0].t_start = rates[hiIdx[imax]].time;
      supply[0].touches = 1;
      nSup = 1;
     }
   if(nDem == 0 && nLo > 0)
     {
      int imin = 0;
      for(int l = 1; l < nLo; l++)
         if(loVal[l] < loVal[imin])
            imin = l;
      ArrayResize(demand, 1);
      demand[0].p_low   = loVal[imin];
      demand[0].p_high  = loVal[imin] + atr * ZONE_LASTRESORT_ATR;
      demand[0].t_start = rates[loIdx[imin]].time;
      demand[0].touches = 1;
      nDem = 1;
     }

   /* -------- nearest-first pick, then hand back (renderer draws) - */
   PickNearest(supply, nSup, closeRef);
   PickNearest(demand, nDem, closeRef);

   int takeS = MathMin(nSup, maxZones);
   ArrayResize(supplyOut, takeS, ARRAY_RESERVE_CHUNK);
   for(int cs = 0; cs < takeS; cs++)
      supplyOut[cs] = supply[cs];
   int takeD = MathMin(nDem, maxZones);
   ArrayResize(demandOut, takeD, ARRAY_RESERVE_CHUNK);
   for(int cd = 0; cd < takeD; cd++)
      demandOut[cd] = demand[cd];

   return(takeS + takeD);
  }

//+------------------------------------------------------------------+
//| Sort one swing series and chain-cluster its values                |
//+------------------------------------------------------------------+
int ClusterAll(const int &idxs[], const double &vals[], const int count,
               const MqlRates &rates[], const double tol, SZoneBox &out[])
  {
   double sv[];
   int    si[];
   ArrayResize(sv, count);
   ArrayResize(si, count);
   for(int a = 0; a < count; a++)
     {
      sv[a] = vals[a];
      si[a] = idxs[a];
     }
   SortByValue(sv, si, count);
   return(ClusterSide(sv, si, count, rates, tol, out));
  }

//+------------------------------------------------------------------+
//| Keep only clusters fully above/below the reference price          |
//| (wantAbove=true -> supply side, false -> demand side)             |
//+------------------------------------------------------------------+
int SideOf(const SZoneBox &src[], const int count, const double refPrice,
           const bool wantAbove, SZoneBox &out[])
  {
   ArrayResize(out, 0);
   for(int i = 0; i < count; i++)
     {
      bool keep = wantAbove ? (src[i].p_low  > refPrice)
                            : (src[i].p_high < refPrice);
      if(!keep)
         continue;
      int at = ArraySize(out);
      ArrayResize(out, at + 1, ARRAY_RESERVE_CHUNK);
      out[at] = src[i];
     }
   return(ArraySize(out));
  }

//+------------------------------------------------------------------+
//| Chain-cluster one side's sorted values                            |
//+------------------------------------------------------------------+
int ClusterSide(const double &vals[], const int &idxs[], const int count,
                const MqlRates &rates[], const double tol, SZoneBox &out[])
  {
   ArrayResize(out, 0);
   if(count <= 0)
      return(0);

   // v1.08 total-width cap: a staircase of swing values each within tolerance
   // of the previous one would chain into ONE zone of unbounded width. Flush
   // early once the cluster spans more than 2.5× the tolerance, even though
   // every individual step is still inside it. (Input is sorted ascending, so
   // curMin never changes after a cluster starts — it IS the original min.)
   const double maxSpan = tol * ZONE_MAX_SPAN_MULT;

   int made = 0;
   double curMin = vals[0];
   double curMax = vals[0];
   int    firstIdx = idxs[0];

   for(int i = 1; i <= count; i++)
     {
      bool flush = (i == count) || (vals[i] - curMax > tol) ||
                   (vals[i] - curMin > maxSpan);
      if(!flush)
        {
         if(vals[i] < curMin) curMin = vals[i];
         if(vals[i] > curMax) curMax = vals[i];
         continue;
        }
      ArrayResize(out, made + 1, ARRAY_RESERVE_CHUNK);
      out[made].p_low   = curMin;
      out[made].p_high  = curMax;
      out[made].t_start = rates[firstIdx].time;
      out[made].touches = CountTouches(vals, count, curMin, curMax);
      firstIdx = (i < count) ? idxs[i] : -1;
      if(i < count)
        {
         curMin = vals[i];
         curMax = vals[i];
        }
      made++;
     }
   return(made);
  }

int CountTouches(const double &vals[], const int count, const double lo, const double hi)
  {
   int n = 0;
   for(int v = 0; v < count; v++)
      if(vals[v] >= lo && vals[v] <= hi)
         n++;
   return(n);
  }

//+------------------------------------------------------------------+
//| Keep the clusters nearest to reference price at the front          |
//+------------------------------------------------------------------+
void PickNearest(SZoneBox &zones[], const int count, const double refPrice)
  {
   if(count <= 1)
      return;
   for(int pass = 0; pass < count - 1; pass++)
     {
      for(int j = 0; j < count - 1 - pass; j++)
        {
         double dJ = MathAbs((zones[j].p_low + zones[j].p_high) * 0.5 - refPrice);
         double dN = MathAbs((zones[j + 1].p_low + zones[j + 1].p_high) * 0.5 - refPrice);
         if(dN < dJ)
           {
            SZoneBox tmp = zones[j];
            zones[j]     = zones[j + 1];
            zones[j + 1] = tmp;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Insertion sort ascending, carrying indices along                    |
//+------------------------------------------------------------------+
void SortByValue(double &vals[], int &idxs[], const int count)
  {
   for(int a = 1; a < count; a++)
     {
      double keyV = vals[a];
      int    keyI = idxs[a];
      int    b    = a - 1;
      while(b >= 0 && vals[b] > keyV)
        {
         vals[b + 1] = vals[b];
         idxs[b + 1] = idxs[b];
         b--;
        }
      vals[b + 1] = keyV;
      idxs[b + 1] = keyI;
     }
  }

//+------------------------------------------------------------------+
//| Blend a color toward the chart background (fake transparency —     |
//| chart objects support no alpha channel). strength 0..1 = share of  |
//| the original color that survives in the tint.                      |
//+------------------------------------------------------------------+
color DimColor(const long chart_id, const color clr, const double strength)
  {
   long bg = 0xFFFFFF;                    // assume white if the query fails
   ChartGetInteger(chart_id, CHART_COLOR_BACKGROUND, 0, bg);
   int c  = (int)clr;
   int cb = (int)bg;
   int r  = (int)MathRound(( c        & 0xFF) * strength + ( cb        & 0xFF) * (1.0 - strength));
   int g  = (int)MathRound(((c >> 8)  & 0xFF) * strength + ((cb >> 8)  & 0xFF) * (1.0 - strength));
   int bl = (int)MathRound(((c >> 16) & 0xFF) * strength + ((cb >> 16) & 0xFF) * (1.0 - strength));
   return((color)((bl << 16) | (g << 8) | r));
  }

/* ------------------------------------------------------------------ */
/* Zone rectangle — thin outline (+ optional dim fill behind candles)  */
/* v2.07: drawn through UpsertRect / UpsertText — an existing box gets */
/* its anchors updated in place instead of delete + recreate.          */
/* ------------------------------------------------------------------ */
void DrawZoneBox(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                 const int lastClosed, const SZoneBox &zone, const double atr,
                 const color clr, const string tag, const string labelText)
  {
   double mid     = (zone.p_low + zone.p_high) * 0.5;
   double half    = (zone.p_high - zone.p_low) * 0.5;
   double minHalf = atr * ZONE_MIN_HALF_ATR;    // keep thin-but-visible band height
   if(half < minHalf)
      half = minHalf;

   datetime t1 = zone.t_start;
   datetime t2 = (datetime)(rates[lastClosed].time + (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars));

   UpsertRect(chart_id, OBJ_PREFIX + "ZONE_" + tag, t1, mid - half, t2, mid + half,
              clr, false, false, STYLE_SOLID);

   /* ---- optional fill (v1.09): dim tint BEHIND candles, outline above --- */
   // Chart objects have no alpha channel, so "transparency" is faked by
   // blending the zone color toward the chart background (DimColor). Default
   // OFF keeps the "thin outline only" spec; the outline itself never changes.
   if(InpZoneFilled)
      UpsertRect(chart_id, OBJ_PREFIX + "ZONE_FILL_" + tag, t1, mid - half, t2, mid + half,
                 DimColor(chart_id, clr, ZONE_FILL_TINT), true, true, STYLE_SOLID);

   if(InpShowLabels)
      UpsertText(chart_id, OBJ_PREFIX + "ZONE_LBL_" + tag, t1, mid + half,
                 labelText, clr, 8, "Arial", ANCHOR_LEFT_LOWER);
  }

/* ------------------------------------------------------------------ */
/* Trend line — two latest swings of prevailing direction              */
/* ------------------------------------------------------------------ */
void DrawTrendLine(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                   const int lastClosed, const int nHi, const int &hiIdx[], const double &hiVal[],
                   const int nLo, const int &loIdx[], const double &loVal[])
  {
   bool dirUp = SlopeUp(rates, lastClosed);

   int p0i = -1;
   int p1i = -1;
   double p0v = 0.0;
   double p1v = 0.0;
   bool have = false;

   if(dirUp && nLo >= 2)
     {
      p0i = loIdx[nLo - 2];
      p0v = loVal[nLo - 2];
      p1i = loIdx[nLo - 1];
      p1v = loVal[nLo - 1];
      have = (p1i > p0i);
     }
   else if(!dirUp && nHi >= 2)
     {
      p0i = hiIdx[nHi - 2];
      p0v = hiVal[nHi - 2];
      p1i = hiIdx[nHi - 1];
      p1v = hiVal[nHi - 1];
      have = (p1i > p0i);
     }
   if(!have)
      return;

   datetime t0 = rates[p0i].time;
   datetime t1 = rates[p1i].time;
   datetime t2 = (datetime)(rates[lastClosed].time +
                            (long)PeriodSeconds(tf) * MathMax(2, InpExtendRightBars) * TREND_EXT_MULT);
   double endPrice = p0v + (t2 - t1) * ((p1v - p0v) / MathMax(1, (double)(t1 - t0)));

   // Clamp the projection: a steep slope between two close-together swings
   // could otherwise shoot the extended line far off scale.
   double avgRange = 0.0;
   for(int br = 1; br <= lastClosed; br++)
      avgRange += (rates[br].high - rates[br].low);
   avgRange /= MathMax(1, lastClosed);
   double maxExt = MathMax(1.0, avgRange) * TREND_MAX_EXT_RANGES;   // ≤ N average bar ranges beyond the last swing
   double delta  = endPrice - p1v;
   if(delta >  maxExt)
      endPrice = p1v + maxExt;
   if(delta < -maxExt)
      endPrice = p1v - maxExt;

   UpsertSegment(chart_id, OBJ_PREFIX + "TREND", t0, p0v, t2, endPrice,
                 COL_TREND, 1, STYLE_SOLID);
  }

//+------------------------------------------------------------------+
//| Cheap SMA slope direction check                                    |
//+------------------------------------------------------------------+
bool SlopeUp(const MqlRates &rates[], const int lastClosed)
  {
   int period = g_slowMaP;
   while(period * 2 > lastClosed && period > 3)
      period /= 2;
   int a = lastClosed - period;          // start of the OLDER window
   if(a < 0)
      return(true);

   double sumNew = 0.0;
   double sumOld = 0.0;
   for(int k = 0; k < period; k++)
     {
      sumNew += rates[lastClosed - k].close;
      sumOld += rates[a - k].close;
     }
   return(sumNew >= sumOld);
  }

/* ------------------------------------------------------------------ */
/* v11.00: OTE (Optimal Trade Entry) pocket — 62%-79% Fibonacci        */
/* retracement of the latest swing leg (the two most recent OPPOSITE   */
/* confirmed swings, whichever pair is more recent overall). Bullish   */
/* leg (low -> high): the pocket sits BELOW the high, at the deep      */
/* retracement a continuation entry waits for. Bearish leg (high ->    */
/* low): mirrored, ABOVE the low.                                      */
/* ------------------------------------------------------------------ */
bool ComputeOTE(const MqlRates &rates[],
               const int &hiIdx[], const double &hiVal[], const int nHi,
               const int &loIdx[], const double &loVal[], const int nLo,
               double &oteLow, double &oteHigh, bool &bullish, datetime &t0)
  {
   oteLow  = 0.0;
   oteHigh = 0.0;
   bullish = false;
   t0      = 0;
   if(nHi < 1 || nLo < 1)
      return(false);

   const int    lastHiIdx = hiIdx[nHi - 1];
   const double lastHiVal = hiVal[nHi - 1];
   const int    lastLoIdx = loIdx[nLo - 1];
   const double lastLoVal = loVal[nLo - 1];

   double legStart, legEnd;
   int    startIdx;
   if(lastHiIdx > lastLoIdx)
     {
      // most recent swing is a HIGH: the leg ran from the prior low up to it
      bullish  = true;
      legStart = lastLoVal;
      legEnd   = lastHiVal;
      startIdx = lastLoIdx;
     }
   else
     {
      // most recent swing is a LOW: the leg ran from the prior high down to it
      bullish  = false;
      legStart = lastHiVal;
      legEnd   = lastLoVal;
      startIdx = lastHiIdx;
     }
   const double legSize = MathAbs(legEnd - legStart);
   if(legSize <= 0.0)
      return(false);

   const double fibLo = MathMin(InpOTEFibLow, InpOTEFibHigh);
   const double fibHi = MathMax(InpOTEFibLow, InpOTEFibHigh);
   if(bullish)
     {
      oteHigh = legEnd - legSize * fibLo;   // 62% back from the high
      oteLow  = legEnd - legSize * fibHi;   // 79% back from the high
     }
   else
     {
      oteLow  = legEnd + legSize * fibLo;   // 62% back up from the low
      oteHigh = legEnd + legSize * fibHi;   // 79% back up from the low
     }
   t0 = rates[startIdx].time;
   return(true);
  }

//+------------------------------------------------------------------+
//| Draw the OTE pocket: a dotted violet outline box over the 62-79%   |
//| retracement zone, labelled with the direction it favors.           |
//+------------------------------------------------------------------+
void DrawOTE(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
            const int lastClosed, const double closeRef, const datetime t0,
            const double oteLow, const double oteHigh, const bool bullish)
  {
   datetime t2 = (datetime)(rates[lastClosed].time +
                            (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars));
   UpsertRect(chart_id, OBJ_PREFIX + "OTE", t0, oteLow, t2, oteHigh,
              COL_OTE, false, false, STYLE_DOT);
   if(InpShowLabels)
      UpsertText(chart_id, OBJ_PREFIX + "OTE_LBL", t0, bullish ? oteHigh : oteLow,
                 "OTE " + (bullish ? "(long)" : "(short)"), COL_OTE, 8, "Arial",
                 bullish ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
  }

/* ------------------------------------------------------------------ */
/* Order block search (last opposite candle before displacement)       */
/* ------------------------------------------------------------------ */
int FindOrderBlock(const MqlRates &rates[], const int lastClosed, const double dThr, const bool bullish)
  {
   int start = lastClosed - MathMin(lastClosed - 3, InpICTLookback);
   if(start < 2)
      start = 2;

   for(int i = lastClosed - 2; i >= start; i--)
     {
      bool obColorOk = bullish ? (rates[i].close < rates[i].open)
                               : (rates[i].close > rates[i].open);
      if(!obColorOk)
         continue;

      double bodyNext = rates[i + 1].close - rates[i + 1].open;
      bool displaced  = bullish ? (bodyNext >= dThr) : (-bodyNext >= dThr);
      if(!displaced)
         continue;

      // impulse must also clear the OB candle's extreme within 2 bars
      bool cleared = bullish
                     ? (rates[i + 1].close > rates[i].high || (i + 2 <= lastClosed && rates[i + 2].high > rates[i].high))
                     : (rates[i + 1].close < rates[i].low  || (i + 2 <= lastClosed && rates[i + 2].low  < rates[i].low));
      if(!cleared)
         continue;

      // mitigation scan — anything trading through the OB kills it
      bool mitigated = false;
      for(int m = i + 2; m <= lastClosed; m++)
        {
         if(bullish && rates[m].low < rates[i].low)
           {
            mitigated = true;
            break;
           }
         if(!bullish && rates[m].high > rates[i].high)
           {
            mitigated = true;
            break;
           }
        }
      if(mitigated)
         continue;

      return(i); // newest unmitigated order block wins
     }
   return(-1);
  }

/* ------------------------------------------------------------------ */
/* v14.00: best-of-N order-block selection (PURE)                      */
/*                                                                      */
/* FindOrderBlockCandidates mirrors FindOrderBlock's scan but collects  */
/* up to maxN unmitigated candidates (newest first) instead of          */
/* returning on the first hit. PickBestOB then scores each candidate    */
/* by its R:R to the nearest external-liquidity target and keeps the    */
/* best — InpPlanCandidates=1 collapses back to the old "newest wins"   */
/* behavior exactly.                                                    */
/* ------------------------------------------------------------------ */
int FindOrderBlockCandidates(const MqlRates &rates[], const int lastClosed, const double dThr,
                             const bool bullish, int &out[], const int maxN)
  {
   ArrayResize(out, 0);
   int start = lastClosed - MathMin(lastClosed - 3, InpICTLookback);
   if(start < 2)
      start = 2;

   for(int i = lastClosed - 2; i >= start && ArraySize(out) < MathMax(1, maxN); i--)
     {
      bool obColorOk = bullish ? (rates[i].close < rates[i].open)
                               : (rates[i].close > rates[i].open);
      if(!obColorOk)
         continue;

      double bodyNext = rates[i + 1].close - rates[i + 1].open;
      bool displaced  = bullish ? (bodyNext >= dThr) : (-bodyNext >= dThr);
      if(!displaced)
         continue;

      bool cleared = bullish
                     ? (rates[i + 1].close > rates[i].high || (i + 2 <= lastClosed && rates[i + 2].high > rates[i].high))
                     : (rates[i + 1].close < rates[i].low  || (i + 2 <= lastClosed && rates[i + 2].low  < rates[i].low));
      if(!cleared)
         continue;

      bool mitigated = false;
      for(int m = i + 2; m <= lastClosed; m++)
        {
         if(bullish && rates[m].low < rates[i].low)   { mitigated = true; break; }
         if(!bullish && rates[m].high > rates[i].high) { mitigated = true; break; }
        }
      if(mitigated)
         continue;

      const int at = ArraySize(out);
      ArrayResize(out, at + 1, ARRAY_RESERVE_CHUNK);
      out[at] = i;
     }
   return(ArraySize(out));
  }

int PickBestOB(const MqlRates &rates[], const int &cands[], const int nCands, const bool bullish,
              const int &hiIdx[], const double &hiVal[], const int nHi,
              const int &loIdx[], const double &loVal[], const int nLo,
              const double atr)
  {
   if(nCands <= 0)
      return(-1);
   int    best      = cands[0];        // newest candidate is the fallback
   double bestScore = -1.0;
   const double stopBuf = atr * PLAN_STOP_BUF_ATR;

   for(int c = 0; c < nCands; c++)
     {
      const int i = cands[c];
      double entry, stop, target;
      bool   ok = false;
      if(bullish)
        {
         entry = rates[i].high;
         stop  = rates[i].low - stopBuf;
         for(int s = nHi - 1; s >= 0; s--)
            if(hiVal[s] > entry) { target = hiVal[s]; ok = true; break; }
        }
      else
        {
         entry = rates[i].low;
         stop  = rates[i].high + stopBuf;
         for(int s = nLo - 1; s >= 0; s--)
            if(loVal[s] < entry) { target = loVal[s]; ok = true; break; }
        }
      if(!ok)
         continue;
      const double risk = MathAbs(entry - stop);
      if(risk <= 0.0)
         continue;
      const double rr = MathAbs(target - entry) / risk;
      if(rr > bestScore)
        {
         bestScore = rr;
         best      = i;
        }
     }
   return(best);
  }

/* ------------------------------------------------------------------ */
/* v12.00: breaker blocks (PURE) — the newest OB candidate (either      */
/* side) that WAS mitigated is checked for a hard opposite-direction    */
/* displacement on the bar that broke it; if found, it is reported as   */
/* a role-flipped breaker instead of just vanishing.                    */
/* ------------------------------------------------------------------ */
bool FindBreakerBlock(const MqlRates &rates[], const int lastClosed, const double dThr,
                      const double atr, bool &wasBull, double &lo, double &hi, datetime &t1)
  {
   wasBull = false;
   lo = 0.0;
   hi = 0.0;
   t1 = 0;
   if(atr <= 0.0)
      return(false);

   int start = lastClosed - MathMin(lastClosed - 3, InpICTLookback);
   if(start < 2)
      start = 2;

   for(int i = lastClosed - 2; i >= start; i--)
     {
      for(int side = 0; side < 2; side++)
        {
         const bool bullish = (side == 0);
         bool obColorOk = bullish ? (rates[i].close < rates[i].open)
                                  : (rates[i].close > rates[i].open);
         if(!obColorOk)
            continue;

         double bodyNext = rates[i + 1].close - rates[i + 1].open;
         bool displaced  = bullish ? (bodyNext >= dThr) : (-bodyNext >= dThr);
         if(!displaced)
            continue;

         bool cleared = bullish
                        ? (rates[i + 1].close > rates[i].high || (i + 2 <= lastClosed && rates[i + 2].high > rates[i].high))
                        : (rates[i + 1].close < rates[i].low  || (i + 2 <= lastClosed && rates[i + 2].low  < rates[i].low));
         if(!cleared)
            continue;

         int mitBar = -1;
         for(int m = i + 2; m <= lastClosed; m++)
           {
            if(bullish && rates[m].low < rates[i].low)    { mitBar = m; break; }
            if(!bullish && rates[m].high > rates[i].high) { mitBar = m; break; }
           }
         if(mitBar < 0)
            continue;                     // still a live, unmitigated OB — not a breaker

         const double mitBody = rates[mitBar].close - rates[mitBar].open;
         const bool   flipped = bullish ? (-mitBody >= BREAKER_DISP_ATR * atr)
                                        : ( mitBody >= BREAKER_DISP_ATR * atr);
         if(!flipped)
            continue;

         wasBull = bullish;
         lo = rates[i].low;
         hi = rates[i].high;
         t1 = rates[i].time;
         return(true);                    // newest breaker wins
        }
     }
   return(false);
  }

/* ------------------------------------------------------------------ */
/* v12.00: structure-shift warning (PURE) — a fresh counter-trend       */
/* CHoCH/MSS while price has not yet reached ENTRY contradicts the      */
/* active plan without invalidating it outright (self-heal still owns  */
/* that call once STOP is actually hit).                                */
/* ------------------------------------------------------------------ */
bool DetectStructureShift(const int lastClosed, const int chocIdx, const int mssIdx,
                          const double closeRef, const double planEntry, const double planTarget)
  {
   const bool isLong = (planTarget > planEntry);
   const int  freshWindow = STRUCT_DASH_CTX * 3;

   if(isLong)
     {
      // waiting for price to pull back down into ENTRY; a fresh bearish
      // low-break (chocIdx) while price is still above ENTRY contradicts it.
      if(chocIdx >= 0 && closeRef > planEntry && lastClosed - chocIdx <= freshWindow)
         return(true);
     }
   else
     {
      // waiting for price to rally up into ENTRY; a fresh bullish
      // high-break (mssIdx) while price is still below ENTRY contradicts it.
      if(mssIdx >= 0 && closeRef < planEntry && lastClosed - mssIdx <= freshWindow)
         return(true);
     }
   return(false);
  }

void DrawOrderBlock(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                    const int lastClosed, const int obIdx, const bool bullish,
                    const double closeRef, const string namePrefix, const string labelText,
                    const datetime tEndOverride, const double colorDim)
  {
   color  clr  = bullish ? COL_OB_BULL : COL_OB_BEAR;
   string tag  = namePrefix + (bullish ? "OB_BULL" : "OB_BEAR");
   if(colorDim < 1.0)
      clr = DimColor(chart_id, clr, colorDim);   // HTF boxes are dimmed

   datetime t1 = rates[obIdx].time;
   datetime t2 = (tEndOverride > 0)
                 ? tEndOverride
                 : (datetime)(rates[lastClosed].time + (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars));

   UpsertRect(chart_id, OBJ_PREFIX + tag, t1, rates[obIdx].low, t2, rates[obIdx].high,
              clr, false, false, STYLE_SOLID);

   if(InpShowLabels)
     {
      double lblLevel = bullish ? rates[obIdx].low : rates[obIdx].high;
      UpsertText(chart_id, OBJ_PREFIX + tag + "_LBL", t1, lblLevel,
                 labelText, clr, 8, "Arial",
                 lblLevel >= closeRef ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }
  }

/* ------------------------------------------------------------------ */
/* Fair value gaps — detection (PURE, v2.07) + rendering (upsert)      */
/* ------------------------------------------------------------------ */
int FindFVGs(const MqlRates &rates[], const int lastClosed, const double dThr,
             double &fvgLo[], double &fvgHi[], datetime &fvgT1[])
  {
   ArrayResize(fvgLo, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(fvgHi, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(fvgT1, 0, ARRAY_RESERVE_CHUNK);

   int start = lastClosed - MathMin(lastClosed - 4, InpICTLookback);
   if(start < 4)
      start = 4;

   for(int i = lastClosed; i >= start && ArraySize(fvgLo) < MathMax(1, InpMaxFVG); i--)
     {
      double gapBottom = 0.0;
      double gapTop    = 0.0;
      bool   isBullGap = false;
      bool   valid     = false;

      // Bullish FVG: candle low above the high two bars earlier
      if(rates[i].low > rates[i - 2].high)
        {
         isBullGap  = true;
         gapBottom  = rates[i - 2].high;
         gapTop     = rates[i].low;
         valid      = (MathAbs(rates[i - 1].close - rates[i - 1].open) >= dThr * FVG_BODY_ATR);
        }
      // Bearish FVG: candle high below the low two bars earlier
      else if(rates[i].high < rates[i - 2].low)
        {
         isBullGap  = false;
         gapBottom  = rates[i].high;
         gapTop     = rates[i - 2].low;
         valid      = (MathAbs(rates[i - 1].close - rates[i - 1].open) >= dThr * FVG_BODY_ATR);
        }
      if(!valid)
         continue;

      // drop when FULLY filled later
      bool filled = false;
      for(int f = i + 1; f <= lastClosed; f++)
        {
         if(isBullGap && rates[f].low <= gapBottom) { filled = true; break; }
         if(!isBullGap && rates[f].high >= gapTop)  { filled = true; break; }
        }
      if(filled)
         continue;

      int at = ArraySize(fvgLo);                 // collected for the renderer / export
      ArrayResize(fvgLo, at + 1, ARRAY_RESERVE_CHUNK);
      ArrayResize(fvgHi, at + 1, ARRAY_RESERVE_CHUNK);
      ArrayResize(fvgT1, at + 1, ARRAY_RESERVE_CHUNK);
      fvgLo[at] = gapBottom;
      fvgHi[at] = gapTop;
      fvgT1[at] = rates[i - 2].time;
     }
   return(ArraySize(fvgLo));
  }

//+------------------------------------------------------------------+
//| Draw the detected gaps (main chart or HTF overlay — prefix decides)|
//+------------------------------------------------------------------+
void RenderFVGs(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                const int lastClosed, const double &fvgLo[], const double &fvgHi[],
                const datetime &fvgT1[], const int nFvg, const double closeRef,
                const string namePrefix, const string labelPrefix,
                const datetime tEndOverride, const double colorDim)
  {
   datetime tEnd = (tEndOverride > 0)
                   ? tEndOverride
                   : (datetime)(rates[lastClosed].time + (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars));
   color clr = COL_FVG;
   if(colorDim < 1.0)
      clr = DimColor(chart_id, clr, colorDim);   // HTF gaps are dimmed

   for(int i = 0; i < nFvg; i++)
     {
      UpsertRect(chart_id, OBJ_PREFIX + namePrefix + "FVG_" + IntegerToString(i),
                 fvgT1[i], fvgLo[i], tEnd, fvgHi[i], clr, false, false, STYLE_DASH);

      if(InpShowLabels)
         UpsertText(chart_id, OBJ_PREFIX + namePrefix + "FVG_LBL_" + IntegerToString(i),
                    fvgT1[i], fvgHi[i],
                    labelPrefix + "FVG " + IntegerToString(i + 1),
                    clr, 8, "Arial",
                    fvgHi[i] >= closeRef ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }
  }

/* ------------------------------------------------------------------ */
/* Structure breaks — detection (PURE, v2.07): reports the newest      */
/* CHoCH (tight magenta) and MSS/BOS (wide blue) breaks; the renderer  */
/* draws the dashes from the state struct.                             */
/* ------------------------------------------------------------------ */
int FindStructureBreaks(const MqlRates &rates[], const int lastClosed,
                        const int &hiIdx[], const double &hiVal[], const int nHi,
                        const int &loIdx[], const double &loVal[], const int nLo,
                        int &chocIdx, double &chocLvl, int &mssIdx, double &mssLvl)
  {
   chocIdx = -1;
   chocLvl = 0.0;
   mssIdx  = -1;
   mssLvl  = 0.0;
   int drawn = 0;
   int loBreak = -1;
   double loLevel = 0.0;
   bool haveLoBreak = LatestBreak(rates, lastClosed, loIdx, loVal, nLo, false, loBreak, loLevel);

   int hiBreak = -1;
   double hiLevel = 0.0;
   bool haveHiBreak = LatestBreak(rates, lastClosed, hiIdx, hiVal, nHi, true, hiBreak, hiLevel);

   if(haveLoBreak && haveHiBreak && loBreak == hiBreak)
      haveLoBreak = false; // avoid stacking two dashes on the identical bar

   if(haveLoBreak)
     {
      // STYLE_DOT keeps CHoCH visually distinct from the wide MSS/BOS dashes
      chocIdx = loBreak;
      chocLvl = loLevel;
      drawn++;
     }

   if(haveHiBreak)
     {
      mssIdx = hiBreak;
      mssLvl = hiLevel;
      drawn++;
     }

   return(drawn);
  }

//+------------------------------------------------------------------+
//| Most recent confirmed swing whose level a CLOSE broke through      |
//+------------------------------------------------------------------+
bool LatestBreak(const MqlRates &rates[], const int lastClosed,
                 const int &swIdx[], const double &swVal[], const int count,
                 const bool highs, int &breakIdx, double &level)
  {
   breakIdx = -1;
   level    = 0.0;

   for(int s = count - 1; s >= 0; s--)
     {
      int conf = swIdx[s];
      for(int j = conf + 1; j <= lastClosed; j++)
        {
         bool broken = highs
                       ? (rates[j].close > swVal[s])
                       : (rates[j].close < swVal[s]);
         if(broken)
           {
            breakIdx = j;
            level    = swVal[s];
            return(true);
           }
        }
     }
   return(false);
  }

void DrawBreakDash(const long chart_id, const MqlRates &rates[], const int lastClosed,
                   const int brkIdx, const double level,
                   const color clr, const ENUM_LINE_STYLE style, const int width, const string label)
  {
   int ctx = STRUCT_DASH_CTX;
   int x0 = MathMax(1, brkIdx - ctx);
   // rates[] holds indices 0..lastClosed+1 (lastClosed+1 = forming bar).
   // Indexing beyond lastClosed+1 is a critical 'array out of range' error
   // that unloads the EA — clamp the dash end to the forming bar.
   int x1 = MathMin(lastClosed + 1, brkIdx + ctx);
   if(x1 > lastClosed + 1)
      x1 = lastClosed + 1;
   if(x1 <= x0)
      return;

   datetime t0 = rates[x0].time;
   datetime t1 = rates[x1].time;

   UpsertSegment(chart_id, OBJ_PREFIX + label, t0, level, t1, level, clr, width, style);

   if(InpShowLabels)
      UpsertText(chart_id, OBJ_PREFIX + label + "_LBL", t1, level, label,
                 clr, 8, "Arial Bold", ANCHOR_LEFT_UPPER);
  }

/* ------------------------------------------------------------------ */
/* Liquidity pools — equal highs (BSL) / equal lows (SSL)              */
/* ------------------------------------------------------------------ */
void DrawPoolLine(const long chart_id, const datetime tStart, const datetime tEnd,
                  const double level, const double closeRef,
                  const string tag, const string labelText)
  {
   UpsertSegment(chart_id, OBJ_PREFIX + tag, tStart, level, tEnd, level,
                 COL_LIQ, 1, STYLE_DASH);

   if(InpShowLabels)
      UpsertText(chart_id, OBJ_PREFIX + tag + "_LBL", tStart, level, labelText,
                 COL_LIQ, 8, "Arial",
                 level >= closeRef ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
  }

/* ------------------------------------------------------------------ */
/* Liquidity pool detection (PURE, v2.07) — equal highs (BSL) /        */
/* equal lows (SSL); renderer draws from the state arrays.             */
/* ------------------------------------------------------------------ */
int FindLiquidity(const MqlRates &rates[], const int lastClosed,
                  const double atr, const double closeRef,
                  const int &hiIdx[], const double &hiVal[], const int nHi,
                  const int &loIdx[], const double &loVal[], const int nLo,
                  double &bslOut[], datetime &bslTOut[],
                  double &sslOut[], datetime &sslTOut[])
  {
   ArrayResize(bslOut, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(bslTOut, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(sslOut, 0, ARRAY_RESERVE_CHUNK);
   ArrayResize(sslTOut, 0, ARRAY_RESERVE_CHUNK);
   if(atr <= 0.0 || (nHi + nLo) < 2)
      return(0);

   // A pool is a cluster of at least two swings inside a NARROW tolerance
   // (equal highs / equal lows). Clusters with one touch are just swing marks.
   const double tol     = atr * MathMax(0.05, InpLiqTolATR);
   const int    maxEach = MathMax(1, InpMaxLiqPerSide);
   int made = 0;

   /* ---- buy side: equal highs ABOVE price (resting buy stops) ---- */
   SZoneBox hiPools[];
   int nHiP = ClusterAll(hiIdx, hiVal, nHi, rates, tol, hiPools);
   SZoneBox bsl[];
   int nBsl = SideOf(hiPools, nHiP, closeRef, true, bsl);
   int keptB = 0;
   for(int b = 0; b < nBsl; b++)
     {
      if(bsl[b].touches < 2)
         continue;
      bsl[keptB] = bsl[b];
      keptB++;
     }
   PickNearest(bsl, keptB, closeRef);
   int keepB = MathMin(keptB, maxEach);
   for(int b = 0; b < keepB; b++)
     {
      int at = ArraySize(bslOut);
      ArrayResize(bslOut, at + 1, ARRAY_RESERVE_CHUNK);
      ArrayResize(bslTOut, at + 1, ARRAY_RESERVE_CHUNK);
      bslOut[at] = bsl[b].p_high;
      bslTOut[at] = bsl[b].t_start;
      made++;
     }

   /* ---- sell side: equal lows BELOW price (resting sell stops) ---- */
   SZoneBox loPools[];
   int nLoP = ClusterAll(loIdx, loVal, nLo, rates, tol, loPools);
   SZoneBox ssl[];
   int nSsl = SideOf(loPools, nLoP, closeRef, false, ssl);
   int keptS = 0;
   for(int s = 0; s < nSsl; s++)
     {
      if(ssl[s].touches < 2)
         continue;
      ssl[keptS] = ssl[s];
      keptS++;
     }
   PickNearest(ssl, keptS, closeRef);
   int keepS = MathMin(keptS, maxEach);
   for(int s = 0; s < keepS; s++)
     {
      int at = ArraySize(sslOut);
      ArrayResize(sslOut, at + 1, ARRAY_RESERVE_CHUNK);
      ArrayResize(sslTOut, at + 1, ARRAY_RESERVE_CHUNK);
      sslOut[at] = ssl[s].p_low;
      sslTOut[at] = ssl[s].t_start;
      made++;
     }

   return(made);
  }

/* ------------------------------------------------------------------ */
/* Premium / discount — detection (PURE, v2.07) + rendering (upsert)   */
/* ------------------------------------------------------------------ */
void ComputeEQ(const MqlRates &rates[], const int lastClosed,
               const int &hiIdx[], const double &hiVal[], const int nHi,
               const int &loIdx[], const double &loVal[], const int nLo,
               double &eq, double &rangeHi, double &rangeLo, datetime &eqT0)
  {
   eq      = 0.0;
   rangeHi = 0.0;
   rangeLo = 0.0;
   eqT0    = 0;
   if(nHi < 1 || nLo < 1)
      return;

   int hiMax = 0;
   for(int h = 1; h < nHi; h++)
      if(hiVal[h] > hiVal[hiMax])
         hiMax = h;
   int loMin = 0;
   for(int l = 1; l < nLo; l++)
      if(loVal[l] < loVal[loMin])
         loMin = l;

   rangeHi = hiVal[hiMax];
   rangeLo = loVal[loMin];
   if(rangeHi <= rangeLo)
      return;

   eq   = (rangeHi + rangeLo) * 0.5;
   eqT0 = rates[MathMin(hiIdx[hiMax], loIdx[loMin])].time;   // older extreme
  }

void RenderPremiumDiscount(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                           const int lastClosed, const double closeRef,
                           const double eq, const double rangeHi, const double rangeLo,
                           const datetime eqT0)
  {
   datetime tEnd = (datetime)(rates[lastClosed].time +
                              (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars) * EQ_EXT_MULT);

   UpsertSegment(chart_id, OBJ_PREFIX + "PD_EQ", eqT0, eq, tEnd, eq, COL_EQ, 1, STYLE_DOT);

   if(InpShowLabels)
     {
      // element-wise assignment (MQL5 initialization lists want constants)
      string tags[3];
      string labels[3];
      double levels[3];
      tags[0]   = "PD_EQ_LBL";
      tags[1]   = "PD_PREM_LBL";
      tags[2]   = "PD_DISC_LBL";
      labels[0] = "EQ 50%";
      labels[1] = "premium";
      labels[2] = "discount";
      levels[0] = eq;
      levels[1] = (rangeHi + eq) * 0.5;
      levels[2] = (rangeLo + eq) * 0.5;
      for(int i = 0; i < 3; i++)
         UpsertText(chart_id, OBJ_PREFIX + tags[i], tEnd, levels[i], labels[i],
                    COL_EQ, 8, "Arial",
                    levels[i] >= closeRef ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
     }
  }

/* ------------------------------------------------------------------ */
/* Killzones — dim session fills BEHIND the candles (opt-in)           */
/* ------------------------------------------------------------------ */
void DrawKillzone(const long chart_id, const datetime dayStart, const int startHour,
                  const int lenHours, const color clr, const string sessionName,
                  const int dayOffset, const bool withLabel, const double top, const double lblY)
  {
   datetime t1 = (datetime)((long)dayStart + (long)MathMax(0, startHour) * 3600);
   datetime t2 = (datetime)((long)t1 + (long)MathMax(1, lenHours) * 3600);

   string oname = OBJ_PREFIX + "KZ_" + sessionName + "_" + IntegerToString(dayOffset);
   UpsertRect(chart_id, oname, t1, 0.0, t2, top,
              DimColor(chart_id, clr, KZ_TINT_STRENGTH), true, true, STYLE_SOLID);

   if(withLabel && InpShowLabels)
      UpsertText(chart_id, OBJ_PREFIX + "KZ_LBL_" + sessionName, t1, lblY,
                 sessionName, clr, 8, "Arial", ANCHOR_LEFT_LOWER);
  }

void DrawKillzones(const long chart_id, const string symbol, const MqlRates &rates[],
                   const int lastClosed, const double closeRef, const double atr)
  {
   const int days = MathMax(1, InpKZDays);

   // data-driven anchors: ceiling far above any wick, labels just above price
   double top  = closeRef * 2.0;
   double lblY = closeRef + atr * 2.0;
   if(atr > 0.0)
     {
      double hi = rates[lastClosed].high;
      for(int b = MathMax(1, lastClosed - KZ_LOOKBACK_BARS); b <= lastClosed; b++)
         if(rates[b].high > hi)
            hi = rates[b].high;
      top  = hi + atr * KZ_TOP_ATR;
      lblY = hi + atr * KZ_LBL_ATR;
     }

   for(int d = 0; d < days; d++)
     {
      datetime dayStart = iTime(symbol, PERIOD_D1, d);
      if(dayStart <= 0)
         continue;
      DrawKillzone(chart_id, dayStart, InpKZAsiaStart,    MathMax(1, InpKZLengthHours) * 2,
                   COL_KZ_ASIA, "ASIA", d, (d == 0), top, lblY);
      DrawKillzone(chart_id, dayStart, InpKZLondonStart,  MathMax(1, InpKZLengthHours),
                   COL_KZ_LON, "LONDON", d, (d == 0), top, lblY);
      DrawKillzone(chart_id, dayStart, InpKZNewYorkStart, MathMax(1, InpKZLengthHours),
                   COL_KZ_NY, "NY", d, (d == 0), top, lblY);
     }
  }

/* ------------------------------------------------------------------ */
/* v11.00: daily / weekly open reference lines                         */
/* ------------------------------------------------------------------ */
void ComputeDayWeekOpens(const string symbol, double &dOpen, datetime &dOpenT,
                         double &wOpen, datetime &wOpenT)
  {
   dOpen  = 0.0;
   dOpenT = 0;
   wOpen  = 0.0;
   wOpenT = 0;
   dOpenT = iTime(symbol, PERIOD_D1, 0);
   if(dOpenT > 0)
      dOpen = iOpen(symbol, PERIOD_D1, 0);
   wOpenT = iTime(symbol, PERIOD_W1, 0);
   if(wOpenT > 0)
      wOpen = iOpen(symbol, PERIOD_W1, 0);
  }

void RenderDayWeekOpens(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                        const int lastClosed, const double closeRef,
                        const double dOpen, const datetime dOpenT,
                        const double wOpen, const datetime wOpenT)
  {
   datetime tEnd = (datetime)(rates[lastClosed].time +
                              (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars));
   const int dg = (int)SymbolInfoInteger(ChartSymbol(chart_id), SYMBOL_DIGITS);
   if(dOpen > 0.0 && dOpenT > 0)
     {
      UpsertSegment(chart_id, OBJ_PREFIX + "D_OPEN", dOpenT, dOpen, tEnd, dOpen,
                    COL_DOPEN, 1, STYLE_DOT);
      if(InpShowLabels)
         UpsertText(chart_id, OBJ_PREFIX + "D_OPEN_LBL", dOpenT, dOpen,
                    "D-OPEN " + DoubleToString(dOpen, dg), COL_DOPEN, 8, "Arial",
                    dOpen >= closeRef ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }
   if(wOpen > 0.0 && wOpenT > 0)
     {
      UpsertSegment(chart_id, OBJ_PREFIX + "W_OPEN", wOpenT, wOpen, tEnd, wOpen,
                    COL_DOPEN, 1, STYLE_DASHDOT);
      if(InpShowLabels)
         UpsertText(chart_id, OBJ_PREFIX + "W_OPEN_LBL", wOpenT, wOpen,
                    "W-OPEN " + DoubleToString(wOpen, dg), COL_DOPEN, 8, "Arial",
                    wOpen >= closeRef ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }
  }

/* ------------------------------------------------------------------ */
/* HTF overlay — higher-timeframe order blocks & FVGs, dimmed          */
/* ------------------------------------------------------------------ */
int DrawHTFOverlay(const long chart_id, const string symbol, const ENUM_TIMEFRAMES tf,
                   const MqlRates &rates[], const int lastClosed, const double closeRef)
  {
   if(InpHTF <= tf)                       // same or lower TF selected -> nothing to add
      return(0);

   double htfAtr = GetAtr(symbol, InpHTF);
   const double dThr = htfAtr * InpDisplacementATR;
   if(dThr <= 0.0)
      return(0);

   MqlRates htfRates[];
   int total = CopyRates(symbol, InpHTF, 0, HTF_NEED_BARS, htfRates);
   if(total < HTF_MIN_BARS)
      return(0);
   const int htfLast = total - 2;
   if(htfLast < 10)
      return(0);

   // extend boxes to "now" on the CHART's timeframe so they reach the right edge
   datetime tEnd = (datetime)(rates[lastClosed].time +
                              (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars));
   string htfName = StringSubstr(EnumToString(InpHTF), 7);   // "PERIOD_H4" -> "H4"

   int drawn = 0;

   if(InpDrawOB)
     {
      int bullH = FindOrderBlock(htfRates, htfLast, dThr, true);
      int bearH = FindOrderBlock(htfRates, htfLast, dThr, false);
      if(bullH >= 0)
        {
         DrawOrderBlock(chart_id, htfRates, tf, htfLast, bullH, true, closeRef,
                        "HTF_", htfName + " bullish OB", tEnd, HTF_DIM_STRENGTH);
         drawn++;
        }
      if(bearH >= 0)
        {
         DrawOrderBlock(chart_id, htfRates, tf, htfLast, bearH, false, closeRef,
                        "HTF_", htfName + " bearish OB", tEnd, HTF_DIM_STRENGTH);
         drawn++;
        }
     }
   if(!InpDrawFVG)
      return(drawn);
   double   htfFvgLo[];
   double   htfFvgHi[];
   datetime htfFvgT1[];
   int nHtfFvg = FindFVGs(htfRates, htfLast, dThr, htfFvgLo, htfFvgHi, htfFvgT1);
   RenderFVGs(chart_id, htfRates, tf, htfLast, htfFvgLo, htfFvgHi, htfFvgT1, nHtfFvg,
              closeRef, "HTF_", htfName + " ", tEnd, HTF_DIM_STRENGTH);
   drawn += nHtfFvg;
   return(drawn);
  }

/* ------------------------------------------------------------------ */
/* JSON export — one state file per symbol/timeframe for dashboards    */
/* v2.07: reads the SMarketState struct directly (pure calculation     */
/* output), and serializes through the embedded CJsonWriter.           */
/* ------------------------------------------------------------------ */
string JNum(const double v, const int digits)
  {
   if(v == 0.0)
      return("null");
   return(DoubleToString(v, digits));
  }

/* ================================================================== */
/*  CJsonWriter — embedded zero-dependency JSON builder (v2.07)        */
/*                                                                     */
/*  Replaces the hand-concatenated payload strings. Every string goes  */
/*  through the escape helper, every number is formatted with explicit */
/*  digits, and Build() strips the trailing comma and closes the       */
/*  object exactly once. JAson.mqh was deliberately NOT pulled in: it  */
/*  would turn this single-file EA into a two-file install with an     */
/*  Include-folder dependency — this writer gives the same guarantees  */
/*  and keeps the kit self-contained. The byte-exact                   */
/*  StringToCharArray(-1) conversion at push time stays (v2.02 fix).   */
/* ================================================================== */
class CJsonWriter
  {
private:
   string m_buf;
public:
   void CJsonWriter() { m_buf = "{"; }
   // escaped string field
   void Add(const string key, const string val)
     {
      m_buf += "\"" + BridgeJsonEscape(key) + "\":\"" + BridgeJsonEscape(val) + "\",";
     }
   // pre-serialized raw JSON fragment (array / nested object / null)
   void AddRaw(const string key, const string rawJson)
     {
      m_buf += "\"" + BridgeJsonEscape(key) + "\":" + rawJson + ",";
     }
   // number field with explicit digits (always plain decimal — valid JSON)
   void AddNum(const string key, const double val, const int digits)
     {
      m_buf += "\"" + BridgeJsonEscape(key) + "\":" + DoubleToString(val, digits) + ",";
     }
   // strip trailing comma, close the object, hand the document out
   string Build()
     {
      int len = StringLen(m_buf);
      if(len > 1 && StringGetCharacter(m_buf, len - 1) == ',')
         m_buf = StringSubstr(m_buf, 0, len - 1);
      m_buf += "}";
      string out = m_buf;
      m_buf = "{";                        // reusable for the next payload
      return(out);
     }
  };

//+------------------------------------------------------------------+
//| Small array builders (schema-compatible with the v1 export)        |
//+------------------------------------------------------------------+
string JsonZoneArray(const SZoneBox &zones[], const int digits)
  {
   string out = "[";
   for(int i = 0; i < ArraySize(zones); i++)
     {
      if(i > 0)
         out += ",";
      out += "{\"low\":" + DoubleToString(zones[i].p_low, digits) +
             ",\"high\":" + DoubleToString(zones[i].p_high, digits) + "}";
     }
   return(out + "]");
  }

string JsonBarBox(const MqlRates &bar, const int digits)
  {
   return("{\"low\":" + DoubleToString(bar.low, digits) +
          ",\"high\":" + DoubleToString(bar.high, digits) + "}");
  }

string JsonNumArray(const double &vals[], const int digits)
  {
   string out = "[";
   for(int i = 0; i < ArraySize(vals); i++)
     {
      if(i > 0)
         out += ",";
      out += DoubleToString(vals[i], digits);
     }
   return(out + "]");
  }

void WriteChartJSON(const SMarketState &st, const MqlRates &rates[])
  {
   const int    digits = (int)SymbolInfoInteger(st.symbol, SYMBOL_DIGITS);
   const string tfName = StringSubstr(EnumToString(st.tf), 7);   // "PERIOD_H1" -> "H1"

   CJsonWriter w;
   w.Add("symbol", st.symbol);
   w.Add("tf", tfName);
   w.Add("bar", TimeToString(st.closedBar, TIME_DATE | TIME_MINUTES));
   w.AddNum("close", st.closeRef, digits);
   w.AddNum("atr", st.atr, digits + 2);
   w.AddRaw("supply", JsonZoneArray(st.supply, digits));
   w.AddRaw("demand", JsonZoneArray(st.demand, digits));

   string ob = "{\"bull\":";
   ob += (st.bullIdx >= 0) ? JsonBarBox(rates[st.bullIdx], digits) : "null";
   ob += ",\"bear\":";
   ob += (st.bearIdx >= 0) ? JsonBarBox(rates[st.bearIdx], digits) : "null";
   ob += "}";
   w.AddRaw("orderBlocks", ob);

   string fvg = "[";
   for(int f = 0; f < st.fvgCount; f++)
     {
      if(f > 0)
         fvg += ",";
      fvg += "{\"low\":" + DoubleToString(st.fvgLo[f], digits) +
             ",\"high\":" + DoubleToString(st.fvgHi[f], digits) + "}";
     }
   fvg += "]";
   w.AddRaw("fvgs", fvg);

   string liq = "{\"bsl\":" + JsonNumArray(st.bslLv, digits) +
                ",\"ssl\":" + JsonNumArray(st.sslLv, digits) + "}";
   w.AddRaw("liquidity", liq);

   w.AddRaw("equilibrium", JNum(st.eq, digits));

   string plan = "null";
   if(st.planOk && st.planEntry != 0.0)
     {
      double risk = MathAbs(st.planEntry - st.planStop);
      double rr   = (risk > 0.0) ? MathAbs(st.planTarget - st.planEntry) / risk : 0.0;
      CJsonWriter p;
      p.Add("side", (st.planTarget > st.planEntry) ? "long" : "short");
      p.AddNum("entry", st.planEntry, digits);
      p.AddNum("stop", st.planStop, digits);
      p.AddNum("target", st.planTarget, digits);
      p.AddNum("rr", rr, 2);
      plan = p.Build();
     }
   w.AddRaw("plan", plan);

   // v11.00 additive fields
   string ote = "null";
   if(st.oteOk)
     {
      CJsonWriter o;
      o.AddNum("low", st.oteLow, digits);
      o.AddNum("high", st.oteHigh, digits);
      o.AddRaw("bullish", st.oteBullish ? "true" : "false");
      ote = o.Build();
     }
   w.AddRaw("ote", ote);
   w.AddRaw("dOpen", JNum(st.dOpen, digits));
   w.AddRaw("wOpen", JNum(st.wOpen, digits));

   // v12.00 / v14.00 additive fields
   string breaker = "null";
   if(st.breakerOk)
     {
      CJsonWriter b;
      b.AddNum("low", st.breakerLo, digits);
      b.AddNum("high", st.breakerHi, digits);
      b.AddRaw("wasBullish", st.breakerWasBull ? "true" : "false");
      breaker = b.Build();
     }
   w.AddRaw("breaker", breaker);
   w.AddRaw("planShiftWarn", st.planShiftWarn ? "true" : "false");
   if(st.volRegime != "")
     {
      w.Add("volRegime", st.volRegime);
      w.AddNum("volRatio", st.volRatio, 2);
      if(st.suggestedRiskPct > 0.0)
         w.AddNum("suggestedRiskPct", st.suggestedRiskPct, 2);
     }

   string json = w.Build();

   string fname = "PAICT_" + st.symbol + "_" + tfName + ".json";
   int fh = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE)
     {
      Print("PAICT: cannot write ", fname, " (err ", GetLastError(), ")");
      return;
     }
   FileWriteString(fh, json);
   FileClose(fh);
  }

/* ------------------------------------------------------------------ */
/* Trade plan — selection (PURE, v2.07) + rendering (upsert).          */
/* Rendered look unchanged: filled ENTRY (gold) / STOP (red) /         */
/* TARGET (green) zone BANDS (identical rectangles, only the color     */
/* differs), the level lines, priced labels and the R:R text.          */
/*                                                                     */
/* ICT-first: entry at the most recent unmitigated order block's       */
/* proximal edge (OB high for a long, OB low for a short), stop at     */
/* the OB's far edge (+PLAN_STOP_BUF_ATR buffer), target at the        */
/* nearest confirmed swing extreme beyond that entry (external         */
/* liquidity). Falls back to a zone-to-zone price-action plan built    */
/* from the EXACT supply/demand boxes the state carries (computed      */
/* once in BuildZones — v1.08 removed the private re-cluster here):    */
/* entry at the proximal edge of the nearest zone on the trend side,   */
/* stop at the zone's far edge, target at the opposite zone's near     */
/* edge.                                                                */
/* ------------------------------------------------------------------ */
bool ComputeTradePlan(const MqlRates &rates[], const int lastClosed,
                      const double closeRef, const double atr,
                      const int &hiIdx[], const double &hiVal[], const int nHi,
                      const int &loIdx[], const double &loVal[], const int nLo,
                      const int bullIdx, const int bearIdx,
                      const SZoneBox &drawnSupply[], const int nSupDrawn,
                      const SZoneBox &drawnDemand[], const int nDemDrawn,
                      double &outEntry, double &outStop, double &outTarget)
  {
   const double stopBuf = atr * PLAN_STOP_BUF_ATR;

   /* ---- 1) ICT plan: order block -> external liquidity ---------- */
   if(bullIdx >= 0)
     {
      double entry  = rates[bullIdx].high;             // proximal edge for a long
      double stop   = rates[bullIdx].low - stopBuf;    // far edge of the OB
      double target = 0.0;
      bool   ok     = false;
      for(int s = nHi - 1; s >= 0; s--)
        {
         if(hiVal[s] > entry)
           {
            target = hiVal[s];
            ok     = true;
            break;
           }
        }
      if(ok)
        {
         outEntry  = entry;
         outStop   = stop;
         outTarget = target;
         return(true);
        }
     }
   // v15.02: a separate `if`, not `else if` — when BOTH an unmitigated
   // bullish and bearish OB exist but the bullish one has no valid target
   // beyond it, the bearish candidate must still get evaluated instead of
   // being skipped straight to the price-action fallback.
   if(bearIdx >= 0)
     {
      double entry  = rates[bearIdx].low;              // proximal edge for a short
      double stop   = rates[bearIdx].high + stopBuf;   // far edge of the OB
      double target = 0.0;
      bool   ok     = false;
      for(int s = nLo - 1; s >= 0; s--)
        {
         if(loVal[s] < entry)
           {
            target = loVal[s];
            ok     = true;
            break;
           }
        }
      if(ok)
        {
         outEntry  = entry;
         outStop   = stop;
         outTarget = target;
         return(true);
        }
     }

   /* ---- 2) Price-action fallback: DETECTED zone edge -> opposite zone -- */
   // v1.08: the boxes arrive from BuildZones (already side-filtered,
   // nearest-first) — the very rectangles the renderer draws. No re-clustering,
   // so plan levels can never reference a zone that is not visible on screen.
   if(nSupDrawn < 1 && nDemDrawn < 1)
      return(false);

   bool   dirUp = SlopeUp(rates, lastClosed);
   int    eSide = -1;                          // entry zone index
   int    tSide = -1;                          // target zone index
   double bestD = DBL_MAX;

   if(dirUp)
     {
      // long: enter at the nearest demand zone below, target the nearest supply zone above
      for(int i = 0; i < nDemDrawn; i++)
        {
         double midS = (drawnDemand[i].p_low + drawnDemand[i].p_high) * 0.5;
         if(midS < closeRef && closeRef - midS < bestD)
           {
            bestD = closeRef - midS;
            eSide = i;
           }
        }
      bestD = DBL_MAX;
      for(int j = 0; j < nSupDrawn; j++)
        {
         double midR = (drawnSupply[j].p_low + drawnSupply[j].p_high) * 0.5;
         if(midR > closeRef && midR - closeRef < bestD)
           {
            bestD = midR - closeRef;
            tSide = j;
           }
        }
      if(eSide >= 0 && tSide >= 0)
        {
         outEntry  = drawnDemand[eSide].p_high;             // proximal demand edge
         outStop   = drawnDemand[eSide].p_low - stopBuf;    // far demand edge
         outTarget = drawnSupply[tSide].p_low;              // proximal supply edge
         return(true);
        }
     }
   else
     {
      // short: enter at the nearest supply zone above, target the nearest demand zone below
      for(int i = 0; i < nSupDrawn; i++)
        {
         double midR = (drawnSupply[i].p_low + drawnSupply[i].p_high) * 0.5;
         if(midR > closeRef && midR - closeRef < bestD)
           {
            bestD = midR - closeRef;
            eSide = i;
           }
        }
      bestD = DBL_MAX;
      for(int j = 0; j < nDemDrawn; j++)
        {
         double midS = (drawnDemand[j].p_low + drawnDemand[j].p_high) * 0.5;
         if(midS < closeRef && closeRef - midS < bestD)
           {
            bestD = closeRef - midS;
            tSide = j;
           }
        }
      if(eSide >= 0 && tSide >= 0)
        {
         outEntry  = drawnSupply[eSide].p_low;              // proximal supply edge
         outStop   = drawnSupply[eSide].p_high + stopBuf;   // far supply edge
         outTarget = drawnDemand[tSide].p_high;             // proximal demand edge
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Draw the plan from the state: three bands + lines + R:R (upsert)   |
//+------------------------------------------------------------------+
void RenderTradePlan(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                     const int lastClosed, const double closeRef,
                     const double entry, const double stop, const double target,
                     const bool washout, const bool shiftWarn)
  {
   DrawPlanLine(chart_id, rates, tf, lastClosed, entry,  closeRef, COL_ENTRY,  "ENTRY",  "ENTRY",  washout);
   DrawPlanLine(chart_id, rates, tf, lastClosed, target, closeRef, COL_TARGET, "TARGET", "TARGET", washout);
   DrawPlanLine(chart_id, rates, tf, lastClosed, stop,   closeRef, COL_STOP,   "STOP",   "STOP",   washout);
   DrawPlanRR(chart_id, rates, tf, lastClosed, entry, target, stop, closeRef);

   // v12.00: a fresh counter-trend CHoCH/MSS before ENTRY was reached —
   // the plan stays drawn (still a human call) but gets flagged.
   if(shiftWarn && InpShowLabels)
     {
      const datetime t1 = (datetime)(rates[lastClosed].time +
                                     (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars));
      UpsertText(chart_id, OBJ_PREFIX + "PLAN_SHIFT", t1, entry,
                 "STRUCTURE SHIFT", COL_CHOCH, 8, "Arial Bold",
                 entry >= closeRef ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
     }
  }

//+------------------------------------------------------------------+
//| v12.00: draw a breaker block — the same rectangle style as a live   |
//| order block, but dashed and in the flipped-role color so it reads  |
//| distinctly ("this used to be support, it's resistance now").       |
//+------------------------------------------------------------------+
void DrawBreakerBlock(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                      const int lastClosed, const double closeRef,
                      const datetime t1, const double lo, const double hi, const bool wasBull)
  {
   const datetime t2 = (datetime)(rates[lastClosed].time +
                                  (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars));
   UpsertRect(chart_id, OBJ_PREFIX + "BREAKER", t1, lo, t2, hi,
              COL_BREAKER, false, false, STYLE_DASH);
   if(InpShowLabels)
      UpsertText(chart_id, OBJ_PREFIX + "BREAKER_LBL", t1, wasBull ? lo : hi,
                 wasBull ? "breaker (was bull OB)" : "breaker (was bear OB)",
                 COL_BREAKER, 8, "Arial",
                 (wasBull ? lo : hi) >= closeRef ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
  }

//+------------------------------------------------------------------+
//| Small R:R text between ENTRY and TARGET at the plan's right edge  |
//+------------------------------------------------------------------+
void DrawPlanRR(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                const int lastClosed, const double entry, const double target,
                const double stop, const double closeRef)
  {
   if(!InpShowLabels)
      return;
   double risk = MathAbs(entry - stop);
   if(risk <= 0.0)
      return;
   double rr  = MathAbs(target - entry) / risk;
   double mid = (entry + target) * 0.5;

   datetime t1 = (datetime)(rates[lastClosed].time +
                            (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars));
   UpsertText(chart_id, OBJ_PREFIX + "PLAN_RR", t1, mid,
              "R:R 1:" + DoubleToString(rr, 1), COL_TARGET, 8, "Arial",
              mid >= closeRef ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
  }

//+------------------------------------------------------------------+
//| Co-pilot HUD (v4.00) — pixel-anchored labels, drawn per chart:     |
//|   RISK 1.0% = 0.25 lots        (this chart's plan, override-aware) |
//|   HEAT 1.20% (3 pos, 1 no-SL)  (account-wide manual-trade risk)    |
//|   MAX PORTFOLIO HEAT           flashing red when heat >= threshold |
//| Everything goes through UpsertLabel, so SweepUndrawn removes the   |
//| lines the moment the plan forms/disappears or a toggle goes off.   |
//+------------------------------------------------------------------+
void RenderRiskHUD(const long chart_id, const SMarketState &st)
  {
   int y = HUD_Y;

   if(InpRiskHUD && st.planOk)
     {
      const double lots = ComputeRiskLots(st.symbol, st.planEntry, st.planStop, g_ov.riskPct);
      if(lots > 0.0)
        {
         UpsertLabel(chart_id, OBJ_PREFIX + "HUD_RISK", HUD_X, y,
                     "RISK " + DoubleToString(g_ov.riskPct, 1) + "% = " +
                     DoubleToString(lots, 2) + " lots",
                     COL_ENTRY, HUD_FONT, "Arial Bold", CORNER_LEFT_UPPER);
         y += HUD_LINE_H + 2;
        }
     }

   if(InpHeatTracker)
     {
      SHeat h;
      ComputePortfolioHeat(h);
      const color  heatClr = h.alert ? COL_STOP : (h.pct > 0.0 ? COL_TARGET : COL_LIQ);
      const string heatTxt = "HEAT " + DoubleToString(h.pct, 2) + "% (" +
                             IntegerToString(h.positions) + " pos" +
                             (h.noSl > 0 ? ", " + IntegerToString(h.noSl) + " no-SL" : "") + ")";
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_HEAT", HUD_X, y,
                  heatTxt, heatClr, HUD_FONT, "Arial", CORNER_LEFT_UPPER);
      y += HUD_LINE_H;
      if(h.alert)
        {
         g_heatBlink = !g_heatBlink;          // alternate every render pass
         if(g_heatBlink)
            UpsertLabel(chart_id, OBJ_PREFIX + "HUD_HEAT_ALERT", HUD_X, y,
                        "MAX PORTFOLIO HEAT", COL_STOP, HUD_FONT_ALERT,
                        "Arial Bold", CORNER_LEFT_UPPER);
        }
     }
  }

//+------------------------------------------------------------------+
//| One plan level — filled zone band (v2.06) + solid segment + label |
//| The band is the SAME rectangle for every level: same height       |
//| (InpPlanZoneHeightATR × ATR, centered on the level), same x-range |
//| as the line — the ONLY difference between ENTRY / STOP / TARGET   |
//| bands is the color. v2.07: all three objects upsert in place.     |
//+------------------------------------------------------------------+
void DrawPlanLine(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                  const int lastClosed, const double level, const double closeRef,
                  const color clr, const string tag, const string label,
                  const bool washout)
  {
   int x0 = MathMax(0, lastClosed - MathMax(1, InpPlanBars));
   datetime t0 = rates[x0].time;                                     // x0 <= lastClosed: in bounds
   datetime t1 = (datetime)(rates[lastClosed].time +
                            (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars));

   // v4.00: during a news blackout the BANDS wash out toward the chart
   // background (lines + labels stay readable) — a red NEWS column marks
   // the blackout window itself.
   color bandClr = clr;
   if(washout)
      bandClr = DimColor(chart_id, clr, NEWS_WASH_STRENGTH);

   // v2.06 — filled zone rectangle at this level (ENTRY below+above strip:
   // one band at entry, the STOP band below it, the TARGET band above)
   // v4.00: g_ov.planZones is the remote-control mirror of InpPlanZones.
   if(InpPlanZones && g_ov.planZones)
     {
      const string sym = ChartSymbol(chart_id);
      const double atr   = GetAtr(sym, tf);
      const double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double half = MathMax(0.02, InpPlanZoneHeightATR) * atr * 0.5;
      half = MathMax(half, point);                    // never a zero-height strip
      UpsertRect(chart_id, OBJ_PREFIX + tag + "_ZONE", t0, level - half, t1, level + half,
                 bandClr, true, InpPlanZoneBack, STYLE_SOLID);
     }

   UpsertSegment(chart_id, OBJ_PREFIX + tag, t0, level, t1, level,
                 clr, MathMax(1, InpPlanWidth), STYLE_SOLID);

   if(InpShowLabels)
     {
      string ltext = label;
      if(InpPlanLabelPrice)
        {
         int    pdigits = (int)SymbolInfoInteger(ChartSymbol(chart_id), SYMBOL_DIGITS);
         ltext = label + " " + DoubleToString(level, pdigits);
        }
      // label sits above the line when the level is above price, below otherwise
      UpsertText(chart_id, OBJ_PREFIX + tag + "_LBL", t1, level, ltext,
                 clr, 9, "Arial Bold",
                 level >= closeRef ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }
  }

/* ================================================================== */
/* v11.00: PRICE-IN-ZONE PUSH ALERTS                                   */
/*                                                                     */
/* Watches the attach chart's live Bid against the attach chart's plan */
/* cache (g_plan — the same state-driven cache the Web Bridge reads).  */
/* Fires SendNotification (mobile push, when a MetaQuotes ID is        */
/* configured under Tools -> Options -> Notifications) plus an Alert() */
/* + Print() fallback that always works locally. Throttled per KIND    */
/* (ENTRY / STOP / TARGET) so a plan sitting exactly on a level does   */
/* not spam a push every OnTimer tick.                                 */
/* ================================================================== */
void FireAlert(const string kind, const string planKey, const string text)
  {
   int slot = -1;
   for(int i = 0; i < 3; i++)
      if(g_lastAlertKind[i] == kind)
        {
         slot = i;
         break;
        }
   if(slot < 0)
      return;                                  // unknown kind — never configured, ignore

   const datetime now = TimeCurrent();
   if(g_lastAlertPlanKey[slot] == planKey &&
      now - g_lastAlertTimeAt[slot] < MathMax(1, InpAlertCooldownMin) * 60)
      return;                                  // same kind, same plan, still cooling down
   g_lastAlertPlanKey[slot] = planKey;
   g_lastAlertTimeAt[slot]  = now;

   Alert(text);
   Print("PAICT alert: ", text);
   ResetLastError();
   if(!SendNotification(text))
     {
      const int err = GetLastError();
      if(err != 4515 && err != 0)             // 4515: no MetaQuotes ID configured — expected on many setups
         Print("PAICT alert: SendNotification failed (error ", err, ") — chart Alert()/Print() still fired.");
     }
  }

void CheckPriceAlerts()
  {
   if(!InpPriceAlerts || !g_plan.ok)
      return;
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0)
      return;
   const double atr = GetAtr(_Symbol, (ENUM_TIMEFRAMES)_Period);
   const double tol = MathMax(atr * ALERT_TOL_ATR, _Point);
   const int    dg  = _Digits;
   const bool   isLong = (g_plan.target > g_plan.entry);
   // Identifies THIS plan instance so a freshly formed plan's first ENTRY
   // alert is never suppressed by a cooldown a different, older plan left
   // behind, and switching kinds on the same plan still throttles per kind.
   const string planKey = DoubleToString(g_plan.entry, dg) + "/" +
                          DoubleToString(g_plan.stop, dg) + "/" +
                          DoubleToString(g_plan.target, dg);

   if(MathAbs(bid - g_plan.entry) <= tol)
      FireAlert("ENTRY", planKey, "PAICT " + _Symbol + " " + BridgeTimeframeLabel() +
                ": price in ENTRY zone " + DoubleToString(g_plan.entry, dg) +
                " (" + (isLong ? "long" : "short") + ")");
   else if((isLong && bid <= g_plan.stop) || (!isLong && bid >= g_plan.stop))
      FireAlert("STOP", planKey, "PAICT " + _Symbol + " " + BridgeTimeframeLabel() +
                ": STOP touched at " + DoubleToString(g_plan.stop, dg));
   else if((isLong && bid >= g_plan.target) || (!isLong && bid <= g_plan.target))
      FireAlert("TARGET", planKey, "PAICT " + _Symbol + " " + BridgeTimeframeLabel() +
                ": TARGET touched at " + DoubleToString(g_plan.target, dg));
  }

/* ================================================================== */
/*  V6.00 MICROSTRUCTURE — volume profile, fractal matrix, cone        */
/* ================================================================== */
string TFLabel(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return(s);
  }

//+------------------------------------------------------------------+
//| Swing-structure trend score of ONE timeframe: +1 higher highs AND  |
//| higher lows, -1 lower lows AND lower highs, 0 mixed. Reuses the    |
//| same FindSwings detector as the chart markup (confirmed bars only).|
//+------------------------------------------------------------------+
int TrendScoreTF(const string sym, const ENUM_TIMEFRAMES tf)
  {
   MqlRates r[];
   ResetLastError();
   const int total = CopyRates(sym, tf, 1, 80, r);   // closed bars only
   if(total < 20)
      return(0);
   int hiIdx[]; double hiVal[]; int loIdx[]; double loVal[];
   int nHi = 0, nLo = 0;
   FindSwings(r, total - 1, InpSwingStrength, hiIdx, hiVal, nHi, loIdx, loVal, nLo);
   if(nHi < 2 || nLo < 2)
      return(0);
   const double h1 = hiVal[nHi - 1], h2 = hiVal[nHi - 2];
   const double l1 = loVal[nLo - 1], l2 = loVal[nLo - 2];
   if(h1 > h2 && l1 > l2)
      return(1);
   if(h1 < h2 && l1 < l2)
      return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
//| Tick-volume profile over the recent sessions: POC = busiest bucket,|
//| VAH/VAL = value area holding 70% of the volume around the POC.     |
//+------------------------------------------------------------------+
bool BuildVolumeProfile(const MqlRates &rates[], const int lastClosed, const int span,
                        const int rows, double &vpLo[], double &vpHi[], double &vpVol[],
                        int &pocIdx, double &vah, double &val)
  {
   const int nRows = (int)MathMax(4, MathMin(VP_MAX_ROWS, rows));
   if(span < 30 || lastClosed + 1 < span)
      return(false);
   const int i0 = lastClosed + 1 - span;
   double mn = DBL_MAX, mx = -DBL_MAX;
   for(int i = i0; i <= lastClosed; i++)
     {
      const double mid = 0.5 * (rates[i].high + rates[i].low);
      if(mid < mn)
         mn = mid;
      if(mid > mx)
         mx = mid;
     }
   if(mx - mn <= 0.0)
      return(false);
   const double step = (mx - mn) / nRows;
   ArrayResize(vpLo, nRows, ARRAY_RESERVE_CHUNK);
   ArrayResize(vpHi, nRows, ARRAY_RESERVE_CHUNK);
   ArrayResize(vpVol, nRows, ARRAY_RESERVE_CHUNK);
   for(int r0 = 0; r0 < nRows; r0++)
     {
      vpLo[r0]  = mn + r0 * step;
      vpHi[r0]  = vpLo[r0] + step;
      vpVol[r0] = 0.0;
     }
   for(int i = i0; i <= lastClosed; i++)
     {
      const double mid = 0.5 * (rates[i].high + rates[i].low);
      int b = (int)((mid - mn) / step);
      if(b < 0)
         b = 0;
      if(b >= nRows)
         b = nRows - 1;
      vpVol[b] += (double)rates[i].tick_volume;
     }
   pocIdx = 0;
   double total = 0.0;
   for(int r0 = 0; r0 < nRows; r0++)
     {
      if(vpVol[r0] > vpVol[pocIdx])
         pocIdx = r0;
      total += vpVol[r0];
     }
   if(total <= 0.0 || vpVol[pocIdx] <= 0.0)
      return(false);
   int l = pocIdx, r1 = pocIdx;
   double acc = vpVol[pocIdx];
   const double target = total * VP_VALUE_AREA_PCT;
   while(acc < target && (l > 0 || r1 < nRows - 1))
     {
      const double vl = (l > 0) ? vpVol[l - 1] : -1.0;
      const double vr = (r1 < nRows - 1) ? vpVol[r1 + 1] : -1.0;
      if(vr >= vl)
        {
         r1++;
         acc += vpVol[r1];
        }
      else
        {
         l--;
         acc += vpVol[l];
        }
     }
   vah = vpHi[r1];
   val = vpLo[l];
   return(true);
  }

void DrawVolumeProfile(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                       const int lastClosed, const SMarketState &st)
  {
   const int barsPerDay = MathMax(1, 86400 / MathMax(60, PeriodSeconds(tf)));
   const int span = MathMax(30, MathMin(lastClosed + 1,
                                        MathMax(30, MathMax(1, InpVPDays) * barsPerDay)));
   double vpLo[], vpHi[], vpVol[];
   int poc = -1;
   double vah = 0.0, val = 0.0;
   if(!BuildVolumeProfile(rates, lastClosed, span, InpVPRows, vpLo, vpHi, vpVol, poc, vah, val))
     {
      g_vpPoc = 0.0; g_vpVah = 0.0; g_vpVal = 0.0;  // insufficient data — don't publish a stale prior read
      return;
     }
   const datetime t0    = rates[lastClosed + 1 - span].time;
   const long     barSec= MathMax(60, PeriodSeconds(tf));
   double maxVol = 0.0;
   for(int r0 = 0; r0 < ArraySize(vpVol); r0++)
      if(vpVol[r0] > maxVol)
         maxVol = vpVol[r0];
   if(maxVol <= 0.0)
     {
      g_vpPoc = 0.0; g_vpVah = 0.0; g_vpVal = 0.0;
      return;
     }
   for(int r0 = 0; r0 < ArraySize(vpVol); r0++)
     {
      if(vpVol[r0] <= 0.0)
         continue;
      const int      wBars = (int)MathMax(1.0, MathRound(vpVol[r0] / maxVol *
                                                        MathMax(2, InpVPWidthBars)));
      const datetime t1 = (datetime)((long)t0 + (long)wBars * barSec);
      const bool inVA = (vpHi[r0] <= vah + (vah - val) * 0.01 &&
                         vpLo[r0] >= val - (vah - val) * 0.01);
      const color c = (r0 == poc) ? COL_ENTRY
                                  : DimColor(chart_id, VP_ROW_COLOR, inVA ? 0.55 : 0.30);
      UpsertRect(chart_id, OBJ_PREFIX + "VP_R" + IntegerToString(r0),
                 t0, vpLo[r0], t1, vpHi[r0], c, true, true, STYLE_SOLID);
     }
   const datetime tEnd = (datetime)((long)t0 + (long)MathMax(2, InpVPWidthBars) * barSec);
   const int dg = (int)SymbolInfoInteger(ChartSymbol(chart_id), SYMBOL_DIGITS);
   UpsertSegment(chart_id, OBJ_PREFIX + "VP_POC", t0, vpHi[poc], tEnd, vpHi[poc],
                 COL_ENTRY, 2, STYLE_SOLID);
   UpsertSegment(chart_id, OBJ_PREFIX + "VP_VAH", t0, vah, tEnd, vah, COL_LIQ, 1, STYLE_DOT);
   UpsertSegment(chart_id, OBJ_PREFIX + "VP_VAL", t0, val, tEnd, val, COL_LIQ, 1, STYLE_DOT);
   if(InpShowLabels)
     {
      UpsertText(chart_id, OBJ_PREFIX + "VP_L0", tEnd, vpHi[poc],
                 "POC " + DoubleToString(0.5 * (vpLo[poc] + vpHi[poc]), dg),
                 COL_ENTRY, 8, "Arial Bold", ANCHOR_LEFT_LOWER);
      UpsertText(chart_id, OBJ_PREFIX + "VP_L1", tEnd, vah, "VAH " + DoubleToString(vah, dg),
                 COL_LIQ, 8, "Arial", ANCHOR_LEFT_LOWER);
      UpsertText(chart_id, OBJ_PREFIX + "VP_L2", tEnd, val, "VAL " + DoubleToString(val, dg),
                 COL_LIQ, 8, "Arial", ANCHOR_LEFT_UPPER);
     }
   g_vpPoc = 0.5 * (vpLo[poc] + vpHi[poc]);
   g_vpVah = vah;
   g_vpVal = val;
  }

//+------------------------------------------------------------------+
//| Probability cone: ±Nσ random-walk projection of the NEXT bars from |
//| the |Δclose| statistics of the recent window (sqrt-time scaling).  |
//+------------------------------------------------------------------+
void DrawProbabilityCone(const long chart_id, const MqlRates &rates[], const ENUM_TIMEFRAMES tf,
                         const int lastClosed, const double closeRef)
  {
   if(closeRef <= 0.0 || lastClosed < 30)
      return;
   const int win = MathMin(CONE_LOOKBACK_BARS, lastClosed);
   double sum = 0.0, sumsq = 0.0;
   int n = 0;
   for(int i = lastClosed - win + 1; i <= lastClosed; i++)
     {
      const double d = rates[i].close - rates[i - 1].close;
      sum  += d;
      sumsq+= d * d;
      n++;
     }
   if(n < 20)
      return;
   const double mean = sum / n;
   double varr = sumsq / n - mean * mean;
   if(varr < 0.0)
      varr = 0.0;
   const double sd = MathSqrt(varr);
   if(sd <= 0.0)
      return;
   const long     barSec   = MathMax(60, PeriodSeconds(tf));
   const int      coneBars = (int)MathMax(2, InpConeBars);
   const datetime t0       = rates[lastClosed].time;
   const datetime tm       = (datetime)((long)t0 + (long)(coneBars / 2) * barSec);
   const datetime t1       = (datetime)((long)t0 + (long)coneBars * barSec);
   const double   hwM      = CONE_SIGMAS * sd * MathSqrt((double)MathMax(1, coneBars / 2));
   const double   hwH      = CONE_SIGMAS * sd * MathSqrt((double)coneBars);
   UpsertSegment(chart_id, OBJ_PREFIX + "CONE_M",  t0, closeRef,        t1, closeRef,        COL_LIQ, 1, STYLE_DOT);
   UpsertSegment(chart_id, OBJ_PREFIX + "CONE_U1", t0, closeRef,        tm, closeRef + hwM, COL_EQ,  1, STYLE_DOT);
   UpsertSegment(chart_id, OBJ_PREFIX + "CONE_U2", tm, closeRef + hwM,  t1, closeRef + hwH, COL_EQ,  1, STYLE_DOT);
   UpsertSegment(chart_id, OBJ_PREFIX + "CONE_D1", t0, closeRef,        tm, closeRef - hwM, COL_EQ,  1, STYLE_DOT);
   UpsertSegment(chart_id, OBJ_PREFIX + "CONE_D2", tm, closeRef - hwM,  t1, closeRef - hwH, COL_EQ,  1, STYLE_DOT);
   if(InpShowLabels)
     {
      UpsertText(chart_id, OBJ_PREFIX + "CONE_LU", t1, closeRef + hwH,
                 "+" + DoubleToString(CONE_SIGMAS, 0) + "s", COL_EQ, 8, "Arial", ANCHOR_LEFT_LOWER);
      UpsertText(chart_id, OBJ_PREFIX + "CONE_LD", t1, closeRef - hwH,
                 "-" + DoubleToString(CONE_SIGMAS, 0) + "s", COL_EQ, 8, "Arial", ANCHOR_LEFT_UPPER);
     }
  }

/* ================================================================== */
/*  V7.00 SIMULATION — Monte Carlo TP/SL + DOM ladder strip            */
/* ================================================================== */

//+------------------------------------------------------------------+
//| Zero-drift random walk with per-bar sigma = ATR: first touch of    |
//| TARGET vs STOP inside the horizon, averaged over InpMCRuns runs.   |
//| Seeded from the plan levels so the same plan gives the same read   |
//| (no flicker between refreshes). ATR-based sigma is a deliberate    |
//| upper bound — treat the output as a COMPARISON metric, not odds.   |
//+------------------------------------------------------------------+
void MonteCarloEvaluate(const double entry, const double stop, const double target,
                        const double atr, const int runs, const int horizon)
  {
   g_mcTP = 0.0;
   g_mcSL = 0.0;
   const double riskD = MathAbs(entry - stop);
   if(riskD <= 0.0 || MathAbs(target - entry) <= 0.0 || atr <= 0.0)
      return;
   const int  R      = (int)MathMax(100, MathMin(MC_MAX_RUNS, runs));
   const int  B      = (int)MathMax(5, MathMin(MC_MAX_BARS, horizon));
   const bool isLong = (target > entry);
   int seed = (int)(MathRound(entry * 131.0)) ^ (int)(MathRound(stop * 77.0));
   MathSrand(MathAbs(seed));
   int tp = 0, sl = 0;
   for(int r0 = 0; r0 < R; r0++)
     {
      double p = entry;
      for(int b = 0; b < B; b++)
        {
         const double u1 = (MathRand() + 1.0) / 32769.0;   // (0, 1]
         const double u2 = MathRand() / 32768.0;           // [0, 1)
         const double z  = MathSqrt(-2.0 * MathLog(u1)) * MathCos(2.0 * M_PI * u2);
         p += atr * z;
         if(isLong)
           {
            if(p >= target) { tp++; break; }
            if(p <= stop)   { sl++; break; }
           }
         else
           {
            if(p <= target) { tp++; break; }
            if(p >= stop)   { sl++; break; }
           }
        }
     }
   g_mcTP = 100.0 * tp / R;
   g_mcSL = 100.0 * sl / R;
  }

//+------------------------------------------------------------------+
//| v15.01: lazily subscribe ONE symbol to Depth of Market. A single    |
//| MarketBookAdd(_Symbol) in OnInit only ever covered the attach       |
//| chart — every other covered symbol's ladder strip stayed empty.     |
//+------------------------------------------------------------------+
bool EnsureDOMSubscription(const string sym)
  {
   for(int i = 0; i < ArraySize(g_domSubs); i++)
      if(g_domSubs[i] == sym)
         return(true);
   ResetLastError();
   if(!MarketBookAdd(sym))
     {
      if(!g_domWarned)
        {
         g_domWarned = true;
         Print("PAICT DOM: MarketBookAdd failed for ", sym, " (error ", GetLastError(),
               ") — its ladder strip stays off for this broker/symbol.");
        }
      return(false);
     }
   const int at = ArraySize(g_domSubs);
   ArrayResize(g_domSubs, at + 1, ARRAY_RESERVE_CHUNK);
   g_domSubs[at] = sym;
   return(true);
  }

//+------------------------------------------------------------------+
//| Depth of Market ladder: bid/ask volume bars reaching back from the |
//| forming bar. Needs a broker that serves MarketBookGet.             |
//+------------------------------------------------------------------+
void DrawDOMStrip(const long chart_id, const string sym, const ENUM_TIMEFRAMES tf)
  {
   if(!EnsureDOMSubscription(sym))
      return;
   MqlBookInfo book[];
   if(!MarketBookGet(sym, book) || ArraySize(book) == 0)
     {
      if(!g_domWarned)
        {
         g_domWarned = true;
         Print("PAICT DOM: no Depth of Market data from the broker — the ladder strip stays off.");
        }
      return;
     }
   const double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point <= 0.0)
      return;
   const long     barSec = MathMax(60, PeriodSeconds(tf));
   const datetime tRight = (datetime)((long)iTime(sym, tf, 0) + barSec);
   const double   half   = 2.5 * point;
   const int      maxL   = MathMax(1, MathMin(DOM_MAX_LEVELS, InpDOMLevels));
   double maxVol = 0.0;
   int nBids = 0, nAsks = 0;
   for(int i = 0; i < ArraySize(book) && (nBids < maxL || nAsks < maxL); i++)
     {
      const double v = (double)book[i].volume;   // MqlBookInfo.volume is long — there is no volume_dbl member
      if(v <= 0.0)
         continue;
      if(v > maxVol)
         maxVol = v;
      if(book[i].type == BOOK_TYPE_BUY)
         nBids++;
      else
         nAsks++;
     }
   if(maxVol <= 0.0)
      return;
   nBids = 0;
   nAsks = 0;
   for(int i = 0; i < ArraySize(book) && (nBids < maxL || nAsks < maxL); i++)
     {
      const double v = (double)book[i].volume;   // MqlBookInfo.volume is long — there is no volume_dbl member
      if(v <= 0.0)
         continue;
      const bool isBid = (book[i].type == BOOK_TYPE_BUY);
      if(isBid)
        {
         if(nBids >= maxL)
            continue;
         nBids++;
        }
      else
        {
         if(nAsks >= maxL)
            continue;
         nAsks++;
        }
      const int      wBars = (int)MathMax(1.0, MathRound(v / maxVol * DOM_WIDTH_BARS));
      const datetime t0    = (datetime)((long)tRight - (long)wBars * barSec);
      UpsertRect(chart_id,
                 OBJ_PREFIX + "DOM_" + (isBid ? "B" : "A") +
                 IntegerToString(isBid ? nBids : nAsks),
                 t0, book[i].price - half, tRight, book[i].price + half,
                 isBid ? COL_OB_BULL : COL_OB_BEAR, true, true, STYLE_SOLID);
     }
  }

/* ================================================================== */
/*  V8.00 ORDER FLOW — CVD curve, sweep tags, absorption, displacement */
/* ================================================================== */

//+------------------------------------------------------------------+
//| Tick-volume CVD (delta ≈ tickVol × sign(close-open)) drawn as a    |
//| normalized polyline in the bottom band of the dealing range, with  |
//| a divergence read: price makes a higher high (lower low) the CVD   |
//| does not confirm. Purely local tick-volume proxy — no feed needed. |
//+------------------------------------------------------------------+
void DrawCVD(const long chart_id, const MqlRates &rates[], const int lastClosed,
             const SMarketState &st)
  {
   const int len = (int)MathMax(24, MathMin(300, InpCVDLength));
   if(lastClosed < len + 2 || st.atr <= 0.0)
     {
      g_cvdDir = 0;      // not enough history for a real reading — don't
      g_cvdDiv = false;  // let a stale prior signal keep scoring/pushing
      return;
     }
   const int i0 = lastClosed - len;
   double cvd[];
   ArrayResize(cvd, len + 1, ARRAY_RESERVE_CHUNK);
   double run = 0.0, mnC = 0.0, mxC = 0.0;
   const int    half = len / 2;
   double cvdMaxA = -DBL_MAX, cvdMaxB = -DBL_MAX;
   double cvdMinA =  DBL_MAX, cvdMinB =  DBL_MAX;
   double prMaxA = -DBL_MAX,  prMaxB = -DBL_MAX;
   double prMinA =  DBL_MAX,  prMinB =  DBL_MAX;
   for(int k = 0; k <= len; k++)
     {
      const int i = i0 + k;
      run += (double)rates[i].tick_volume *
             ((rates[i].close >= rates[i].open) ? 1.0 : -1.0);
      cvd[k] = run;
      if(run < mnC)
         mnC = run;
      if(run > mxC)
         mxC = run;
      if(k < half)
        {
         if(run > cvdMaxA) cvdMaxA = run;
         if(run < cvdMinA) cvdMinA = run;
         if(rates[i].high > prMaxA) prMaxA = rates[i].high;
         if(rates[i].low  < prMinA) prMinA = rates[i].low;
        }
      else
        {
         if(run > cvdMaxB) cvdMaxB = run;
         if(run < cvdMinB) cvdMinB = run;
         if(rates[i].high > prMaxB) prMaxB = rates[i].high;
         if(rates[i].low  < prMinB) prMinB = rates[i].low;
        }
     }
   if(mxC - mnC <= 0.0)
      return;
   const double base = (st.rangeHi > st.rangeLo)
                       ? st.rangeLo : (st.closeRef - 4.0 * st.atr);
   const double band = (st.rangeHi > st.rangeLo)
                       ? MathMax(st.atr, (st.rangeHi - st.rangeLo) * CVD_BAND_FRAC)
                       : 1.6 * st.atr;
   const datetime t0     = rates[i0].time;
   const long     barSec = MathMax(60, PeriodSeconds(st.tf));
   const int      step   = MathMax(1, len / CVD_MAX_SEGMENTS);
   const color curveClr = (cvd[len] >= cvd[0]) ? COL_OB_BULL : COL_OB_BEAR;
   const double ref = mxC - mnC;
   g_cvdDir = (cvd[len] > cvd[MathMax(0, len - 5)] + ref * 0.02) ? 1 :
              ((cvd[len] < cvd[MathMax(0, len - 5)] - ref * 0.02) ? -1 : 0);
   for(int k0 = 0; k0 < len; k0 += step)
     {
      const int k1 = MathMin(len, k0 + step);
      const double y0 = base + band * (cvd[k0] - mnC) / ref;
      const double y1 = base + band * (cvd[k1] - mnC) / ref;
      UpsertSegment(chart_id, OBJ_PREFIX + "CVD_" + IntegerToString(k0),
                    (datetime)((long)t0 + (long)k0 * barSec), y0,
                    (datetime)((long)t0 + (long)k1 * barSec), y1, curveClr, 1, STYLE_SOLID);
     }
   g_cvdDiv = false;
   if(prMaxB > prMaxA && cvdMaxB < cvdMaxA)
     {
      g_cvdDiv = true;
      if(InpShowLabels)
         UpsertText(chart_id, OBJ_PREFIX + "CVD_DIV", rates[lastClosed].time, base + band,
                    "CVD DIV-", COL_OB_BEAR, 8, "Arial Bold", ANCHOR_LEFT_UPPER);
     }
   else if(prMinB < prMinA && cvdMinB > cvdMinA)
     {
      g_cvdDiv = true;
      if(InpShowLabels)
         UpsertText(chart_id, OBJ_PREFIX + "CVD_DIV", rates[lastClosed].time, base,
                    "CVD DIV+", COL_OB_BULL, 8, "Arial Bold", ANCHOR_LEFT_LOWER);
     }
  }

//+------------------------------------------------------------------+
//| TRUE SWEEP: a wick raids the pool and the bar CLOSES back inside   |
//| (liquidity grab, reversal expected). FAKEOUT: a bar CLOSES beyond  |
//| the pool — the level gave way. Nearest raid per pool only.         |
//+------------------------------------------------------------------+
void TagSweeps(const long chart_id, const MqlRates &rates[], const SMarketState &st)
  {
   if(st.atr <= 0.0)
      return;
   const int scan = MathMin(SWEEP_SCAN_BARS, st.lastClosed - 2);
   if(scan < 2)
      return;
   for(int b = 0; b < ArraySize(st.bslLv); b++)
     {
      for(int j = st.lastClosed; j > st.lastClosed - scan; j--)
         if(rates[j].high > st.bslLv[b] && rates[j].close < st.bslLv[b])
           {
            if(InpShowLabels)
               UpsertText(chart_id, OBJ_PREFIX + "SWEEP_B" + IntegerToString(b),
                          rates[j].time, rates[j].high + 0.2 * st.atr, "TRUE SWEEP",
                          COL_CHOCH, 8, "Arial Bold", ANCHOR_LEFT_LOWER);
            break;
           }
      for(int j = st.lastClosed; j > st.lastClosed - scan; j--)
         if(rates[j].close > st.bslLv[b])
           {
            if(InpShowLabels)
               UpsertText(chart_id, OBJ_PREFIX + "FAKE_B" + IntegerToString(b),
                          rates[j].time, rates[j].high + 0.45 * st.atr, "FAKEOUT",
                          COL_LIQ, 8, "Arial", ANCHOR_LEFT_LOWER);
            break;
           }
     }
   for(int q = 0; q < ArraySize(st.sslLv); q++)
     {
      for(int j = st.lastClosed; j > st.lastClosed - scan; j--)
         if(rates[j].low < st.sslLv[q] && rates[j].close > st.sslLv[q])
           {
            if(InpShowLabels)
               UpsertText(chart_id, OBJ_PREFIX + "SWEEP_S" + IntegerToString(q),
                          rates[j].time, rates[j].low - 0.2 * st.atr, "TRUE SWEEP",
                          COL_CHOCH, 8, "Arial Bold", ANCHOR_LEFT_UPPER);
            break;
           }
      for(int j = st.lastClosed; j > st.lastClosed - scan; j--)
         if(rates[j].close < st.sslLv[q])
           {
            if(InpShowLabels)
               UpsertText(chart_id, OBJ_PREFIX + "FAKE_S" + IntegerToString(q),
                          rates[j].time, rates[j].low - 0.45 * st.atr, "FAKEOUT",
                          COL_LIQ, 8, "Arial", ANCHOR_LEFT_UPPER);
            break;
           }
     }
  }

//+------------------------------------------------------------------+
//| Absorption: an order-block candle with a SMALL body but TOP tick   |
//| volume = the opposing side was absorbed there (institutional       |
//| footprint proxy from free tick-volume data).                       |
//+------------------------------------------------------------------+
void TagAbsorption(const long chart_id, const MqlRates &rates[], const SMarketState &st)
  {
   if(st.atr <= 0.0)
      return;
   const int win = MathMin(60, st.lastClosed);
   if(win < 10)
      return;
   double vSum = 0.0;
   for(int i = st.lastClosed - win + 1; i <= st.lastClosed; i++)
      vSum += (double)rates[i].tick_volume;
   const double vThr = (vSum / win) * ABSORB_VOL_MULT;
   if(st.bullIdx >= 0 && st.bullIdx > st.lastClosed - win)
     {
      const double body = MathAbs(rates[st.bullIdx].close - rates[st.bullIdx].open);
      if(body <= ABSORB_BODY_ATR * st.atr && (double)rates[st.bullIdx].tick_volume >= vThr &&
         InpShowLabels)
         UpsertText(chart_id, OBJ_PREFIX + "ABS_B", rates[st.bullIdx].time,
                    rates[st.bullIdx].low - 0.15 * st.atr, "ABS+",
                    COL_OB_BULL, 8, "Arial Bold", ANCHOR_LEFT_UPPER);
     }
   if(st.bearIdx >= 0 && st.bearIdx > st.lastClosed - win)
     {
      const double body = MathAbs(rates[st.bearIdx].close - rates[st.bearIdx].open);
      if(body <= ABSORB_BODY_ATR * st.atr && (double)rates[st.bearIdx].tick_volume >= vThr &&
         InpShowLabels)
         UpsertText(chart_id, OBJ_PREFIX + "ABS_S", rates[st.bearIdx].time,
                    rates[st.bearIdx].high + 0.15 * st.atr, "ABS-",
                    COL_OB_BEAR, 8, "Arial Bold", ANCHOR_LEFT_LOWER);
     }
  }

//+------------------------------------------------------------------+
//| Displacement grade 1-10: CHoCH break-bar body in ATR steps of 0.20 |
//| (grade 5 ≈ 1.0 ATR body). Grade + direction feed the Master Score. |
//+------------------------------------------------------------------+
void TagDisplacement(const long chart_id, const MqlRates &rates[], const SMarketState &st)
  {
   g_dispGrade = 0;
   const int    idx = (st.chocIdx >= 0) ? st.chocIdx : st.mssIdx;
   const double lvl = (st.chocIdx >= 0) ? st.chocLvl : st.mssLvl;
   if(idx < 0 || st.atr <= 0.0)
      return;
   const double body = MathAbs(rates[idx].close - rates[idx].open);
   g_dispGrade = (int)MathMax(1.0, MathMin(10.0, MathRound(body / (DISP_GRADE_ATR_STEP * st.atr))));
   g_dispLong  = (rates[idx].close > lvl);
   if(InpShowLabels)
      UpsertText(chart_id, OBJ_PREFIX + "DISP", rates[idx].time,
                 rates[idx].high + 0.25 * st.atr, "D" + IntegerToString(g_dispGrade),
                 COL_CHOCH, 8, "Arial Bold", ANCHOR_LEFT_LOWER);
  }

/* ================================================================== */
/*  V9.00 INTERMARKET — correlation watch + named ICT patterns         */
/* ================================================================== */
double Pearson(const double &x[], const double &y[], const int n)
  {
   if(n < 3)
      return(0.0);
   double sx = 0.0, sy = 0.0;
   for(int i = 0; i < n; i++)
     {
      sx += x[i];
      sy += y[i];
     }
   const double mx = sx / n, my = sy / n;
   double sxy = 0.0, sxx = 0.0, syy = 0.0;
   for(int i = 0; i < n; i++)
     {
      const double dx = x[i] - mx, dy = y[i] - my;
      sxy += dx * dy;
      sxx += dx * dx;
      syy += dy * dy;
     }
   if(sxx <= 0.0 || syy <= 0.0)
      return(0.0);
   return(sxy / MathSqrt(sxx * syy));
  }

//+------------------------------------------------------------------+
//| Pearson r of bar returns vs every OTHER covered chart symbol; HUD  |
//| reports the strongest pair and flags a divergence when the attach  |
//| symbol moved >= 2 ATR over the window while |r| stayed low.        |
//+------------------------------------------------------------------+
void RenderCorrelation(const long chart_id, const string sym, const ENUM_TIMEFRAMES tf,
                       const int y, const SMarketState &st)
  {
   g_corrSym = "";
   g_corrR = 0.0;
   g_corrWarn = false;
   const int win = MathMax(20, InpCorrBars);
   double a[];
   ResetLastError();
   if(CopyClose(sym, tf, 1, win + 1, a) < win + 1)
      return;
   double ra[];
   ArrayResize(ra, win, ARRAY_RESERVE_CHUNK);
   for(int i = 0; i < win; i++)
      ra[i] = (a[i] > 0.0) ? (a[i + 1] / a[i] - 1.0) : 0.0;
   double bestAbs = 0.0, bestR = 0.0;
   string bestSym = "";
   for(int c = 0; c < ArraySize(g_charts); c++)
     {
      const string other = ChartSymbol(g_charts[c].chart_id);
      if(other == "" || other == sym)
         continue;
      double b[];
      if(CopyClose(other, tf, 1, win + 1, b) < win + 1)
         continue;
      double rb[];
      ArrayResize(rb, win, ARRAY_RESERVE_CHUNK);
      for(int i = 0; i < win; i++)
         rb[i] = (b[i] > 0.0) ? (b[i + 1] / b[i] - 1.0) : 0.0;
      const double r0 = Pearson(ra, rb, win);
      if(MathAbs(r0) > bestAbs)
        {
         bestAbs = MathAbs(r0);
         bestR   = r0;
         bestSym = other;
        }
     }
   if(bestSym == "")
      return;                      // no second covered symbol yet
   g_corrSym = bestSym;
   g_corrR   = bestR;
   const double moveAtrs = (st.atr > 0.0) ? MathAbs(a[win] - a[0]) / st.atr : 0.0;
   g_corrWarn = (moveAtrs >= 2.0 && bestAbs < MathMax(0.05, InpCorrWarn));
   UpsertLabel(chart_id, OBJ_PREFIX + "HUD_CORR", HUD_X, y,
               "CORR " + bestSym + " r=" + DoubleToString(bestR, 2) +
               (g_corrWarn ? " DIVERGING" : ""),
               g_corrWarn ? COL_KZ_LON : COL_LIQ, HUD_FONT, "Arial", CORNER_LEFT_UPPER);
  }

//+------------------------------------------------------------------+
//| Named ICT patterns: Turtle Soup (a wick raids the prior 20-bar     |
//| extreme and closes back inside) + the Power-of-3 day open with its |
//| AMD phase read (accumulation range -> expansion).                  |
//+------------------------------------------------------------------+
void DrawICTPatterns(const long chart_id, const MqlRates &rates[], const SMarketState &st)
  {
   if(st.atr <= 0.0)
      return;
   const int lc = st.lastClosed;
   g_tsoupBull = false;
   g_tsoupBear = false;
   if(lc >= TSoup_LOOKBACK + 2)
     {
      double hh = -DBL_MAX, ll = DBL_MAX;
      for(int i = lc - TSoup_LOOKBACK; i < lc; i++)
        {
         if(rates[i].high > hh)
            hh = rates[i].high;
         if(rates[i].low < ll)
            ll = rates[i].low;
        }
      const double c = rates[lc].close;
      if(rates[lc].low <= ll + TSoup_TOL_ATR * st.atr && c > ll)
        {
         g_tsoupBull = true;
         if(InpShowLabels)
            UpsertText(chart_id, OBJ_PREFIX + "TSOUP_B", rates[lc].time,
                       ll - 0.15 * st.atr, "TURTLE SOUP", COL_OB_BULL, 8, "Arial Bold",
                       ANCHOR_LEFT_UPPER);
        }
      if(rates[lc].high >= hh - TSoup_TOL_ATR * st.atr && c < hh)
        {
         g_tsoupBear = true;
         if(InpShowLabels)
            UpsertText(chart_id, OBJ_PREFIX + "TSOUP_S", rates[lc].time,
                       hh + 0.15 * st.atr, "TURTLE SOUP", COL_OB_BEAR, 8, "Arial Bold",
                       ANCHOR_LEFT_LOWER);
        }
     }
   const long dayStart = ((long)rates[lc].time / 86400) * 86400;
   int first = -1;
   const int scan = MathMin(DAY_OPEN_MAX_BARS, lc);
   for(int i = lc - scan; i <= lc && first < 0; i++)
      if((long)rates[i].time >= dayStart)
         first = i;
   if(first >= 0 && first < lc)
     {
      const double dayOpen  = rates[first].open;
      const long   barSec   = MathMax(60, PeriodSeconds(st.tf));
      const datetime t1     = (datetime)((long)rates[lc].time +
                                         (long)MathMax(1, InpExtendRightBars) * barSec);
      UpsertSegment(chart_id, OBJ_PREFIX + "P3_OPEN", rates[first].time, dayOpen, t1, dayOpen,
                    COL_KZ_NY, 1, STYLE_DOT);
      const int rangeBars = MathMin(lc - first, MathMax(3, (int)(10800 / barSec)));
      double frh = -DBL_MAX, frl = DBL_MAX;
      for(int i = first; i <= first + rangeBars && i <= lc; i++)
        {
         if(rates[i].high > frh)
            frh = rates[i].high;
         if(rates[i].low < frl)
            frl = rates[i].low;
        }
      string phase = "AMD ACCUM";
      if(rates[lc].close > frh)
         phase = "P3 EXPAND UP";
      else if(rates[lc].close < frl)
         phase = "P3 EXPAND DN";
      if(InpShowLabels)
         UpsertText(chart_id, OBJ_PREFIX + "P3_LBL", t1, dayOpen,
                    "P3 " + DoubleToString(dayOpen,
                    (int)SymbolInfoInteger(ChartSymbol(chart_id), SYMBOL_DIGITS)) +
                    " · " + phase, COL_KZ_NY, 8, "Arial", ANCHOR_LEFT_UPPER);
     }
  }

/* ================================================================== */
/*  V10.00 ZENITH TERMINAL — sandbox, master score, HUD block          */
/* ================================================================== */

//+------------------------------------------------------------------+
//| Draggable sandbox line: SELECTABLE trend segment. While the user   |
//| holds it selected the renderer never re-anchors it (no fighting    |
//| the drag); a fresh plan (or RESET_SANDBOX) re-anchors on release.  |
//+------------------------------------------------------------------+
bool UpsertDragLine(const long chart_id, const string name, const datetime t1, const datetime t2,
                    const double price, const color clr, const int width, const bool reanchor)
  {
   if(g_drawSuppressed)
      return(false);
   if(ObjectFind(chart_id, name) < 0)
     {
      if(!ObjectCreate(chart_id, name, OBJ_TREND, 0, t1, price, t2, price))
         return(false);
      ObjectSetInteger(chart_id, name, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(chart_id, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(chart_id, name, OBJPROP_RAY_RIGHT, false);
     }
   else if(reanchor && !ObjectGetInteger(chart_id, name, OBJPROP_SELECTED))
     {
      ObjectSetInteger(chart_id, name, OBJPROP_TIME,  0, (long)t1);
      ObjectSetDouble(chart_id,  name, OBJPROP_PRICE, 0, price);
      ObjectSetInteger(chart_id, name, OBJPROP_TIME,  1, (long)t2);
      ObjectSetDouble(chart_id,  name, OBJPROP_PRICE, 1, price);
     }
   ObjectSetInteger(chart_id, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(chart_id, name, OBJPROP_WIDTH, MathMax(1, width));
   ObjectSetInteger(chart_id, name, OBJPROP_STYLE, STYLE_SOLID);
   DrawnMark(name);
   return(true);
  }

void RenderSandbox(const long chart_id, const MqlRates &rates[], const int lastClosed,
                   const ENUM_TIMEFRAMES tf, const SMarketState &st)
  {
   if(!st.planOk)
     {
      g_sb.active = false;
      return;
     }
   const bool reanchor = (!g_sb.active || g_sb.planEntry != st.planEntry ||
                          g_sb.planStop != st.planStop || g_sb.planTarget != st.planTarget);
   if(reanchor)
     {
      g_sb.planEntry = st.planEntry;
      g_sb.planStop  = st.planStop;
      g_sb.planTarget= st.planTarget;
      g_sb.entry     = st.planEntry;
      g_sb.stop      = st.planStop;
      g_sb.tp        = st.planTarget;
      g_sb.active    = true;
     }
   const datetime t0 = rates[MathMax(0, lastClosed - MathMax(1, InpPlanBars))].time;
   const datetime t1 = (datetime)(rates[lastClosed].time +
                       (long)PeriodSeconds(tf) * MathMax(1, InpExtendRightBars + 4));
   const int w = MathMax(1, InpPlanWidth) + 1;
   UpsertDragLine(chart_id, OBJ_PREFIX + "SB_E", t0, t1, g_sb.entry, COL_ENTRY,  w, reanchor);
   UpsertDragLine(chart_id, OBJ_PREFIX + "SB_S", t0, t1, g_sb.stop,  COL_STOP,   w, reanchor);
   UpsertDragLine(chart_id, OBJ_PREFIX + "SB_T", t0, t1, g_sb.tp,    COL_TARGET, w, reanchor);
   if(InpShowLabels)
     {
      const int dg = (int)SymbolInfoInteger(ChartSymbol(chart_id), SYMBOL_DIGITS);
      UpsertText(chart_id, OBJ_PREFIX + "SB_EL", t1, g_sb.entry,
                 "SB ENTRY " + DoubleToString(g_sb.entry, dg), COL_ENTRY, 8, "Arial",
                 ANCHOR_LEFT_LOWER);
      UpsertText(chart_id, OBJ_PREFIX + "SB_SL", t1, g_sb.stop,
                 "SB STOP " + DoubleToString(g_sb.stop, dg), COL_STOP, 8, "Arial",
                 ANCHOR_LEFT_UPPER);
      UpsertText(chart_id, OBJ_PREFIX + "SB_TL", t1, g_sb.tp,
                 "SB TARGET " + DoubleToString(g_sb.tp, dg), COL_TARGET, 8, "Arial",
                 ANCHOR_LEFT_LOWER);
     }
  }

//+------------------------------------------------------------------+
//| Master Score 0-100: R:R (25) + fractal alignment vs the side (15)  |
//| + Monte Carlo TP% (20) + agreeing displacement (10) + CVD (10),    |
//| minus correlation divergence (5) and heat alert (15); a news       |
//| blackout scales the total to 20%. Verdict thresholds are inputs.   |
//+------------------------------------------------------------------+
int ComputeMasterScore(const SMarketState &st)
  {
   if(!st.planOk || st.atr <= 0.0)
      return(-1);
   const bool   isLong = (st.planTarget > st.planEntry);
   const double risk   = MathAbs(st.planEntry - st.planStop);
   const double rr     = (risk > 0.0) ? MathAbs(st.planTarget - st.planEntry) / risk : 0.0;
   int s = (int)MathMin(25.0, rr * 12.5);
   const int alignSide = (isLong ? g_alignScore : -g_alignScore);
   s += (int)MathRound(15.0 * (alignSide + 5) / 10.0);
   s += (int)MathRound(20.0 * MathMax(0.0, MathMin(100.0, g_mcTP)) / 100.0);
   const int dispAgree = ((g_dispLong ? 1 : -1) * (isLong ? 1 : -1));
   if(dispAgree > 0)
      s += (int)MathMin(10, g_dispGrade);
   if(g_cvdDir == (isLong ? 1 : -1))
      s += 10;
   else if(g_cvdDir == 0)
      s += 5;
   if(g_corrWarn)
      s -= 5;
   // v16.00: gate a trend-continuation plan (fractal-aligned with its own
   // side) against the regime read — fighting a RANGING chart is penalized,
   // riding a TRENDING one is rewarded. A plan the fractals disagree with
   // (alignSide <= 0) is not "continuation" and is left ungated either way.
   if(InpRegime && alignSide > 0)
     {
      if(st.regime == "RANGING")
         s -= 15;
      else if(st.regime == "TRENDING")
         s += 5;
     }
   SHeat h;
   ComputePortfolioHeat(h);
   if(h.alert)
      s -= 15;
   datetime nt;
   string   nn;
   if(NewsBlackoutActive(nt, nn))
      s = (int)(s * 0.2);
   return((int)MathMax(0.0, MathMin(100.0, s)));
  }

//+------------------------------------------------------------------+
//| v17.00 — Confluence Fusion: counts how many independent reads      |
//| already computed for this chart agree with the active plan's       |
//| direction, and turns the count into a 0-100 score + tag string.    |
//+------------------------------------------------------------------+
int ComputeConfluence(const SMarketState &st, int &confCount, string &confTags)
  {
   confCount = 0;
   confTags  = "";
   if(!st.planOk)
      return(0);
   const bool isLong = (st.planTarget > st.planEntry);
   const int  dir    = isLong ? 1 : -1;

   if(st.bullIdx >= 0 && isLong)  { confCount++; confTags += (confTags == "" ? "" : "+") + string("OB"); }
   if(st.bearIdx >= 0 && !isLong) { confCount++; confTags += (confTags == "" ? "" : "+") + string("OB"); }
   if(st.fvgCount > 0)            { confCount++; confTags += (confTags == "" ? "" : "+") + string("FVG"); }
   if(st.structCount > 0)         { confCount++; confTags += (confTags == "" ? "" : "+") + string("STRUCT"); }
   if((isLong && ArraySize(st.sslLv) > 0) || (!isLong && ArraySize(st.bslLv) > 0))
                                   { confCount++; confTags += (confTags == "" ? "" : "+") + string("LIQ"); }
   if(st.oteOk && st.oteBullish == isLong)
                                   { confCount++; confTags += (confTags == "" ? "" : "+") + string("OTE"); }
   const int alignSide = (isLong ? g_alignScore : -g_alignScore);
   if(alignSide > 0)              { confCount++; confTags += (confTags == "" ? "" : "+") + string("FRACTAL"); }
   if(!g_corrWarn && g_corrSym != "")
                                   { confCount++; confTags += (confTags == "" ? "" : "+") + string("CORR"); }
   if(g_cvdDir == dir)            { confCount++; confTags += (confTags == "" ? "" : "+") + string("CVD"); }
   if(g_mcTP >= 55.0)             { confCount++; confTags += (confTags == "" ? "" : "+") + string("MC"); }
   if(InpRegime && st.regime == "TRENDING" && alignSide > 0)
                                   { confCount++; confTags += (confTags == "" ? "" : "+") + string("REGIME"); }

   const int total = 10;
   return((int)MathRound(100.0 * confCount / total));
  }

//+------------------------------------------------------------------+
//| v18.00 — Harmonic XABCD scan. Walks the last 5 confirmed swing     |
//| points (X-A-B-C-D) drawn from the shared hi/lo swing arrays and    |
//| tests the AB/XA, BC/AB and CD/BC ratios against each pattern's     |
//| canonical Fibonacci bands (tolerance-widened). Heuristic, not a    |
//| certified harmonic scanner.                                        |
//+------------------------------------------------------------------+
bool RatioNear(const double ratio, const double target, const double tolPct)
  {
   const double tol = target * (tolPct / 100.0);
   return(ratio >= target - tol && ratio <= target + tol);
  }

bool ComputeHarmonic(const int hiIdx[], const double hiVal[], const int nHi,
                     const int loIdx[], const double loVal[], const int nLo,
                     const double tolPct, string &pattern, int &dir,
                     double &przLo, double &przHi)
  {
   pattern = ""; dir = 0; przLo = 0.0; przHi = 0.0;
   // merge the last few highs/lows chronologically into one swing series
   int    idx[]; double val[];
   int    ih = 0, il = 0;
   while(ih < nHi && il < nLo)
     {
      if(hiIdx[ih] > loIdx[il]) { ArrayResize(idx, ArraySize(idx) + 1); idx[ArraySize(idx) - 1] = hiIdx[ih]; ArrayResize(val, ArraySize(val) + 1); val[ArraySize(val) - 1] = hiVal[ih]; ih++; }
      else                      { ArrayResize(idx, ArraySize(idx) + 1); idx[ArraySize(idx) - 1] = loIdx[il]; ArrayResize(val, ArraySize(val) + 1); val[ArraySize(val) - 1] = loVal[il]; il++; }
     }
   while(ih < nHi) { ArrayResize(idx, ArraySize(idx) + 1); idx[ArraySize(idx) - 1] = hiIdx[ih]; ArrayResize(val, ArraySize(val) + 1); val[ArraySize(val) - 1] = hiVal[ih]; ih++; }
   while(il < nLo) { ArrayResize(idx, ArraySize(idx) + 1); idx[ArraySize(idx) - 1] = loIdx[il]; ArrayResize(val, ArraySize(val) + 1); val[ArraySize(val) - 1] = loVal[il]; il++; }

   const int cnt = ArraySize(idx);
   if(cnt < 5)
      return(false);
   // most recent 5 points, oldest first: X A B C D
   const double X = val[cnt - 5], A = val[cnt - 4], B = val[cnt - 3], C = val[cnt - 2], D = val[cnt - 1];
   const double legXA = MathAbs(A - X);
   const double legAB = MathAbs(B - A);
   const double legBC = MathAbs(C - B);
   const double legCD = MathAbs(D - C);
   if(legXA <= 0.0 || legAB <= 0.0 || legBC <= 0.0)
      return(false);
   const double abXa = legAB / legXA;
   const double bcAb = legBC / legAB;

   bool bullish = (X < A) && (B < A) && (C > B) && (D < C);   // D makes the lowest low = bullish reversal (long PRZ)
   bool bearish = (X > A) && (B > A) && (C < B) && (D > C);

   // canonical AB=XA retracement bands per pattern. Gartley and Crab both
   // target AB=0.618 of XA — they are told apart by the D leg, not AB: a
   // Gartley's D stays a RETRACEMENT within the XA range, while a Crab's D
   // OVERSHOOTS beyond X (its defining 1.618 XA extension). Checking AB
   // alone previously let GARTLEY (checked first) win every 0.618 match,
   // making CRAB unreachable even on genuine Crab geometry.
   string patNames[3] = {"GARTLEY", "BAT", "BUTTERFLY"};
   double patAb[3]     = {0.618, 0.50, 0.786};

   for(int i = 0; i < 3; i++)
     {
      if(!RatioNear(abXa, patAb[i], tolPct))
         continue;
      if(bcAb < 0.30 || bcAb > 0.95)     // BC must be a real retracement of AB
         continue;
      if(bullish || bearish)
        {
         pattern = patNames[i];
         if(i == 0)                     // AB=0.618: disambiguate Gartley vs Crab
           {
            const bool overshoot = bullish ? (D < X) : (D > X);
            pattern = overshoot ? "CRAB" : "GARTLEY";
           }
         dir     = bullish ? 1 : -1;
         const double przCenter = D;
         const double band      = legCD * (tolPct / 100.0) * 2.0;
         przLo = przCenter - band;
         przHi = przCenter + band;
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| v18.00 — simplified Elliott Wave read: classifies the same swing   |
//| series as an impulse leg (1-5, reported as its current leg) or a   |
//| corrective ABC, purely from alternating swing direction + length.  |
//+------------------------------------------------------------------+
void ComputeElliott(const int hiIdx[], const double hiVal[], const int nHi,
                    const int loIdx[], const double loVal[], const int nLo,
                    string &wave, int &dir)
  {
   wave = ""; dir = 0;
   int    idx[]; double val[];
   int    ih = 0, il = 0;
   while(ih < nHi && il < nLo)
     {
      if(hiIdx[ih] > loIdx[il]) { ArrayResize(idx, ArraySize(idx) + 1); idx[ArraySize(idx) - 1] = hiIdx[ih]; ArrayResize(val, ArraySize(val) + 1); val[ArraySize(val) - 1] = hiVal[ih]; ih++; }
      else                      { ArrayResize(idx, ArraySize(idx) + 1); idx[ArraySize(idx) - 1] = loIdx[il]; ArrayResize(val, ArraySize(val) + 1); val[ArraySize(val) - 1] = loVal[il]; il++; }
     }
   while(ih < nHi) { ArrayResize(idx, ArraySize(idx) + 1); idx[ArraySize(idx) - 1] = hiIdx[ih]; ArrayResize(val, ArraySize(val) + 1); val[ArraySize(val) - 1] = hiVal[ih]; ih++; }
   while(il < nLo) { ArrayResize(idx, ArraySize(idx) + 1); idx[ArraySize(idx) - 1] = loIdx[il]; ArrayResize(val, ArraySize(val) + 1); val[ArraySize(val) - 1] = loVal[il]; il++; }

   const int cnt = ArraySize(idx);
   if(cnt < 6)
      return;
   // last 6 points = 5 legs; count consecutive legs that each extend
   // beyond the previous same-direction leg (an impulse signature) vs.
   // three legs of roughly overlapping range (a corrective signature).
   int   sameDirRun = 0;
   double legs[5];
   for(int i = 0; i < 5; i++)
      legs[i] = val[cnt - 5 + i] - val[cnt - 6 + i];
   for(int i = 1; i < 5; i++)
      if(MathAbs(legs[i]) > MathAbs(legs[i - 1]) * 0.9)
         sameDirRun++;

   if(sameDirRun >= 3)
     {
      wave = "WAVE " + IntegerToString(MathMin(5, sameDirRun + 2));
      dir  = (legs[4] > 0) ? 1 : -1;
     }
   else
     {
      wave = "WAVE C";
      dir  = (legs[4] > 0) ? 1 : -1;
     }
  }

//+------------------------------------------------------------------+
//| v19.00 — yield curve spread (long-end minus short-end bond CFD)    |
//| and its inversion flag. Silently unavailable (ok=false) when the   |
//| broker doesn't carry the configured symbols.                       |
//+------------------------------------------------------------------+
bool ComputeYieldCurve(const string shortSym, const string longSym,
                       double &spread, bool &inverted)
  {
   spread = 0.0; inverted = false;
   if(shortSym == "" || longSym == "")
      return(false);
   double sp = SymbolInfoDouble(shortSym, SYMBOL_BID);
   double lp = SymbolInfoDouble(longSym, SYMBOL_BID);
   if(sp <= 0.0 || lp <= 0.0)
      return(false);
   spread   = lp - sp;
   inverted = (spread < 0.0);
   return(true);
  }

//+------------------------------------------------------------------+
//| v19.00 — intermarket lead/lag: has the lead symbol moved past      |
//| InpLeadAtrMult x its own ATR over the last few closed bars?        |
//+------------------------------------------------------------------+
bool ComputeLeadLag(const string leadSym, const double atrMult,
                    double &moveInAtr, int &dir, bool &flash)
  {
   moveInAtr = 0.0; dir = 0; flash = false;
   if(leadSym == "")
      return(false);
   MqlRates lr[];
   ResetLastError();
   int total = CopyRates(leadSym, PERIOD_CURRENT, 0, 10, lr);
   if(total < 6)
      return(false);
   const double atr = GetAtr(leadSym, PERIOD_CURRENT);
   if(atr <= 0.0)
      return(false);
   const int last = total - 2;
   const double move = lr[last].close - lr[MathMax(0, last - 3)].close;
   moveInAtr = MathAbs(move) / atr;
   dir       = (move > 0.0) ? 1 : ((move < 0.0) ? -1 : 0);
   flash     = (moveInAtr >= MathMax(0.01, atrMult));
   return(true);
  }

//+------------------------------------------------------------------+
//| v20.00 — Oracle Score: master 45% + confluence 25% + flow          |
//| sentiment 15% (CVD direction agreeing with the plan) + regime      |
//| alignment 15% (TRENDING+aligned or RANGING+countertrend = full     |
//| credit). >= InpOracleGoAt flashes PERFECT SETUP on the HUD.        |
//+------------------------------------------------------------------+
int ComputeOracleScore(const SMarketState &st, const int masterScore, const int confluence)
  {
   if(masterScore < 0 || !st.planOk)
      return(-1);
   const bool isLong    = (st.planTarget > st.planEntry);
   const int  alignSide = (isLong ? g_alignScore : -g_alignScore);
   double flow = 50.0;
   if(g_cvdDir == (isLong ? 1 : -1))
      flow = 100.0;
   else if(g_cvdDir == -(isLong ? 1 : -1))
      flow = 0.0;
   double regimeAlign = 50.0;
   if(InpRegime)
     {
      if(st.regime == "TRENDING" && alignSide > 0)
         regimeAlign = 100.0;
      else if(st.regime == "RANGING" && alignSide <= 0)
         regimeAlign = 100.0;
      else if(st.regime == "RANGING" && alignSide > 0)
         regimeAlign = 0.0;
     }
   const double score = masterScore * 0.45 + confluence * 0.25 + flow * 0.15 + regimeAlign * 0.15;
   return((int)MathMax(0.0, MathMin(100.0, MathRound(score))));
  }

//+------------------------------------------------------------------+
//| v21.00 — Local Market Profile (TPO): buckets each                  |
//| InpTpoPeriodMin-minute period of the CURRENT session into a letter |
//| and tallies which price rows it touched, from confirmed bars only. |
//| Derives the TPO Point of Control (row touched by the most distinct |
//| periods), a 70% Value Area grown outward from the POC, Single      |
//| Prints (rows touched by exactly one period) and Poor High/Low      |
//| (the session extreme was touched by 2+ periods — never firmly      |
//| rejected).                                                          |
//+------------------------------------------------------------------+
bool ComputeTPOProfile(const MqlRates &rates[], const int lastClosed, const double atr,
                       const int periodMin, double &poc, double &vah, double &val,
                       int &singlePrints, bool &poorHigh, bool &poorLow)
  {
   poc = 0.0; vah = 0.0; val = 0.0; singlePrints = 0; poorHigh = false; poorLow = false;
   if(atr <= 0.0 || periodMin < 1)
      return(false);

   MqlDateTime dtNow;
   TimeToStruct(rates[lastClosed].time, dtNow);
   dtNow.hour = 0; dtNow.min = 0; dtNow.sec = 0;
   const datetime dayStart = StructToTime(dtNow);

   int first = lastClosed;
   while(first > 0 && rates[first - 1].time >= dayStart)
      first--;
   if(lastClosed - first + 1 < 3)
      return(false);

   double sessHi = rates[first].high, sessLo = rates[first].low;
   for(int i = first; i <= lastClosed; i++)
     {
      sessHi = MathMax(sessHi, rates[i].high);
      sessLo = MathMin(sessLo, rates[i].low);
     }
   if(sessHi <= sessLo)
      return(false);

   const double rowSize = MathMax(_Point * 10.0, atr * 0.1);
   const int nRows = (int)MathMax(1.0, MathMin(400.0, (sessHi - sessLo) / rowSize + 1.0));

   int rowLastPeriod[];
   int rowPeriodCount[];
   ArrayResize(rowLastPeriod, nRows);
   ArrayResize(rowPeriodCount, nRows);
   ArrayInitialize(rowLastPeriod, -1);
   ArrayInitialize(rowPeriodCount, 0);

   for(int i = first; i <= lastClosed; i++)
     {
      const int per = (int)((long)(rates[i].time - dayStart) / (periodMin * 60));
      int r0 = (int)((rates[i].low  - sessLo) / rowSize);
      int r1 = (int)((rates[i].high - sessLo) / rowSize);
      r0 = (int)MathMax(0, MathMin(nRows - 1, r0));
      r1 = (int)MathMax(0, MathMin(nRows - 1, r1));
      for(int r = r0; r <= r1; r++)
        {
         if(rowLastPeriod[r] != per)
           {
            rowLastPeriod[r] = per;
            rowPeriodCount[r]++;
           }
        }
     }

   int total = 0, pocRow = 0, pocCount = 0;
   for(int r = 0; r < nRows; r++)
     {
      total += rowPeriodCount[r];
      if(rowPeriodCount[r] > pocCount) { pocCount = rowPeriodCount[r]; pocRow = r; }
      if(rowPeriodCount[r] == 1) singlePrints++;
     }
   if(total <= 0)
      return(false);

   poc = sessLo + (pocRow + 0.5) * rowSize;

   int lo = pocRow, hi = pocRow;
   int covered = rowPeriodCount[pocRow];
   const int target70 = (int)MathCeil(total * 0.70);
   while(covered < target70 && (lo > 0 || hi < nRows - 1))
     {
      const int belowCnt = (lo > 0) ? rowPeriodCount[lo - 1] : -1;
      const int aboveCnt = (hi < nRows - 1) ? rowPeriodCount[hi + 1] : -1;
      if(aboveCnt >= belowCnt && hi < nRows - 1) { hi++; covered += rowPeriodCount[hi]; }
      else if(lo > 0)                            { lo--; covered += rowPeriodCount[lo]; }
      else break;
     }
   val = sessLo + lo * rowSize;
   vah = sessLo + (hi + 1) * rowSize;

   poorHigh = (rowPeriodCount[nRows - 1] >= 2);
   poorLow  = (rowPeriodCount[0] >= 2);
   return(true);
  }

//+------------------------------------------------------------------+
//| v22.00 — Walk-Forward Matrix: replays the SAME displacement        |
//| signature FindOrderBlockCandidates looks for, over the last        |
//| `bars` closed bars, restricted to the CURRENT plan's direction,    |
//| then forward-simulates each historical match with the plan's own   |
//| risk/reward distances to see whether target or stop would have     |
//| been hit first. Deliberately simplified: uses TODAY's ATR/risk     |
//| distance for every historical bar (not a re-estimated historical   |
//| ATR) and a bounded forward window — a signature backtest, not a    |
//| full re-simulation, matching this kit's documented heuristics.     |
//+------------------------------------------------------------------+
void ComputeWalkForward(const MqlRates &rates[], const int lastClosed, const double atr,
                        const bool isLong, const double riskDist, const double rewardDist,
                        const int bars, double &winPct, double &expR, int &trades)
  {
   winPct = 0.0; expR = 0.0; trades = 0;
   if(atr <= 0.0 || riskDist <= 0.0 || rewardDist <= 0.0)
      return;
   const int fwdCap = 60;
   const int start  = MathMax(2, lastClosed - MathMax(20, bars));
   int wins = 0;
   for(int i = lastClosed - fwdCap - 2; i >= start; i--)
     {
      const bool sigColorOk = isLong ? (rates[i].close < rates[i].open) : (rates[i].close > rates[i].open);
      if(!sigColorOk)
         continue;
      const double bodyNext = rates[i + 1].close - rates[i + 1].open;
      const bool displaced  = isLong ? (bodyNext >= atr * InpDisplacementATR)
                                     : (-bodyNext >= atr * InpDisplacementATR);
      if(!displaced)
         continue;

      const double entry  = rates[i + 1].close;
      const double target = isLong ? entry + rewardDist : entry - rewardDist;
      const double stop   = isLong ? entry - riskDist    : entry + riskDist;
      bool hitTarget = false, hitStop = false;
      for(int f = i + 2; f <= MathMin(lastClosed, i + 2 + fwdCap); f++)
        {
         if(isLong)
           {
            if(rates[f].low  <= stop)   { hitStop = true; break; }
            if(rates[f].high >= target) { hitTarget = true; break; }
           }
         else
           {
            if(rates[f].high >= stop)   { hitStop = true; break; }
            if(rates[f].low  <= target) { hitTarget = true; break; }
           }
        }
      if(!hitTarget && !hitStop)
         continue;
      trades++;
      if(hitTarget)
         wins++;
     }
   if(trades > 0)
     {
      winPct = 100.0 * wins / trades;
      const double rr = rewardDist / riskDist;
      expR = (winPct / 100.0) * rr - (1.0 - winPct / 100.0) * 1.0;
     }
  }

//+------------------------------------------------------------------+
//| v23.00 — Z-score spread vs. the strongest correlated covered       |
//| symbol, index-aligned by bar (an approximation, not a true         |
//| time-synchronized join — consistent with this kit's "deliberately  |
//| simplified" heuristics elsewhere).                                  |
//+------------------------------------------------------------------+
bool ComputeStatArb(const MqlRates &rates[], const int lastClosed, const string corrSym,
                    const ENUM_TIMEFRAMES tf, const int bars, const double zThresh,
                    double &zScore, bool &flag)
  {
   zScore = 0.0; flag = false;
   if(corrSym == "")
      return(false);
   const int n = MathMin(bars, lastClosed);
   if(n < 20)
      return(false);
   MqlRates other[];
   if(CopyRates(corrSym, tf, 0, n + 2, other) < n + 2)
      return(false);
   const int otherLast = ArraySize(other) - 2;

   double spread[];
   ArrayResize(spread, n);
   for(int i = 0; i < n; i++)
     {
      const double a = rates[lastClosed - n + 1 + i].close;
      const double b = other[otherLast - n + 1 + i].close;
      spread[i] = a - b;
     }
   double mean = 0.0;
   for(int i = 0; i < n; i++)
      mean += spread[i];
   mean /= n;
   double sq = 0.0;
   for(int i = 0; i < n; i++)
      sq += (spread[i] - mean) * (spread[i] - mean);
   const double sd = MathSqrt(sq / n);
   if(sd <= 0.0)
      return(false);
   zScore = (spread[n - 1] - mean) / sd;
   flag   = (MathAbs(zScore) >= zThresh);
   return(true);
  }

//+------------------------------------------------------------------+
//| v24.00 — cumulative normal / normal density (Abramowitz-Stegun     |
//| approximation — MQL5 has no built-in stats library).                |
//+------------------------------------------------------------------+
double NormCDF(const double x)
  {
   const double a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741,
                a4 = -1.453152027, a5 = 1.061405429, p = 0.3275911;
   const double sign = (x < 0.0) ? -1.0 : 1.0;
   const double ax = MathAbs(x) / MathSqrt(2.0);
   const double t  = 1.0 / (1.0 + p * ax);
   const double y  = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * MathExp(-ax * ax);
   return(0.5 * (1.0 + sign * y));
  }

double NormPDF(const double x)
  {
   return(MathExp(-0.5 * x * x) / MathSqrt(2.0 * M_PI));
  }

//+------------------------------------------------------------------+
//| v24.00 — standard Black-Scholes European call/put price + vega.    |
//+------------------------------------------------------------------+
void BlackScholes(const bool isCall, const double S, const double K, const double T,
                  const double r, const double vol, double &price, double &vega)
  {
   price = 0.0; vega = 0.0;
   if(S <= 0.0 || K <= 0.0 || T <= 0.0 || vol <= 0.0)
      return;
   const double d1 = (MathLog(S / K) + (r + 0.5 * vol * vol) * T) / (vol * MathSqrt(T));
   const double d2 = d1 - vol * MathSqrt(T);
   if(isCall)
      price = S * NormCDF(d1) - K * MathExp(-r * T) * NormCDF(d2);
   else
      price = K * MathExp(-r * T) * NormCDF(-d2) - S * NormCDF(-d1);
   vega = S * NormPDF(d1) * MathSqrt(T);
  }

//+------------------------------------------------------------------+
//| v24.00 — implied volatility via Newton-Raphson (vega-guided), with |
//| a bisection fallback when vega collapses (deep ITM/OTM, near       |
//| expiry) or Newton steps out of a sane volatility range.            |
//+------------------------------------------------------------------+
double ImpliedVol(const bool isCall, const double S, const double K, const double T,
                  const double r, const double marketPrice)
  {
   if(marketPrice <= 0.0 || S <= 0.0 || K <= 0.0 || T <= 0.0)
      return(0.0);
   double vol = 0.30;
   for(int i = 0; i < 50; i++)
     {
      double price, vega;
      BlackScholes(isCall, S, K, T, r, vol, price, vega);
      if(vega < 1e-8)
         break;
      const double diff = price - marketPrice;
      if(MathAbs(diff) < 1e-5)
         return(MathMax(0.001, vol));
      vol -= diff / vega;
      if(vol <= 0.001 || vol > 5.0)
         break;
     }
   double lo = 0.001, hi = 5.0;
   for(int i = 0; i < 60; i++)
     {
      const double mid = (lo + hi) / 2.0;
      double price, vega;
      BlackScholes(isCall, S, K, T, r, mid, price, vega);
      if(price > marketPrice)
         hi = mid;
      else
         lo = mid;
     }
   return((lo + hi) / 2.0);
  }

double GammaOf(const double S, const double K, const double T, const double r, const double vol)
  {
   if(S <= 0.0 || K <= 0.0 || T <= 0.0 || vol <= 0.0)
      return(0.0);
   const double d1 = (MathLog(S / K) + (r + 0.5 * vol * vol) * T) / (vol * MathSqrt(T));
   return(NormPDF(d1) / (S * vol * MathSqrt(T)));
  }

//+------------------------------------------------------------------+
//| v24.00 — reads the two named option symbols' mid price, solves     |
//| each leg's implied vol, and reports the shared strike as the       |
//| gamma/magnet level. Silently unavailable when the broker doesn't   |
//| list the symbols — most retail forex/CFD brokers don't carry       |
//| option instruments on majors/XAUUSD at all.                        |
//+------------------------------------------------------------------+
bool ComputeOptionsGreeks(const string callSym, const string putSym, const double underlying,
                          const double strike, const datetime expiry, const double riskFreeRate,
                          double &ivCall, double &ivPut, double &gammaLevel)
  {
   ivCall = 0.0; ivPut = 0.0; gammaLevel = 0.0;
   if(callSym == "" || putSym == "" || underlying <= 0.0 || strike <= 0.0)
      return(false);
   const double callBid = SymbolInfoDouble(callSym, SYMBOL_BID);
   const double callAsk = SymbolInfoDouble(callSym, SYMBOL_ASK);
   const double putBid  = SymbolInfoDouble(putSym, SYMBOL_BID);
   const double putAsk  = SymbolInfoDouble(putSym, SYMBOL_ASK);
   if(callBid <= 0.0 || callAsk <= 0.0 || putBid <= 0.0 || putAsk <= 0.0)
      return(false);
   const datetime exp = (expiry > 0) ? expiry : (datetime)SymbolInfoInteger(callSym, SYMBOL_EXPIRATION_TIME);
   if(exp <= TimeCurrent())
      return(false);
   const double T = MathMax(1.0 / 365.0, (double)(exp - TimeCurrent()) / (365.0 * 24.0 * 3600.0));
   const double callMid = (callBid + callAsk) / 2.0;
   const double putMid  = (putBid + putAsk) / 2.0;
   ivCall = ImpliedVol(true,  underlying, strike, T, riskFreeRate, callMid);
   ivPut  = ImpliedVol(false, underlying, strike, T, riskFreeRate, putMid);
   gammaLevel = strike;   // both legs share the strike; report it as the magnet/repulsion level
   return(true);
  }

void RenderMasterScoreLabel(const long chart_id)
  {
   if(g_masterScore < 0 || StringLen(g_masterVerdict) == 0)
      return;
   const color c = (g_masterVerdict == "GO") ? COL_TARGET :
                   ((g_masterVerdict == "WAIT") ? COL_KZ_LON : COL_STOP);
   const int width = (int)ChartGetInteger(chart_id, CHART_WIDTH_IN_PIXELS, 0);
   const int x = MathMax(HUD_X, width / 2 - MASTER_HALF_W);
   UpsertLabel(chart_id, OBJ_PREFIX + "HUD_MASTER", x, MASTER_Y,
               g_masterVerdict + " " + IntegerToString(g_masterScore),
               c, MASTER_FONT, "Arial Black", CORNER_LEFT_UPPER);
  }

//+------------------------------------------------------------------+
//| v20.00 — Oracle Score HUD line, below the Master Score verdict.    |
//| >= InpOracleGoAt flashes "PERFECT SETUP" instead of the plain      |
//| number so it reads as an event, not just another metric.           |
//+------------------------------------------------------------------+
void RenderOracleLabel(const long chart_id)
  {
   if(g_oracleScore < 0)
      return;
   const color c = g_oraclePerfect ? COL_TARGET :
                   ((g_oracleScore >= 50) ? COL_KZ_LON : COL_STOP);
   const int width = (int)ChartGetInteger(chart_id, CHART_WIDTH_IN_PIXELS, 0);
   const int x = MathMax(HUD_X, width / 2 - ORACLE_HALF_W);
   const string txt = g_oraclePerfect ? "PERFECT SETUP " + IntegerToString(g_oracleScore) :
                      "ORACLE " + IntegerToString(g_oracleScore);
   UpsertLabel(chart_id, OBJ_PREFIX + "HUD_ORACLE", x, ORACLE_Y,
               txt, c, ORACLE_FONT, "Arial Bold", CORNER_LEFT_UPPER);
  }

//+------------------------------------------------------------------+
//| Zenith HUD block (below the v4 co-pilot lines): muted flag, tuner  |
//| suggestions, fractal alignment matrix, Monte Carlo read, correla-  |
//| tion watch. Also refreshes the shared metric bus for this chart.   |
//+------------------------------------------------------------------+
int RenderZenithHUD(const long chart_id, const string sym, const ENUM_TIMEFRAMES tf,
                    const SMarketState &st, const bool setupMuted)
  {
   int y = HUD_Y + ZEN_HUD_Y_OFF;
   // v15.02: setupMuted is THIS chart's own self-heal read, passed in by the
   // caller — g_setupMuted is the ATTACH chart's shared flag and previously
   // leaked "SETUP MUTED" onto every other covered chart's HUD too.
   if(InpSelfHeal && setupMuted)
     {
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_MUTED", HUD_X, y,
                  "SETUP MUTED (self-heal)", COL_STOP, HUD_FONT_ALERT, "Arial Bold",
                  CORNER_LEFT_UPPER);
      y += HUD_LINE_H + 4;
     }
   if(InpTunerFile && ArraySize(g_tunerKeys) > 0)
     {
      string joined = "";
      for(int i = 0; i < ArraySize(g_tunerKeys); i++)
         joined += (i == 0 ? "" : " · ") + g_tunerKeys[i] + "=" + g_tunerVals[i];
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_TUNER", HUD_X, y, "TUNER " + joined,
                  COL_KZ_LON, HUD_FONT, "Arial", CORNER_LEFT_UPPER);
      y += HUD_LINE_H;
     }
   if(InpFractalAlign)
     {
      ENUM_TIMEFRAMES tfs[ALIGN_TFS_TOTAL] = {PERIOD_M1, PERIOD_M5, PERIOD_M15,
                                              PERIOD_H1, PERIOD_H4};
      int    score  = 0;
      string detail = "";
      for(int k = 0; k < ALIGN_TFS_TOTAL; k++)
        {
         const int s1 = TrendScoreTF(sym, tfs[k]);
         score  += s1;
         detail += (k == 0 ? "" : " ") + TFLabel(tfs[k]) +
                   (s1 > 0 ? "+" : (s1 < 0 ? "-" : "0"));
        }
      g_alignScore  = score;
      g_alignDetail = detail;
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_ALIGN", HUD_X, y,
                  "ALIGN " + IntegerToString(score) + "/5 · " + detail,
                  (score > 0 ? COL_TARGET : (score < 0 ? COL_STOP : COL_LIQ)),
                  HUD_FONT, "Arial", CORNER_LEFT_UPPER);
      y += HUD_LINE_H;
     }
   if(InpMonteCarlo && st.planOk)
     {
      MonteCarloEvaluate(st.planEntry, st.planStop, st.planTarget, st.atr,
                         InpMCRuns, InpMCBars);
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_MC", HUD_X, y,
                  "MC TP " + DoubleToString(g_mcTP, 0) + "% · SL " +
                  DoubleToString(g_mcSL, 0) + "% (" +
                  IntegerToString((int)MathMax(100, MathMin(MC_MAX_RUNS, InpMCRuns))) + ")",
                  COL_EQ, HUD_FONT, "Arial", CORNER_LEFT_UPPER);
      y += HUD_LINE_H;
     }
   else
     {
      g_mcTP = 0.0;
      g_mcSL = 0.0;
     }
   if(InpCorrelation)
     {
      RenderCorrelation(chart_id, sym, tf, y, st);
      y += HUD_LINE_H;
     }
   if(InpTradeStats && chart_id == ChartID() && g_statsTrades > 0)
     {
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_STATS", HUD_X, y,
                  "STATS " + DoubleToString(g_statsWinPct, 0) + "% WIN · " +
                  DoubleToString(g_statsExpR, 2) + "R EXP (" +
                  IntegerToString(g_statsTrades) + ")",
                  (g_statsExpR >= 0.0 ? COL_TARGET : COL_STOP), HUD_FONT, "Arial",
                  CORNER_LEFT_UPPER);
      y += HUD_LINE_H;
     }
   if(InpVolRegime && st.volRegime != "")
     {
      const color vc = (st.volRegime == "HIGH") ? COL_KZ_LON :
                       (st.volRegime == "LOW" ? COL_LIQ : COL_TARGET);
      string txt = "VOL " + st.volRegime + " (" + DoubleToString(st.volRatio, 1) + "x)";
      if(st.volRegime == "HIGH" && st.suggestedRiskPct > 0.0)
         txt += " · suggested risk " + DoubleToString(st.suggestedRiskPct, 2) + "%";
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_VOL", HUD_X, y, txt, vc, HUD_FONT, "Arial",
                  CORNER_LEFT_UPPER);
      y += HUD_LINE_H;
     }
   if(InpSessionCountdown)
     {
      string nextLbl = "";
      ComputeSessionCountdown(nextLbl);
      if(nextLbl != "")
        {
         UpsertLabel(chart_id, OBJ_PREFIX + "HUD_NEXT", HUD_X, y, nextLbl, COL_LIQ,
                     HUD_FONT, "Arial", CORNER_LEFT_UPPER);
         y += HUD_LINE_H;
        }
     }
   // v21.00: local TPO market profile
   if(InpTpoProfile && st.tpoOk)
     {
      const int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      string txt = "TPO POC " + DoubleToString(st.tpoPoc, dg) + " · VA " +
                   DoubleToString(st.tpoVal, dg) + "-" + DoubleToString(st.tpoVah, dg) +
                   " · " + IntegerToString(st.tpoSinglePrints) + " single prints";
      if(st.tpoPoorHigh)
         txt += " · POOR HIGH";
      if(st.tpoPoorLow)
         txt += " · POOR LOW";
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_TPO", HUD_X, y, txt, COL_EQ,
                  HUD_FONT, "Arial", CORNER_LEFT_UPPER);
      y += HUD_LINE_H;
     }
   // v22.00: walk-forward matrix — the CURRENT setup's own historical track record
   if(InpWalkForward && st.wfTrades > 0)
     {
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_WF", HUD_X, y,
                  "WF " + DoubleToString(st.wfWinPct, 0) + "% WR · " +
                  (st.wfExpectancyR >= 0.0 ? "+" : "") + DoubleToString(st.wfExpectancyR, 2) +
                  "R · n=" + IntegerToString(st.wfTrades),
                  (st.wfExpectancyR >= 0.0 ? COL_TARGET : COL_STOP), HUD_FONT, "Arial",
                  CORNER_LEFT_UPPER);
      y += HUD_LINE_H;
     }
   // v23.00: statistical arbitrage — Z-score spread vs. the strongest correlated symbol
   if(InpStatArb && st.statArbSym != "")
     {
      const color zc = st.statArbFlag ? COL_KZ_LON : COL_LIQ;
      string txt = "Z " + DoubleToString(st.statArbZ, 2) + " vs " + st.statArbSym;
      if(st.statArbFlag)
         txt += " · STAT ARB OPPORTUNITY";
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_STATARB", HUD_X, y, txt, zc, HUD_FONT,
                  st.statArbFlag ? "Arial Bold" : "Arial", CORNER_LEFT_UPPER);
      y += HUD_LINE_H;
     }
   // v24.00: options Greeks / implied volatility
   if(InpOptionsGreeks && st.optOk)
     {
      UpsertLabel(chart_id, OBJ_PREFIX + "HUD_OPT", HUD_X, y,
                  "IV C " + DoubleToString(st.ivCall * 100.0, 1) + "% / P " +
                  DoubleToString(st.ivPut * 100.0, 1) + "% · GAMMA " +
                  DoubleToString(st.gammaLevel, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
                  COL_EQ, HUD_FONT, "Arial", CORNER_LEFT_UPPER);
      y += HUD_LINE_H;
     }
   return(y);
  }

/* ================================================================== */
/* v15.00 COCKPIT SUMMARY — cross-chart leaderboard + session countdown */
/* ================================================================== */
int LeaderIndex(const string key, const bool create)
  {
   for(int i = 0; i < ArraySize(g_leader); i++)
      if(g_leader[i].key == key)
         return(i);
   if(!create)
      return(-1);
   const int at = ArraySize(g_leader);
   ArrayResize(g_leader, at + 1, ARRAY_RESERVE_CHUNK);
   g_leader[at].key     = key;
   g_leader[at].label   = key;
   g_leader[at].score   = -1;
   g_leader[at].verdict = "";
   return(at);
  }

void UpdateLeaderboard(const string sym, const ENUM_TIMEFRAMES tf, const int score, const string verdict)
  {
   const string tfLabel = TFLabel(tf);
   const int    at      = LeaderIndex(sym + "|" + tfLabel, true);
   g_leader[at].label   = sym + " " + tfLabel;
   g_leader[at].score   = score;
   g_leader[at].verdict = verdict;
  }

//+------------------------------------------------------------------+
//| Drop leaderboard rows for chart/timeframe pairs no longer covered   |
//| by any open chart (a closed chart's last score would otherwise      |
//| linger forever).                                                     |
//+------------------------------------------------------------------+
void PruneLeaderboard()
  {
   int kept  = 0;
   int total = ArraySize(g_leader);
   for(int i = 0; i < total; i++)
     {
      bool alive = false;
      for(int c = 0; c < ArraySize(g_charts); c++)
        {
         const long cid = g_charts[c].chart_id;
         if(ChartSymbol(cid) + "|" + TFLabel((ENUM_TIMEFRAMES)ChartPeriod(cid)) == g_leader[i].key)
           {
            alive = true;
            break;
           }
        }
      if(alive)
        {
         if(kept != i)
            g_leader[kept] = g_leader[i];
         kept++;
        }
     }
   if(kept != total)
      ArrayResize(g_leader, kept);
  }

//+------------------------------------------------------------------+
//| Draw the top InpLeaderboardRows rows (by Master Score, descending)  |
//| as a compact HUD block. Returns the number of lines drawn so the    |
//| caller can advance its own y cursor.                                 |
//+------------------------------------------------------------------+
int RenderLeaderboard(const long chart_id, const int y0)
  {
   const int n = ArraySize(g_leader);
   if(n == 0)
      return(0);

   SLeaderRow sorted[];
   ArrayResize(sorted, n);
   for(int i = 0; i < n; i++)
      sorted[i] = g_leader[i];
   for(int a = 0; a < n - 1; a++)
      for(int b = 0; b < n - 1 - a; b++)
         if(sorted[b + 1].score > sorted[b].score)
           {
            SLeaderRow tmp = sorted[b];
            sorted[b]      = sorted[b + 1];
            sorted[b + 1]  = tmp;
           }

   const int rows = MathMin(n, MathMax(1, InpLeaderboardRows));
   string joined = "LEADER ";
   for(int i = 0; i < rows; i++)
     {
      const color c = (sorted[i].verdict == "GO") ? COL_TARGET :
                      (sorted[i].verdict == "WAIT" ? COL_KZ_LON : COL_LIQ);
      joined += (i == 0 ? "" : "  ") + IntegerToString(i + 1) + "." + sorted[i].label + " " +
               (sorted[i].score >= 0 ? IntegerToString(sorted[i].score) : "-");
     }
   UpsertLabel(chart_id, OBJ_PREFIX + "HUD_LEADER", HUD_X, y0, joined, COL_LIQ,
               LEADERBOARD_FONT, "Arial", CORNER_LEFT_UPPER);
   return(1);
  }

//+------------------------------------------------------------------+
//| Nearest killzone transition (an open or a close) from server time,  |
//| independent of whether killzone shading itself is enabled.          |
//+------------------------------------------------------------------+
void ComputeSessionCountdown(string &label)
  {
   label = "";
   const datetime now = TimeTradeServer();
   if(now <= 0)
      return;
   MqlDateTime dtNow;
   TimeToStruct(now, dtNow);
   const datetime dayStart = now - (dtNow.hour * 3600 + dtNow.min * 60 + dtNow.sec);

   string names[3]  = {"ASIA", "LONDON", "NY"};
   int    starts[3] = {InpKZAsiaStart, InpKZLondonStart, InpKZNewYorkStart};
   int    lens[3]   = {MathMax(1, InpKZLengthHours) * 2, MathMax(1, InpKZLengthHours),
                       MathMax(1, InpKZLengthHours)};

   datetime bestTime = 0;
   string   bestLabel = "";
   for(int i = 0; i < 3; i++)
     {
      // A session whose window crosses midnight (e.g. start 23, length 3)
      // opened YESTERDAY and may still be active right now — check that
      // window first, since the today-anchored one below would otherwise
      // report it as "opens in 22h" instead of "closes in 1h".
      const datetime sPrev = dayStart - 86400 + (long)MathMax(0, starts[i]) * 3600;
      const datetime ePrev = sPrev + (long)lens[i] * 3600;
      datetime s, e;
      if(now >= sPrev && now < ePrev)
        {
         s = sPrev;
         e = ePrev;
        }
      else
        {
         s = dayStart + (long)MathMax(0, starts[i]) * 3600;
         e = s + (long)lens[i] * 3600;
         while(e <= now)          // roll forward until this session's window is ahead of now
           {
            s += 86400;
            e += 86400;
           }
        }
      datetime candTime; string candLabel;
      if(now < s)
        {
         candTime  = s;
         candLabel = names[i] + " opens in ";
        }
      else
        {
         candTime  = e;
         candLabel = names[i] + " closes in ";
        }
      if(bestTime == 0 || candTime < bestTime)
        {
         bestTime  = candTime;
         bestLabel = candLabel;
        }
     }
   if(bestTime == 0)
      return;
   const long remain = (long)(bestTime - now);
   const int  hh = (int)(remain / 3600);
   const int  mm = (int)((remain % 3600) / 60);
   label = "NEXT: " + bestLabel + (hh > 0 ? IntegerToString(hh) + "h" : "") + IntegerToString(mm) + "m";
  }

/* ================================================================== */
/*  WEB BRIDGE — MATRIX PUSH + REMOTE CONTROL (v4.00)                  */
/*                                                                     */
/*  Streams the ATTACH chart's live trade plan (the gold ENTRY /       */
/*  red STOP / green TARGET levels — colors are inputs) to a local     */
/*  HTTP bridge so a web dashboard can display it. v2.07 reads the     */
/*  plan from the g_plan SMarketState cache — NOT from chart objects — */
/*  so the push works with the chart hidden and does not depend on     */
/*  the renderer at all. Levels come from CONFIRMED bars only —        */
/*  non-repainting.                                                    */
/*                                                                     */
/*  One-time MT5 setup (otherwise WebRequest fails with an error):     */
/*    Tools -> Options -> Expert Advisors ->                           */
/*    tick "Allow WebRequest for listed URL" and add the host,         */
/*    e.g.  http://127.0.0.1:8891                                      */
/*                                                                     */
/*  v4.00 TWO-WAY: right after every accepted push the EA also GETs    */
/*  /v1/poll?slot=SYMBOL|TF from the same host. The bridge answers     */
/*  with pending commands, one per line: "CMD <id> <action> <value>".  */
/* Whitelist: SET_RISK (risk %), TOGGLE_ZONES (0/1), SET_RENDER       */
/*  (0/1), TOGGLE_SANDBOX (0/1), RESET_SANDBOX, PING. Commands write  */
/*  the g_ov runtime mirrors — inputs stay read-only — so the local   */
/*  dashboard can drive the EA live. v10.00: every accepted push also */
/*  rewrites MQL5\Files\PAICT_matrix_snapshot.json (mailbox IPC — the */
/*  dashboard/tuner can read the file with ZERO HTTP round-trips).    */
/*  v11.00: the payload additionally carries the OTE pocket and the   */
/*  daily/weekly open levels — additive keys, older dashboards ignore */
/*  what they do not recognize.                                       */
/* ================================================================== */

//+------------------------------------------------------------------+
//| JSON string escaping (quotes + backslashes)                       |
//+------------------------------------------------------------------+
string BridgeJsonEscape(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   return(s);
  }

//+------------------------------------------------------------------+
//| Human timeframe label, e.g. "M5" instead of "PERIOD_M5"           |
//+------------------------------------------------------------------+
string BridgeTimeframeLabel()
  {
   string s = EnumToString((ENUM_TIMEFRAMES)_Period);
   StringReplace(s, "PERIOD_", "");
   return(s);
  }

//+------------------------------------------------------------------+
//| Inject the wall-clock time at PUSH moment. The dedupe key must    |
//| stay time-free, or every build differs and the throttle never     |
//| engages (v2.01 pushed on every refresh tick because of this).     |
//+------------------------------------------------------------------+
string BridgeWithTime(const string core)
  {
   string t = TimeToString(TimeGMT(), TIME_DATE|TIME_SECONDS);
   return(StringSubstr(core, 0, StringLen(core) - 1) +
          ",\"time\":\"" + t + " GMT\"}");
  }

//+------------------------------------------------------------------+
//| v4.00 co-pilot fields appended to EVERY matrix payload (additive — |
//| older dashboards simply ignore unknown keys):                      |
//|   riskPct / riskLots  simulated sizing for the current plan        |
//|   heatPct / heatAlert portfolio heat across open manual trades     |
//|   newsBlackout / newsEvent  economic-calendar blackout state       |
//| Heat + news are computed live here (account-level, chart-free) so  |
//| they stay fresh between bars; the push dedupe picks the changes up |
//| automatically.                                                     |
//+------------------------------------------------------------------+
void AppendCopilotJSON(CJsonWriter &w, const double entry, const double stop)
  {
   if(InpRiskHUD && g_plan.ok)
     {
      const double lots = ComputeRiskLots(_Symbol, entry, stop, g_ov.riskPct);
      if(lots > 0.0)
        {
         w.AddNum("riskPct", g_ov.riskPct, 2);
         w.AddNum("riskLots", lots, 2);
        }
     }
   if(InpHeatTracker)
     {
      SHeat h;
      ComputePortfolioHeat(h);
      w.AddNum("heatPct", h.pct, 2);
      w.AddRaw("heatAlert", h.alert ? "true" : "false");
     }
   datetime nt   = 0;
   string   nname = "";
   const bool blackout = NewsBlackoutActive(nt, nname);
   w.AddRaw("newsBlackout", blackout ? "true" : "false");
   if(blackout)
      w.Add("newsEvent", nname);
  }

//+------------------------------------------------------------------+
//| v10.00 zenith fields appended to EVERY matrix payload (additive —  |
//| older dashboards ignore unknown keys). Reads the attach chart's    |
//| metric-bus snapshot taken in DrawOnChart: alignment, Monte Carlo,  |
//| CVD, displacement, correlation, volume profile, tuner suggestions, |
//| self-heal mute, sandbox levels and the Master Score verdict.       |
//| v11.00: also the OTE pocket + daily/weekly open reference levels.  |
//+------------------------------------------------------------------+
void AppendZenithJSON(CJsonWriter &w)
  {
   w.AddNum("alignScore", g_zen.align, 0);
   if(g_zen.mcTP > 0.0 || g_zen.mcSL > 0.0)
     {
      w.AddNum("mcTP", g_zen.mcTP, 0);
      w.AddNum("mcSL", g_zen.mcSL, 0);
     }
   w.AddNum("cvdDir", g_zen.cvdDir, 0);
   if(g_zen.cvdDiv)
      w.AddRaw("cvdDiv", "true");
   if(g_zen.disp > 0)
      w.AddNum("displacement", g_zen.disp, 0);
   if(g_zen.corrSym != "")
     {
      w.Add("corrSym", g_zen.corrSym);
      w.AddNum("corrR", g_zen.corrR, 2);
      if(g_zen.corrWarn)
         w.AddRaw("corrWarn", "true");
     }
   if(g_zen.poc > 0.0)
     {
      w.AddNum("poc", g_zen.poc, _Digits);
      w.AddNum("vah", g_zen.vah, _Digits);
      w.AddNum("val", g_zen.val, _Digits);
     }
   w.AddRaw("setupMuted", g_zen.muted ? "true" : "false");
   if(g_zen.master >= 0)
     {
      w.AddNum("masterScore", g_zen.master, 0);
      w.Add("masterVerdict", g_zen.verdict);
     }
   if(g_zen.sbActive)
     {
      w.AddNum("sbEntry", g_zen.sbE, _Digits);
      w.AddNum("sbStop", g_zen.sbS, _Digits);
      w.AddNum("sbTP", g_zen.sbT, _Digits);
      w.AddRaw("sbActive", "true");
     }
   if(g_zen.oteOk)
     {
      w.AddNum("oteLow", g_zen.oteLow, _Digits);
      w.AddNum("oteHigh", g_zen.oteHigh, _Digits);
      w.AddRaw("oteBullish", g_zen.oteBullish ? "true" : "false");
     }
   if(g_zen.dOpen > 0.0)
      w.AddNum("dOpen", g_zen.dOpen, _Digits);
   if(g_zen.wOpen > 0.0)
      w.AddNum("wOpen", g_zen.wOpen, _Digits);
   if(g_zen.planShiftWarn)
      w.AddRaw("planShiftWarn", "true");
   if(g_zen.volRegime != "")
     {
      w.Add("volRegime", g_zen.volRegime);
      if(g_zen.suggestedRiskPct > 0.0)
         w.AddNum("suggestedRiskPct", g_zen.suggestedRiskPct, 2);
     }
   if(g_zen.statsTrades > 0)
     {
      w.AddNum("statsWinPct", g_zen.statsWinPct, 1);
      w.AddNum("statsExpectancyR", g_zen.statsExpectancyR, 2);
      w.AddNum("statsTrades", g_zen.statsTrades, 0);
     }
   // v16.00: regime + volatility contraction
   if(g_zen.regime != "")
     {
      w.Add("regime", g_zen.regime);
      w.AddNum("hurst", g_zen.hurst, 2);
      w.AddNum("ker", g_zen.ker, 2);
     }
   if(g_zen.vcvSqueeze > 0.0)
     {
      w.AddNum("vcvSqueeze", g_zen.vcvSqueeze, 2);
      if(g_zen.vcvCone)
         w.AddRaw("vcvCone", "true");
     }
   // v17.00: confluence fusion
   if(g_zen.confCount > 0 || g_zen.confluence > 0)
     {
      w.AddNum("confluence", g_zen.confluence, 0);
      w.AddNum("confCount", g_zen.confCount, 0);
      w.Add("confTags", g_zen.confTags);
     }
   // v18.00: harmonic pattern + Elliott wave
   if(g_zen.harmonic != "")
     {
      w.Add("harmonic", g_zen.harmonic);
      w.AddNum("harmDir", g_zen.harmDir, 0);
      w.AddNum("przLo", g_zen.przLo, _Digits);
      w.AddNum("przHi", g_zen.przHi, _Digits);
     }
   if(g_zen.elliott != "")
     {
      w.Add("elliott", g_zen.elliott);
      w.AddNum("ewDir", g_zen.ewDir, 0);
     }
   // v19.00: macro crosscurrents
   if(g_zen.ycOk)
     {
      w.AddNum("ycSpread", g_zen.ycSpread, 5);
      w.AddRaw("ycInverted", g_zen.ycInverted ? "true" : "false");
     }
   if(g_zen.leadSym != "")
     {
      w.Add("leadSym", g_zen.leadSym);
      w.AddNum("leadMove", g_zen.leadMove, 2);
      w.AddNum("leadDir", g_zen.leadDir, 0);
      w.AddRaw("leadFlash", g_zen.leadFlash ? "true" : "false");
     }
   // v20.00: Oracle Score
   if(g_zen.oracleScore >= 0)
      w.AddNum("oracleScore", g_zen.oracleScore, 0);
   // v21.00: local TPO market profile
   if(g_zen.tpoOk)
     {
      w.AddNum("tpoPoc", g_zen.tpoPoc, _Digits);
      w.AddNum("tpoVah", g_zen.tpoVah, _Digits);
      w.AddNum("tpoVal", g_zen.tpoVal, _Digits);
      w.AddNum("tpoSinglePrints", g_zen.tpoSinglePrints, 0);
      if(g_zen.tpoPoorHigh)
         w.AddRaw("tpoPoorHigh", "true");
      if(g_zen.tpoPoorLow)
         w.AddRaw("tpoPoorLow", "true");
     }
   // v22.00: walk-forward matrix
   if(g_zen.wfTrades > 0)
     {
      w.AddNum("wfWinPct", g_zen.wfWinPct, 1);
      w.AddNum("wfExpectancyR", g_zen.wfExpectancyR, 2);
      w.AddNum("wfTrades", g_zen.wfTrades, 0);
     }
   // v23.00: statistical arbitrage
   if(g_zen.statArbSym != "")
     {
      w.AddNum("statArbZ", g_zen.statArbZ, 2);
      w.Add("statArbSym", g_zen.statArbSym);
      if(g_zen.statArbFlag)
         w.AddRaw("statArbFlag", "true");
     }
   // v24.00: options Greeks / implied volatility
   if(g_zen.optOk)
     {
      w.AddNum("ivCall", g_zen.ivCall, 4);
      w.AddNum("ivPut", g_zen.ivPut, 4);
      w.AddNum("gammaLevel", g_zen.gammaLevel, _Digits);
     }
   if(ArraySize(g_journalNotes) > 0)
     {
      string nb = "[";
      for(int i = 0; i < ArraySize(g_journalNotes); i++)
        {
         if(i > 0)
            nb += ",";
         nb += "{\"time\":\"" + BridgeJsonEscape(g_journalNotes[i].timeStr) + "\",\"price\":" +
               DoubleToString(g_journalNotes[i].price, _Digits) + ",\"text\":\"" +
               BridgeJsonEscape(g_journalNotes[i].text) + "\"}";
        }
      nb += "]";
      w.AddRaw("notes", nb);
     }
   if(ArraySize(g_leader) > 0)
     {
      string lb = "[";
      for(int i = 0; i < ArraySize(g_leader); i++)
        {
         if(i > 0)
            lb += ",";
         lb += "{\"chart\":\"" + BridgeJsonEscape(g_leader[i].label) + "\",\"score\":" +
               IntegerToString(g_leader[i].score) + ",\"verdict\":\"" +
               BridgeJsonEscape(g_leader[i].verdict) + "\"}";
        }
      lb += "]";
      w.AddRaw("leaderboard", lb);
     }
   string nextSession = "";
   ComputeSessionCountdown(nextSession);
   if(nextSession != "")
      w.Add("nextSession", nextSession);
   if(ArraySize(g_tunerKeys) > 0)
     {
      string joined = "";
      for(int i = 0; i < ArraySize(g_tunerKeys); i++)
         joined += (i == 0 ? "" : "; ") + g_tunerKeys[i] + "=" + g_tunerVals[i];
      w.Add("tuner", joined);
     }
  }

//+------------------------------------------------------------------+
//| Build the matrix payload from the ATTACH chart's plan cache.       |
//| v2.07: reads g_plan (state-driven MVC) instead of scraping         |
//| OBJPROP_PRICE off the drawn plan lines — works with charts hidden. |
//| Returns "" while the trade plan has not formed yet.                |
//+------------------------------------------------------------------+
string MatrixBuildJSON()
  {
   if(!g_plan.ok)
      return("");

   double entry = g_plan.entry;
   double stop  = g_plan.stop;
   double tp    = g_plan.target;
   if(entry <= 0.0 || stop <= 0.0 || tp <= 0.0)
      return("");

   double risk = MathAbs(entry - stop);
   if(risk <= 0.0)
      return("");
   double rr   = MathAbs(tp - entry) / risk;
   string side = (tp > entry) ? "long" : "short";   // target above entry = long setup

   CJsonWriter w;
   w.Add("symbol", _Symbol);
   w.Add("timeframe", BridgeTimeframeLabel());
   w.Add("side", side);
   w.AddNum("entry", entry, _Digits);
   w.AddNum("sl", stop, _Digits);
   w.AddNum("tp", tp, _Digits);
   w.AddNum("rr", rr, 2);
   w.Add("status", "live");
   AppendCopilotJSON(w, entry, stop);
   AppendZenithJSON(w);
   return(w.Build());
  }

//+------------------------------------------------------------------+
//| Heartbeat payload used until the trade plan has formed            |
//+------------------------------------------------------------------+
string MatrixHeartbeatJSON()
  {
   CJsonWriter w;
   w.Add("symbol", _Symbol);
   w.Add("timeframe", BridgeTimeframeLabel());
   w.AddNum("entry", 0.0, _Digits);
   w.AddNum("sl", 0.0, _Digits);
   w.AddNum("tp", 0.0, _Digits);
   w.AddNum("rr", 0.0, 2);
   w.Add("status", "awaiting_plan");
   AppendCopilotJSON(w, 0.0, 0.0);
   AppendZenithJSON(w);
   return(w.Build());
  }

//+------------------------------------------------------------------+
//| Hex dump of the first N array bytes (v2.04 bridge forensics)      |
//+------------------------------------------------------------------+
string BridgeHexHead(const char &arr[], int maxBytes)
  {
   int    total = ArraySize(arr);
   int    n     = MathMin(maxBytes, total);
   string out   = "";
   for(int i = 0; i < n; i++)
      out += StringFormat("%02X ", (uchar)arr[i]);
   if(total > n)
      out += "...";
   return(out);
  }

//+------------------------------------------------------------------+
//| POST the current matrix to the bridge (deduped + throttled)       |
//| - fires when the payload changes, on every closed bar of the       |
//|   attach chart, plus a 30 s heartbeat                              |
//| - failures retry at most every 30 s (re-attach for an instant try) |
//+------------------------------------------------------------------+
void PushMatrixToBridge()
  {
   if(!InpBridgeEnabled)
      return;

   string core = MatrixBuildJSON();
   if(core == "")
      core = MatrixHeartbeatJSON();      // EA is alive, plan not ready yet

   bool changed = (core != g_bridgeLastJSON);
   bool newbar  = (iTime(_Symbol, _Period, 0) != g_bridgeLastBar);
   bool due     = (TimeCurrent() - g_bridgeLastTry >= BRIDGE_HEARTBEAT_SEC);
   if(!changed && !newbar && !due)
      return;

   g_bridgeLastJSON = core;
   g_bridgeLastTry  = TimeCurrent();
   g_bridgeLastBar  = iTime(_Symbol, _Period, 0);

   string json = BridgeWithTime(core);    // time injected only now (v2.02)

   // v10.00 mailbox IPC: the exact same payload lands in
   // MQL5\Files\PAICT_matrix_snapshot.json — local readers (dashboard,
   // tuner) consume it with zero HTTP round-trips.
   if(InpMailboxIPC)
     {
      const int fh = FileOpen("PAICT_matrix_snapshot.json",
                              FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(fh != INVALID_HANDLE)
        {
         FileWriteString(fh, json);
         FileClose(fh);
        }
     }

   char   post[];
   char   result[];
   string resultHeaders = "";
   string headers       = "Content-Type: application/json\r\n";

   // v2.01 BUG: passing StringLen(json) as count made the function treat it
   // as "array elements including the terminal 0", so the LAST character of
   // the JSON (the closing brace) was dropped — body-parser then failed with
   // entity.parse.failed. The default count (-1) copies the whole string
   // plus the terminator; the resize below strips ONLY the terminator.
   StringToCharArray(json, post);
   ArrayResize(post, ArraySize(post) - 1);

   int res = WebRequest("POST", InpBridgeURL, headers, InpBridgeTimeoutMs,
                        post, result, resultHeaders);
   if(res == -1)
     {
      Print("Matrix Bridge: WebRequest failed. Error ", GetLastError(),
            " - whitelist '", InpBridgeURL,
            "' under Tools -> Options -> Expert Advisors -> Allow WebRequest.");
      return;
     }
   // v15.01 correction: the 7-argument WebRequest() (method, url, headers,
   // timeout, data[], result[], result_headers) returns the actual HTTP
   // status code, not a body-byte count — the v2.03 "res is bytes, parse
   // resultHeaders instead" theory was wrong, and it made ok2xx depend on
   // resultHeaders starting with "HTTP/", which is not guaranteed even on
   // a perfectly healthy 200 response, silently skipping PollRemoteCommands
   // on every push. `res` is now the source of truth; resultHeaders is
   // parsed only for the human-readable status line in the log/forensics.
   const bool ok2xx = (res >= 200 && res <= 299);
   string statusLine = "";
   if(StringFind(resultHeaders, "HTTP/") == 0)
     {
      const int sp = StringFind(resultHeaders, "\r\n");
      statusLine = (sp >= 0) ? StringSubstr(resultHeaders, 0, sp) : resultHeaders;
     }
   else
      statusLine = "HTTP " + IntegerToString(res);
   if(ok2xx && InpRemoteControl)
      PollRemoteCommands();   // v4.00 two-way: collect + apply bridge commands
   if(InpBridgeVerbose || !ok2xx)
      Print("Matrix Bridge: pushed ", ArraySize(post), " bytes, reply ",
            ArraySize(result), " bytes <- ", statusLine,
            " (", _Symbol, " ", BridgeTimeframeLabel(), ")");
   if(!ok2xx)   // non-2xx: show WHAT the server actually said
     {
      string body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      StringReplace(body, "\r", " ");
      StringReplace(body, "\n", " ");
      if(StringLen(body) > BRIDGE_BODY_SNIP)
         body = StringSubstr(body, 0, BRIDGE_BODY_SNIP) + " ...";
      Print("Matrix Bridge: reply body: ", body);
      // v2.04 forensics: empty body / missing status line = the reply is
      // not normal HTTP text. Dump raw sizes + bytes so the responder
      // (binary protocol, compressed page, port squatter) identifies
      // itself in one journal line.
      Print("Matrix Bridge: forensics: bodyBytes=", ArraySize(result),
            ", hdr[0..", BRIDGE_HDR_SNIP, "]=\"", StringSubstr(resultHeaders, 0, BRIDGE_HDR_SNIP),
            "\", body[0..", BRIDGE_HEX_SNIP, " hex]=", BridgeHexHead(result, BRIDGE_HEX_SNIP));
     }
  }
