const fs = require("fs");
const els = {};
global.document = { getElementById: (id) => (els[id] ??= { id, innerHTML: "", textContent: "", hidden: false, value: "", className: "",
  addEventListener() {} }) };
global.localStorage = { getItem: () => null, setItem() {} };
global.setInterval = () => {};
const now = Date.now() / 1000;
const st = {
  now,
  fleet: { id: "20261018-120000", status: "running", started: now - 600, finished: null, levels: ["smoke"],
    model: "anthropic/claude-sonnet-5-5", cases_per_session: 8,
    servers: { lem: { summary: "lem: cuda", head: "develop @ abc", down: false }, minid: { summary: "minid", head: "develop @ c2a", down: true } },
    lanes: [
      { name: "lem-1", server: "lem", status: "running", level: "smoke", batch: ["S-F003", "S-F004"], live_case: "S-F004", since: now - 30, sessions: 3, cost: 1.2 },
      { name: "lem-2", server: "lem", status: "exclusive", level: "smoke", batch: ["S-P001"], live_case: null, since: now - 5, sessions: 2, cost: 0.8 },
      { name: "minid-1", server: "minid", status: "cases done", level: null, batch: [], live_case: null, since: null, sessions: 1, cost: 0.1 } ],
    cases: { "S-F001": { level: "smoke", lane: "minid-1", server: "minid", load: "none", outcome: "pass" },
      "S-F002": { level: "smoke", lane: "script", server: "lem", load: "none", outcome: "fail" },
      "S-F003": { level: "smoke", lane: "lem-1", server: "lem", load: "light", outcome: "pass" },
      "S-F004": { level: "smoke", lane: "lem-1", server: "lem", load: "light", outcome: "running" },
      "S-F005": { level: "smoke", lane: "lem-1", server: "lem", load: "heavy", outcome: "queued" },
      "S-P001": { level: "smoke", lane: "lem-2", server: "lem", load: "exclusive", outcome: "running" },
      "S-F007": { level: "smoke", lane: "lem-2", server: "lem", load: "none", outcome: "skip" },
      "S-F008": { level: "smoke", lane: "lem-2", server: "lem", load: "none", outcome: "fail", issue: "#9" },
      "S-F009": { level: "smoke", lane: null, server: null, load: "?", outcome: "unplaced" } },
    unplaced: [{ level: "smoke", cases: ["S-F009"], why: { lem: "x" } }],
    events: [{ time: now - 20, text: "S-F007 skipped on minid; queued on lem-2" }] },
  failures: { rows: [{ case: "S-F008", level: "smoke", lane: "lem-2", server: "lem", load: "none", note: null,
      issues: [{ number: 9, url: "https://github.com/o/r/issues/9", title: "S-F008 [lem]: bad <thing>", state: "open", labels: ["regression"] },
               { number: 4, url: "https://github.com/o/r/issues/4", title: "S-F008 older", state: "closed", labels: [] },
               { repo: "harnest", number: 130, url: "https://github.com/o/h/issues/130", title: "suite: S-F008 - stale", state: "open", labels: ["suite"] }] },
    { case: "S-F002", level: "smoke", lane: "script", server: "lem", load: "none", note: null, issues: [] }], errors: [], fetched: now - 30 },
  fleet_runs: [{ id: "20261017-1", status: "done", levels: ["smoke"], started: now - 9000, finished: now - 6000, outcomes: { pass: 70, fail: 2 }, cost: 9.5 }],
  single: { lem: [{ time: "09:25:11", level: "smoke", head: "develop @ x", total: 80, per: 8, sessions_total: 11, sessions_done: 4, cases_done: 32, cost: 3.1,
    results: { "S-F001": "pass", "S-F002": "fail" }, skips: 1, current: { session: 5, of: 10, cases: ["S-F033"] }, status: "running" }], mac: [], minid: [] },
  requirements: { lem: [{ level: "all", status: "running", sessions_done: 35, sessions_total: 55, recorded: 400, cost: 6.1 }] },
  coverage: [{ level: "smoke", cases: 82, current: 82, loads: { none: 58, light: 18 } }, { level: "complete", cases: 460, current: 389, loads: { none: 294, unknown: 71 } }],
  drivers: [],
};
global.fetch = async () => ({ json: async () => st });
const page = fs.readFileSync(process.argv[2], "utf8"); eval(page.match(/<script>([\s\S]*)<\/script>/)[1].replace(/^poll\(\);$/m, ""));
(async () => {
  await poll();
  const out = (id) => els[id].innerHTML + els[id].textContent;
  const want = [["fleet", "%"], ["fleet", "s-running"], ["fleet", "unplaced: S-F009"], ["by-level", "smoke"], ["by-server", "lem (script)"],
    ["by-load", "exclusive"], ["lanes", "▶ <b>S-F004</b>"], ["lanes", "exclusive"], ["lanes", "server down"], ["events", "queued on lem-2"],
    ["cases", "fail #9"], ["single", "session 5 of 10"], ["coverage", "389/460"], ["coverage", "generating all"], ["runs", "20261017-1"],
    ["fails", 'href="https://github.com/o/r/issues/9"'], ["fails", "bad &lt;thing&gt;"], ["fails", 'st closed'],
    ["fails", "no issue recorded or open"], ["fails-meta", "2 failed · 1 open issue · 1 case change proposed"], ["fails", "harnest#130"],
    ["hsummary", "fleet 20261018-120000"]];
  let bad = 0;
  for (const [id, s] of want) if (!out(id).includes(s)) { bad++; console.log("MISSING in #" + id + ": " + s); }
  const pctText = els.fleet.innerHTML.match(/<div class="big">(\d+)%/);
  if (bad || !pctText || pctText[1] !== "67") { console.log("FAIL", bad, pctText && pctText[1]); process.exit(1); } console.log("ok");
})();
