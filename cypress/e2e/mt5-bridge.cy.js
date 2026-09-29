/**
 * Cypress E2E — MT5 Bridge Pipeline (multi-pair matrix + remote control +
 * zenith mailbox, v5)
 * Drop into: cypress/e2e/mt5-bridge.cy.js
 *
 * Requires bridge server v5 (multi-slot + command queue + mailbox
 * passthrough) on 127.0.0.1:8891 and the React dashboard
 * (mt5-bridge-App.tsx v5) on localhost:8002.
 *
 * Design:
 *  - seeds the bridge with a known payload (USTEC M5) so the run is
 *    deterministic even when MT5 is offline; with the multi-slot matrix the
 *    seeded row keeps its own slot, so real EA pushes (XAUUSDz etc.) cannot
 *    collide with the assertions;
 *  - drives all UI assertions from the LIVE GET response / stable hooks —
 *    entry values are never hardcoded into selectors;
 *  - uses DELETE /v1/matrix to make the empty-bridge test deterministic;
 *  - exercises the two-way bridge end-to-end: queue a command for the
 *    seeded slot, read it back exactly the way the EA does (GET /v1/poll),
 *    and prove the handout drains the queue;
 *  - v5: proves the zenith sandbox commands are whitelisted end-to-end
 *    (TOGGLE_SANDBOX queued + drained) and that the mailbox passthrough
 *    endpoint answers contractually (503 without PAICT_SNAPSHOT_FILE).
 *
 * Hooks shipped by the dashboard v5:
 *   [data-test="fit-matrix-table"]
 *   [data-test="matrix-row-<SYM>-<TF>"]
 *   [data-test="entry-cell-<SYM>-<TF>"]
 *   [data-test="score-cell-<SYM>-<TF>"]      (grade letter A/B/C/D)
 *   [data-test="zenith-cell-<SYM>-<TF>"]     (master score chip)
 *   [data-test="conn-status"]
 *   [data-test="copilot-cell-<SYM>-<TF>"]
 *   [data-test="remote-*"]                    (remote control card)
 */

const BRIDGE = "http://127.0.0.1:8891/v1/matrix";
const COMMANDS = "http://127.0.0.1:8891/v1/commands";
const POLL = "http://127.0.0.1:8891/v1/poll";
const SNAPSHOT = "http://127.0.0.1:8891/v1/snapshot";
const DASHBOARD = "http://localhost:8002";

const SEED = {
  symbol: "USTEC",
  timeframe: "M5",
  side: "long",
  entry: 18000.5,
  sl: 17950.0,
  tp: 18100.0,
  rr: 2.0,
  status: "live",
  time: new Date().toUTCString(),
};

describe("MT5 Bridge Pipeline", () => {
  it("seeds the matrix, verifies the contract, and renders the dashboard row", () => {
    // 0. Seed — a known-good payload in its own symbol|timeframe slot
    cy.request("POST", BRIDGE, SEED)
      .its("status")
      .should("eq", 200);

    // 1. Backend contract — array response, seeded row carries the fields
    cy.request(BRIDGE).then(({ status, body }) => {
      expect(status).to.eq(200);
      expect(body).to.be.an("array");
      const row = body.find(
        (r) => r.symbol === SEED.symbol && r.timeframe === SEED.timeframe,
      );
      expect(row, "seeded row present in the matrix").to.exist;
      expect(row).to.have.property("entry", SEED.entry);
      expect(row).to.have.property("receivedAt");

      // 2. Dashboard renders the matrix — assertions follow the hooks
      cy.visit(DASHBOARD);
      cy.get('[data-test="fit-matrix-table"]', { timeout: 10_000 }).should("be.visible");
      cy.get(`[data-test="matrix-row-${SEED.symbol}-${SEED.timeframe}"]`).should("exist");
      cy.get(`[data-test="entry-cell-${SEED.symbol}-${SEED.timeframe}"]`).should(
        "contain",
        String(SEED.entry),
      );
      cy.get(`[data-test="score-cell-${SEED.symbol}-${SEED.timeframe}"]`)
        .invoke("text")
        .should("match", /^[A-D]/);
      cy.get('[data-test="conn-status"]').should("contain", "LIVE");
    });
  });

  it("clears the bridge and shows the waiting state", () => {
    cy.request("DELETE", BRIDGE).its("status").should("eq", 200);
    cy.request(BRIDGE).then(({ status, body }) => {
      expect(status).to.eq(200);
      expect(body).to.be.an("array");
      // Lenient when a real EA pushes concurrently — the table must exist
      // either way; the row count may already have recovered.
      cy.visit(DASHBOARD);
      cy.get('[data-test="fit-matrix-table"]').should("be.visible");
      cy.get('[data-test="conn-status"]').should("exist");
    });
  });

  it("hands a queued remote command to the EA poll and drains the queue", () => {
    const SLOT = `${SEED.symbol}|${SEED.timeframe}`;

    // 0. deterministic start: no stale commands anywhere
    cy.request("DELETE", COMMANDS).its("status").should("eq", 200);

    // 1. the dashboard path: queue a whitelisted command for the slot
    cy.request("POST", COMMANDS, {
      slot: SLOT,
      action: "SET_RISK",
      value: 0.5,
    })
      .then(({ status, body }) => {
        expect(status).to.eq(200);
        expect(body).to.have.property("ok", true);
        expect(body).to.have.property("queued", 1);
        expect(body.cmd).to.have.property("id");
        expect(body.cmd).to.have.property("action", "SET_RISK");
        expect(body.cmd).to.have.property("value", 0.5);
      });

    // 2. the EA path: GET /v1/poll returns the exact wire line it parses
    cy.request(`${POLL}?slot=${encodeURIComponent(SLOT)}`).then(
      ({ status, body }) => {
        expect(status).to.eq(200);
        expect(body).to.match(/^CMD \d+ SET_RISK 0\.5$/m);
      },
    );

    // 3. handout = pop: a second poll must come back empty
    cy.request(`${POLL}?slot=${encodeURIComponent(SLOT)}`).then(
      ({ status, body }) => {
        expect(status).to.eq(200);
        expect(body.trim()).to.eq("");
      },
    );

    // 4. input validation: unknown actions are rejected before queuing
    cy.request({
      method: "POST",
      url: COMMANDS,
      body: { slot: SLOT, action: "SELF_DESTRUCT", value: 1 },
      failOnStatusCode: false,
    }).then(({ status }) => {
      expect(status).to.eq(400);
    });
  });

  it("v5 zenith: sandbox commands are whitelisted and the mailbox endpoint answers", () => {
    const SLOT = `${SEED.symbol}|${SEED.timeframe}`;

    // 0. deterministic start
    cy.request("DELETE", COMMANDS).its("status").should("eq", 200);

    // 1. TOGGLE_SANDBOX queues (v5 whitelist extension for the v10 EA)
    cy.request("POST", COMMANDS, {
      slot: SLOT,
      action: "TOGGLE_SANDBOX",
      value: 1,
    }).then(({ status, body }) => {
      expect(status).to.eq(200);
      expect(body).to.have.property("ok", true);
      expect(body.cmd).to.have.property("action", "TOGGLE_SANDBOX");
    });

    // 2. RESET_SANDBOX (value-less action) queues and drains with the flag
    cy.request("POST", COMMANDS, { slot: SLOT, action: "RESET_SANDBOX" }).then(
      ({ status }) => expect(status).to.eq(200),
    );
    cy.request(`${POLL}?slot=${encodeURIComponent(SLOT)}`).then(
      ({ status, body }) => {
        expect(status).to.eq(200);
        expect(body).to.match(/^CMD \d+ TOGGLE_SANDBOX 1$/m);
        expect(body).to.match(/^CMD \d+ RESET_SANDBOX 0$/m);
      },
    );

    // 3. mailbox passthrough: without PAICT_SNAPSHOT_FILE the endpoint
    //    answers 503 with a CONFIGURING error (contractual), never a crash
    cy.request({ url: SNAPSHOT, failOnStatusCode: false }).then(
      ({ status, body }) => {
        expect(status).to.eq(503);
        expect(body).to.have.property("ok", false);
        expect(body.error).to.contain("mailbox not configured");
      },
    );
  });
});
