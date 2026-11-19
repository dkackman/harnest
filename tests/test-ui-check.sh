#!/usr/bin/env bash
# tools/ui-check/ui-check.mjs, the tester's one way into dw's web UI: a fixed
# headless-Chromium runner driven by a JSON spec in /tmp/dw-ui-*.json. Runs it
# against a local fixture page (tests/fixtures/ui-check) served on 127.0.0.1,
# never a real dw. Needs node and tools/ui-check/node_modules (npm install
# there); without them the file is skipped, not failed.
. "$(dirname "$0")/lib.sh"
runner="$HARNEST/tools/ui-check/ui-check.mjs"
if ! command -v node >/dev/null || [ ! -f "$HARNEST/tools/ui-check/node_modules/playwright-core/package.json" ]; then
  echo "$(basename "$0"): skipped: playwright-core not installed (cd tools/ui-check && npm install --no-audit --no-fund)"
  exit 0
fi

specs="/tmp/dw-ui-test-$$"
trap 'rm -rf "$T"; rm -f "$specs"-*.json /tmp/dw-ui-link-$$.json; [ -n "${srv:-}" ] && kill "$srv" 2>/dev/null' EXIT

python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$HARNEST/tests/fixtures/ui-check" > "$T/srv.out" 2>&1 &
srv=$!
port=""
for _ in $(seq 1 50); do
  port="$(sed -nE 's/.*port ([0-9]+).*/\1/p' "$T/srv.out" | head -1)"
  [ -n "$port" ] && break
  python3 -c 'import time; time.sleep(0.1)'
done
[ -n "$port" ] || { echo "  FAIL: fixture server did not start"; cat "$T/srv.out"; exit 1; }
export DW_URL="http://127.0.0.1:$port/mcp"

n=0
# run <spec-json>: writes the spec to /tmp/dw-ui-test-<pid>-<n>.json, runs it; $out and $rc hold the result
run() {
  n=$((n + 1))
  printf '%s\n' "$1" > "$specs-$n.json"
  out="$(node "$runner" "$specs-$n.json" 2>"$T/err")"
  rc=$?
}
j() { jq -r "$1" <<< "$out"; }

# --- goto, expect_text, inspect, wait_text, click, fill, screenshot
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "wait_text", "text": "cross-origin: blocked", "timeout_ms": 10000},
  {"step": "expect_text", "text": "steps: 3"},
  {"step": "expect_text", "text": "not on the page"},
  {"step": "expect_text", "regex": "estimate: low conf\\w+"},
  {"step": "inspect", "text": "estimate: low confidence"},
  {"step": "fill", "label": "Prompt", "value": "a red fox"},
  {"step": "wait_text", "text": "typed: a red fox"},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "valid: true"},
  {"step": "screenshot", "name": "test-'$$'"}
]}'
eq "a good spec exits 0" 0 "$rc"
eq "every step ok" true "$(j .ok)"
eq "goto ok" true "$(j '.steps[0].ok')"
eq "expect_text finds a line" true "$(j '.steps[2].result.found')"
has "expect_text returns the snippet" "steps: 3" "$(j '.steps[2].result.snippet')"
eq "expect_text says false for an absent line" false "$(j '.steps[3].result.found')"
eq "expect_text by regex" true "$(j '.steps[4].result.found')"
eq "inspect: tag" p "$(j '.steps[5].result.tag')"
eq "inspect: class list" "plan-line warn" "$(j '.steps[5].result.classes | join(" ")')"
eq "inspect: computed colour" "rgb(180, 83, 9)" "$(j '.steps[5].result.color')"
eq "inspect: font weight" 700 "$(j '.steps[5].result.font_weight')"
eq "inspect: aria attributes" polite "$(j '.steps[5].result.aria["aria-live"]')"
eq "inspect: the closest ancestor with a class" plan "$(j '.steps[5].result.ancestor.classes | join(" ")')"
eq "click and wait_text see the real answer" true "$(j '.steps[9].ok')"
eq "screenshot lands in /tmp/dw-ui-shots" "/tmp/dw-ui-shots/test-$$.png" "$(j '.steps[10].result.path')"
ok "the screenshot is a file" test -s "/tmp/dw-ui-shots/test-$$.png"
rm -f "/tmp/dw-ui-shots/test-$$.png"

# --- the origin lock: the fixture's fetch to localhost:<port> is aborted
has "another origin is blocked" "http://localhost:$port/api/validate" "$(j '.blocked | join(" ")')"
run '{"steps": [{"step": "goto", "path": "/"}, {"step": "wait_text", "text": "cross-origin: blocked"}]}'
eq "the page sees the cross-origin fetch fail" true "$(j .ok)"
run '{"steps": [{"step": "goto", "path": "file:///etc/hosts"}]}'
eq "file:// navigation is refused" false "$(j '.steps[0].ok')"
eq "a refused step is still exit 0" 0 "$rc"
run '{"steps": [{"step": "goto", "path": "//localhost:'$port'/"}]}'
eq "a protocol-relative path to another origin is refused" false "$(j '.steps[0].ok')"
run '{"steps": [{"step": "goto", "path": "data:text/html,hi"}]}'
eq "data: navigation is refused" false "$(j '.steps[0].ok')"
run '{"base": "http://localhost:'$port'", "steps": [{"step": "goto", "path": "/"}]}'
eq "a base other than DW_URL's origin is an invalid spec" 2 "$rc"

# --- mock: the real answer with named fields overwritten, the rest kept
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "mock", "url_glob": "**/api/validate", "set": {"plan.host_memory": {"projected_mb": 15648}, "plan.estimate.minutes": null, "downloads_required.0.repo": "org-a/gated-repo", "downloads_required[1]": {"repo": "org-b/missing-repo"}}},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "valid: true"},
  {"step": "expect_text", "text": "host RAM: 15648 MB"},
  {"step": "expect_text", "text": "minutes: null"},
  {"step": "expect_text", "text": "basis: observed"},
  {"step": "expect_text", "text": "downloads: org-a/gated-repo, org-b/missing-repo"},
  {"step": "unmock", "url_glob": "**/api/validate"},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "minutes: 4"}
]}'
eq "mock spec ok" true "$(j .ok)"
eq "mock sets a dotted path to an object" true "$(j '.steps[4].result.found')"
eq "mock sets a field to null" true "$(j '.steps[5].result.found')"
eq "mock keeps the fields it was not told to set" true "$(j '.steps[6].result.found')"
eq "mock indexes arrays (a.0.b and a[1])" true "$(j '.steps[7].result.found')"
eq "unmock restores the real answer" true "$(j '.steps[10].ok')"
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "mock", "url_glob": "**/api/validate", "once": true, "set": {"plan.estimate.basis": "unknown"}},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "basis: unknown"},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "basis: observed"}
]}'
eq "mock once answers one request, then the real one" true "$(j .ok)"
run '{"steps": [{"step": "mock", "url_glob": "**/x", "set": {"__proto__.polluted": 1}}]}'
eq "a prototype key in a dotted path is an invalid spec" 2 "$rc"

# --- record / recorded: every matching request from that point, mocked or not
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "valid: true"},
  {"step": "record", "url_glob": "**/api/validate"},
  {"step": "record", "url_glob": "**/api/jobs**"},
  {"step": "record", "url_glob": "**/api/note"},
  {"step": "mock", "url_glob": "**/api/validate", "once": true, "set": {"plan.estimate.basis": "unknown"}},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "basis: unknown"},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "basis: observed"},
  {"step": "click", "role": "button", "name": "Run"},
  {"step": "wait_text", "text": "typed: posted"},
  {"step": "click", "role": "button", "name": "Note"},
  {"step": "wait_text", "text": "valid: true"},
  {"step": "recorded", "url_glob": "**/api/validate"},
  {"step": "recorded", "url_glob": "**/api/jobs**"},
  {"step": "recorded", "url_glob": "**/api/note"}
]}'
eq "record spec ok" true "$(j .ok)"
eq "record starts at its step (the earlier request is not in it), and sees mocked and real requests" 2 "$(j '.steps[15].result.count')"
eq "a recorded request has its method" GET "$(j '.steps[15].result.requests[0].method')"
eq "and its path" /api/validate "$(j '.steps[15].result.requests[0].url')"
ok "and a timestamp" test "$(j '.steps[15].result.requests[0].timestamp | type')" = number
eq "a POST is recorded" POST "$(j '.steps[16].result.requests[0].method')"
eq "with its query" "/api/jobs?sizes=false" "$(j '.steps[16].result.requests[0].url')"
eq "a JSON body is parsed" catalog/flux.json "$(j '.steps[16].result.requests[0].body.workflow_path')"
eq "keeping its types" false "$(j '.steps[16].result.requests[0].body.sizes')"
eq "a text body is text" string "$(j '.steps[17].result.requests[0].body | type')"
has "starting with what was sent" "plain note xxx" "$(j '.steps[17].result.requests[0].body')"
ok "cut to 4 KB" test "$(j '.steps[17].result.requests[0].body | length')" -le 4200
run '{"steps": [{"step": "recorded", "url_glob": "**/never"}]}'
eq "recorded without a record step fails the step" false "$(j '.steps[0].ok')"
run '{"steps": [{"step": "record", "url_glob": "**/x", "limit": 5}]}'
eq "record takes url_glob only" 2 "$rc"

# --- locators are visible text and role only
run '{"steps": [{"step": "click", "selector": "#v"}]}'
eq "a CSS selector is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "click", "css": "button"}]}'
eq "a css key is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "inspect", "xpath": "//p"}]}'
eq "an xpath key is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "eval", "js": "1"}]}'
eq "an unknown step is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "wait_text", "text": "x", "timeout_ms": 60000}]}'
eq "a wait over 30 s is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "screenshot", "name": "../etc/x"}]}'
eq "a screenshot name with a slash is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "goto", "path": "/"}, {"step": "click", "role": "button", "name": "No such button"}]}'
eq "a missing element fails its step" false "$(j '.steps[1].ok')"
eq "and the run" false "$(j .ok)"
has "the failed step says why" "No such button" "$(j '.steps[1].error')"

# --- the spec path: /tmp/dw-ui-*.json, a regular file, no symlink
printf '{"steps": []}\n' > "$T/elsewhere.json"
node "$runner" "$T/elsewhere.json" >/dev/null 2>&1; eq "a spec outside /tmp/dw-ui-* exits 2" 2 $?
printf '{"steps": []}\n' > "$specs-real.json"
ln -sf "$specs-real.json" "/tmp/dw-ui-link-$$.json"
node "$runner" "/tmp/dw-ui-link-$$.json" >/dev/null 2>&1; eq "a symlinked spec exits 2" 2 $?
node "$runner" "/tmp/dw-ui-missing-$$.json" >/dev/null 2>&1; eq "a missing spec exits 2" 2 $?
node "$runner" "/tmp/../tmp/dw-ui-test-$$-real.json" >/dev/null 2>&1; eq "a spec path with .. exits 2" 2 $?
node "$runner" "$specs-real.json" extra >/dev/null 2>&1; eq "an extra argument exits 2" 2 $?
node "$runner" >/dev/null 2>&1; eq "no argument exits 2" 2 $?
printf 'not json' > "$specs-bad.json"
node "$runner" "$specs-bad.json" >/dev/null 2>&1; eq "a spec that is not JSON exits 2" 2 $?
head -c 300000 /dev/zero | tr '\0' ' ' > "$specs-big.json"
node "$runner" "$specs-big.json" >/dev/null 2>&1; eq "a spec over 256 KB exits 2" 2 $?
DW_URL='' node "$runner" "$specs-real.json" >/dev/null 2>&1; eq "no DW_URL and no base exits 2" 2 $?
finish
