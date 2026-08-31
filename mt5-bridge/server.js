/**
 * mt5-bridge reference server v6 — MULTI-WINDOW WEBSOCKET STREAMING
 * + multi-pair matrix + two-way remote control + mailbox passthrough
 * (C:\Users\25193\mt5-bridge\web\mt_nodejs\server.js or similar)
 *
 * What changed vs v5:
 *  - MULTI-WINDOW WEBSOCKET (RFC 6455, pure Node core — no `ws` package):
 *    every connected dashboard window gets pushed the full matrix the
 *    moment ANY EA push lands, plus command-queue updates and a 30 s
 *    keepalive ping. Point any number of browser windows/monitors at
 *    ws://127.0.0.1:8891/ (same port as HTTP — the same server just
 *    upgrades the protocol). HTTP polling stays as the fallback.
 *  - Wire messages: {type:"hello"} on connect, {type:"matrix", rows:[...]}
 *    on every push/clear, {type:"commands", slots} when the queue changes.
 *
 * What carried over from v5/v4 (unchanged):
 *  - COMMAND QUEUE: POST /v1/commands {slot, action, value}, the EA pulls
 *    GET /v1/poll?slot=SYMBOL|TF after every accepted push; the queue
 *    drains (exactly-once). Whitelist: SET_RISK, TOGGLE_ZONES, SET_RENDER,
 *    TOGGLE_SANDBOX, RESET_SANDBOX, PING — anything else is a 400.
 *  - MAILBOX PASSTHROUGH: GET /v1/snapshot serves the EA's
 *    PAICT_matrix_snapshot.json verbatim when PAICT_SNAPSHOT_FILE is set.
 *  - MULTI-SLOT matrix keyed "SYMBOL|TIMEFRAME", GET /v1/matrix returns an
 *    ARRAY newest-first, DELETE /v1/matrix clears the rows.
 *
 * Run:
 *    npm init -y && npm i express
 *    node mt5-bridge-server.js            (BRIDGE_PORT=8892 to dodge a busy port)
 *    PAICT_SNAPSHOT_FILE="C:\Users\me\AppData\Roaming\MetaQuotes\Terminal\XXX\MQL5\Files\PAICT_matrix_snapshot.json" node mt5-bridge-server.js
 *
 * Smoke test without MT5:
 *    curl -X POST http://127.0.0.1:8891/v1/matrix ^
 *         -H "Content-Type: application/json" ^
 *         -d "{\"symbol\":\"XAUUSDz\",\"timeframe\":\"M15\",\"side\":\"long\",\"entry\":2350.5,\"sl\":2340.0,\"tp\":2371.5,\"rr\":2.0,\"status\":\"live\",\"time\":\"2026.08.29 06:08:02 GMT\"}"
 *    curl http://127.0.0.1:8891/v1/matrix
 *    curl -X POST http://127.0.0.1:8891/v1/commands -H "Content-Type: application/json" ^
 *         -d "{\"slot\":\"XAUUSDz|M15\",\"action\":\"SET_RISK\",\"value\":0.5}"
 *    curl "http://127.0.0.1:8891/v1/poll?slot=XAUUSDz%7CM15"
 *
 * Contract (matches PAICT_ChartMarkup.mq5 v15.00 pushes — all oracle keys
 * optional, older dashboards ignore them):
 *    POST   /v1/matrix     { symbol, timeframe, side, entry, sl, tp, rr,
 *                            status, time, riskPct?, riskLots?, heatPct?,
 *                            heatAlert?, newsBlackout?, newsEvent?,
 *                            alignScore?, mcTP?, mcSL?, cvdDir?, cvdDiv?,
 *                            displacement?, corrSym?, corrR?, corrWarn?,
 *                            poc?, vah?, val?, setupMuted?, masterScore?,
 *                            masterVerdict?, sbEntry?, sbStop?, sbTP?,
 *                            sbActive?, tuner?,
 *                            regime?, hurst?, ker?, vcvSqueeze?, vcvCone?,
 *                            confluence?, confCount?, confTags?, harmonic?,
 *                            harmDir?, przLo?, przHi?, elliott?, ewDir?,
 *                            ycSpread?, ycInverted?, leadSym?, leadMove?,
 *                            leadDir?, leadFlash?, oracleScore?, notes? }
 *    GET    /v1/matrix     -> [ row, ... ]  newest first (row = last push per symbol+tf)
 *    DELETE /v1/matrix     -> { ok: true, cleared: true }
 *    POST   /v1/commands   -> { ok: true, queued: N, slot }
 *    GET    /v1/poll?slot= -> text/plain "CMD <id> <action> <value>" lines, then clears
 *    GET    /v1/commands   -> { ok: true, slots: { slot: [cmd, ...] } }
 *    DELETE /v1/commands   -> { ok: true, cleared: true }
 *    GET    /v1/snapshot   -> the EA mailbox JSON verbatim (503 when unset/stale)
 *    POST   /v1/news       -> { slot, event: {id, biasDir, score, headline, tags, at} }
 *                             (paict_news.py). Deduped by event.id; the freshest
 *                             event per slot is also mirrored onto that slot's
 *                             matrix row (newsBiasDir/newsBiasScore/newsHeadline)
 *                             so existing matrix consumers see it for free.
 *    GET    /v1/news[?slot=] -> [ event, ... ] newest-first for one slot, or
 *                             { slot: [event, ...], ... } for all slots
 *    POST   /v1/vision     -> { slot, source, patterns:[...], wicks:[...] }
 *                             (paict_vision.py). Replaces the slot's prior
 *                             reading and is mirrored onto that slot's matrix
 *                             row (visionPatterns/visionWicks).
 *    GET    /v1/vision[?slot=] -> { patterns, wicks, source, receivedAt } for
 *                             one slot, or { slot: {...}, ... } for all slots
 *    GET    /v1/health     -> uptime + push stats + ws clients + mailbox state
 *    WS     /              -> RFC 6455 upgrade, broadcast feed (see above)
 *
 * The EA POSTs /v1/matrix and GETs /v1/poll; paict_news.py/paict_vision.py
 * POST /v1/news and /v1/vision from the same machine; the dashboard (any
 * number of windows) consumes the REST + the WebSocket feed.
 */

"use strict";

const express = require("express");
const fs = require("fs");
const app = express();

app.disable("x-powered-by");

// REQUIRED. Without express.json(), req.body is undefined and any
// `req.body.symbol` access throws TypeError -> the classic HTML 500.
app.use(express.json({ limit: "64kb" }));

// CORS — the React dashboard (e.g. http://localhost:8002) fetches this
// API from the browser, so the browser needs an explicit allow-origin.
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

// Multi-slot matrix — one row per SYMBOL|TIMEFRAME; every push upserts.
const MAX_ROWS = 50;
const matrix = new Map(); // "XAUUSDz|M15" -> { ...payload, receivedAt }
const stats = { posts: 0, lastPostAt: null, lastError: null };

// ---- v6 multi-window WebSocket streaming (RFC 6455, Node core only) -----
const crypto = require("crypto");
const WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const WS_MAX_BUFFER = 1024 * 1024; // 1 MB per-socket frame buffer cap
const WS_CLIENTS = new Set();

const wsAccept = (key) =>
  crypto.createHash("sha1").update(key + WS_MAGIC).digest("base64");

// unmasked server->client text frame
function wsEncode(text) {
  const payload = Buffer.from(text, "utf8");
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.from([0x81, len]);
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payload]);
}

function wsSend(client, text) {
  try {
    if (!client.sock.destroyed) client.sock.write(wsEncode(text));
  } catch {
    WS_CLIENTS.delete(client);
  }
}

function wsBroadcast(text) {
  for (const c of [...WS_CLIENTS]) wsSend(c, text);
}

const wsBroadcastMatrix = () =>
  wsBroadcast(
    JSON.stringify({
      type: "matrix",
      rows: rowsNewestFirst(),
      at: new Date().toISOString(),
    }),
  );

function wsBroadcastCommands() {
  const slots = {};
  for (const [k, v] of commands) if (v.length) slots[k] = v;
  wsBroadcast(JSON.stringify({ type: "commands", slots, nextId: nextCmdId }));
}

// incremental frame reader (client frames are always masked per RFC 6455)
function wsFeed(client, chunk) {
  client.buf = Buffer.concat([client.buf, chunk]);
  if (client.buf.length > WS_MAX_BUFFER) {
    client.sock.destroy();
    return;
  }
  for (;;) {
    const buf = client.buf;
    if (buf.length < 2) return;
    const opcode = buf[0] & 0x0f;
    const masked = (buf[1] & 0x80) !== 0;
    let len = buf[1] & 0x7f;
    let off = 2;
    if (len === 126) {
      if (buf.length < 4) return;
      len = buf.readUInt16BE(2);
      off = 4;
    } else if (len === 127) {
      if (buf.length < 10) return;
      const big = buf.readBigUInt64BE(2);
      if (big > BigInt(WS_MAX_BUFFER)) {
        client.sock.destroy();
        return;
      }
      len = Number(big);
      off = 10;
    }
    if (len > WS_MAX_BUFFER) {
      client.sock.destroy();
      return;
    }
    const maskLen = masked ? 4 : 0;
    if (buf.length < off + maskLen + len) return;
    let payload = buf.subarray(off + maskLen, off + maskLen + len);
    if (masked) {
      const mask = buf.subarray(off, off + 4);
      const un = Buffer.allocUnsafe(len);
      for (let i = 0; i < len; i++) un[i] = payload[i] ^ mask[i & 3];
      payload = un;
    }
    client.buf = buf.subarray(off + maskLen + len);
    if (opcode === 0x8) {
      // close — echo an empty close frame and drop
      try {
        client.sock.end(Buffer.from([0x88, 0x00]));
      } catch {
        /* already gone */
      }
      return;
    }
    if (opcode === 0x9) {
      // ping -> pong (same payload)
      const head = Buffer.from([0x8a, Math.min(payload.length, 125)]);
      try {
        client.sock.write(Buffer.concat([head, payload.subarray(0, 125)]));
      } catch {
        WS_CLIENTS.delete(client);
      }
    }
    // text/binary/continuation frames from the dashboard are ignored —
    // this feed is one-way push (the dashboard talks REST).
  }
}

// 30 s keepalive ping — dead sockets surface on write error and drop
setInterval(() => {
  for (const c of [...WS_CLIENTS]) {
    if (c.sock.destroyed) {
      WS_CLIENTS.delete(c);
      continue;
    }
    try {
      c.sock.write(Buffer.from([0x89, 0x00]));
    } catch {
      WS_CLIENTS.delete(c);
    }
  }
}, 30000).unref();

// v4 two-way bridge — pending commands per slot, popped on handout.
const MAX_PENDING_PER_SLOT = 20;
const commands = new Map(); // "XAUUSDz|M15" -> [ { id, action, value, ts } ]
let nextCmdId = 1;

// action -> value validator ("number" | "flag" | "none")
const ACTIONS = {
  SET_RISK: "number",
  TOGGLE_ZONES: "flag",
  SET_RENDER: "flag",
  TOGGLE_SANDBOX: "flag",
  RESET_SANDBOX: "none",
  PING: "none",
};

// v5 mailbox passthrough — set PAICT_SNAPSHOT_FILE to the EA's
// PAICT_matrix_snapshot.json (inside MQL5\Files) to enable /v1/snapshot.
const SNAPSHOT_FILE = process.env.PAICT_SNAPSHOT_FILE || "";

const slotKey = (v) => String(v || "").trim().toUpperCase();

// Matrix rows are keyed by the RAW "symbol|timeframe" (case preserved, e.g.
// "XAUUSDz|M15") so the dashboard can display the broker's exact symbol
// spelling, while /v1/commands, /v1/news and /v1/vision all key by the
// uppercased slotKey(). Merging a news/vision reading onto its matrix row
// needs a case-insensitive match against that raw key — matrix.has(slot)
// would silently miss any symbol carrying a broker suffix like "z" or "m".
const findMatrixKey = (slot) => {
  for (const k of matrix.keys()) if (slotKey(k) === slot) return k;
  return null;
};

const rowsNewestFirst = () =>
  [...matrix.values()].sort((a, z) =>
    String(z.receivedAt).localeCompare(String(a.receivedAt)),
  );

app.post("/v1/matrix", (req, res) => {
  const b = req.body || {};
  if (typeof b.symbol !== "string" || b.symbol.length === 0) {
    return res
      .status(400)
      .json({ ok: false, error: "missing symbol — is the body JSON?" });
  }
  stats.posts += 1;
  stats.lastPostAt = new Date().toISOString();
  const key = `${b.symbol}|${b.timeframe || "?"}`;
  matrix.set(key, { ...b, receivedAt: stats.lastPostAt });
  if (matrix.size > MAX_ROWS) {
    // evict the single oldest row so long sessions cannot grow unbounded
    const oldest = rowsNewestFirst()[rowsNewestFirst().length - 1];
    if (oldest) matrix.delete(`${oldest.symbol}|${oldest.timeframe || "?"}`);
  }
  wsBroadcastMatrix(); // v6: push every monitor window instantly
  res.json({ ok: true, stored: key, pairs: matrix.size });
});

app.get("/v1/matrix", (req, res) => res.json(rowsNewestFirst()));

app.delete("/v1/matrix", (req, res) => {
  matrix.clear();
  wsBroadcastMatrix();
  res.json({ ok: true, cleared: true });
});

// ---- v4 remote control -------------------------------------------------

app.post("/v1/commands", (req, res) => {
  const b = req.body || {};
  const slot = slotKey(b.slot);
  const action = String(b.action || "").trim().toUpperCase();
  if (!slot) {
    return res
      .status(400)
      .json({ ok: false, error: "missing slot — use \"SYMBOL|TIMEFRAME\"" });
  }
  if (!(action in ACTIONS)) {
    return res.status(400).json({
      ok: false,
      error: `unknown action — use ${Object.keys(ACTIONS).join(" | ")}`,
    });
  }
  let value = b.value;
  if (ACTIONS[action] === "number") {
    value = Number(value);
    if (!Number.isFinite(value) || value <= 0) {
      return res
        .status(400)
        .json({ ok: false, error: "value must be a positive number" });
    }
  } else if (ACTIONS[action] === "flag") {
    value = value ? 1 : 0;
  } else {
    value = 0;
  }
  if (!commands.has(slot)) commands.set(slot, []);
  const q = commands.get(slot);
  const cmd = { id: nextCmdId++, action, value, ts: new Date().toISOString() };
  q.push(cmd);
  if (q.length > MAX_PENDING_PER_SLOT) q.shift(); // cap: drop the oldest
  wsBroadcastCommands(); // v6: every monitor window sees the queue live
  res.json({ ok: true, queued: q.length, slot, cmd });
});

// The EA polls this right after every accepted push. One command per line:
//   CMD <id> <action> <value>
// Handout = pop (drain), so commands are applied exactly once.
app.get("/v1/poll", (req, res) => {
  const slot = slotKey(req.query.slot);
  const q = commands.get(slot);
  if (q && q.length) {
    const lines = q.splice(0).map((c) => `CMD ${c.id} ${c.action} ${c.value}`);
    wsBroadcastCommands(); // queue drained — monitors update
    res.type("text/plain").send(lines.join("\n") + "\n");
  } else {
    res.type("text/plain").send("");
  }
});

// Debug/dashboard view of what is still pending.
app.get("/v1/commands", (req, res) => {
  const slots = {};
  for (const [k, v] of commands) if (v.length) slots[k] = v;
  res.json({ ok: true, slots, nextId: nextCmdId });
});

app.delete("/v1/commands", (req, res) => {
  commands.clear();
  wsBroadcastCommands();
  res.json({ ok: true, cleared: true });
});

// ---- v5 mailbox passthrough --------------------------------------------

// Serves the EA's local snapshot file verbatim. Readers get `mtimeMs` so
// they can detect a stale mailbox (the EA rewrites it on every push).
app.get("/v1/snapshot", (req, res) => {
  if (!SNAPSHOT_FILE) {
    return res.status(503).json({
      ok: false,
      error:
        "mailbox not configured — start the server with PAICT_SNAPSHOT_FILE=<path to MQL5\\Files\\PAICT_matrix_snapshot.json>",
    });
  }
  fs.readFile(SNAPSHOT_FILE, "utf8", (err, data) => {
    if (err) {
      return res
        .status(503)
        .json({ ok: false, error: `mailbox unreadable: ${err.code || err.message}` });
    }
    let mtimeMs = 0;
    try {
      mtimeMs = Math.round(fs.statSync(SNAPSHOT_FILE).mtimeMs);
    } catch {
      /* stat raced a rewrite — mtime stays 0, body still served */
    }
    res.type("application/json").send(data.length ? data : "{}\n");
    res.setHeader("X-Mailbox-Mtime", String(mtimeMs));
  });
});

// ---- news sentiment (paict_news.py) ------------------------------------

const MAX_NEWS_PER_SLOT = 20;
const news = new Map(); // "XAUUSDz|M15" -> [ {id, biasDir, score, headline, tags, at, receivedAt}, ... ] newest-first

app.post("/v1/news", (req, res) => {
  const b = req.body || {};
  const slot = slotKey(b.slot);
  const ev = b.event || {};
  if (!slot) {
    return res
      .status(400)
      .json({ ok: false, error: 'missing slot — use "SYMBOL|TIMEFRAME"' });
  }
  if (typeof ev.id !== "string" || ev.id.length === 0) {
    return res.status(400).json({ ok: false, error: "missing event.id" });
  }
  if (!news.has(slot)) news.set(slot, []);
  const q = news.get(slot);
  if (q.some((e) => e.id === ev.id)) {
    // paict_news.py retries a line until the POST succeeds, so a re-delivery
    // of an already-stored id is expected, not an error — dedupe silently.
    return res.json({ ok: true, slot, deduped: true });
  }
  const stored = { ...ev, receivedAt: new Date().toISOString() };
  q.unshift(stored);
  if (q.length > MAX_NEWS_PER_SLOT) q.length = MAX_NEWS_PER_SLOT;
  // Mirror the freshest reading onto the matrix row (if the slot already has
  // one) so the dashboard's existing per-row rendering picks it up with no
  // separate fetch — same pattern as every other oracle-engine field.
  const mk = findMatrixKey(slot);
  if (mk) {
    matrix.set(mk, {
      ...matrix.get(mk),
      newsBiasDir: stored.biasDir,
      newsBiasScore: stored.score,
      newsHeadline: stored.headline,
    });
  }
  wsBroadcastMatrix();
  wsBroadcast(JSON.stringify({ type: "news", slot, event: stored }));
  res.json({ ok: true, slot, stored: true });
});

app.get("/v1/news", (req, res) => {
  if (req.query.slot) return res.json(news.get(slotKey(req.query.slot)) || []);
  const out = {};
  for (const [k, v] of news) out[k] = v;
  res.json(out);
});

// ---- chart vision (paict_vision.py) ------------------------------------

const vision = new Map(); // "XAUUSDz|M15" -> { source, patterns, wicks, receivedAt }

app.post("/v1/vision", (req, res) => {
  const b = req.body || {};
  const slot = slotKey(b.slot);
  if (!slot) {
    return res
      .status(400)
      .json({ ok: false, error: 'missing slot — use "SYMBOL|TIMEFRAME"' });
  }
  const stored = {
    source: typeof b.source === "string" ? b.source : "paict-vision",
    patterns: Array.isArray(b.patterns) ? b.patterns : [],
    wicks: Array.isArray(b.wicks) ? b.wicks : [],
    receivedAt: new Date().toISOString(),
  };
  vision.set(slot, stored);
  const mk = findMatrixKey(slot);
  if (mk) {
    matrix.set(mk, {
      ...matrix.get(mk),
      visionPatterns: stored.patterns,
      visionWicks: stored.wicks,
    });
  }
  wsBroadcastMatrix();
  wsBroadcast(JSON.stringify({ type: "vision", slot, ...stored }));
  res.json({
    ok: true,
    slot,
    patterns: stored.patterns.length,
    wicks: stored.wicks.length,
  });
});

app.get("/v1/vision", (req, res) => {
  if (req.query.slot) {
    return res.json(vision.get(slotKey(req.query.slot)) || { patterns: [], wicks: [] });
  }
  const out = {};
  for (const [k, v] of vision) out[k] = v;
  res.json(out);
});

// ------------------------------------------------------------------------

app.get("/v1/health", (req, res) =>
  res.json({
    ok: true,
    ...stats,
    pairs: matrix.size,
    newsSlots: news.size,
    visionSlots: vision.size,
    wsClients: WS_CLIENTS.size,
    pendingCommands: [...commands.values()].reduce((n, q) => n + q.length, 0),
    mailbox: SNAPSHOT_FILE ? "configured" : "off",
    uptimeSec: Math.round(process.uptime()),
  }),
);

// Body-parser errors (malformed JSON) land HERE — readable JSON, not HTML.
app.use((err, req, res, next) => {
  stats.lastError = err.type || err.message;
  console.error("[bridge]", err.status || 500, err.type || "", err.message);
  res
    .status(err.status || 500)
    .json({ ok: false, error: err.type || err.message });
});

const PORT = process.env.BRIDGE_PORT || 8891;
const server = app.listen(PORT, "127.0.0.1", () => {
  console.log(`[bridge] listening on http://127.0.0.1:${PORT}`);
  console.log(
    "[bridge] matrix: POST/GET/DELETE /v1/matrix · remote: POST /v1/commands, GET /v1/poll · mailbox: GET /v1/snapshot · health: GET /v1/health · ws: ws://127.0.0.1:" +
      PORT +
      "/ (multi-window feed)",
  );
});

// v6: the SAME HTTP server upgrades to WebSocket for the multi-window feed
server.on("upgrade", (req, socket) => {
  try {
    const key = req.headers["sec-websocket-key"];
    const isWs = String(req.headers.upgrade || "").toLowerCase() === "websocket";
    if (!isWs || !key) {
      socket.write("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n");
      socket.destroy();
      return;
    }
    socket.write(
      "HTTP/1.1 101 Switching Protocols\r\n" +
        "Upgrade: websocket\r\n" +
        "Connection: Upgrade\r\n" +
        `Sec-WebSocket-Accept: ${wsAccept(key)}\r\n` +
        "\r\n",
    );
    socket.setNoDelay(true);
    const client = { sock: socket, buf: Buffer.alloc(0) };
    WS_CLIENTS.add(client);
    socket.on("data", (chunk) => wsFeed(client, chunk));
    socket.on("close", () => WS_CLIENTS.delete(client));
    socket.on("error", () => {
      WS_CLIENTS.delete(client);
      try {
        socket.destroy();
      } catch {
        /* already gone */
      }
    });
    wsSend(client, JSON.stringify({ type: "hello", clients: WS_CLIENTS.size }));
    wsSend(
      client,
      JSON.stringify({
        type: "matrix",
        rows: rowsNewestFirst(),
        at: new Date().toISOString(),
      }),
    );
  } catch {
    try {
      socket.destroy();
    } catch {
      /* nothing left to do */
    }
  }
});
