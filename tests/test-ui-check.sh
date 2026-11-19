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
trap 'rm -rf "$T"; rm -f "$specs"-*.json /tmp/dw-ui-link-$$.json; for p in ${srv:-} ${asrv:-}; do kill "$p" 2>/dev/null; done' EXIT

# serve <out> [token]: starts the fixture server (tests/fixtures/ui-check-server.py) in the
# background; $! is its pid and the port it printed lands in $port
serve() {
  python3 -u "$HARNEST/tests/fixtures/ui-check-server.py" "$HARNEST/tests/fixtures/ui-check" ${2:+"$2"} > "$1" 2>&1 &
  port=""
  for _ in $(seq 1 50); do
    port="$(sed -nE 's/.*port ([0-9]+).*/\1/p' "$1" | head -1)"
    [ -n "$port" ] && break
    python3 -c 'import time; time.sleep(0.1)'
  done
  [ -n "$port" ] || { echo "  FAIL: fixture server did not start"; cat "$1"; exit 1; }
}
serve "$T/srv.out"
srv=$!
export DW_URL="http://127.0.0.1:$port/mcp"
unset HARNEST_MCP_CONFIG

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
shot="$(j '.steps[10].result.path')"
shotdir="$(dirname "$shot")"
tmpdir="$(node -e 'process.stdout.write(require("os").tmpdir())')"
has "screenshot lands in a fresh private dir under the temp dir" "$tmpdir/dw-ui-shots-" "$shotdir/"
eq "named for the step" "test-$$.png" "$(basename "$shot")"
ok "the screenshot is a file" test -s "$shot"
fails "and not a symlink" test -L "$shot"
eq "the shot dir is 0700" 700 "$(stat -f %Lp "$shotdir")"
eq "the shot is 0600" 600 "$(stat -f %Lp "$shot")"
eq "the output lists the shots" "$shot" "$(j '.shots | join(" ")')"
[ -n "$shotdir" ] && case "$shotdir" in "$tmpdir"/dw-ui-shots-*) rm -rf "$shotdir" ;; esac
run '{"steps": [{"step": "screenshot", "name": "a"}, {"step": "screenshot", "name": "b"}]}'
eq "two shots in one run" 2 "$(j '.shots | length')"
eq "share one run dir" 1 "$(j '[.shots[] | split("/")[:-1] | join("/")] | unique | length')"
d1="$(j '.shots[0]' | xargs dirname)"
run '{"steps": [{"step": "screenshot", "name": "a"}]}'
d2="$(j '.shots[0]' | xargs dirname)"
fails "each run gets its own dir" test "$d1" = "$d2"
for d in "$d1" "$d2"; do case "$d" in "$tmpdir"/dw-ui-shots-*) rm -rf "$d" ;; esac; done
run '{"steps": [{"step": "screenshot", "name": "a"}, {"step": "screenshot", "name": "a"}]}'
eq "a name taken in this run fails its step (never overwrites)" false "$(j '.steps[1].ok')"
d1="$(j '.shots[0]' | xargs dirname)"; case "$d1" in "$tmpdir"/dw-ui-shots-*) rm -rf "$d1" ;; esac
run '{"steps": [{"step": "goto", "path": "/"}]}'
eq "a run with no screenshot lists none" 0 "$(j '.shots | length')"

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
run '{"base": "http://127.0.0.1:'$port'/", "steps": [{"step": "goto", "path": "/"}]}'
eq "a base on DW_URL's origin is accepted" true "$(j .ok)"
DW_URL='' run '{"base": "http://127.0.0.1:'$port'", "steps": [{"step": "goto", "path": "/"}]}'
eq "no DW_URL: a spec base alone is refused (fail closed)" 2 "$rc"
DW_URL='not a url' run '{"steps": [{"step": "goto", "path": "/"}]}'
eq "a DW_URL that is not a URL exits 2" 2 "$rc"
DW_URL='file:///etc/hosts' run '{"steps": [{"step": "goto", "path": "/"}]}'
eq "a DW_URL that is not http(s) exits 2" 2 "$rc"

# --- no side door past the MCP denylist: DELETE, and every write route but validate and a run, are aborted
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "click", "role": "button", "name": "Delete model"},
  {"step": "wait_text", "text": "admin: d failed"},
  {"step": "mock", "url_glob": "**/api/system/diffusers/update", "set": {"ok": true}},
  {"step": "click", "role": "button", "name": "Update diffusers"},
  {"step": "wait_text", "text": "admin: u failed"},
  {"step": "unmock", "url_glob": "**/api/system/diffusers/update"},
  {"step": "click", "role": "button", "name": "Save workflow"},
  {"step": "wait_text", "text": "admin: s failed"},
  {"step": "click", "role": "button", "name": "Run"},
  {"step": "wait_text", "text": "run: answered 501"},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "valid: true"}
]}'
eq "denied-route spec ok" true "$(j .ok)"
has "a DELETE (delete_model) is aborted and reported" "DELETE http://127.0.0.1:$port/api/models?repo=org/x" "$(j '.blocked | join(" ")')"
has "a POST to update_diffusers is aborted and reported" "POST http://127.0.0.1:$port/api/system/diffusers/update" "$(j '.blocked | join(" ")')"
eq "a mock on a denied route never reaches the server" 0 "$(j '.steps[6].result.hits')"
has "a PUT (workflow save) is aborted and reported" "PUT http://127.0.0.1:$port/api/workflows/mine" "$(j '.blocked | join(" ")')"
eq "the allowed POST to /api/jobs reaches the server" true "$(j '.steps[10].ok')"
eq "and is not in blocked" "" "$(j '[.blocked[] | select(test("/api/jobs"))] | join(" ")')"
eq "nor is GET /api/validate" "" "$(j '[.blocked[] | select(test("127.0.0.1:'$port'/api/validate"))] | join(" ")')"

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
  {"step": "record", "url_glob": "**/api/validate?note=1"},
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
  {"step": "recorded", "url_glob": "**/api/validate?note=1"}
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
run '{"steps": [{"step": "screenshot", "name": "a.png"}]}'
eq "a screenshot name with a dot is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "screenshot", "name": "'"$(printf 'a%.0s' $(seq 1 65))"'"}]}'
eq "a screenshot name over 64 chars is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "goto", "path": "/"}, {"step": "click", "role": "button", "name": "No such button"}]}'
eq "a missing element fails its step" false "$(j '.steps[1].ok')"
eq "and the run" false "$(j .ok)"
has "the failed step says why" "No such button" "$(j '.steps[1].error')"

# --- stub: answers a write route without sending it; the request is still recorded
c0="$(grep -c 'POST /api/jobs?sizes=false' "$T/srv.out")"
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "record", "url_glob": "**/api/jobs?**"},
  {"step": "stub", "url_glob": "**/api/jobs?**", "json": {"id": "j-1"}, "status": 201},
  {"step": "click", "role": "button", "name": "Run"},
  {"step": "wait_text", "text": "run: answered 201"},
  {"step": "recorded", "url_glob": "**/api/jobs?**"},
  {"step": "stub", "url_glob": "**/api/validate", "json": {"valid": false}},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "basis: observed"},
  {"step": "unmock", "url_glob": "**/api/jobs?**"},
  {"step": "click", "role": "button", "name": "Run"},
  {"step": "wait_text", "text": "run: answered 501"}
]}'
eq "stub spec ok" true "$(j .ok)"
eq "a stubbed POST is answered with the stub (status kept)" true "$(j '.steps[4].ok')"
eq "and still recorded, with its body" catalog/flux.json "$(j '.steps[5].result.requests[0].body.workflow_path')"
eq "a stub answers writes only: a GET on its route gets the real answer" true "$(j '.steps[8].ok')"
eq "unmock removes a stub: the next POST reaches the server" true "$(j '.steps[11].ok')"
eq "unmock counts the stub's hits" 1 "$(j '.steps[9].result.hits')"
eq "the stubbed POST never reached the server (one POST there, after unmock)" $((c0 + 1)) "$(grep -c 'POST /api/jobs?sizes=false' "$T/srv.out")"
run '{"steps": [{"step": "stub", "url_glob": "{**/api/validate,**/api/jobs/*/cancel}", "json": null}]}'
eq "a stub on {validate, cancel} is valid" 0 "$rc"
for g in '**' '**/api/**' '**/api/models' '**/api/jobs**' '**/api/jobs*' '**/api/jobs/*/rerun*' '**/api/jobs/*/rerun-restart-batch*' '{**/api/jobs/*/rerun-restart-batch,**/api/models}' '{**/api/jobs,**/api/models}' '**/api/jobs/**/cancel'; do
  run '{"steps": [{"step": "stub", "url_glob": "'"$g"'", "json": {}, "method": "POST"}]}'
  eq "a POST stub on $g (not only a POST_ALLOWED route) is an invalid spec" 2 "$rc"
done
run '{"steps": [{"step": "stub", "url_glob": "{**/api/jobs/*/rerun,**/api/jobs/j-1/rerun?x=1}", "json": {}}]}'
eq "a stub on /api/jobs/<id>/rerun is valid" 0 "$rc"
run '{"steps": [{"step": "stub", "url_glob": "**/api/jobs/*/rerun-restart-batch", "json": {}, "method": "POST"}]}'
eq "a stub on /rerun-restart-batch is valid" 0 "$rc"
run '{"steps": [{"step": "stub", "url_glob": "**/api/jobs", "json": {}, "status": 99}]}'
eq "a stub status outside 100-599 is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "stub", "url_glob": "**/api/jobs", "json": {}, "status": 600}]}'
eq "a stub status of 600 is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "stub", "url_glob": "**/api/jobs", "json": {}, "method": "DELETE"}]}'
eq "a stub method other than GET or POST is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "stub", "url_glob": "**/api/jobs"}]}'
eq "a stub without json is an invalid spec" 2 "$rc"

# --- POST /api/jobs/<id>/rerun is allowed (rerun_job); /rerun-restart-batch is not
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "click", "role": "button", "name": "Again"},
  {"step": "wait_text", "text": "rerun: rr answered 501"},
  {"step": "click", "role": "button", "name": "Restart batch"},
  {"step": "wait_text", "text": "rerun: rb failed"},
  {"step": "record", "url_glob": "**/api/jobs/*/rerun"},
  {"step": "stub", "url_glob": "**/api/jobs/*/rerun", "json": {"id": "j-8"}, "status": 201},
  {"step": "click", "role": "button", "name": "Again"},
  {"step": "wait_text", "text": "rerun: rr answered 201"},
  {"step": "recorded", "url_glob": "**/api/jobs/*/rerun"}
]}'
eq "rerun spec ok" true "$(j .ok)"
eq "a rerun POST reaches the server" true "$(j '.steps[2].ok')"
eq "and is not blocked" "" "$(j '[.blocked[] | select(test("/rerun$"))] | join(" ")')"
has "a rerun-restart-batch POST is aborted and reported" "POST http://127.0.0.1:$port/api/jobs/j-7/rerun-restart-batch" "$(j '.blocked | join(" ")')"
eq "a stub answers a rerun POST" true "$(j '.steps[8].ok')"
eq "and the stubbed rerun is recorded with its body" true "$(j '.steps[9].result.requests[0].body.new_seed')"

# --- /rerun-restart-batch is stub-only: a stub answers it, a real POST or a mock is blocked
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "record", "url_glob": "**/api/jobs/*/rerun-restart-batch"},
  {"step": "stub", "url_glob": "**/api/jobs/*/rerun-restart-batch", "json": {"queued": 3}, "status": 202},
  {"step": "click", "role": "button", "name": "Restart batch"},
  {"step": "wait_text", "text": "rerun: rb answered 202"},
  {"step": "recorded", "url_glob": "**/api/jobs/*/rerun-restart-batch"},
  {"step": "unmock", "url_glob": "**/api/jobs/*/rerun-restart-batch"},
  {"step": "mock", "url_glob": "**/api/jobs/*/rerun-restart-batch", "set": {"a": 1}},
  {"step": "click", "role": "button", "name": "Restart batch"},
  {"step": "wait_text", "text": "rerun: rb failed"}
]}'
eq "restart-batch stub spec ok" true "$(j .ok)"
eq "a stub answers the restart-batch POST" true "$(j '.steps[4].ok')"
eq "and records its body" true "$(j '.steps[5].result.requests[0].body.new_seed')"
eq "only the mocked POST is reported blocked (the stubbed one never was)" 1 "$(j '[.blocked[] | select(test("rerun-restart-batch"))] | length')"
has "a mocked (fetching) restart-batch POST is blocked and reported" "POST http://127.0.0.1:$port/api/jobs/j-7/rerun-restart-batch" "$(j '.blocked | join(" ")')"

# --- inspect: the element's attributes, handlers as <handler>, values and count capped
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "inspect", "text": "Docs link"},
  {"step": "inspect", "text": "Many attributes"}
]}'
eq "attributes spec ok" true "$(j .ok)"
eq "inspect: id attribute" doc-link "$(j '.steps[1].result.attributes.id')"
eq "inspect: title attribute" "Open the docs" "$(j '.steps[1].result.attributes.title')"
eq "inspect: href attribute" "/docs?x=1" "$(j '.steps[1].result.attributes.href')"
eq "inspect: aria attribute" Docs "$(j '.steps[1].result.attributes["aria-label"]')"
eq "inspect: data attribute" doc "$(j '.steps[1].result.attributes["data-kind"]')"
eq "inspect: an on* handler is present, its body not reported" "<handler>" "$(j '.steps[1].result.attributes.onclick')"
fails "the handler body is nowhere in the output" grep -q "return false" <<< "$out"
eq "inspect: the ancestor's attributes" nav "$(j '.steps[1].result.ancestor.attributes["data-area"]')"
eq "and its title" "Site links" "$(j '.steps[1].result.ancestor.attributes.title')"
eq "at most 40 attributes" 40 "$(j '.steps[2].result.attributes | length')"
eq "the rest counted" 11 "$(j '.steps[2].result.attributes_dropped')"
eq "a value cut to 500 chars" 500 "$(j '.steps[2].result.attributes.title | length')"

# --- mock/stub status on a GET, stub on any same-origin GET, abort a GET
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "stub", "url_glob": "**/api/validate", "method": "GET", "json": {"detail": "nope"}, "status": 404},
  {"step": "click", "role": "button", "name": "Load"},
  {"step": "wait_text", "text": "load: 404 nope"},
  {"step": "unmock", "url_glob": "**/api/validate"},
  {"step": "mock", "url_glob": "**/api/validate", "status": 500},
  {"step": "click", "role": "button", "name": "Load"},
  {"step": "wait_text", "text": "load: 500 observed"},
  {"step": "unmock", "url_glob": "**/api/validate"},
  {"step": "mock", "url_glob": "**/api/validate", "status": 503, "set": {"plan.estimate.basis": "guess"}},
  {"step": "click", "role": "button", "name": "Load"},
  {"step": "wait_text", "text": "load: 503 guess"},
  {"step": "unmock", "url_glob": "**/api/validate"},
  {"step": "abort", "url_glob": "{**/api/validate,**/api/jobs/*/rerun}"},
  {"step": "click", "role": "button", "name": "Load"},
  {"step": "wait_text", "text": "load: failed"},
  {"step": "click", "role": "button", "name": "Again"},
  {"step": "wait_text", "text": "rerun: rr answered 501"},
  {"step": "unmock", "url_glob": "{**/api/validate,**/api/jobs/*/rerun}"},
  {"step": "click", "role": "button", "name": "Load"},
  {"step": "wait_text", "text": "load: 200 observed"},
  {"step": "stub", "url_glob": "**/api/no-such-thing", "json": {"items": []}},
  {"step": "stub", "url_glob": "**/api/models", "json": {}, "status": 200}
]}'
eq "GET status spec ok" true "$(j .ok)"
eq "a GET stub answers with its status and JSON" true "$(j '.steps[3].ok')"
eq "a mock sets the status of the real answer" true "$(j '.steps[7].ok')"
eq "and fields with it" true "$(j '.steps[11].ok')"
eq "abort fails a GET as a network error" true "$(j '.steps[15].ok')"
eq "abort leaves a POST on its glob alone" true "$(j '.steps[17].ok')"
eq "unmock counts the abort's hits (the GET only)" 1 "$(j '.steps[18].result.hits')"
eq "unmock removes an abort" true "$(j '.steps[20].ok')"
eq "a GET stub on any same-origin path is valid (defaults to GET off the write routes)" GET "$(j '.steps[22].result.method')"
s0="$(grep -c 'GET /api/validate' "$T/srv.out")"
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "wait_text", "regex": "auth: \\d+"},
  {"step": "stub", "url_glob": "**/api/validate", "method": "GET", "json": {"detail": "stubbed"}},
  {"step": "click", "role": "button", "name": "Load"},
  {"step": "wait_text", "text": "load: 200 stubbed"},
  {"step": "stub", "url_glob": "**/api/jobs/*/rerun", "method": "GET", "json": {"id": "never"}},
  {"step": "click", "role": "button", "name": "Again"},
  {"step": "wait_text", "text": "rerun: rr answered 501"}
]}'
eq "GET stub run ok" true "$(j .ok)"
eq "a GET stub never fetches (one GET there: the page load)" $((s0 + 1)) "$(grep -c 'GET /api/validate' "$T/srv.out")"
eq "a GET stub does not answer a POST on its glob (it reached the server)" true "$(j '.steps[7].ok')"
run '{"steps": [{"step": "mock", "url_glob": "**/x"}]}'
eq "a mock needs set or status" 2 "$rc"
run '{"steps": [{"step": "mock", "url_glob": "**/x", "status": 99}]}'
eq "a mock status outside 100-599 is an invalid spec" 2 "$rc"
run '{"steps": [{"step": "abort", "url_glob": "**/x", "once": true}]}'
eq "abort takes url_glob only" 2 "$rc"

# --- dup_ids: DOM ids that occur more than once
run '{"steps": [{"step": "goto", "path": "/"}, {"step": "dup_ids"}]}'
eq "dup_ids spec ok" true "$(j .ok)"
eq "dup_ids lists each repeated id once" "thrice twice" "$(j '.steps[1].result.ids | sort | join(" ")')"
eq "with its count" 3 "$(j '.steps[1].result.counts.thrice')"
run '{"steps": [{"step": "dup_ids", "id": "x"}]}'
eq "dup_ids takes no keys" 2 "$rc"

# --- window_flag: a __name on window, primitives only
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "window_flag", "name": "__APP_READY"},
  {"step": "window_flag", "name": "__count"},
  {"step": "window_flag", "name": "__label"},
  {"step": "window_flag", "name": "__nothing"},
  {"step": "window_flag", "name": "__never_set"}
]}'
eq "window_flag spec ok" true "$(j .ok)"
eq "a boolean flag" true "$(j '.steps[1].result.value')"
eq "a number flag" 3 "$(j '.steps[2].result.value')"
eq "a string flag" ready "$(j '.steps[3].result.value')"
eq "a null flag" null "$(j '.steps[4].result.type')"
eq "an unset flag is undefined" undefined "$(j '.steps[5].result.type')"
for f in __obj __fn __long; do
  run '{"steps": [{"step": "goto", "path": "/"}, {"step": "window_flag", "name": "'"$f"'"}]}'
  eq "window_flag $f (not a primitive, or a string over 200) fails its step" false "$(j '.steps[1].ok')"
  has "saying why" "window_flag" "$(j '.steps[1].error')"
done
for f in 'APP_READY' '__a.b' '__' 'document.cookie' '__a()' "__$(printf 'a%.0s' $(seq 1 41))"; do
  run '{"steps": [{"step": "window_flag", "name": "'"$f"'"}]}'
  eq "window_flag name $f is an invalid spec" 2 "$rc"
done

# --- goto loads pages only
run '{"steps": [{"step": "goto", "path": "/plain.txt"}, {"step": "expect_text", "text": "plain text"}]}'
eq "goto to a document that is not text/html fails its step" false "$(j '.steps[0].ok')"
has "saying why" "text/html" "$(j '.steps[0].error')"

# --- a catastrophic regex runs in the page: the step cap still ends it
start="$(date +%s)"
run '{"steps": [{"step": "goto", "path": "/"}, {"step": "expect_text", "regex": "^(a+)+$"}]}'
took=$(( $(date +%s) - start ))
ok "a backtracking regex ends within the step cap ($took s)" test "$took" -le 45
eq "its step fails" false "$(j '.steps[1].ok')"
has "on the cap" "over 30 s" "$(j '.steps[1].error')"
eq "exit 0" 0 "$rc"
eq "one JSON document" 1 "$(jq -s length <<< "$out")"

# --- SIGTERM: the browser is closed and a partial result printed
n=$((n + 1))
printf '%s\n' '{"steps": [{"step": "goto", "path": "/"}, {"step": "expect_text", "regex": "^(a+)+$"}]}' > "$specs-$n.json"
node "$runner" "$specs-$n.json" > "$T/term.out" 2>"$T/term.err" &
np=$!
# descendants <pid>: every process under it
descendants() { local c; for c in $(pgrep -P "$1"); do echo "$c"; descendants "$c"; done; }
kids=""
for _ in $(seq 1 100); do
  kids="$(descendants "$np" | tr '\n' ' ')"
  [ "$(echo $kids | wc -w)" -ge 3 ] && break
  python3 -c 'import time; time.sleep(0.1)'
done
python3 -c 'import time; time.sleep(3)'
kids="$(descendants "$np" | tr '\n' ' ')"
ok "the run has a browser to close" test -n "$kids"
start="$(date +%s)"
kill -TERM "$np"
wait "$np"; trc=$?
took=$(( $(date +%s) - start ))
ok "SIGTERM ends the run promptly ($took s)" test "$took" -le 10
eq "with exit 0" 0 "$trc"
out="$(cat "$T/term.out")"
eq "one JSON document" 1 "$(jq -s length <<< "$out")"
eq "a partial result, not ok" false "$(j .ok)"
has "saying it was terminated" "SIGTERM" "$(j .error)"
eq "the step done before it is in the result" true "$(j '.steps[0].ok')"
python3 -c 'import time; time.sleep(1)'
left=""
for k in $kids; do kill -0 "$k" 2>/dev/null && left="$left $k"; done
eq "no Chromium process of the run is left" "" "$left"

# --- delay_ms on mock and stub: the answer is held, so a stale one can arrive after a newer one
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "mock", "url_glob": "**/api/validate", "once": true, "delay_ms": 2000, "set": {"plan.estimate.basis": "stale-mock"}},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "basis: observed"},
  {"step": "expect_text", "text": "basis: stale-mock"},
  {"step": "wait_text", "text": "basis: stale-mock", "timeout_ms": 8000},
  {"step": "expect_text", "text": "basis: observed"}
]}'
eq "delayed mock spec ok" true "$(j .ok)"
eq "the second (undelayed) answer shows first" false "$(j '.steps[5].result.found')"
eq "the delayed first answer lands last" false "$(j '.steps[7].result.found')"
eq "the result says the delay" 2000 "$(j '.steps[1].result.delay_ms')"
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "stub", "url_glob": "**/api/validate", "method": "GET", "delay_ms": 2000, "json": {"valid": "stale-stub"}},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "unmock", "url_glob": "**/api/validate"},
  {"step": "click", "role": "button", "name": "Validate"},
  {"step": "wait_text", "text": "valid: true"},
  {"step": "expect_text", "text": "valid: stale-stub"},
  {"step": "wait_text", "text": "valid: stale-stub", "timeout_ms": 8000},
  {"step": "expect_text", "text": "valid: true"}
]}'
eq "delayed stub spec ok" true "$(j .ok)"
eq "stub: the later undelayed answer shows first" false "$(j '.steps[6].result.found')"
eq "stub: the delayed answer lands last" false "$(j '.steps[8].result.found')"
for bad in -1 10001 1.5 '"5"' true null; do
  run '{"steps": [{"step": "stub", "url_glob": "**/api/validate", "json": {}, "delay_ms": '"$bad"'}]}'
  eq "stub delay_ms $bad is an invalid spec" 2 "$rc"
  run '{"steps": [{"step": "mock", "url_glob": "**/x", "status": 500, "delay_ms": '"$bad"'}]}'
  eq "mock delay_ms $bad is an invalid spec" 2 "$rc"
done
run '{"steps": [{"step": "mock", "url_glob": "**/x", "status": 500, "delay_ms": 10000}, {"step": "stub", "url_glob": "**/y", "json": {}, "delay_ms": 0}]}'
eq "delay_ms 0 and 10000 are accepted" true "$(j .ok)"
run '{"steps": [{"step": "abort", "url_glob": "**/x", "delay_ms": 5}]}'
eq "delay_ms on another step is refused" 2 "$rc"

# --- SIGTERM while a delayed route is pending
n=$((n + 1))
printf '%s\n' '{"steps": [{"step": "goto", "path": "/"}, {"step": "stub", "url_glob": "**/api/validate", "method": "GET", "delay_ms": 10000, "json": {"valid": 1}}, {"step": "click", "role": "button", "name": "Validate"}, {"step": "wait_text", "text": "never shown", "timeout_ms": 30000}]}' > "$specs-$n.json"
node "$runner" "$specs-$n.json" > "$T/dterm.out" 2>"$T/dterm.err" &
dp=$!
python3 -c 'import time; time.sleep(4)'
start="$(date +%s)"
kill -TERM "$dp"
wait "$dp"; drc=$?
took=$(( $(date +%s) - start ))
ok "SIGTERM during a delayed route ends the run promptly ($took s)" test "$took" -le 5
eq "with exit 0" 0 "$drc"
out="$(cat "$T/dterm.out")"
has "saying it was terminated" "SIGTERM" "$(j .error)"
eq "the delayed stub step itself was done" true "$(j '.steps[1].ok')"

# --- the bearer token: from the session's MCP config, into localStorage, never printed
tok="tok-sekret-$$"
serve "$T/asrv.out" "$tok"
asrv=$!
aport="$port"
cfg() { printf '{"mcpServers": {"dw": {"type": "http", "url": "%s", "headers": {"Authorization": "Bearer %s"}}}}\n' "$1" "$2" > "$T/mcp.json"; }
authspec='{"steps": [{"step": "goto", "path": "/"}, {"step": "wait_text", "regex": "auth: \\d+"}, {"step": "expect_text", "regex": "^auth: "}, {"step": "expect_text", "text": "token: "}]}'
cfg "http://127.0.0.1:$aport/mcp" "$tok"
DW_URL="http://127.0.0.1:$aport/mcp" HARNEST_MCP_CONFIG="$T/mcp.json" run "$authspec"
eq "token run ok" true "$(j .ok)"
eq "with the token injected, the page's API call is let in" "auth: 200" "$(j '.steps[2].result.snippet')"
fails "the token is nowhere in stdout" grep -q "$tok" <<< "$out"
fails "nor in stderr" grep -q "$tok" "$T/err"
eq "the page text that shows it is scrubbed" "token: <token>" "$(j '.steps[3].result.snippet')"
has "and so is a console error naming it" "the token is <token>" "$(j '.console_errors | join(" ")')"
DW_URL="http://127.0.0.1:$aport/mcp" HARNEST_MCP_CONFIG="$T/mcp.json" run '{"steps": [{"step": "goto", "path": "/"}, {"step": "inspect", "regex": "^token: "}, {"step": "window_flag", "name": "__token"}]}'
eq "an attribute holding the token is scrubbed" "<token>" "$(j '.steps[1].result.attributes["data-token"]')"
eq "so is a window flag holding it" "<token>" "$(j '.steps[2].result.value')"
fails "the token is nowhere in that output" grep -q "$tok" <<< "$out"
DW_URL="http://127.0.0.1:$aport/mcp" run "$authspec"
eq "without a config, no token: the API answers 401" "auth: 401" "$(j '.steps[2].result.snippet')"
cfg "http://127.0.0.1:$aport/mcp" ""
DW_URL="http://127.0.0.1:$aport/mcp" HARNEST_MCP_CONFIG="$T/mcp.json" run "$authspec"
eq "an empty token in the config: run without one" "auth: 401" "$(j '.steps[2].result.snippet')"
cfg "http://localhost:$aport/mcp" "$tok"
DW_URL="http://127.0.0.1:$aport/mcp" HARNEST_MCP_CONFIG="$T/mcp.json" run "$authspec"
eq "a config for another origin gives no token" "auth: 401" "$(j '.steps[2].result.snippet')"
DW_URL="http://127.0.0.1:$aport/mcp" HARNEST_MCP_CONFIG="$T/no-such.json" run "$authspec"
eq "a missing config: run without one" "auth: 401" "$(j '.steps[2].result.snippet')"
run '{"token": "x", "steps": []}'
eq "a token in the spec is an invalid spec" 2 "$rc"

# --- fetch: a direct GET or HEAD of one base-origin path, from the runner, never the page
r0="$(grep -c 'from=redirect' "$T/srv.out")"
run '{"steps": [
  {"step": "fetch", "path": "/api/fetch/json?x=1"},
  {"step": "fetch", "path": "/api/fetch/json", "method": "HEAD"},
  {"step": "fetch", "path": "/api/fetch/big"},
  {"step": "fetch", "path": "/api/fetch/plain"},
  {"step": "fetch", "path": "/api/fetch/bad-json"},
  {"step": "fetch", "path": "/api/fetch/problem"},
  {"step": "fetch", "path": "/api/fetch/redirect"},
  {"step": "fetch", "path": "/api/fetch/redirect-off"},
  {"step": "stub", "url_glob": "**/api/fetch/json", "method": "GET", "json": {"stubbed": true}},
  {"step": "abort", "url_glob": "**/api/fetch/plain"},
  {"step": "fetch", "path": "/api/fetch/json"},
  {"step": "fetch", "path": "/api/fetch/plain", "method": "GET"},
  {"step": "fetch", "path": "/openapi.json"},
  {"step": "fetch", "path": "/api/fetch/deep"},
  {"step": "fetch", "path": "/api/fetch/stream"},
  {"step": "fetch", "path": "/api/%2F%2Flocalhost:'"$port"'/x"}
]}'
eq "fetch spec ok" true "$(j .ok)"
eq "fetch: the status" 200 "$(j '.steps[0].result.status')"
eq "fetch: the content type" application/json "$(j '.steps[0].result.content_type')"
eq "fetch: a JSON body is parsed" lora-a "$(j '.steps[0].result.body.items[0].name')"
eq "keeping its types" 16 "$(j '.steps[0].result.body.items[0].rank | tostring')"
eq "the query is sent" "/api/fetch/json?x=1" "$(j '.steps[0].result.body.query')"
eq "a whole read is not truncated" false "$(j '.steps[0].result.truncated')"
ok "and counts its bytes" test "$(j '.steps[0].result.bytes')" -gt 10
eq "HEAD: the status" 200 "$(j '.steps[1].result.status')"
eq "HEAD: body null" null "$(j '.steps[1].result.body')"
eq "HEAD: no bytes" 0 "$(j '.steps[1].result.bytes')"
eq "a body over 256 KB is truncated" true "$(j '.steps[2].result.truncated')"
eq "read to 262144 bytes" 262144 "$(j '.steps[2].result.bytes')"
eq "a truncated JSON body is text" string "$(j '.steps[2].result.body | type')"
eq "cut to the cap" 262144 "$(j '.steps[2].result.body | length')"
eq "a non-JSON body is text" "plain text, not a page" "$(j '.steps[3].result.body' | head -1)"
has "with its content type" text/plain "$(j '.steps[3].result.content_type')"
eq "JSON that does not parse is text" '{"items": [1, 2' "$(j '.steps[4].result.body')"
ok "with json_error" test -n "$(j '.steps[4].result.json_error // empty')"
eq "an error status comes back as is" 404 "$(j '.steps[5].result.status')"
eq "a +json type is parsed" "no such lora" "$(j '.steps[5].result.body.detail')"
eq "a redirect is returned, not followed" 302 "$(j '.steps[6].result.status')"
eq "with its same-origin location as a path" "/api/fetch/json?from=redirect" "$(j '.steps[6].result.location')"
eq "and the target was never requested" "$r0" "$(grep -c 'from=redirect' "$T/srv.out")"
eq "an off-origin location is not named" "<off-origin>" "$(j '.steps[7].result.location')"
fails "nor is its host anywhere in that step" grep -q localhost <<< "$(j '.steps[7]')"
eq "a GET stub does not apply to fetch" lora-a "$(j '.steps[10].result.body.items[0].name')"
eq "nor does an abort" 200 "$(j '.steps[11].result.status')"
eq "/openapi.json is read" 3.1.0 "$(j '.steps[12].result.body.openapi')"
eq "JSON too deep to print is text" string "$(j '.steps[13].result.body | type')"
eq "with json_error too deeply nested" "too deeply nested" "$(j '.steps[13].result.json_error')"
eq "a chunked body with no end stops at the cap" 262144 "$(j '.steps[14].result.bytes')"
eq "and is truncated" true "$(j '.steps[14].result.truncated')"
eq "an encoded //host stays on the base origin" 404 "$(j '.steps[15].result.status')"
# fetch is the runner, not the page: record and the lock never see it
run '{"steps": [
  {"step": "goto", "path": "/"},
  {"step": "record", "url_glob": "**/api/fetch/**"},
  {"step": "fetch", "path": "/api/fetch/json"},
  {"step": "recorded", "url_glob": "**/api/fetch/**"}
]}'
eq "a fetch is never in recorded" 0 "$(j '.steps[3].result.count')"
fails "nor in blocked" grep -q fetch <<< "$(j '.blocked | tostring')"
# an endless body: what was read comes back when the step timer fires (about 30 s)
run '{"steps": [{"step": "fetch", "path": "/api/fetch/drip"}]}'
eq "a body that never ends is not a failure" true "$(j '.steps[0].ok')"
eq "it is timed_out" true "$(j '.steps[0].result.timed_out')"
eq "and truncated" true "$(j '.steps[0].result.truncated')"
has "with what was read" tick "$(j '.steps[0].result.body')"
# fetch reads /api/... and /openapi.json only: never the UI bundle (dw source)
for p in / /index.html /assets/x.js /outputs/x /plain.txt /apix /openapi.json/x /api /api/../assets/x.js /api/%2e%2e/assets/x.js /api/%2E%2E/assets/x.js /api/%2e%2e%2fassets/x.js /api/x/%2e%2e/%2e%2e/assets/x.js '/api/x%5c..%5cy'; do
  run '{"steps": [{"step": "fetch", "path": "'"$p"'"}]}'
  eq "fetch path $p is refused" 2 "$rc"
done
run '{"steps": [{"step": "fetch", "path": "/assets/x.js"}]}'
has "a refusal says what fetch reads" "/api/... or /openapi.json" "$(j .error)"
run '{"steps": [{"step": "fetch", "path": "/api/%2e%2e/assets/x.js"}]}'
has "an encoded dot segment is named as such" "/api/... or /openapi.json" "$(j .error)"
for p in '//localhost:'$port'/' 'http://localhost:'$port'/' 'https://127.0.0.1:'$port'/' 'api/fetch/json' '/\\\\localhost' '/api\\\\x' '/a\u0001b' '/a\u007fb' '' 'file:///etc/hosts'; do
  run '{"steps": [{"step": "fetch", "path": "'"$p"'"}]}'
  eq "fetch path $p is an invalid spec" 2 "$rc"
done
for m in POST DELETE PUT get '"x"' 1 null; do
  case "$m" in '"'*|1|null) mv="$m" ;; *) mv="\"$m\"" ;; esac
  run '{"steps": [{"step": "fetch", "path": "/api/fetch/json", "method": '"$mv"'}]}'
  eq "fetch method $m is an invalid spec" 2 "$rc"
done
run '{"steps": [{"step": "fetch", "path": "/api/fetch/json", "headers": {"X": "1"}}]}'
eq "fetch takes no headers" 2 "$rc"
run '{"steps": [{"step": "fetch", "path": "/api/fetch/json", "body": "x"}]}'
eq "fetch takes no body" 2 "$rc"
run '{"steps": [{"step": "fetch"}]}'
eq "fetch needs path" 2 "$rc"
run '{"steps": [{"step": "fetch", "path": 5}]}'
eq "a fetch path that is not a string is an invalid spec" 2 "$rc"
# the token: sent as the bearer header, scrubbed even when the server echoes it back
fspec='{"steps": [{"step": "fetch", "path": "/api/fetch/echo"}, {"step": "fetch", "path": "/api/fetch/json"}, {"step": "fetch", "path": "/api/fetch/redirect"}]}'
cfg "http://127.0.0.1:$aport/mcp" "$tok"
DW_URL="http://127.0.0.1:$aport/mcp" HARNEST_MCP_CONFIG="$T/mcp.json" run "$fspec"
eq "fetch with a token ok" true "$(j .ok)"
eq "the token is sent as a bearer header, and scrubbed in the echo" "Bearer <token>" "$(j '.steps[0].result.body.you_sent')"
eq "the API lets it in" 200 "$(j '.steps[1].result.status')"
fails "the token is nowhere in the fetch output" grep -q "$tok" <<< "$out"
fails "nor in its stderr" grep -q "$tok" "$T/err"
# a cut through the token at the cap, the token in Location and in a cut content type
DW_URL="http://127.0.0.1:$aport/mcp" HARNEST_MCP_CONFIG="$T/mcp.json" run '{"steps": [{"step": "fetch", "path": "/api/fetch/cut-token"}, {"step": "fetch", "path": "/api/fetch/leaky"}]}'
eq "cut and leaky ok" true "$(j .ok)"
eq "the cap cuts the token" true "$(j '.steps[0].result.truncated')"
has "its prefix is scrubbed" "<token>" "$(j '.steps[0].result.body' | tail -c 20)"
fails "no 8-char prefix of the token survives the cut" grep -qF "${tok:0:8}" <<< "$out"
eq "a 3xx with the token in Location" 302 "$(j '.steps[1].result.status')"
eq "has it scrubbed" "/api/fetch/json?t=<token>" "$(j '.steps[1].result.location')"
has "the content type is scrubbed before its cut" "<token>" "$(j '.steps[1].result.content_type')"
fails "no 8-char prefix of the token in the content type" grep -qF "${tok:0:8}" <<< "$(j '.steps[1].result.content_type')"
DW_URL="http://127.0.0.1:$aport/mcp" run "$fspec"
eq "without a config, fetch sends no token: 401" 401 "$(j '.steps[0].result.status')"

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
