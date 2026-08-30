/**
 * mt5-bridge dashboard v7 — THE MULTI-MONITOR COCKPIT (EA v15.00 payload)
 *
 * Drop-in React page for the trade plans the EA pushes to the Node bridge
 * (server v6). Live via WebSocket (ws://127.0.0.1:8891/ — pushed on every
 * EA push) with a 3 s HTTP polling fallback (GET /v1/matrix).
 *
 * v7 changes (Multi-Monitor Cockpit + Oracle engines, EA v15.00):
 *  - FIVE MONITOR VIEWS, one per physical screen — switch with the tabs or
 *    the URL hash (#matrix / #heatmap / #montecarlo / #journal / #oracle),
 *    so Monitor 1 holds the Matrix Table, Monitor 2 the CVD/Delta Heatmap,
 *    Monitor 3 the Monte Carlo Simulator, Monitor 4 the Journal, Monitor 5
 *    the Oracle console — ALL windows fed by the same local bridge.
 *  - WebSocket live feed: rows arrive the instant the EA pushes (no polling
 *    latency); the conn pill shows LIVE·WS. Polling fallback is automatic.
 *  - New columns: REGIME (v14 TRENDING green / RANGING yellow / TRANSITION
 *    slate, with Hurst + KER), CONF (v12 Confluence Fusion 0-100 + stacked
 *    methodologies, flashing HIGH CONFLUENCE at 4+), ORACLE (v15 0-100
 *    fused score, flashing PERFECT SETUP at >= 85).
 *  - New warnings: red YIELD CURVE INVERTED (v15 bond-CFD spread), flashing
 *    amber LEAD <SYM> MOVING (v15 lead/lag), amber VCV CONE (v14
 *    contraction), green HIGH CONFLUENCE (v12).
 *  - Journal view renders the EA v11 on-chart notes (notes[] payload: the
 *    double-click chart journal) beside the tuner suggestions.
 *  - Carried over from v6/v5/v4: MASTER SCORE / VERDICT columns, grade
 *    chips, strategy views, smart sorting, heatmap rows, DIVERGING / NEWS /
 *    MAX HEAT tags, click-to-pin, live sandbox box, remote control, raw
 *    payload viewer, conn pill.
 *
 * Cypress hooks (this file only — the spec drives the server directly):
 *   [data-test="fit-matrix-table"]            the matrix table (matrix view)
 *   [data-test="matrix-row-<SYM>-<TF>"]       one row per symbol+timeframe
 *   [data-test="entry-cell-<SYM>-<TF>"]       raw ENTRY number cell
 *   [data-test="score-cell-<SYM>-<TF>"]       grade letter (A/B/C/D)
 *   [data-test="zenith-cell-<SYM>-<TF>"]      master chip (v5 compat)
 *   [data-test="master-cell-<SYM>-<TF>"]      0-100 value score (v6)
 *   [data-test="verdict-cell-<SYM>-<TF>"]     GO / WAIT / NO TRADE chip (v6)
 *   [data-test="warn-cell-<SYM>-<TF>"]        all warning tags (v6/v7)
 *   [data-test="regime-cell-<SYM>-<TF>"]      v14 regime chip (v7)
 *   [data-test="conf-cell-<SYM>-<TF>"]        v12 confluence cell (v7)
 *   [data-test="oracle-cell-<SYM>-<TF>"]      v15 oracle score cell (v7)
 *   [data-test="news-cell-<SYM>-<TF>"]        v16 news-sentiment bias (paict_news.py)
 *   [data-test="vision-cell-<SYM>-<TF>"]      v16 chart-vision pattern/wick (paict_vision.py)
 *   [data-test="conn-status"]                 LIVE·WS / LIVE / AWAITING / OFFLINE
 *   [data-test="ws-status"]                   WebSocket feed state (v7)
 *   [data-test="monitor-matrix|heatmap|montecarlo|journal|oracle"]  view tabs
 *   [data-test="copilot-cell-<SYM>-<TF>"]     risk lots / heat / news chips
 *   [data-test="view-pa|ict|zenith"]          strategy view toggles (v6)
 *   [data-test="grade-all|a|b|c"]             grade filter chips (v6)
 *   [data-test="sort-master|mc|rr|oracle"]    sorting chips (v6/v7)
 *   [data-test="pin-card"]                    pinned summary card (v6)
 *   [data-test="sandbox-box"]                 sandbox live box (v6)
 *   [data-test="sandbox-rr"] / "sandbox-lots" live sandbox reads (v6)
 *   [data-test="heat-card-<SYM>-<TF>"]        heatmap monitor cards (v7)
 *   [data-test="mc-row-<SYM>-<TF>"]           Monte Carlo monitor rows (v7)
 *   [data-test="journal-row-<i>"]             journal note rows (v7)
 *   [data-test="yc-panel"] / "lead-panel"     Oracle console panels (v7)
 *   [data-test="remote-*"]                    remote control (unchanged)
 *
 * CORS note: the Node bridge must send Access-Control-Allow-Origin for the
 * origin this page is served from (the reference server sends "*").
 * WebSocket is same-port on the bridge (ws://127.0.0.1:8891/) — browsers
 * do not enforce CORS on WebSocket, the bridge accepts any upgrade.
 */

import React, { useEffect, useMemo, useRef, useState } from "react";

const BRIDGE_URL = "http://127.0.0.1:8891/v1/matrix";
const COMMANDS_URL = "http://127.0.0.1:8891/v1/commands";
const WS_URL = "ws://127.0.0.1:8891/";
const POLL_MS = 3000;
const FRESH_MS = 90_000;

/** Verdict thresholds — mirror the EA inputs InpMasterGoAt / InpMasterWaitAt. */
const GO_AT = 70;
const WAIT_AT = 45;
/** Grade thresholds on the Value Score. */
const GRADE_A = 85;
const GRADE_B = 70;
const GRADE_C = 45;
/** v15 Oracle: the EA flashes PERFECT SETUP at InpOracleGoAt (default 85). */
const PERFECT_AT = 85;

type NoteRow = { time?: string; price?: number; text?: string };

type Row = {
  symbol?: string;
  timeframe?: string;
  side?: string;
  entry?: number;
  sl?: number;
  tp?: number;
  rr?: number;
  status?: string;
  time?: string;
  receivedAt?: string;
  // v4.00 co-pilot fields (additive — the EA pushes them when enabled)
  riskPct?: number;
  riskLots?: number;
  heatPct?: number;
  heatAlert?: boolean;
  newsBlackout?: boolean;
  newsEvent?: string;
  // v5-v10 zenith fields (additive)
  alignScore?: number;
  mcTP?: number;
  mcSL?: number;
  cvdDir?: number;
  cvdDiv?: boolean;
  displacement?: number;
  corrSym?: string;
  corrR?: number;
  corrWarn?: boolean;
  poc?: number;
  vah?: number;
  val?: number;
  setupMuted?: boolean;
  masterScore?: number;
  masterVerdict?: string;
  sbEntry?: number;
  sbStop?: number;
  sbTP?: number;
  sbActive?: boolean;
  tuner?: string;
  // v11-v15 oracle fields (additive)
  regime?: string; // TRENDING / RANGING / TRANSITION
  hurst?: number;
  ker?: number;
  vcvSqueeze?: number;
  vcvCone?: boolean;
  confluence?: number;
  confCount?: number;
  confTags?: string;
  harmonic?: string;
  harmDir?: number;
  przLo?: number;
  przHi?: number;
  elliott?: string;
  ewDir?: number;
  ycSpread?: number;
  ycInverted?: boolean;
  leadSym?: string;
  leadMove?: number;
  leadDir?: number;
  leadFlash?: boolean;
  oracleScore?: number;
  notes?: NoteRow[];
  // v16/v17 local-sensor fields (paict_news.py / paict_vision.py, additive)
  newsBiasDir?: number;
  newsBiasScore?: number;
  newsHeadline?: string;
  visionPatterns?: { name: string; conf: number; barsAgo: number; dir: number }[];
  visionWicks?: { barsAgo: number; side: string; strength: number }[];
};

type ViewKey = "pa" | "ict" | "zenith";
type SortKey = "oracle" | "master" | "mc" | "rr";
type GradeKey = "all" | "a" | "b" | "c";
type MonitorKey = "matrix" | "heatmap" | "montecarlo" | "journal" | "oracle";

const MONITORS: [MonitorKey, string][] = [
  ["matrix", "Matrix Table"],
  ["heatmap", "CVD / Delta Heatmap"],
  ["montecarlo", "Monte Carlo"],
  ["journal", "Journal"],
  ["oracle", "Oracle"],
];

const monitorFromHash = (): MonitorKey => {
  if (typeof window === "undefined") return "matrix";
  const h = window.location.hash.replace("#", "");
  return MONITORS.some(([k]) => k === h) ? (h as MonitorKey) : "matrix";
};

const COLORS = {
  bg: "#0b0e14",
  card: "#12161f",
  border: "#232a38",
  text: "#e6eaf2",
  muted: "#8b93a7",
  entry: "#ffc53d", // bright gold  — matches EA InpEntryColor
  sl: "#ff5c5c", // vivid red    — matches EA InpStopColor
  tp: "#3ddc97", // vivid green  — matches EA InpTargetColor
  amber: "#e0a34a",
  violet: "#a78bfa", // matches EA COL_EQ (confluence / harmonics)
  pill: { ok: "#123b2a", warn: "#3b2f12", off: "#3b1414" },
};

function ageOf(iso?: string): number {
  if (!iso) return Number.POSITIVE_INFINITY;
  const t = Date.parse(iso.endsWith("Z") || iso.includes("+") ? iso : iso + "Z");
  if (Number.isNaN(t)) return Number.POSITIVE_INFINITY;
  return Date.now() - t;
}

function fmtAge(ms: number): string {
  if (!Number.isFinite(ms)) return "—";
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${s % 60}s`;
  return `${Math.floor(m / 60)}h ${m % 60}m`;
}

/** Legacy 0-100 quality score: R:R (40) + freshness (35) + live status (25). */
function qualityScore(row: Row): number {
  const rr = Number(row.rr) || 0;
  const rrPts = rr >= 3 ? 40 : rr >= 2 ? 32 : rr >= 1.5 ? 24 : rr >= 1 ? 14 : 6;
  const age = ageOf(row.receivedAt);
  const frPts =
    age < 180_000 ? 35 : age < 600_000 ? 28 : age < 1_800_000 ? 18 : age < 7_200_000 ? 8 : 0;
  const stPts = row.status === "live" ? 25 : row.status === "awaiting_plan" ? 5 : 10;
  return Math.min(100, rrPts + frPts + stPts);
}

/**
 * v6 Value Score — the EA's Master Score when the payload carries one
 * (v10+ rows); older rows fall back to the legacy quality score.
 */
function valueScore(row: Row): number {
  // guard: the EA never pushes negative scores (an awaiting plan omits the
  // keys) — treat any negative as absent so a seeded/test -1 can never tint
  // a row red or print "-1" as if it were a real read.
  return typeof row.masterScore === "number" && row.masterScore >= 0
    ? row.masterScore
    : qualityScore(row);
}

function gradeOf(row: Row): { grade: string; score: number } {
  const score = valueScore(row);
  const grade = score >= GRADE_A ? "A" : score >= GRADE_B ? "B" : score >= GRADE_C ? "C" : "D";
  return { grade, score };
}

/** Same thresholds as the EA chart label (GO >= 70, WAIT >= 45, else NO TRADE). */
function verdictOf(row: Row): string {
  if (row.masterVerdict) return row.masterVerdict;
  if (typeof row.masterScore !== "number" || row.masterScore < 0) return "";
  return row.masterScore >= GO_AT ? "GO" : row.masterScore >= WAIT_AT ? "WAIT" : "NO TRADE";
}

const gradeColor = (g: string) =>
  g === "A" ? COLORS.tp : g === "B" ? COLORS.entry : g === "C" ? COLORS.amber : COLORS.sl;

const verdictColor = (v?: string) =>
  v === "GO" ? COLORS.tp : v === "WAIT" ? COLORS.amber : v === "NO TRADE" ? COLORS.sl : COLORS.muted;

/** v14 regime chip colors — green trend, yellow range, slate transition. */
const regimeColor = (r?: string) =>
  r === "TRENDING" ? COLORS.tp : r === "RANGING" ? COLORS.amber : COLORS.muted;

/** Heatmap tint: red → amber → green with the live Value Score. */
function heatTint(score: number): string {
  const t = Math.max(0, Math.min(100, score)) / 100;
  const hue = Math.round(t * 140); // 0 = red, ~60 = amber, 140 = green
  const alpha = 0.10 + 0.16 * Math.abs(t - 0.5) * 2; // strongest at the extremes
  return `hsla(${hue}, 62%, 45%, ${alpha.toFixed(3)})`;
}

const SORTERS: Record<SortKey, (r: Row) => number> = {
  oracle: (r) => (typeof r.oracleScore === "number" && r.oracleScore >= 0 ? r.oracleScore : -1),
  master: (r) => (typeof r.masterScore === "number" && r.masterScore >= 0 ? r.masterScore : -1),
  mc: (r) => (typeof r.mcTP === "number" ? r.mcTP : -1),
  rr: (r) => (typeof r.rr === "number" ? r.rr : -1),
};

const GRADE_MIN: Record<Exclude<GradeKey, "all">, number> = { a: GRADE_A, b: GRADE_B, c: GRADE_C };

/** Sandbox live reads — recomputed from the dragged levels on every update. */
function sandboxReads(row: Row) {
  if (!row.sbActive) return null;
  const e = Number(row.sbEntry);
  const s = Number(row.sbStop);
  const t = Number(row.sbTP);
  if (![e, s, t].every(Number.isFinite) || e === s) return null;
  const dist = Math.abs(e - s);
  const rr = Math.abs(t - e) / dist;
  // lots scale the EA's plan lots by the stop-distance ratio (same risk %)
  const planDist =
    Number.isFinite(Number(row.entry)) && Number.isFinite(Number(row.sl))
      ? Math.abs(Number(row.entry) - Number(row.sl))
      : 0;
  const lots =
    row.riskLots && planDist > 0
      ? (Number(row.riskLots) * planDist) / dist
      : NaN;
  return { e, s, t, dist, rr, lots };
}

/** v7 Monte Carlo expected value per 1R (sigma = ATR is an upper bound). */
function mcEV(row: Row): number | null {
  if (typeof row.mcTP !== "number" || typeof row.mcSL !== "number" || typeof row.rr !== "number")
    return null;
  if (row.mcTP <= 0 && row.mcSL <= 0) return null;
  return (row.mcTP / 100) * row.rr - row.mcSL / 100;
}

export default function Mt5BridgeDashboard() {
  const [rows, setRows] = useState<Row[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [wsLive, setWsLive] = useState(false);
  const [symFilter, setSymFilter] = useState<string>("ALL");
  const [tfFilter, setTfFilter] = useState<string>("ALL");
  const [gradeFilter, setGradeFilter] = useState<GradeKey>("all");
  const [sortBy, setSortBy] = useState<SortKey>("oracle");
  const [view, setView] = useState<ViewKey>("zenith");
  const [monitor, setMonitor] = useState<MonitorKey>(monitorFromHash);
  const [pinned, setPinned] = useState<string | null>(null);
  const [riskInput, setRiskInput] = useState<string>("1.0");
  const [remoteMsg, setRemoteMsg] = useState<string>("no commands sent yet");
  const timer = useRef<number | null>(null);

  /* ---- v7 multi-window WebSocket feed (fallback: 3 s HTTP polling) ---- */
  useEffect(() => {
    let ws: WebSocket | null = null;
    let disposed = false;
    try {
      ws = new WebSocket(WS_URL);
      ws.onopen = () => {
        if (!disposed) setWsLive(true);
      };
      ws.onmessage = (ev: MessageEvent) => {
        try {
          const m = JSON.parse(String(ev.data));
          if (m && m.type === "matrix" && Array.isArray(m.rows)) {
            setRows(m.rows);
            setErr(null);
          }
        } catch {
          /* ignore malformed frames */
        }
      };
      ws.onerror = () => {
        if (!disposed) setWsLive(false);
      };
      ws.onclose = () => {
        if (!disposed) setWsLive(false);
      };
    } catch {
      setWsLive(false);
    }
    return () => {
      disposed = true;
      try {
        ws?.close();
      } catch {
        /* already closed */
      }
    };
  }, []);

  const load = async () => {
    try {
      const r = await fetch(BRIDGE_URL, { cache: "no-store" });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const body = await r.json();
      setRows(Array.isArray(body) ? body : body && body.symbol ? [body] : []);
      setErr(null);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      setErr(msg);
    }
  };

  useEffect(() => {
    load();
    if (wsLive) return; // live push feed — polling redundant
    timer.current = window.setInterval(load, POLL_MS);
    return () => {
      if (timer.current) window.clearInterval(timer.current);
    };
  }, [wsLive]);

  /* ---- monitor view follows the URL hash (one view per monitor) ---- */
  useEffect(() => {
    const on = () => setMonitor(monitorFromHash());
    window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);
  const goMonitor = (m: MonitorKey) => {
    setMonitor(m);
    try {
      window.location.hash = m;
    } catch {
      /* hash blocked — the state still switched */
    }
  };

  const symbols = useMemo(
    () => [...new Set(rows.map((r) => r.symbol || "?"))].sort(),
    [rows],
  );
  const tfs = useMemo(
    () => [...new Set(rows.map((r) => r.timeframe || "?"))].sort(),
    [rows],
  );

  const visible = useMemo(() => {
    const out = rows.filter((r) => {
      if (symFilter !== "ALL" && r.symbol !== symFilter) return false;
      if (tfFilter !== "ALL" && r.timeframe !== tfFilter) return false;
      // v6: grade filters apply STRICTLY to the EA Master Score — rows
      // without one (pre-v10 pushes) are hidden by A+/B+/C+ rather than
      // letting the legacy proxy grade pose as a Zenith signal.
      if (gradeFilter !== "all") {
        if (typeof r.masterScore !== "number") return false;
        if (r.masterScore < GRADE_MIN[gradeFilter]) return false;
      }
      return true;
    });
    out.sort((a, b) => SORTERS[sortBy](b) - SORTERS[sortBy](a));
    return out;
  }, [rows, symFilter, tfFilter, gradeFilter, sortBy]);

  const anyLiveFresh = rows.some(
    (r) => r.status === "live" && ageOf(r.receivedAt) < FRESH_MS,
  );
  const conn = !err && rows.length > 0 ? (anyLiveFresh ? "LIVE" : "AWAITING") : "OFFLINE";
  const connLabel = conn === "LIVE" && wsLive ? "LIVE·WS" : conn;
  const connStyle =
    conn === "LIVE"
      ? { background: COLORS.pill.ok, color: COLORS.tp }
      : conn === "AWAITING"
        ? { background: COLORS.pill.warn, color: COLORS.entry }
        : { background: COLORS.pill.off, color: "#ff8080" };

  const pinnedRow =
    visible.find((r) => `${r.symbol}|${r.timeframe}` === pinned) || visible[0];
  const pinnedSlot = pinnedRow ? `${pinnedRow.symbol}|${pinnedRow.timeframe}` : "";
  const pinnedSb = pinnedRow ? sandboxReads(pinnedRow) : null;

  const sendCommand = async (action: string, value: string | number) => {
    if (!pinnedSlot) return;
    try {
      const r = await fetch(COMMANDS_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ slot: pinnedSlot, action, value }),
      });
      const body = await r.json();
      setRemoteMsg(
        r.ok
          ? `queued #${body.cmd?.id ?? "?"} ${action} ${value} → ${body.slot} (EA pulls on next push)`
          : `rejected: ${body.error ?? `HTTP ${r.status}`}`,
      );
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      setRemoteMsg(`bridge error: ${msg}`);
    }
  };

  const th: React.CSSProperties = {
    ...{ padding: "8px 10px", textAlign: "left", fontSize: 11, letterSpacing: 1 },
    color: COLORS.muted,
    borderBottom: `1px solid ${COLORS.border}`,
    whiteSpace: "nowrap",
  };
  const td: React.CSSProperties = {
    padding: "8px 10px",
    fontSize: 13,
    borderBottom: `1px solid ${COLORS.border}`,
  };

  const chip = (active: boolean): React.CSSProperties => ({
    padding: "4px 10px",
    borderRadius: 999,
    border: `1px solid ${active ? "#4a7dff" : COLORS.border}`,
    background: active ? "#16233d" : COLORS.card,
    color: active ? "#cfe0ff" : COLORS.muted,
    fontSize: 12,
    cursor: "pointer",
  });

  const btn: React.CSSProperties = {
    padding: "8px 14px",
    borderRadius: 8,
    border: `1px solid ${COLORS.border}`,
    background: "#16233d",
    color: COLORS.text,
    fontSize: 12,
    fontWeight: 700,
    cursor: "pointer",
  };

  const tag = (text: string, color: string, pulse = false): React.ReactElement => (
    <span
      style={{
        color,
        fontWeight: 700,
        fontSize: 11,
        border: `1px solid ${color}44`,
        borderRadius: 6,
        padding: "1px 6px",
        whiteSpace: "nowrap",
        ...(pulse ? { animation: "paictPulse 1.1s ease-in-out infinite" } : {}),
      }}
    >
      {text}
    </span>
  );

  const levelCard = (
    label: string,
    value: number | undefined,
    color: string,
  ) => (
    <div
      style={{
        flex: "1 1 140px",
        background: COLORS.card,
        border: `1px solid ${COLORS.border}`,
        borderLeft: `4px solid ${color}`,
        borderRadius: 10,
        padding: "10px 14px",
      }}
    >
      <div style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>{label}</div>
      <div style={{ color, fontSize: 22, fontWeight: 700, fontVariantNumeric: "tabular-nums" }}>
        {value ? Number(value).toFixed(2) : "—"}
      </div>
    </div>
  );

  const copilotCell = (r: Row) => {
    const parts: { text: string; color: string; pulse?: boolean }[] = [];
    if (r.riskLots) parts.push({ text: `${Number(r.riskLots).toFixed(2)}L`, color: COLORS.entry });
    if (typeof r.heatPct === "number" && r.receivedAt) {
      parts.push({
        text: `heat ${r.heatPct.toFixed(2)}%`,
        color: r.heatAlert ? COLORS.sl : r.heatPct > 0 ? COLORS.tp : COLORS.muted,
      });
    }
    if (r.newsBlackout) parts.push({ text: "NEWS", color: COLORS.sl });
    if (r.setupMuted) parts.push({ text: "MUTED", color: COLORS.sl });
    if (parts.length === 0) return <span style={{ color: COLORS.muted }}>—</span>;
    return (
      <span style={{ display: "inline-flex", gap: 6, flexWrap: "wrap" }}>
        {parts.map((p, i) => (
          <span
            key={i}
            style={{
              color: p.color,
              fontWeight: 700,
              fontSize: 11,
              border: `1px solid ${p.color}44`,
              borderRadius: 6,
              padding: "1px 6px",
              ...(p.pulse ? { animation: "paictPulse 1.1s ease-in-out infinite" } : {}),
            }}
          >
            {p.text}
          </span>
        ))}
      </span>
    );
  };

  /** v6 MASTER cell: the 0-100 Value Score as the big number (+ MC beside). */
  const masterCell = (r: Row) => {
    if (typeof r.masterScore !== "number" || r.masterScore < 0)
      return <span style={{ color: COLORS.muted }}>—</span>;
    const s = r.masterScore;
    const c = s >= GO_AT ? COLORS.tp : s >= WAIT_AT ? COLORS.amber : COLORS.sl;
    return (
      <span
        data-test={`master-cell-${r.symbol}-${r.timeframe}`}
        style={{ display: "inline-flex", gap: 8, alignItems: "baseline", whiteSpace: "nowrap" }}
      >
        <b style={{ color: c, fontSize: 17, fontVariantNumeric: "tabular-nums" }}>{s}</b>
        {typeof r.mcTP === "number" && r.mcTP > 0 && (
          <span style={{ color: COLORS.muted, fontSize: 11 }}>mc {Math.round(r.mcTP)}%</span>
        )}
      </span>
    );
  };

  /** v6 VERDICT cell: GO / WAIT / NO TRADE chip with the dot. */
  const verdictCell = (r: Row) => {
    const v = verdictOf(r);
    const dot = v === "GO" ? "🟢" : v === "WAIT" ? "🟡" : v === "NO TRADE" ? "🔴" : "⚪";
    if (!v) return <span style={{ color: COLORS.muted }}>—</span>;
    const vc = verdictColor(v);
    return (
      <span
        data-test={`verdict-cell-${r.symbol}-${r.timeframe}`}
        style={{
          color: vc,
          fontWeight: 800,
          fontSize: 12,
          border: `1px solid ${vc}55`,
          borderRadius: 6,
          padding: "2px 8px",
          whiteSpace: "nowrap",
        }}
      >
        {dot} {v}
      </span>
    );
  };

  /** v5-compat zenith chip (kept for existing test hooks). */
  const zenithCell = (r: Row) => {
    const v = verdictOf(r);
    if (!v) return <span style={{ color: COLORS.muted }}>—</span>;
    const vc = verdictColor(v);
    return (
      <span
        data-test={`zenith-cell-${r.symbol}-${r.timeframe}`}
        style={{ display: "inline-flex", gap: 6, alignItems: "center", flexWrap: "wrap" }}
      >
        <span
          style={{
            color: vc,
            fontWeight: 800,
            fontSize: 12,
            border: `1px solid ${vc}55`,
            borderRadius: 6,
            padding: "2px 8px",
          }}
        >
          {v} {typeof r.masterScore === "number" ? r.masterScore : ""}
        </span>
        {typeof r.alignScore === "number" && (
          <span
            style={{
              color:
                r.alignScore > 0 ? COLORS.tp : r.alignScore < 0 ? COLORS.sl : COLORS.muted,
              fontWeight: 700,
              fontSize: 11,
            }}
          >
            {r.alignScore > 0 ? "+" : ""}
            {r.alignScore} align
          </span>
        )}
      </span>
    );
  };

  /** v7 REGIME cell — TRENDING green / RANGING yellow / TRANSITION slate. */
  const regimeCell = (r: Row) => {
    if (!r.regime) return <span style={{ color: COLORS.muted }}>—</span>;
    const rc = regimeColor(r.regime);
    return (
      <span
        data-test={`regime-cell-${r.symbol}-${r.timeframe}`}
        style={{
          color: rc,
          fontWeight: 800,
          fontSize: 11,
          border: `1px solid ${rc}55`,
          borderRadius: 6,
          padding: "2px 8px",
          whiteSpace: "nowrap",
        }}
        title={typeof r.hurst === "number" ? `Hurst ${r.hurst.toFixed(2)} · KER ${Number(r.ker ?? 0).toFixed(2)}` : ""}
      >
        {r.regime}
      </span>
    );
  };

  /** v7 CONF cell — Confluence Fusion + stacked methodology tags. */
  const confCell = (r: Row) => {
    if (typeof r.confluence !== "number" || (r.confluence <= 0 && !r.confCount))
      return <span style={{ color: COLORS.muted }}>—</span>;
    const high = (r.confCount ?? 0) >= 4;
    const cc = high ? COLORS.tp : COLORS.violet;
    return (
      <span
        data-test={`conf-cell-${r.symbol}-${r.timeframe}`}
        style={{ display: "inline-flex", gap: 6, alignItems: "baseline", whiteSpace: "nowrap" }}
      >
        <b style={{ color: cc, fontSize: 15, fontVariantNumeric: "tabular-nums" }}>
          {r.confluence}
        </b>
        <span style={{ color: COLORS.muted, fontSize: 11 }}>
          {r.confCount ?? "?"}× {r.confTags ?? ""}
        </span>
        {high && (
          <span
            style={{
              color: COLORS.tp,
              fontWeight: 800,
              fontSize: 10,
              animation: "paictPulse 1.1s ease-in-out infinite",
              whiteSpace: "nowrap",
            }}
          >
            HIGH CONFLUENCE
          </span>
        )}
      </span>
    );
  };

  /** v7 ORACLE cell — the 0-100 fused score, PERFECT SETUP flash >= 85. */
  const oracleCell = (r: Row) => {
    if (typeof r.oracleScore !== "number" || r.oracleScore < 0)
      return <span style={{ color: COLORS.muted }}>—</span>;
    const perfect = r.oracleScore >= PERFECT_AT;
    const oc = perfect ? COLORS.tp : r.oracleScore >= GO_AT ? COLORS.tp : r.oracleScore >= WAIT_AT ? COLORS.amber : COLORS.sl;
    return (
      <span
        data-test={`oracle-cell-${r.symbol}-${r.timeframe}`}
        style={{ display: "inline-flex", gap: 8, alignItems: "baseline", whiteSpace: "nowrap" }}
      >
        <b style={{ color: oc, fontSize: 18, fontVariantNumeric: "tabular-nums" }}>
          {r.oracleScore}
        </b>
        {perfect && (
          <span
            style={{
              color: COLORS.tp,
              fontWeight: 800,
              fontSize: 11,
              animation: "paictPulse 1.1s ease-in-out infinite",
              whiteSpace: "nowrap",
            }}
          >
            PERFECT SETUP
          </span>
        )}
      </span>
    );
  };

  /** v16 NEWS cell — paict_news.py's freshest bias for this slot. */
  const newsCell = (r: Row) => {
    if (typeof r.newsBiasDir !== "number") return <span style={{ color: COLORS.muted }}>—</span>;
    const up = r.newsBiasDir > 0;
    const nc = r.newsBiasDir === 0 ? COLORS.muted : up ? COLORS.tp : COLORS.sl;
    return (
      <span
        data-test={`news-cell-${r.symbol}-${r.timeframe}`}
        style={{ display: "inline-flex", gap: 6, alignItems: "baseline", whiteSpace: "nowrap" }}
        title={r.newsHeadline ?? ""}
      >
        <b style={{ color: nc, fontSize: 13 }}>{up ? "▲" : r.newsBiasDir < 0 ? "▼" : "•"}</b>
        <span style={{ color: COLORS.muted, fontSize: 11, maxWidth: 160, overflow: "hidden", textOverflow: "ellipsis" }}>
          {r.newsHeadline ?? `bias ${r.newsBiasScore ?? 0}`}
        </span>
      </span>
    );
  };

  /** v16 VISION cell — paict_vision.py's top pattern + any wick-rejects. */
  const visionCell = (r: Row) => {
    const pats = r.visionPatterns ?? [];
    const wicks = r.visionWicks ?? [];
    if (pats.length === 0 && wicks.length === 0) return <span style={{ color: COLORS.muted }}>—</span>;
    const top = pats[0];
    return (
      <span
        data-test={`vision-cell-${r.symbol}-${r.timeframe}`}
        style={{ display: "inline-flex", gap: 6, alignItems: "baseline", whiteSpace: "nowrap" }}
      >
        {top && (
          <span style={{ color: COLORS.violet, fontWeight: 700, fontSize: 11 }}>
            {top.name} {top.conf}%
          </span>
        )}
        {wicks.length > 0 && (
          <span style={{ color: COLORS.amber, fontSize: 10 }}>
            {wicks[0].side.toUpperCase()} WICK {wicks[0].strength}
          </span>
        )}
      </span>
    );
  };

  /** v6/v7 WARNINGS cell — all engines' alerts in one place. */
  const warnCell = (r: Row) => {
    const parts: React.ReactElement[] = [];
    if (r.corrWarn)
      parts.push(tag(`DIVERGING${r.corrSym ? ` ${r.corrSym}` : ""}`, COLORS.amber));
    if (r.newsBlackout) parts.push(tag("NEWS", COLORS.sl));
    if (r.heatAlert) parts.push(tag("MAX HEAT", COLORS.sl, true));
    if (r.ycInverted) parts.push(tag("YIELD CURVE INVERTED", COLORS.sl, true));
    if (r.leadFlash && r.leadSym)
      parts.push(tag(`LEAD ${r.leadSym} MOVING`, COLORS.amber, true));
    if (r.vcvCone) parts.push(tag("VCV CONE", COLORS.amber, true));
    if ((r.confCount ?? 0) >= 4) parts.push(tag("HIGH CONFLUENCE", COLORS.tp, true));
    if (r.setupMuted) parts.push(tag("MUTED", COLORS.muted));
    if (parts.length === 0) return <span style={{ color: COLORS.muted }}>—</span>;
    return (
      <span data-test={`warn-cell-${r.symbol}-${r.timeframe}`} style={{ display: "inline-flex", gap: 6, flexWrap: "wrap" }}>
        {parts.map((p, i) => (
          <React.Fragment key={i}>{p}</React.Fragment>
        ))}
      </span>
    );
  };

  // Column presets per strategy view (beyond the core SYMBOL..R:R).
  const viewCols: Record<ViewKey, string[]> = {
    pa: ["ALERTS", "STATUS", "AGE"],
    ict: ["DISP", "MASTER", "VERDICT", "CONF", "ALERTS", "AGE"],
    zenith: ["MASTER", "VERDICT", "REGIME", "CONF", "ORACLE", "NEWS", "VISION", "ALERTS", "STATUS", "AGE"],
  };
  const cols = viewCols[view];
  const colCount = 7 + cols.length + (cols.includes("MASTER") ? 1 : 0);
  const cell = (col: string, r: Row) => {
    switch (col) {
      case "MASTER":
        return masterCell(r);
      case "VERDICT":
        return verdictCell(r);
      case "REGIME":
        return regimeCell(r);
      case "CONF":
        return confCell(r);
      case "ORACLE":
        return oracleCell(r);
      case "NEWS":
        return newsCell(r);
      case "VISION":
        return visionCell(r);
      case "ALERTS":
        return (
          <span data-test={`copilot-cell-${r.symbol}-${r.timeframe}`}>
            {copilotCell(r)}
            {warnCell(r)}
          </span>
        );
      case "DISP":
        return typeof r.displacement === "number" && r.displacement > 0 ? (
          <span style={{ color: COLORS.entry, fontWeight: 700 }}>D{r.displacement}</span>
        ) : (
          <span style={{ color: COLORS.muted }}>—</span>
        );
      case "STATUS":
        return (
          <span style={{ color: r.status === "live" ? COLORS.tp : COLORS.muted }}>
            {r.status || "—"}
          </span>
        );
      case "AGE":
        return <span style={{ color: COLORS.muted }}>{fmtAge(ageOf(r.receivedAt))}</span>;
      default:
        return null;
    }
  };

  /* ---------------- Monitor 4: journal rows (notes + tuner) ---------------- */
  const journalRows = useMemo(() => {
    const out: { slot: string; time: string; price: number; text: string }[] = [];
    for (const r of rows) {
      const slot = `${r.symbol}|${r.timeframe}`;
      for (const n of r.notes ?? []) {
        if (n && n.text)
          out.push({
            slot,
            time: n.time ?? "?",
            price: Number(n.price ?? 0),
            text: n.text,
          });
      }
    }
    return out;
  }, [rows]);

  /* ---------------- Monitor 5: oracle console data ---------------- */
  const ycRows = rows.filter((r) => typeof r.ycSpread === "number");
  const leadRows = rows.filter((r) => r.leadFlash && r.leadSym);
  const regimeCounts = useMemo(() => {
    const c = { TRENDING: 0, RANGING: 0, TRANSITION: 0 };
    for (const r of rows) {
      if (r.regime === "TRENDING") c.TRENDING += 1;
      else if (r.regime === "RANGING") c.RANGING += 1;
      else if (r.regime === "TRANSITION") c.TRANSITION += 1;
    }
    return c;
  }, [rows]);
  const perfectRows = visible.filter(
    (r) => typeof r.oracleScore === "number" && r.oracleScore >= PERFECT_AT,
  );

  return (
    <div
      style={{
        minHeight: "100vh",
        background: COLORS.bg,
        color: COLORS.text,
        font: "14px/1.45 ui-sans-serif, system-ui, Segoe UI, Arial",
        padding: 20,
      }}
    >
      <style>{`@keyframes paictPulse { 0%, 100% { opacity: 1 } 50% { opacity: 0.3 } }`}</style>
      <div
        style={{
          maxWidth: 1280,
          margin: "0 auto",
          display: "grid",
          gap: 16,
          // minmax(0, …) lets grid children shrink below their content width so
          // the matrix table scrolls INSIDE its card instead of stretching the
          // page on phones.
          gridTemplateColumns: "minmax(0, 1fr)",
        }}
      >
        {/* header */}
        <header style={{ display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
          <h1 style={{ fontSize: 20, margin: 0, fontWeight: 700 }}>PAICT Multi-Monitor Cockpit</h1>
          <span
            style={{
              color: COLORS.muted,
              fontSize: 11,
              border: `1px solid ${COLORS.border}`,
              borderRadius: 999,
              padding: "2px 10px",
            }}
          >
            dashboard v7
          </span>
          <span
            data-test="conn-status"
            style={{
              ...connStyle,
              padding: "4px 12px",
              borderRadius: 999,
              fontSize: 12,
              fontWeight: 700,
              letterSpacing: 1,
            }}
          >
            {connLabel}
          </span>
          <span
            data-test="ws-status"
            style={{
              color: wsLive ? COLORS.tp : COLORS.muted,
              fontSize: 11,
              border: `1px solid ${wsLive ? `${COLORS.tp}55` : COLORS.border}`,
              borderRadius: 999,
              padding: "2px 10px",
            }}
          >
            {wsLive ? "WS FEED PUSHING" : "WS off — polling fallback"}
          </span>
          <span style={{ color: COLORS.muted, fontSize: 12 }}>
            {err ? `bridge error: ${err}` : `${rows.length} pair(s) · ${wsLive ? "pushed live" : `polling every ${POLL_MS / 1000}s`}`}
          </span>
        </header>

        {/* v7 monitor tabs — one view per physical screen */}
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
          <span style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>MONITOR</span>
          {MONITORS.map(([k, label]) => (
            <button
              key={k}
              data-test={`monitor-${k}`}
              style={chip(monitor === k)}
              onClick={() => goMonitor(k)}
            >
              {label}
            </button>
          ))}
          <span style={{ color: COLORS.muted, fontSize: 11 }}>
            · put one view per screen — every window shares the same local feed
          </span>
        </div>

        {/* filters: symbol + tf (all views) */}
        <div style={{ display: "flex", gap: 14, flexWrap: "wrap", alignItems: "center" }}>
          <span style={{ color: COLORS.muted, fontSize: 12 }}>SYMBOL</span>
          {["ALL", ...symbols].map((s) => (
            <button key={s} style={chip(symFilter === s)} onClick={() => setSymFilter(s)}>
              {s}
            </button>
          ))}
          <span style={{ color: COLORS.muted, fontSize: 12, marginLeft: 8 }}>TF</span>
          {["ALL", ...tfs].map((t) => (
            <button key={t} style={chip(tfFilter === t)} onClick={() => setTfFilter(t)}>
              {t}
            </button>
          ))}
        </div>

        {/* v6 control bar: view · grade · sort (matrix monitor) */}
        {monitor === "matrix" && (
          <div
            style={{
              display: "flex",
              gap: 14,
              flexWrap: "wrap",
              alignItems: "center",
              background: COLORS.card,
              border: `1px solid ${COLORS.border}`,
              borderRadius: 10,
              padding: "10px 12px",
            }}
          >
            <span style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>VIEW</span>
            <button data-test="view-pa" style={chip(view === "pa")} onClick={() => setView("pa")}>
              PA · Zones
            </button>
            <button data-test="view-ict" style={chip(view === "ict")} onClick={() => setView("ict")}>
              ICT · OB/FVG
            </button>
            <button
              data-test="view-zenith"
              style={chip(view === "zenith")}
              onClick={() => setView("zenith")}
            >
              Zenith · Full
            </button>
            <span style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1, marginLeft: 10 }}>
              GRADE
            </span>
            {(
              [
                ["all", "ALL"],
                ["a", "A+ (85)"],
                ["b", "B+ (70)"],
                ["c", "C+ (45)"],
              ] as [GradeKey, string][]
            ).map(([k, label]) => (
              <button
                key={k}
                data-test={`grade-${k}`}
                style={chip(gradeFilter === k)}
                onClick={() => setGradeFilter(k)}
              >
                {label}
              </button>
            ))}
            <span style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1, marginLeft: 10 }}>
              SORT ▾
            </span>
            {(
              [
                ["oracle", "ORACLE"],
                ["master", "MASTER"],
                ["mc", "MC TP%"],
                ["rr", "R:R"],
              ] as [SortKey, string][]
            ).map(([k, label]) => (
              <button
                key={k}
                data-test={`sort-${k}`}
                style={chip(sortBy === k)}
                onClick={() => setSortBy(k)}
              >
                {label}
              </button>
            ))}
          </div>
        )}

        {/* ================= MONITOR 1: matrix table ================= */}
        {monitor === "matrix" && (
          <div
            style={{
              background: COLORS.card,
              border: `1px solid ${COLORS.border}`,
              borderRadius: 12,
              overflow: "auto",
            }}
          >
            <table data-test="fit-matrix-table" style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr>
                  {["SYMBOL", "TF", "SIDE", "ENTRY", "SL", "TP", "R:R", ...cols].map((h) => (
                    <th key={h} style={th}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {visible.length === 0 && (
                  <tr>
                    <td style={{ ...td, color: COLORS.muted }} colSpan={colCount}>
                      waiting for the first push — attach the EA and keep the bridge running…
                    </td>
                  </tr>
                )}
                {visible.map((r) => {
                  const key = `${r.symbol}|${r.timeframe}`;
                  const { grade } = gradeOf(r);
                  const side = r.side || "—";
                  const sideColor =
                    side === "long" ? COLORS.tp : side === "short" ? COLORS.sl : COLORS.muted;
                  const vs = valueScore(r);
                  const hasMaster = typeof r.masterScore === "number" && r.masterScore >= 0;
                  return (
                    <tr
                      key={key}
                      data-test={`matrix-row-${r.symbol}-${r.timeframe}`}
                      onClick={() => setPinned(key)}
                      style={{
                        cursor: "pointer",
                        background: pinnedRow === r ? "#151b28" : hasMaster ? heatTint(vs) : "transparent",
                        opacity: r.newsBlackout ? 0.55 : 1,
                      }}
                    >
                      <td style={{ ...td, fontWeight: 700, whiteSpace: "nowrap" }}>
                        {r.symbol || "—"}
                      </td>
                      <td style={td}>{r.timeframe || "—"}</td>
                      <td style={{ ...td, color: sideColor, fontWeight: 600 }}>{side.toUpperCase()}</td>
                      <td
                        data-test={`entry-cell-${r.symbol}-${r.timeframe}`}
                        style={{
                          ...td,
                          color: COLORS.entry,
                          fontWeight: 700,
                          fontVariantNumeric: "tabular-nums",
                          whiteSpace: "nowrap",
                        }}
                      >
                        {r.entry ? String(r.entry) : "—"}
                      </td>
                      <td style={{ ...td, color: COLORS.sl, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
                        {r.sl ? String(r.sl) : "—"}
                      </td>
                      <td style={{ ...td, color: COLORS.tp, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
                        {r.tp ? String(r.tp) : "—"}
                      </td>
                      <td style={td}>{r.rr ? `1:${Number(r.rr).toFixed(2)}` : "—"}</td>
                      {cols.includes("MASTER") && (
                        <td
                          data-test={`score-cell-${r.symbol}-${r.timeframe}`}
                          style={{ ...td, fontWeight: 800, color: gradeColor(grade), fontSize: 15 }}
                        >
                          {grade}
                        </td>
                      )}
                      {cols.map((c) => (
                        <td key={c} style={td}>
                          {cell(c, r)}
                        </td>
                      ))}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {/* ================= MONITOR 2: CVD / delta heatmap ================= */}
        {monitor === "heatmap" && (
          <div style={{ display: "grid", gap: 12, gridTemplateColumns: "repeat(auto-fill, minmax(270px, 1fr))" }}>
            {visible.length === 0 && (
              <div style={{ color: COLORS.muted, fontSize: 13 }}>
                waiting for the first push — attach the EA and keep the bridge running…
              </div>
            )}
            {visible.map((r) => {
              const vs = valueScore(r);
              const cvdArrow = r.cvdDir === 1 ? "▲" : r.cvdDir === -1 ? "▼" : "•";
              const cvdColor = r.cvdDir === 1 ? COLORS.tp : r.cvdDir === -1 ? COLORS.sl : COLORS.muted;
              return (
                <div
                  key={`${r.symbol}|${r.timeframe}`}
                  data-test={`heat-card-${r.symbol}-${r.timeframe}`}
                  onClick={() => setPinned(`${r.symbol}|${r.timeframe}`)}
                  style={{
                    cursor: "pointer",
                    background: COLORS.card,
                    border: `1px solid ${COLORS.border}`,
                    borderRadius: 12,
                    padding: "12px 14px",
                    position: "relative",
                    overflow: "hidden",
                    opacity: r.newsBlackout ? 0.55 : 1,
                  }}
                >
                  <div
                    style={{
                      position: "absolute",
                      inset: 0,
                      background: heatTint(vs),
                      pointerEvents: "none",
                    }}
                  />
                  <div style={{ position: "relative", display: "grid", gap: 8 }}>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
                      <b style={{ fontSize: 15 }}>{r.symbol} {r.timeframe}</b>
                      <span style={{ color: verdictColor(verdictOf(r)), fontWeight: 800, fontSize: 12 }}>
                        {verdictOf(r) || "—"}
                      </span>
                    </div>
                    <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
                      <span style={{ fontSize: 30, fontWeight: 800, fontVariantNumeric: "tabular-nums", color: gradeColor(gradeOf(r).grade) }}>
                        {vs}
                      </span>
                      <span style={{ color: COLORS.muted, fontSize: 11 }}>
                        master {typeof r.masterScore === "number" ? r.masterScore : "—"}
                        {typeof r.oracleScore === "number" && r.oracleScore >= 0 ? ` · oracle ${r.oracleScore}` : ""}
                      </span>
                    </div>
                    <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                      <span style={{ color: cvdColor, fontWeight: 800, fontSize: 14 }}>
                        {cvdArrow} CVD
                      </span>
                      {r.cvdDiv && <span style={{ color: COLORS.amber, fontSize: 11, fontWeight: 700 }}>DIV</span>}
                      {typeof r.displacement === "number" && r.displacement > 0 && (
                        <span style={{ color: COLORS.entry, fontSize: 11, fontWeight: 700 }}>D{r.displacement}</span>
                      )}
                      {r.regime && (
                        <span style={{ color: regimeColor(r.regime), fontSize: 11, fontWeight: 800 }}>
                          {r.regime}
                        </span>
                      )}
                      <span style={{ color: COLORS.muted, fontSize: 11 }}>R:R {r.rr ? `1:${Number(r.rr).toFixed(2)}` : "—"}</span>
                    </div>
                    <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                      {r.corrWarn && tag(`DIVERGING${r.corrSym ? ` ${r.corrSym}` : ""}`, COLORS.amber)}
                      {r.heatAlert && tag("MAX HEAT", COLORS.sl, true)}
                      {r.ycInverted && tag("YC INVERTED", COLORS.sl, true)}
                      {r.leadFlash && r.leadSym && tag(`LEAD ${r.leadSym}`, COLORS.amber, true)}
                      {r.vcvCone && tag("VCV CONE", COLORS.amber, true)}
                      {(r.confCount ?? 0) >= 4 && tag("HIGH CONFLUENCE", COLORS.tp, true)}
                      {r.newsBlackout && tag("NEWS", COLORS.sl)}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* ================= MONITOR 3: Monte Carlo simulator ================= */}
        {monitor === "montecarlo" && (
          <div
            style={{
              background: COLORS.card,
              border: `1px solid ${COLORS.border}`,
              borderRadius: 12,
              overflow: "auto",
              padding: "4px 0",
            }}
          >
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr>
                  {["PAIR", "VERDICT", "TP FIRST", "SL FIRST", "R:R", "EV / 1R", "HORIZON"].map((h) => (
                    <th key={h} style={th}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {visible.length === 0 && (
                  <tr>
                    <td style={{ ...td, color: COLORS.muted }} colSpan={7}>
                      no plans to simulate yet…
                    </td>
                  </tr>
                )}
                {[...visible]
                  .sort((a, b) => (mcEV(b) ?? -9) - (mcEV(a) ?? -9))
                  .map((r) => {
                    const ev = mcEV(r);
                    return (
                      <tr key={`${r.symbol}|${r.timeframe}`} data-test={`mc-row-${r.symbol}-${r.timeframe}`}>
                        <td style={{ ...td, fontWeight: 700, whiteSpace: "nowrap" }}>
                          {r.symbol} {r.timeframe}
                        </td>
                        <td style={{ ...td, color: verdictColor(verdictOf(r)), fontWeight: 700 }}>
                          {verdictOf(r) || "—"}
                        </td>
                        <td style={{ ...td, minWidth: 140 }}>
                          {typeof r.mcTP === "number" && r.mcTP > 0 ? (
                            <span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
                              <span
                                style={{
                                  width: `${Math.max(2, Math.min(100, r.mcTP))}px`,
                                  height: 8,
                                  background: COLORS.tp,
                                  borderRadius: 4,
                                  display: "inline-block",
                                }}
                              />
                              <b style={{ color: COLORS.tp }}>{Math.round(r.mcTP)}%</b>
                            </span>
                          ) : (
                            <span style={{ color: COLORS.muted }}>—</span>
                          )}
                        </td>
                        <td style={{ ...td, minWidth: 140 }}>
                          {typeof r.mcSL === "number" && r.mcSL > 0 ? (
                            <span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
                              <span
                                style={{
                                  width: `${Math.max(2, Math.min(100, r.mcSL))}px`,
                                  height: 8,
                                  background: COLORS.sl,
                                  borderRadius: 4,
                                  display: "inline-block",
                                }}
                              />
                              <b style={{ color: COLORS.sl }}>{Math.round(r.mcSL)}%</b>
                            </span>
                          ) : (
                            <span style={{ color: COLORS.muted }}>—</span>
                          )}
                        </td>
                        <td style={td}>{r.rr ? `1:${Number(r.rr).toFixed(2)}` : "—"}</td>
                        <td style={{ ...td, fontWeight: 800, color: (ev ?? 0) > 0 ? COLORS.tp : COLORS.sl }}>
                          {ev !== null ? `${ev >= 0 ? "+" : ""}${ev.toFixed(2)}R` : "—"}
                        </td>
                        <td style={{ ...td, color: COLORS.muted }}>40 bars (σ = ATR)</td>
                      </tr>
                    );
                  })}
              </tbody>
            </table>
            <div style={{ color: COLORS.muted, fontSize: 11, padding: "8px 12px" }}>
              EV/1R = P(TP first) × R:R − P(SL first). Honest caveat: the EA's random walk uses σ = ATR
              as an upper-bound volatility proxy — compare rows, do not read absolute probabilities as gospel.
            </div>
          </div>
        )}

        {/* ================= MONITOR 4: journal ================= */}
        {monitor === "journal" && (
          <div style={{ display: "grid", gap: 12 }}>
            <div
              style={{
                background: COLORS.card,
                border: `1px solid ${COLORS.border}`,
                borderRadius: 12,
                padding: "12px 14px",
                display: "grid",
                gap: 8,
              }}
            >
              <div style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>
                ON-CHART JOURNAL — double-click any MT5 chart to pin a note at that exact price/time;
                the EA stores it in MQL5\Files\PAICT_Notes.csv and pushes it here as notes[]
              </div>
              {journalRows.length === 0 && (
                <div style={{ color: COLORS.muted, fontSize: 13 }}>
                  no notes yet — double-click a chart covered by the EA, type, press ENTER
                </div>
              )}
              {journalRows.map((n, i) => (
                <div
                  key={`${n.slot}-${n.time}-${i}`}
                  data-test={`journal-row-${i}`}
                  style={{
                    display: "flex",
                    gap: 14,
                    flexWrap: "wrap",
                    alignItems: "baseline",
                    borderBottom: `1px solid ${COLORS.border}`,
                    paddingBottom: 6,
                  }}
                >
                  <span style={{ color: COLORS.violet, fontWeight: 700, fontSize: 11, whiteSpace: "nowrap" }}>
                    [N]
                  </span>
                  <span style={{ color: COLORS.muted, fontSize: 12, minWidth: 130 }}>{n.time}</span>
                  <b style={{ fontSize: 12, whiteSpace: "nowrap" }}>{n.slot}</b>
                  <span style={{ color: COLORS.entry, fontSize: 12, fontVariantNumeric: "tabular-nums" }}>
                    @ {n.price.toFixed(2)}
                  </span>
                  <span style={{ fontSize: 13 }}>{n.text}</span>
                </div>
              ))}
            </div>
            {visible.some((r) => r.tuner) && (
              <div
                style={{
                  background: COLORS.card,
                  border: `1px solid ${COLORS.border}`,
                  borderRadius: 12,
                  padding: "12px 14px",
                  display: "grid",
                  gap: 6,
                }}
              >
                <div style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>
                  TUNER SUGGESTIONS (paict_tuner.py — suggestions only, nothing applies itself)
                </div>
                {visible
                  .filter((r) => r.tuner)
                  .map((r) => (
                    <div key={`${r.symbol}|${r.timeframe}`} style={{ fontSize: 12 }}>
                      <b>{r.symbol} {r.timeframe}</b> — <span style={{ color: COLORS.amber }}>{r.tuner}</span>
                    </div>
                  ))}
              </div>
            )}
          </div>
        )}

        {/* ================= MONITOR 5: oracle console ================= */}
        {monitor === "oracle" && (
          <div style={{ display: "grid", gap: 12 }}>
            {perfectRows.length > 0 && (
              <div
                style={{
                  background: "#0d2b1c",
                  border: `2px solid ${COLORS.tp}`,
                  borderRadius: 12,
                  padding: "16px 20px",
                  display: "flex",
                  gap: 16,
                  flexWrap: "wrap",
                  alignItems: "center",
                }}
              >
                <span
                  style={{
                    color: COLORS.tp,
                    fontWeight: 900,
                    fontSize: 26,
                    animation: "paictPulse 1.1s ease-in-out infinite",
                  }}
                >
                  PERFECT SETUP
                </span>
                {perfectRows.map((r) => (
                  <span key={`${r.symbol}|${r.timeframe}`} style={{ color: COLORS.text, fontWeight: 700 }}>
                    {r.symbol} {r.timeframe} — oracle {r.oracleScore} · master {r.masterScore}
                  </span>
                ))}
              </div>
            )}
            <div
              style={{
                background: COLORS.card,
                border: `1px solid ${COLORS.border}`,
                borderRadius: 12,
                overflow: "auto",
              }}
            >
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <thead>
                  <tr>
                    {["PAIR", "ORACLE", "MASTER", "CONFLUENCE", "REGIME", "H/K", "NEWS", "VISION"].map((h) => (
                      <th key={h} style={th}>
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {visible.length === 0 && (
                    <tr>
                      <td style={{ ...td, color: COLORS.muted }} colSpan={8}>
                        oracle idles until the EA pushes plans…
                      </td>
                    </tr>
                  )}
                  {[...visible]
                    .sort((a, b) => (b.oracleScore ?? -1) - (a.oracleScore ?? -1))
                    .map((r) => (
                      <tr
                        key={`${r.symbol}|${r.timeframe}`}
                        data-test={`oracle-row-${r.symbol}-${r.timeframe}`}
                        onClick={() => setPinned(`${r.symbol}|${r.timeframe}`)}
                        style={{ cursor: "pointer" }}
                      >
                        <td style={{ ...td, fontWeight: 700, whiteSpace: "nowrap" }}>
                          {r.symbol} {r.timeframe}
                        </td>
                        <td style={td}>{oracleCell(r)}</td>
                        <td style={td}>{masterCell(r)}</td>
                        <td style={td}>{confCell(r)}</td>
                        <td style={td}>{regimeCell(r)}</td>
                        <td style={{ ...td, color: COLORS.muted, fontSize: 11 }}>
                          {typeof r.hurst === "number"
                            ? `H ${r.hurst.toFixed(2)} / KER ${Number(r.ker ?? 0).toFixed(2)}`
                            : "—"}
                        </td>
                        <td style={td}>{newsCell(r)}</td>
                        <td style={td}>{visionCell(r)}</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
            <div style={{ display: "grid", gap: 12, gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))" }}>
              <div
                data-test="yc-panel"
                style={{
                  background: COLORS.card,
                  border: `1px solid ${COLORS.border}`,
                  borderRadius: 12,
                  padding: "12px 14px",
                  display: "grid",
                  gap: 6,
                }}
              >
                <div style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>
                  LOCAL YIELD CURVE (bond CFDs, v15)
                </div>
                {ycRows.length === 0 && (
                  <div style={{ color: COLORS.muted, fontSize: 12 }}>
                    no bond quotes — set InpYieldShort / InpYieldLong to your broker's bond CFDs
                  </div>
                )}
                {ycRows.map((r) => (
                  <div key={`${r.symbol}|${r.timeframe}`} style={{ fontSize: 12, display: "flex", gap: 10, flexWrap: "wrap" }}>
                    <b>{r.symbol}</b>
                    <span style={{ color: r.ycInverted ? COLORS.sl : COLORS.muted, fontWeight: 700 }}>
                      {r.ycInverted ? "INVERTED " : "spread "}
                      {Number(r.ycSpread).toFixed(0)} bps
                    </span>
                  </div>
                ))}
              </div>
              <div
                data-test="lead-panel"
                style={{
                  background: COLORS.card,
                  border: `1px solid ${COLORS.border}`,
                  borderRadius: 12,
                  padding: "12px 14px",
                  display: "grid",
                  gap: 6,
                }}
              >
                <div style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>
                  LEAD/LAG WATCH (intermarket, v15)
                </div>
                {leadRows.length === 0 && (
                  <div style={{ color: COLORS.muted, fontSize: 12 }}>
                    quiet — no lead asset moving beyond 0.8 × its own ATR
                  </div>
                )}
                {leadRows.map((r) => (
                  <div key={`${r.symbol}|${r.timeframe}`} style={{ fontSize: 12, display: "flex", gap: 10, flexWrap: "wrap" }}>
                    <b style={{ color: COLORS.amber }}>
                      LEAD {r.leadSym} {Number(r.leadMove) >= 0 ? "+" : ""}
                      {Number(r.leadMove).toFixed(1)}σ
                    </b>
                    <span>— expect {r.symbol} reaction ({(r.leadDir ?? 0) > 0 ? "up" : "down"})</span>
                  </div>
                ))}
              </div>
              <div
                style={{
                  background: COLORS.card,
                  border: `1px solid ${COLORS.border}`,
                  borderRadius: 12,
                  padding: "12px 14px",
                  display: "grid",
                  gap: 6,
                }}
              >
                <div style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>
                  REGIME DISTRIBUTION (v14)
                </div>
                <div style={{ display: "flex", gap: 12, flexWrap: "wrap", fontSize: 12 }}>
                  <span style={{ color: COLORS.tp, fontWeight: 700 }}>TRENDING {regimeCounts.TRENDING}</span>
                  <span style={{ color: COLORS.amber, fontWeight: 700 }}>RANGING {regimeCounts.RANGING}</span>
                  <span style={{ color: COLORS.muted, fontWeight: 700 }}>TRANSITION {regimeCounts.TRANSITION}</span>
                </div>
                <div style={{ color: COLORS.muted, fontSize: 11 }}>
                  Hurst R/S + Kaufman ER classify every covered chart; the Master Score is gated −15 when
                  an ICT trend-continuation plan fights a RANGING regime (+5 when it rides a TRENDING one).
                </div>
              </div>
            </div>
          </div>
        )}

        {/* pinned / newest row detail (matrix monitor) */}
        {monitor === "matrix" && pinnedRow && (
          <>
            <div data-test="pin-card" style={{ display: "grid", gap: 12 }}>
              <div style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>
                PINNED — {pinnedSlot}
              </div>
              <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
                {levelCard("ENTRY", pinnedRow.entry, COLORS.entry)}
                {levelCard("STOP LOSS", pinnedRow.sl, COLORS.sl)}
                {levelCard("TAKE PROFIT", pinnedRow.tp, COLORS.tp)}
                <div
                  style={{
                    flex: "1 1 140px",
                    background: COLORS.card,
                    border: `1px solid ${COLORS.border}`,
                    borderLeft: "4px solid #8b93a7",
                    borderRadius: 10,
                    padding: "10px 14px",
                  }}
                >
                  <div style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>R : R</div>
                  <div style={{ fontSize: 22, fontWeight: 700, color: COLORS.text }}>
                    {pinnedRow.rr ? `1 : ${Number(pinnedRow.rr).toFixed(2)}` : "—"}
                  </div>
                </div>
              </div>

              {/* v6 sandbox live box — follows chart drags */}
              {pinnedSb && (
                <div
                  data-test="sandbox-box"
                  style={{
                    background: COLORS.card,
                    border: `1px solid ${COLORS.entry}55`,
                    borderRadius: 10,
                    padding: "10px 14px",
                    display: "flex",
                    gap: 18,
                    flexWrap: "wrap",
                    alignItems: "center",
                    fontSize: 12,
                  }}
                >
                  <span style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>
                    SANDBOX (dragged on chart — live)
                  </span>
                  <span>
                    E / S / T{" "}
                    <b style={{ color: COLORS.entry, fontVariantNumeric: "tabular-nums" }}>
                      {pinnedSb.e.toFixed(2)} / {pinnedSb.s.toFixed(2)} / {pinnedSb.t.toFixed(2)}
                    </b>
                  </span>
                  <span>
                    R:R{" "}
                    <b data-test="sandbox-rr" style={{ color: COLORS.text }}>
                      1 : {pinnedSb.rr.toFixed(2)}
                    </b>
                  </span>
                  <span>
                    LOTS{" "}
                    <b data-test="sandbox-lots" style={{ color: COLORS.entry }}>
                      {Number.isFinite(pinnedSb.lots)
                        ? `≈ ${pinnedSb.lots.toFixed(2)} @ risk ${pinnedRow.riskPct ?? "?"}%`
                        : "set risk % + plan on chart"}
                    </b>
                  </span>
                  <span style={{ color: COLORS.muted }}>
                    re-reads the V10 drag on every update
                  </span>
                </div>
              )}

              {/* co-pilot + oracle summary line for the pinned slot */}
              <div
                style={{
                  background: COLORS.card,
                  border: `1px solid ${pinnedRow.newsBlackout ? COLORS.sl : COLORS.border}`,
                  borderRadius: 10,
                  padding: "10px 14px",
                  fontSize: 12,
                  color: COLORS.muted,
                  display: "flex",
                  gap: 16,
                  flexWrap: "wrap",
                }}
              >
                <span>
                  COPILOT —{" "}
                  <b style={{ color: COLORS.entry }}>
                    {pinnedRow.riskLots
                      ? `risk ${pinnedRow.riskPct ?? "?"}% = ${Number(pinnedRow.riskLots).toFixed(2)} lots`
                      : "risk sizing awaiting plan"}
                  </b>
                </span>
                <span>
                  HEAT{" "}
                  <b style={{ color: pinnedRow.heatAlert ? COLORS.sl : COLORS.tp }}>
                    {typeof pinnedRow.heatPct === "number" ? `${pinnedRow.heatPct.toFixed(2)}%` : "—"}
                    {pinnedRow.heatAlert ? " · MAX PORTFOLIO HEAT" : ""}
                  </b>
                </span>
                <span>
                  NEWS{" "}
                  <b style={{ color: pinnedRow.newsBlackout ? COLORS.sl : COLORS.muted }}>
                    {pinnedRow.newsBlackout
                      ? `BLACKOUT${pinnedRow.newsEvent ? `: ${pinnedRow.newsEvent}` : ""}`
                      : "clear"}
                  </b>
                </span>
                <span>
                  MASTER{" "}
                  <b style={{ color: verdictColor(pinnedRow.masterVerdict) }}>
                    {pinnedRow.masterVerdict && (pinnedRow.masterScore ?? -1) >= 0
                      ? `${pinnedRow.masterVerdict} ${pinnedRow.masterScore ?? ""}`
                      : "—"}
                  </b>
                </span>
                <span>
                  ORACLE{" "}
                  <b style={{ color: (pinnedRow.oracleScore ?? -1) >= PERFECT_AT ? COLORS.tp : COLORS.text }}>
                    {typeof pinnedRow.oracleScore === "number" && pinnedRow.oracleScore >= 0
                      ? pinnedRow.oracleScore
                      : "—"}
                  </b>
                </span>
                <span>
                  CONFLUENCE{" "}
                  <b style={{ color: COLORS.violet }}>
                    {typeof pinnedRow.confluence === "number" && pinnedRow.confluence > 0
                      ? `${pinnedRow.confluence} · ${pinnedRow.confCount ?? "?"}× ${pinnedRow.confTags ?? ""}`
                      : "—"}
                  </b>
                </span>
                <span>
                  REGIME{" "}
                  <b style={{ color: regimeColor(pinnedRow.regime) }}>
                    {pinnedRow.regime ?? "—"}
                    {typeof pinnedRow.hurst === "number"
                      ? ` · H ${pinnedRow.hurst.toFixed(2)}/${Number(pinnedRow.ker ?? 0).toFixed(2)}`
                      : ""}
                  </b>
                </span>
                <span>
                  PATTERN{" "}
                  <b style={{ color: COLORS.violet }}>
                    {pinnedRow.harmonic
                      ? `${pinnedRow.harmonic}${pinnedRow.harmDir && pinnedRow.harmDir > 0 ? " (bull)" : " (bear)"}`
                      : pinnedRow.elliott
                        ? `EW ${pinnedRow.elliott}`
                        : "—"}
                  </b>
                </span>
                <span>
                  YC{" "}
                  <b style={{ color: pinnedRow.ycInverted ? COLORS.sl : COLORS.muted }}>
                    {typeof pinnedRow.ycSpread === "number"
                      ? `${pinnedRow.ycSpread.toFixed(0)} bps${pinnedRow.ycInverted ? " INVERTED" : ""}`
                      : "—"}
                  </b>
                </span>
                <span>
                  LEAD{" "}
                  <b style={{ color: pinnedRow.leadFlash ? COLORS.amber : COLORS.muted }}>
                    {pinnedRow.leadFlash && pinnedRow.leadSym
                      ? `${pinnedRow.leadSym} ${Number(pinnedRow.leadMove).toFixed(1)}σ`
                      : "—"}
                  </b>
                </span>
                <span>
                  ALIGN{" "}
                  <b style={{ color: (pinnedRow.alignScore ?? 0) > 0 ? COLORS.tp : COLORS.muted }}>
                    {typeof pinnedRow.alignScore === "number"
                      ? `${pinnedRow.alignScore > 0 ? "+" : ""}${pinnedRow.alignScore}/5`
                      : "—"}
                  </b>
                </span>
                <span>
                  MC{" "}
                  <b style={{ color: COLORS.text }}>
                    {typeof pinnedRow.mcTP === "number" && pinnedRow.mcTP > 0
                      ? `TP ${Math.round(pinnedRow.mcTP)}% · SL ${Math.round(pinnedRow.mcSL ?? 0)}%`
                      : "—"}
                  </b>
                </span>
                <span>
                  CVD{" "}
                  <b
                    style={{
                      color:
                        (pinnedRow.cvdDir ?? 0) > 0
                          ? COLORS.tp
                          : (pinnedRow.cvdDir ?? 0) < 0
                            ? COLORS.sl
                            : COLORS.muted,
                    }}
                  >
                    {pinnedRow.cvdDir === 1 ? "up" : pinnedRow.cvdDir === -1 ? "down" : "—"}
                    {pinnedRow.cvdDiv ? " · DIV" : ""}
                  </b>
                </span>
                <span>
                  CORR{" "}
                  <b style={{ color: pinnedRow.corrWarn ? COLORS.amber : COLORS.muted }}>
                    {pinnedRow.corrSym
                      ? `${pinnedRow.corrSym} r=${Number(pinnedRow.corrR ?? 0).toFixed(2)}${pinnedRow.corrWarn ? " DIVERGING" : ""}`
                      : "—"}
                  </b>
                </span>
                <span>
                  POC/VA{" "}
                  <b style={{ color: COLORS.text }}>
                    {pinnedRow.poc
                      ? `${Number(pinnedRow.poc).toFixed(2)} · ${Number(pinnedRow.vah).toFixed(2)}/${Number(pinnedRow.val).toFixed(2)}`
                      : "—"}
                  </b>
                </span>
                <span>
                  SANDBOX{" "}
                  <b style={{ color: pinnedRow.sbActive ? COLORS.entry : COLORS.muted }}>
                    {pinnedRow.sbActive
                      ? `${Number(pinnedRow.sbEntry).toFixed(2)} / ${Number(pinnedRow.sbStop).toFixed(2)} / ${Number(pinnedRow.sbTP).toFixed(2)}`
                      : "—"}
                  </b>
                </span>
                {pinnedRow.tuner && (
                  <span>
                    TUNER <b style={{ color: COLORS.amber }}>{pinnedRow.tuner}</b>
                  </span>
                )}
              </div>
            </div>

            {/* remote control (v4 two-way bridge) */}
            <div
              style={{
                background: COLORS.card,
                border: `1px solid ${COLORS.border}`,
                borderRadius: 10,
                padding: "12px 14px",
                display: "flex",
                gap: 10,
                flexWrap: "wrap",
                alignItems: "center",
              }}
            >
              <span style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1 }}>
                REMOTE CONTROL — {pinnedSlot || "no slot"}
              </span>
              <input
                data-test="remote-risk-input"
                value={riskInput}
                onChange={(e) => setRiskInput(e.target.value)}
                inputMode="decimal"
                style={{
                  width: 80,
                  padding: "8px 10px",
                  borderRadius: 8,
                  border: `1px solid ${COLORS.border}`,
                  background: COLORS.bg,
                  color: COLORS.text,
                  fontSize: 13,
                }}
                placeholder="risk %"
              />
              <button
                data-test="remote-risk-apply"
                style={btn}
                onClick={() => sendCommand("SET_RISK", Number(riskInput) || 0)}
              >
                Apply risk %
              </button>
              <button data-test="remote-zones" style={btn} onClick={() => sendCommand("TOGGLE_ZONES", 1)}>
                Zones on
              </button>
              <button data-test="remote-zones" style={btn} onClick={() => sendCommand("TOGGLE_ZONES", 0)}>
                Zones off
              </button>
              <button data-test="remote-render" style={btn} onClick={() => sendCommand("SET_RENDER", 1)}>
                Render on
              </button>
              <button data-test="remote-render" style={btn} onClick={() => sendCommand("SET_RENDER", 0)}>
                Render off
              </button>
              <button
                data-test="remote-sandbox"
                style={btn}
                onClick={() => sendCommand("TOGGLE_SANDBOX", 1)}
              >
                Sandbox on
              </button>
              <button
                data-test="remote-sandbox"
                style={btn}
                onClick={() => sendCommand("TOGGLE_SANDBOX", 0)}
              >
                Sandbox off
              </button>
              <button
                data-test="remote-sandbox"
                style={btn}
                onClick={() => sendCommand("RESET_SANDBOX", 0)}
              >
                Sandbox reset
              </button>
              <span data-test="remote-status" style={{ color: COLORS.muted, fontSize: 12 }}>
                {remoteMsg}
              </span>
            </div>

            {/* raw payload */}
            <div>
              <div style={{ color: COLORS.muted, fontSize: 11, letterSpacing: 1, marginBottom: 6 }}>
                RAW PAYLOAD — {pinnedRow.symbol} {pinnedRow.timeframe}
              </div>
              <pre
                style={{
                  margin: 0,
                  background: COLORS.card,
                  border: `1px solid ${COLORS.border}`,
                  borderRadius: 10,
                  padding: 14,
                  fontSize: 12,
                  overflow: "auto",
                  maxHeight: 220,
                  color: COLORS.muted,
                }}
              >
                {JSON.stringify(pinnedRow, null, 2)}
              </pre>
            </div>
          </>
        )}

        <footer style={{ color: COLORS.muted, fontSize: 12, paddingBottom: 8 }}>
          MASTER SCORE = R:R (25) + fractal alignment (15) + Monte Carlo TP% (20) + displacement (10) +
          CVD (10), minus correlation divergence and heat penalties, regime-gated (v14: −15
          trend-continuation in a RANGING regime, +5 aligned in TRENDING); news blackout scales it to
          20%. ORACLE SCORE = master 45% + confluence 25% + flow sentiment 15% + regime alignment 15%
          (v15) — ≥ 85 flashes PERFECT SETUP. Verdict GO ≥ 70 · WAIT 45–69 · NO TRADE &lt; 45. Grade
          filters apply strictly to the Master Score (legacy quality grade only displays). Feed:
          WebSocket push from bridge v6 with automatic 3 s polling fallback. EA v15.00 · bridge v6 ·
          dashboard v7.
        </footer>
      </div>
    </div>
  );
}
