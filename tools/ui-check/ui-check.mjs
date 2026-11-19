#!/usr/bin/env node
// ui-check: the tester's one way into dw's web UI (Task 8b, R17).
//
//   node <HARNEST_ROOT>/tools/ui-check/ui-check.mjs /tmp/dw-ui-<case>.json
//
// A fixed headless-Chromium runner. The tester writes no code: it writes a JSON
// spec of steps, and this file is the only thing that drives the browser. It
// finds things by visible text and role (getByRole/getByText/getByLabel/
// getByPlaceholder), never by CSS or XPath, so it stays black-box: it needs no
// selector read from the UI source.
//
// Spec: {"base": optional, "steps": [{"step": "<kind>", ...}, ...]}
//   goto        {path}                          a path on the base origin only, and
//               a text/html page (any other content type fails the step)
//   click       {role, name?} | {text}          [exact?, nth?]
//   fill        {label | placeholder | role+name?, value}  [exact?, nth?]
//   press       {key}
//   mock        {url_glob, set: {"dotted.path": value, ...}, once?}
//               route.fetch() the real request, parse its JSON, set each path
//               (a.b, a.0.b and a[0].b; any JSON value), route.fulfill({json})
//   stub        {url_glob, json, status?}   answer a POST to a POST_ALLOWED route
//               with this JSON (status 200-599, default 200) and never send it; the
//               glob may name only those routes (refused otherwise), and a GET or HEAD
//               on it gets the real answer. A real Run click queues a GPU job: stub it.
//   unmock      {url_glob}   removes the mocks and stubs on that glob
//   record      {url_glob}   from this step on, note every same-origin request
//               the glob matches, mocked or not (a mock on the same glob is fine)
//   recorded    {url_glob}   -> {count, requests: [{method, url (path+query),
//               body (parsed JSON, else text cut to 4 KB, else null), timestamp
//               (epoch ms)}], dropped}; at most 200 kept per glob
//   wait_text   {text | regex, flags?, timeout_ms?}   timeout_ms <= 30000
//   expect_text {text | regex, flags?}  -> {found, snippet, count}; does not wait.
//               The match runs in the page, so a regex that never ends hangs the
//               page, not this process: the step cap still ends the run.
//   inspect     {text | regex, flags?, exact?, nth?}  -> tag, role, classes,
//               color, background_color, font_weight, aria, text, and the same
//               for the closest ancestor with a class
//   screenshot  {name}  -> <os.tmpdir()>/dw-ui-shots-XXXXXX/<name>.png, name
//               [A-Za-z0-9_-]{1,64}; the dir is this run's own (mkdtemp, 0700),
//               the file is created new (O_EXCL, O_NOFOLLOW, 0600)
//
// The base origin is DW_URL's scheme, host and port (its /mcp path dropped).
// DW_URL is required (exit 2 when unset or not http(s)); a spec "base" must
// name the same origin. Every request to another origin is aborted (listed in
// "blocked"), as is any WebSocket there; a main-frame navigation off the
// origin (file:, data:) goes back to about:blank. On the origin, only GET and
// HEAD go anywhere; a write goes only to POST_ALLOWED (validate, submit a run,
// cancel one): DELETE, PUT, PATCH and every other POST (delete_model's
// DELETE /api/models, update_diffusers' POST /api/system/diffusers/update,
// cache clears, workflow and prompt saves...) are aborted and listed in
// "blocked" as "METHOD url", so the UI is no side door past the tester's MCP
// denylist; a mock cannot fetch them either. No downloads, no permissions, no
// service workers, no popups. Each step is capped at 30 s, the whole run at
// 300 s, and the run stops at the first step that fails. SIGTERM (SIGINT,
// SIGHUP) closes the browser and prints the partial result.
//
// Auth: dw's UI sends the bearer token it keeps in localStorage ("dw-api-token",
// JSON; dw ui/src/lib/token.ts). The runner puts it there before any page script
// runs, from the session's MCP config file (the driver's, named by the
// HARNEST_MCP_CONFIG path; the server entry whose url is on the base origin, its
// "Authorization: Bearer <token>" header). Never from the spec. No file or no
// token: the run goes without one (a server with no token). The token is
// replaced by "<token>" everywhere in the output (page text, errors, requests).
//
// Output: one JSON document on stdout, {ok, base, token, steps: [{i, step, ok,
// result | error}], page_errors, console_errors, blocked, shots}; token is
// whether one was injected. Exit 0, unless DW_URL or the spec is invalid or
// its path is not a regular file /tmp/dw-ui-*.json of at most 256 KB owned by
// this user (exit 2, with {ok: false, error}).

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const MAX_SPEC = 256 * 1024;
const MAX_STEPS = 200;
const STEP_MS = 30000;
const DEFAULT_MS = 15000;
const RUN_MS = 300000;
// The only same-origin writes a page may send: validate, submit a run, cancel one
// (the MCP tools validate_workflow, run_workflow and cancel_job, all the tester's).
const POST_ALLOWED = [/^\/api\/validate$/, /^\/api\/jobs$/, /^\/api\/jobs\/[^/]+\/cancel$/];
const READ_METHODS = new Set(["GET", "HEAD"]);
const SPEC_PATH = /^\/tmp\/dw-ui-[A-Za-z0-9_-][A-Za-z0-9._-]*\.json$/;
const BAD_KEYS = new Set(["__proto__", "prototype", "constructor"]);
const MAX_RECORDED = 200;
const MAX_BODY = 4096;
const LOCATOR_KEYS = ["selector", "css", "xpath", "locator", "id", "testid", "data-testid"];
const MAX_ALTERNATIVES = 32;
const MAX_CONFIG = 64 * 1024;
// dw's UI keeps its bearer token here (ui/src/lib/storage.ts prefixes "dw-" and stores JSON).
const TOKEN_KEY = "dw-api-token";
// A stub's glob, each {a,b} alternative: any origin (** or one literal), then exactly a
// POST_ALLOWED path, then nothing or a query.
const STUB_GLOB = /^(?:\*\*|https?:\/\/[^/*?{},]+)\/api\/(?:validate|jobs|jobs\/(?:\*|[A-Za-z0-9_-]+)\/cancel)(?:\?.*)?$/;

// Every form of the token that must never be printed (set once it is read).
const SCRUB = [];
function scrub(text) {
  for (const t of SCRUB) text = text.split(t).join("<token>");
  return text;
}

// One JSON document per run, whatever ends it first (the steps, the run cap, a signal).
let emitted = false;
function emit(doc, code) {
  if (emitted) return;
  emitted = true;
  process.stdout.write(scrub(JSON.stringify(doc)) + "\n", () => process.exit(code));
}

function invalid(msg) {
  process.stderr.write(scrub("ui-check: " + msg) + "\n");
  emit({ ok: false, error: msg }, 2);
  throw new Exit();
}

// Replaced by main() once a browser may be up; before that a signal just ends the run.
let onSignal = (sig) => emit({ ok: false, error: "terminated (" + sig + ")" }, 0);
for (const sig of ["SIGTERM", "SIGINT", "SIGHUP"]) process.on(sig, () => onSignal(sig));

class Exit extends Error {}

// --- the spec file -----------------------------------------------------------
function readSpec(argv) {
  if (argv.length !== 1) invalid("usage: ui-check.mjs /tmp/dw-ui-<name>.json (exactly one argument)");
  const p = argv[0];
  if (!SPEC_PATH.test(p)) invalid("the spec must be /tmp/dw-ui-<name>.json (letters, digits, . _ -): got " + p);
  let st;
  try {
    st = fs.lstatSync(p);
  } catch {
    invalid("no spec file at " + p);
  }
  if (st.isSymbolicLink()) invalid("the spec is a symlink: write it as a regular file");
  if (!st.isFile()) invalid("the spec is not a regular file");
  const real = fs.realpathSync(p);
  if (real !== path.join(fs.realpathSync("/tmp"), path.basename(p))) invalid("the spec resolves outside /tmp: " + real);
  let fd;
  try {
    // O_NONBLOCK: a FIFO swapped in after the lstat cannot hang the open.
    fd = fs.openSync(p, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  } catch (e) {
    invalid("cannot open the spec: " + e.message);
  }
  const fst = fs.fstatSync(fd);
  if (!fst.isFile()) invalid("the spec is not a regular file");
  if (fst.uid !== process.getuid()) invalid("the spec is not this user's file: write it yourself");
  if (fst.size > MAX_SPEC) invalid("the spec is over 256 KB");
  const text = fs.readFileSync(fd, "utf8");
  fs.closeSync(fd);
  try {
    return JSON.parse(text);
  } catch (e) {
    invalid("the spec is not JSON: " + e.message);
  }
}

function originOf(u, what) {
  let url;
  try {
    url = new URL(u);
  } catch {
    invalid(what + " is not a URL: " + u);
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") invalid(what + " must be http or https: " + u);
  return url.origin;
}

// Fail closed: the origin comes from DW_URL, never from the spec alone.
function baseOf(spec) {
  const dw = process.env.DW_URL || "";
  if (!dw) invalid("DW_URL is unset: the runner needs the server's endpoint in its environment");
  const fromEnv = originOf(dw, "DW_URL");
  if (spec.base !== undefined) {
    if (typeof spec.base !== "string") invalid("base must be a string");
    const fromSpec = originOf(spec.base, "base");
    if (fromSpec !== fromEnv) invalid("base " + fromSpec + " is not this server's origin " + fromEnv + " (DW_URL)");
  }
  return fromEnv;
}

// --- step validation ---------------------------------------------------------
const SHAPES = {
  goto: { path: "string" },
  click: { role: "role", name: "text", text: "text", exact: "boolean", nth: "index" },
  fill: { label: "text", placeholder: "text", role: "role", name: "text", value: "string", exact: "boolean", nth: "index" },
  press: { key: "key" },
  mock: { url_glob: "glob", set: "set", once: "boolean" },
  stub: { url_glob: "glob", json: "json", status: "status" },
  unmock: { url_glob: "glob" },
  record: { url_glob: "glob" },
  recorded: { url_glob: "glob" },
  wait_text: { text: "text", regex: "regex", flags: "flags", timeout_ms: "timeout" },
  expect_text: { text: "text", regex: "regex", flags: "flags" },
  inspect: { text: "text", regex: "regex", flags: "flags", exact: "boolean", nth: "index" },
  screenshot: { name: "name" },
};

function pathSegments(dotted) {
  const out = [];
  for (const part of dotted.split(".")) {
    const m = /^([^[\]]*)((?:\[\d+\])*)$/.exec(part);
    if (!m) return null;
    if (m[1] !== "") out.push(m[1]);
    for (const ix of m[2].match(/\d+/g) || []) out.push(Number(ix));
    if (m[1] === "" && !m[2]) return null;
  }
  return out.length ? out : null;
}

function checkValue(kind, v, where) {
  const str = (max) => typeof v === "string" && v.length > 0 && v.length <= max;
  switch (kind) {
    case "string":
      if (typeof v !== "string" || v.length > 10000) invalid(where + " must be a string (at most 10000 chars)");
      return;
    case "text":
      if (!str(500)) invalid(where + " must be a non-empty string of at most 500 chars");
      return;
    case "role":
      if (typeof v !== "string" || !/^[a-z]{2,32}$/.test(v)) invalid(where + " must be an ARIA role name (button, link, textbox...)");
      return;
    case "key":
      if (!str(50)) invalid(where + " must be a key name (Enter, Tab, Control+A...)");
      return;
    case "glob":
      if (!str(500)) invalid(where + " must be a URL glob such as **/api/validate**");
      if (!globAlternatives(v)) invalid(where + " has more than " + MAX_ALTERNATIVES + " {a,b} alternatives");
      return;
    case "json":
      return; // any JSON value: the spec is parsed JSON
    case "status":
      if (!Number.isInteger(v) || v < 200 || v > 599) invalid(where + " must be an HTTP status from 200 to 599");
      return;
    case "boolean":
      if (typeof v !== "boolean") invalid(where + " must be true or false");
      return;
    case "index":
      if (!Number.isInteger(v) || v < 0 || v > 1000) invalid(where + " must be an integer from 0");
      return;
    case "timeout":
      if (!Number.isInteger(v) || v < 1 || v > STEP_MS) invalid(where + " must be an integer from 1 to 30000");
      return;
    case "flags":
      if (typeof v !== "string" || !/^[imsu]{0,4}$/.test(v)) invalid(where + " takes the regex flags i, m, s, u only");
      return;
    case "regex":
      if (!str(500)) invalid(where + " must be a non-empty regex of at most 500 chars");
      try {
        new RegExp(v);
      } catch (e) {
        invalid(where + " is not a valid regex: " + e.message);
      }
      return;
    case "name":
      if (typeof v !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(v)) invalid(where + " must be letters, digits, _ - (at most 64)");
      return;
    case "set":
      if (!v || typeof v !== "object" || Array.isArray(v) || !Object.keys(v).length) invalid(where + " must be an object of dotted paths to values");
      for (const k of Object.keys(v)) {
        const segs = pathSegments(k);
        if (!segs) invalid(where + ": " + JSON.stringify(k) + " is not a dotted path (a.b, a.0.b, a[0].b)");
        if (segs.some((s) => BAD_KEYS.has(String(s)))) invalid(where + ": " + JSON.stringify(k) + " names a prototype key");
      }
      return;
  }
}

function validate(spec) {
  if (!spec || typeof spec !== "object" || Array.isArray(spec)) invalid("the spec must be a JSON object");
  for (const k of Object.keys(spec)) if (k !== "base" && k !== "steps") invalid("unknown spec key " + JSON.stringify(k) + " (base, steps)");
  if (!Array.isArray(spec.steps)) invalid("steps must be an array");
  if (spec.steps.length > MAX_STEPS) invalid("at most " + MAX_STEPS + " steps");
  spec.steps.forEach((s, i) => {
    const where = "step " + i;
    if (!s || typeof s !== "object" || Array.isArray(s)) invalid(where + " must be an object");
    const shape = SHAPES[s.step];
    if (!shape) invalid(where + ": unknown step " + JSON.stringify(s.step) + " (" + Object.keys(SHAPES).join(", ") + ")");
    for (const [k, v] of Object.entries(s)) {
      if (k === "step") continue;
      if (LOCATOR_KEYS.includes(k)) invalid(where + ": no " + k + " locators: find things by visible text or role (role+name, text, label, placeholder)");
      if (!(k in shape)) invalid(where + " (" + s.step + "): unknown key " + JSON.stringify(k) + " (" + Object.keys(shape).join(", ") + ")");
      checkValue(shape[k], v, where + "." + k);
    }
    const has = (k) => s[k] !== undefined;
    const need = (cond, msg) => cond || invalid(where + " (" + s.step + "): " + msg);
    switch (s.step) {
      case "goto":
        need(has("path"), "needs path");
        break;
      case "click":
        need(has("role") !== has("text"), "needs exactly one of role (with name) or text");
        need(!(has("name") && !has("role")), "name goes with role");
        break;
      case "fill":
        need([has("label"), has("placeholder"), has("role")].filter(Boolean).length === 1, "needs exactly one of label, placeholder or role (with name)");
        need(!(has("name") && !has("role")), "name goes with role");
        need(has("value"), "needs value");
        break;
      case "press":
        need(has("key"), "needs key");
        break;
      case "mock":
        need(has("url_glob") && has("set"), "needs url_glob and set");
        break;
      case "stub":
        need(has("url_glob") && has("json"), "needs url_glob and json");
        need(
          globAlternatives(s.url_glob).every((a) => STUB_GLOB.test(a)),
          "a stub answers only the write routes a page may send (POST /api/validate, /api/jobs, " +
            "/api/jobs/<id>/cancel): its url_glob must name only those, such as **/api/jobs?** or **/api/jobs/*/cancel",
        );
        break;
      case "unmock":
      case "record":
      case "recorded":
        need(has("url_glob"), "needs url_glob");
        break;
      case "wait_text":
      case "expect_text":
      case "inspect":
        need(has("text") !== has("regex"), "needs exactly one of text or regex");
        need(!(has("flags") && !has("regex")), "flags go with regex");
        break;
      case "screenshot":
        need(has("name"), "needs name");
        break;
    }
  });
}

// --- the run ---------------------------------------------------------------
function setPath(doc, dotted, value) {
  const segs = pathSegments(dotted);
  let cur = doc;
  for (let i = 0; i < segs.length - 1; i++) {
    const k = segs[i];
    if (cur[k] === null || typeof cur[k] !== "object") cur[k] = typeof segs[i + 1] === "number" ? [] : {};
    cur = cur[k];
  }
  cur[segs[segs.length - 1]] = value;
}

// Playwright's URL glob: ** any characters, * any but /, {a,b} alternatives (not nested),
// everything else literal (? included, as Playwright reads it). Matched here, never as a
// RegExp (the tester's glob must not backtrack): {a,b} expanded, then each alternative by a
// table over (glob tokens x URL characters), linear in each. mock, stub and record share it.
function globAlternatives(glob) {
  let alts = [""];
  let i = 0;
  while (i < glob.length) {
    const open = glob.indexOf("{", i);
    const close = open < 0 ? -1 : glob.indexOf("}", open);
    if (open < 0 || close < 0) {
      alts = alts.map((a) => a + glob.slice(i));
      break;
    }
    const opts = glob.slice(open + 1, close).split(",");
    const head = glob.slice(i, open);
    alts = alts.flatMap((a) => opts.map((o) => a + head + o));
    if (alts.length > MAX_ALTERNATIVES) return null;
    i = close + 1;
  }
  return alts;
}

function globTokens(alt) {
  const t = [];
  for (let i = 0; i < alt.length; i++) {
    if (alt[i] === "*" && alt[i + 1] === "*") {
      t.push("**");
      i++;
    } else t.push(alt[i] === "*" ? "*" : { c: alt[i] });
  }
  return t;
}

function tokensMatch(toks, s) {
  // row[j]: the tokens so far match s.slice(0, j)
  let row = new Array(s.length + 1).fill(false);
  row[0] = true;
  for (const tok of toks) {
    const next = new Array(s.length + 1).fill(false);
    for (let j = 0; j <= s.length; j++) {
      if (tok === "**" || tok === "*") {
        next[j] = row[j] || (j > 0 && next[j - 1] && (tok === "**" || s[j - 1] !== "/"));
      } else next[j] = j > 0 && row[j - 1] && s[j - 1] === tok.c;
    }
    row = next;
  }
  return row[s.length];
}

function globMatcher(glob) {
  const toks = globAlternatives(glob).map(globTokens);
  return (u) => {
    const href = typeof u === "string" ? u : u.href;
    return toks.some((t) => tokensMatch(t, href));
  };
}

function bodyOf(req) {
  const text = req.postData();
  if (text == null) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text.length > MAX_BODY ? text.slice(0, MAX_BODY) : text;
  }
}

function short(s, n = 1000) {
  s = String(s);
  return s.length > n ? s.slice(0, n) + "..." : s;
}

function matcher(s) {
  return s.regex !== undefined ? new RegExp(s.regex, s.flags || "") : s.text;
}

function locate(page, s) {
  let loc;
  const exact = s.exact === true;
  if (s.role !== undefined) loc = page.getByRole(s.role, s.name !== undefined ? { name: s.name, exact } : {});
  else if (s.label !== undefined) loc = page.getByLabel(s.label, { exact });
  else if (s.placeholder !== undefined) loc = page.getByPlaceholder(s.placeholder, { exact });
  else loc = page.getByText(matcher(s), typeof matcher(s) === "string" ? { exact } : {});
  return s.nth !== undefined ? loc.nth(s.nth) : loc;
}

function describe(el) {
  const d = (e) => {
    const cs = getComputedStyle(e);
    const aria = {};
    for (const a of e.attributes) if (a.name.startsWith("aria-")) aria[a.name] = a.value;
    return {
      tag: e.tagName.toLowerCase(),
      role: e.getAttribute("role"),
      classes: Array.from(e.classList),
      color: cs.color,
      background_color: cs.backgroundColor,
      font_weight: cs.fontWeight,
      aria,
      text: (e.textContent || "").slice(0, 500),
    };
  };
  const r = d(el);
  const anc = el.parentElement && el.parentElement.closest("[class]");
  r.ancestor = anc ? d(anc) : null;
  return r;
}

async function main() {
  const argv = process.argv.slice(2);
  const spec = readSpec(argv);
  validate(spec);
  const base = baseOf(spec);
  const token = tokenFor(base);
  const out = { ok: false, base, token: token !== null, steps: [], page_errors: [], console_errors: [], blocked: [], shots: [] };
  let shotDir = null; // this run's own, made at the first screenshot
  let browser;
  let current = null; // the step running now, for a result cut short
  let finishing = false;
  const finish = async (extra) => {
    if (finishing) return;
    finishing = true;
    Object.assign(out, extra || {});
    if (browser) await Promise.race([browser.close().catch(() => {}), new Promise((r) => setTimeout(r, 5000))]);
    emit(out, 0);
  };
  const cut = (error) => {
    if (current) out.steps.push({ i: current.i, step: current.step, ok: false, error });
    current = null;
    return finish({ ok: false, error });
  };
  onSignal = (sig) => cut("terminated (" + sig + ")");
  const runTimer = setTimeout(() => cut("the run exceeded 300 s"), RUN_MS);

  let chromium;
  try {
    ({ chromium } = await import("playwright-core"));
  } catch (e) {
    return finish({ error: "playwright-core is not installed: cd tools/ui-check && npm install --no-audit --no-fund (" + short(e.message, 200) + ")" });
  }
  try {
    // The signals are this file's (onSignal): it closes the browser and prints what it has.
    browser = await chromium.launch({ headless: true, handleSIGINT: false, handleSIGTERM: false, handleSIGHUP: false });
  } catch (e) {
    return finish({ error: "cannot start headless Chromium: " + short(e.message, 500) });
  }
  if (finishing) return browser.close().catch(() => {});
  const context = await browser.newContext({ acceptDownloads: false, permissions: [], serviceWorkers: "block" });
  if (token !== null) {
    // Before any page script, on the base origin only: dw's UI reads it at module load.
    await context.addInitScript(
      ({ key, value, origin }) => {
        try {
          if (location.origin === origin) localStorage.setItem(key, value);
        } catch {}
      },
      { key: TOKEN_KEY, value: JSON.stringify(token), origin: base },
    );
  }
  context.setDefaultTimeout(DEFAULT_MS);
  context.setDefaultNavigationTimeout(STEP_MS);
  const offOrigin = (u) => {
    try {
      const url = new URL(u);
      if (url.protocol === "ws:") url.protocol = "http:";
      if (url.protocol === "wss:") url.protocol = "https:";
      return url.origin !== base;
    } catch {
      return true;
    }
  };
  // A request the run must not send: off the origin, or a same-origin write other
  // than POST_ALLOWED (DELETE, PUT, PATCH, a destructive POST).
  const denied = (req) => {
    const u = req.url();
    if (offOrigin(u)) return true;
    const m = req.method().toUpperCase();
    if (READ_METHODS.has(m)) return false;
    if (m !== "POST") return true;
    return !POST_ALLOWED.some((re) => re.test(new URL(u).pathname));
  };
  const block = (route) => {
    const req = route.request();
    out.blocked.push(short(req.method().toUpperCase() + " " + req.url(), 300));
    return route.abort("blockedbyclient");
  };
  // The lock is the first route, so it runs last: a mock registered later falls back to it
  // for a request it must not send.
  await context.route("**/*", (route) => (denied(route.request()) ? block(route) : route.fallback()));
  await context.routeWebSocket(/.*/, (ws) => {
    if (offOrigin(ws.url())) {
      out.blocked.push(short("WEBSOCKET " + ws.url(), 300));
      return ws.close();
    }
    ws.connectToServer();
  });
  const page = await context.newPage();
  context.on("page", (p) => {
    if (p !== page) p.close().catch(() => {});
  });
  page.on("pageerror", (e) => out.page_errors.push(short(e.message || e, 500)));
  page.on("console", (m) => {
    if (m.type() === "error") out.console_errors.push(short(m.text(), 500));
  });
  page.on("download", (d) => d.cancel().catch(() => {}));
  page.on("framenavigated", (frame) => {
    const u = frame.url();
    if (frame !== page.mainFrame() || u === "about:blank" || !offOrigin(u)) return;
    out.blocked.push(short("NAVIGATE " + u, 300));
    page.goto("about:blank").catch(() => {});
  });

  const mocks = new Map(); // url_glob -> [{match, handler, hits}], mocks and stubs
  const addRoute = async (glob, entry, opts) => {
    entry.match = globMatcher(glob);
    await context.route(entry.match, entry.handler, opts || {});
    if (!mocks.has(glob)) mocks.set(glob, []);
    mocks.get(glob).push(entry);
  };
  // The request event sees every request, a mocked one included, whichever route answers it.
  const records = new Map(); // url_glob -> {match, requests, dropped}
  context.on("request", (req) => {
    const u = req.url();
    if (!records.size || offOrigin(u)) return;
    for (const r of records.values()) {
      if (!r.match(u)) continue;
      if (r.requests.length >= MAX_RECORDED) {
        r.dropped++;
        continue;
      }
      const url = new URL(u);
      r.requests.push({ method: req.method(), url: url.pathname + url.search, body: bodyOf(req), timestamp: Date.now() });
    }
  });
  const run = async (s) => {
    switch (s.step) {
      case "goto": {
        const url = new URL(s.path, base + "/");
        if (url.origin !== base) throw new Error("refused: " + url.href + " is not on " + base);
        const resp = await page.goto(url.href, { waitUntil: "load", timeout: STEP_MS });
        const type = resp ? resp.headers()["content-type"] || "" : "text/html";
        if (!/^text\/html\s*(;|$)/i.test(type)) {
          await page.goto("about:blank").catch(() => {});
          throw new Error("refused: " + url.pathname + " is " + (type || "no content type") + ", not a text/html page; goto loads UI pages only");
        }
        return { url: page.url(), status: resp ? resp.status() : null };
      }
      case "click":
        await locate(page, s).click();
        return { clicked: true };
      case "fill":
        await locate(page, s).fill(s.value);
        return { filled: true };
      case "press":
        await page.keyboard.press(s.key);
        return { pressed: s.key };
      case "mock": {
        const entry = { hits: 0, errors: [] };
        entry.handler = async (route) => {
          if (denied(route.request())) return route.fallback();
          entry.hits++;
          let resp;
          try {
            resp = await route.fetch({ maxRedirects: 0 });
          } catch (e) {
            entry.errors.push(short(e.message, 300));
            return route.abort("failed");
          }
          let doc;
          try {
            doc = JSON.parse(await resp.text());
          } catch (e) {
            entry.errors.push("the real answer is not JSON: " + short(e.message, 200));
            return route.fulfill({ response: resp });
          }
          for (const [k, v] of Object.entries(s.set)) setPath(doc, k, v);
          return route.fulfill({ response: resp, json: doc });
        };
        await addRoute(s.url_glob, entry, s.once ? { times: 1 } : {});
        return { url_glob: s.url_glob, set: Object.keys(s.set), once: s.once === true };
      }
      case "stub": {
        // Answers a POST to a POST_ALLOWED route and never sends it; anything else on the
        // glob (a GET, a path the leading ** let in) goes on to the real route and the lock.
        const entry = { hits: 0, errors: [] };
        entry.handler = (route) => {
          const req = route.request();
          if (req.method().toUpperCase() !== "POST" || denied(req)) return route.fallback();
          entry.hits++;
          return route.fulfill({ status: s.status || 200, json: s.json });
        };
        await addRoute(s.url_glob, entry);
        return { url_glob: s.url_glob, status: s.status || 200 };
      }
      case "unmock": {
        const entries = mocks.get(s.url_glob) || [];
        for (const e of entries) await context.unroute(e.match, e.handler);
        mocks.delete(s.url_glob);
        return {
          url_glob: s.url_glob,
          removed: entries.length,
          hits: entries.reduce((a, e) => a + e.hits, 0),
          errors: entries.flatMap((e) => e.errors),
        };
      }
      case "record":
        if (!records.has(s.url_glob)) records.set(s.url_glob, { match: globMatcher(s.url_glob), requests: [], dropped: 0 });
        return { url_glob: s.url_glob, recording: true };
      case "recorded": {
        const r = records.get(s.url_glob);
        if (!r) throw new Error("no record step for " + s.url_glob + " ran before this one");
        return { url_glob: s.url_glob, count: r.requests.length, requests: r.requests, dropped: r.dropped };
      }
      case "wait_text":
        await page
          .getByText(matcher(s))
          .first()
          .waitFor({ state: "visible", timeout: s.timeout_ms || DEFAULT_MS });
        return { found: true };
      case "expect_text":
        // In the page, never here: a regex that backtracks forever hangs the page's
        // thread, and this process's timers (the step cap, a signal) still fire.
        return await page.evaluate(
          ({ text, src, flags, max }) => {
            const cut = (t) => (t.length > max ? t.slice(0, max) + "..." : t);
            const re = src === null ? null : new RegExp(src, flags);
            const body = document.body ? document.body.innerText : "";
            let count = 0;
            let snippet = null;
            for (const line of body.split("\n")) {
              if (re ? re.test(line) : line.includes(text)) {
                count++;
                if (snippet === null) snippet = cut(line.trim());
              }
            }
            if (!count && re) {
              const m = re.exec(body);
              if (m) {
                count = 1;
                snippet = cut(m[0]);
              }
            }
            if (!count && !re && body.includes(text)) {
              count = 1;
              snippet = cut(text);
            }
            return { found: count > 0, count, snippet };
          },
          { text: s.text ?? null, src: s.regex ?? null, flags: s.flags || "", max: 300 },
        );
      case "inspect": {
        const loc = locate(page, s);
        const matches = await loc.count();
        const first = s.nth !== undefined ? loc : loc.first();
        await first.waitFor({ state: "attached" });
        const info = await first.evaluate(describe);
        return { matches, ...info };
      }
      case "screenshot": {
        // A private dir per run (mkdtemp is 0700 and new), and the file created new
        // in it: nothing another user planted in the temp dir is followed or written.
        const png = await page.screenshot({ fullPage: true, timeout: STEP_MS });
        if (!shotDir) shotDir = fs.mkdtempSync(path.join(os.tmpdir(), "dw-ui-shots-"));
        const file = path.join(shotDir, s.name + ".png");
        const { O_WRONLY, O_CREAT, O_EXCL, O_NOFOLLOW } = fs.constants;
        let fd;
        try {
          fd = fs.openSync(file, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600);
        } catch (e) {
          if (e.code === "EEXIST") throw new Error("a screenshot named " + s.name + " was already taken in this run");
          throw e;
        }
        try {
          fs.writeSync(fd, png);
        } finally {
          fs.closeSync(fd);
        }
        out.shots.push(file);
        return { path: file };
      }
    }
  };

  out.ok = true;
  for (const [i, s] of spec.steps.entries()) {
    if (finishing) return;
    current = { i, step: s.step };
    let timer;
    const cap = new Promise((_, rej) => {
      timer = setTimeout(() => rej(new Error("step took over 30 s")), STEP_MS + 1000);
    });
    try {
      const result = await Promise.race([run(s), cap]);
      out.steps.push({ i, step: s.step, ok: true, result });
    } catch (e) {
      out.steps.push({ i, step: s.step, ok: false, error: short(e.message || e) });
      out.ok = false;
      break;
    } finally {
      clearTimeout(timer);
      current = null;
    }
  }
  clearTimeout(runTimer);
  return finish();
}

// The bearer token for base: the session's MCP config (HARNEST_MCP_CONFIG, written by the
// driver), the server entry on the base origin, its "Authorization: Bearer <token>". null
// when there is none; any problem reading it is the same as none.
function tokenFor(base) {
  const file = process.env.HARNEST_MCP_CONFIG || "";
  if (!file) return null;
  let doc;
  try {
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
    try {
      const st = fs.fstatSync(fd);
      if (!st.isFile() || st.size > MAX_CONFIG) return null;
      doc = JSON.parse(fs.readFileSync(fd, "utf8"));
    } finally {
      fs.closeSync(fd);
    }
  } catch {
    return null;
  }
  for (const srv of Object.values((doc && doc.mcpServers) || {})) {
    let origin;
    try {
      origin = new URL(srv.url).origin;
    } catch {
      continue;
    }
    const m = /^Bearer (\S+)$/.exec(String((srv.headers || {}).Authorization || ""));
    if (origin !== base || !m) continue;
    const t = m[1];
    SCRUB.push(t, JSON.stringify(t).slice(1, -1), encodeURIComponent(t));
    return t;
  }
  return null;
}

main().catch((e) => {
  if (e instanceof Exit) return;
  emit({ ok: false, error: "ui-check failed: " + short(e && e.stack ? e.stack : e) }, 0);
});
