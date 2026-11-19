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
//   goto        {path}                          a path on the base origin only
//   click       {role, name?} | {text}          [exact?, nth?]
//   fill        {label | placeholder | role+name?, value}  [exact?, nth?]
//   press       {key}
//   mock        {url_glob, set: {"dotted.path": value, ...}, once?}
//               route.fetch() the real request, parse its JSON, set each path
//               (a.b, a.0.b and a[0].b; any JSON value), route.fulfill({json})
//   unmock      {url_glob}
//   wait_text   {text | regex, flags?, timeout_ms?}   timeout_ms <= 30000
//   expect_text {text | regex, flags?}  -> {found, snippet, count}; does not wait
//   inspect     {text | regex, flags?, exact?, nth?}  -> tag, role, classes,
//               color, background_color, font_weight, aria, text, and the same
//               for the closest ancestor with a class
//   screenshot  {name}  -> /tmp/dw-ui-shots/<name>.png
//
// The base origin is DW_URL's scheme, host and port (its /mcp path dropped);
// a spec "base" must name the same origin, and is needed only without DW_URL.
// Every request to another origin is aborted (listed in "blocked"), as is any
// WebSocket there; a main-frame navigation off the origin (file:, data:) goes
// back to about:blank. No downloads, no permissions, no service workers, no
// popups. Each step is capped at 30 s, the whole run at 300 s, and the run
// stops at the first step that fails.
//
// Output: one JSON document on stdout, {ok, base, steps: [{i, step, ok,
// result | error}], page_errors, console_errors, blocked}. Exit 0, unless the
// spec is invalid or its path is not a regular file /tmp/dw-ui-*.json of at
// most 256 KB (exit 2, with {ok: false, error}).

import fs from "node:fs";
import path from "node:path";

const MAX_SPEC = 256 * 1024;
const MAX_STEPS = 200;
const STEP_MS = 30000;
const DEFAULT_MS = 15000;
const RUN_MS = 300000;
const SHOTS = "/tmp/dw-ui-shots";
const SPEC_PATH = /^\/tmp\/dw-ui-[A-Za-z0-9_-][A-Za-z0-9._-]*\.json$/;
const BAD_KEYS = new Set(["__proto__", "prototype", "constructor"]);
const LOCATOR_KEYS = ["selector", "css", "xpath", "locator", "id", "testid", "data-testid"];

function emit(doc, code) {
  process.stdout.write(JSON.stringify(doc) + "\n", () => process.exit(code));
}

function invalid(msg) {
  process.stderr.write("ui-check: " + msg + "\n");
  emit({ ok: false, error: msg }, 2);
  throw new Exit();
}

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
    fd = fs.openSync(p, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  } catch (e) {
    invalid("cannot open the spec: " + e.message);
  }
  const fst = fs.fstatSync(fd);
  if (!fst.isFile()) invalid("the spec is not a regular file");
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

function baseOf(spec) {
  const dw = process.env.DW_URL || "";
  const fromEnv = dw ? originOf(dw, "DW_URL") : "";
  if (spec.base !== undefined) {
    if (typeof spec.base !== "string") invalid("base must be a string");
    const fromSpec = originOf(spec.base, "base");
    if (fromEnv && fromSpec !== fromEnv) invalid("base " + fromSpec + " is not this server's origin " + fromEnv + " (DW_URL)");
    return fromSpec;
  }
  if (!fromEnv) invalid("no base: DW_URL is unset and the spec names no base");
  return fromEnv;
}

// --- step validation ---------------------------------------------------------
const SHAPES = {
  goto: { path: "string" },
  click: { role: "role", name: "text", text: "text", exact: "boolean", nth: "index" },
  fill: { label: "text", placeholder: "text", role: "role", name: "text", value: "string", exact: "boolean", nth: "index" },
  press: { key: "key" },
  mock: { url_glob: "glob", set: "set", once: "boolean" },
  unmock: { url_glob: "glob" },
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
      if (typeof v !== "string" || !/^[A-Za-z0-9_-][A-Za-z0-9._-]{0,63}$/.test(v)) invalid(where + " must be letters, digits, . _ - (at most 64)");
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
      case "unmock":
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
  const out = { ok: false, base, steps: [], page_errors: [], console_errors: [], blocked: [] };
  let browser;
  const finish = async (extra) => {
    Object.assign(out, extra || {});
    if (browser) await Promise.race([browser.close().catch(() => {}), new Promise((r) => setTimeout(r, 5000))]);
    emit(out, 0);
  };
  const runTimer = setTimeout(() => finish({ ok: false, error: "the run exceeded 300 s" }), RUN_MS);

  let chromium;
  try {
    ({ chromium } = await import("playwright-core"));
  } catch (e) {
    return finish({ error: "playwright-core is not installed: cd tools/ui-check && npm install --no-audit --no-fund (" + short(e.message, 200) + ")" });
  }
  try {
    browser = await chromium.launch({ headless: true });
  } catch (e) {
    return finish({ error: "cannot start headless Chromium: " + short(e.message, 500) });
  }
  const context = await browser.newContext({ acceptDownloads: false, permissions: [], serviceWorkers: "block" });
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
  // The lock is the first route, so it runs last: a mock registered later falls back to it
  // for a URL off the origin.
  await context.route("**/*", (route) => {
    const u = route.request().url();
    if (offOrigin(u)) {
      out.blocked.push(short(u, 300));
      return route.abort("blockedbyclient");
    }
    return route.fallback();
  });
  await context.routeWebSocket(/.*/, (ws) => {
    if (offOrigin(ws.url())) {
      out.blocked.push(short(ws.url(), 300));
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
    out.blocked.push(short(u, 300));
    page.goto("about:blank").catch(() => {});
  });

  const mocks = new Map(); // url_glob -> [{handler, hits}]
  const run = async (s) => {
    switch (s.step) {
      case "goto": {
        const url = new URL(s.path, base + "/");
        if (url.origin !== base) throw new Error("refused: " + url.href + " is not on " + base);
        const resp = await page.goto(url.href, { waitUntil: "load", timeout: STEP_MS });
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
          if (offOrigin(route.request().url())) return route.fallback();
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
        await context.route(s.url_glob, entry.handler, s.once ? { times: 1 } : {});
        if (!mocks.has(s.url_glob)) mocks.set(s.url_glob, []);
        mocks.get(s.url_glob).push(entry);
        return { url_glob: s.url_glob, set: Object.keys(s.set), once: s.once === true };
      }
      case "unmock": {
        const entries = mocks.get(s.url_glob) || [];
        for (const e of entries) await context.unroute(s.url_glob, e.handler);
        mocks.delete(s.url_glob);
        return {
          url_glob: s.url_glob,
          removed: entries.length,
          hits: entries.reduce((a, e) => a + e.hits, 0),
          errors: entries.flatMap((e) => e.errors),
        };
      }
      case "wait_text":
        await page
          .getByText(matcher(s))
          .first()
          .waitFor({ state: "visible", timeout: s.timeout_ms || DEFAULT_MS });
        return { found: true };
      case "expect_text": {
        const body = await page.evaluate(() => (document.body ? document.body.innerText : ""));
        const lines = body.split("\n");
        let count = 0;
        let snippet = null;
        for (const line of lines) {
          const hit = s.regex !== undefined ? new RegExp(s.regex, s.flags || "").test(line) : line.includes(s.text);
          if (hit) {
            count++;
            if (snippet === null) snippet = short(line.trim(), 300);
          }
        }
        if (!count && s.regex !== undefined && new RegExp(s.regex, s.flags || "").test(body)) {
          count = 1;
          snippet = short(new RegExp(s.regex, s.flags || "").exec(body)[0], 300);
        }
        if (!count && s.text !== undefined && body.includes(s.text)) {
          count = 1;
          snippet = short(s.text, 300);
        }
        return { found: count > 0, count, snippet };
      }
      case "inspect": {
        const loc = locate(page, s);
        const matches = await loc.count();
        const first = s.nth !== undefined ? loc : loc.first();
        await first.waitFor({ state: "attached" });
        const info = await first.evaluate(describe);
        return { matches, ...info };
      }
      case "screenshot": {
        try {
          if (fs.lstatSync(SHOTS).isSymbolicLink()) throw new Error(SHOTS + " is a symlink");
        } catch (e) {
          if (e.code !== "ENOENT") throw e;
          fs.mkdirSync(SHOTS, { mode: 0o700 });
        }
        const file = path.join(SHOTS, s.name + ".png");
        try {
          if (!fs.lstatSync(file).isFile()) throw new Error(file + " is not a regular file");
        } catch (e) {
          if (e.code !== "ENOENT") throw e;
        }
        await page.screenshot({ path: file, fullPage: true, timeout: STEP_MS });
        return { path: file };
      }
    }
  };

  out.ok = true;
  for (const [i, s] of spec.steps.entries()) {
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
    }
  }
  clearTimeout(runTimer);
  return finish();
}

main().catch((e) => {
  if (e instanceof Exit) return;
  emit({ ok: false, error: "ui-check failed: " + short(e && e.stack ? e.stack : e) }, 0);
});
