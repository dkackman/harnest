#!/usr/bin/env bash
# A whole fleet run (harness/drivers/fleet.py), offline: three local servers
# answered by tests/fake-mcp.py on three ports (alpha: the primary, 2 lanes;
# beta: light only; gamma: denies h3), a test profile naming them, a
# requirements file, and a fake claude that reports each case as the
# regression agent does (REGRESSION-CASE as it starts, REGRESSION-RESULT at
# the end) and logs when each session starts and ends.
. "$(dirname "$0")/lib.sh"

git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
mkdir -p "$T/seed/plugins/dw"; echo x > "$T/seed/plugins/dw/README"
git -C "$T/seed" add -A; git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm seed
git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
git clone -q -b develop "$T/origin.git" "$T/src"

mkdir "$T/h"
(cd "$HARNEST" && tar cf - --exclude ./logs --exclude ./.git --exclude ./.env .) | (cd "$T/h" && tar xf -)
cat > "$T/h/regression-suite-smoke.md" <<'EOS'
# tiny smoke
## Fixtures
none
### S-F001 — validate only
steps
### S-F002 — SD 1.5 image
steps
cleanup: S-F003 reads this output first.
### S-F003 — reads S-F002's image
steps
### S-F004 — fails
steps
### S-F005 — LTX shot
steps
### S-F006 — H3 shot
steps
### S-P001 — timing
steps
### S-F007 — beta skips this one
steps
EOS
rm -f "$T/h/regression-requirements.json"
git -C "$T/h" init -q && git -C "$T/h" add -A && git -C "$T/h" -c user.name=t -c user.email=t@t commit -qm h
(cd "$T/h" && python3 - <<'EOF'
import json
from harness import requirements as r
b = r.case_blocks("regression-suite-smoke.md")
need = {"S-F001": ("none", []), "S-F002": ("light", ["sd15"]), "S-F003": ("light", ["sd15"]),
        "S-F004": ("none", []), "S-F005": ("heavy", ["ltx"]), "S-F006": ("heavy", ["h3"]),
        "S-P001": ("exclusive", ["sd15"]), "S-F007": ("none", [])}
json.dump({"version": 1, "cases": {c: {"workflows": [], "models": m, "assets": [], "load": l,
           "hash": r.block_hash(b[c])} for c, (l, m) in need.items()}}, open("regression-requirements.json", "w"))
EOF
)
git -C "$T/h" add -A && git -C "$T/h" -c user.name=t -c user.email=t@t commit -qm req

p1=$((20000 + RANDOM % 20000)); p2=$((p1 + 1)); p3=$((p1 + 2))
cat > "$T/mcp.json" <<EOS
{"$p1": {"hostname": "alpha", "device": "cuda", "workers": 2, "models": {"sd15": 5, "ltx": 160, "h3": 196},
          "workspace_assets": {"regression-smoke": ["fixture.wav"]}},
 "$p2": {"hostname": "beta", "device": "mps", "workers": 1, "models": {"sd15": 5}},
 "$p3": {"hostname": "gamma", "device": "mps", "workers": 1, "models": {"sd15": 5, "ltx": 160, "h3": 50}}}
EOS
FAKE_MCP_LOG="$T/mcp-calls" python3 "$HARNEST/tests/fake-mcp.py" "$T/mcp.json" > "$T/mcp.out" 2>&1 &
mcppid=$!
trap 'kill $mcppid 2>/dev/null; rm -rf "$T"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q ready "$T/mcp.out" 2>/dev/null && break; sleep 0.3; done
git init -q "$T/dw" && git -C "$T/dw" -c user.name=t -c user.email=t@t commit -q --allow-empty -m dw
git -C "$T/dw" branch -q -m develop

server() { # server <name> <port> <backend> <lanes> <heavy> <max_gb> <deny> <downloads>
  cat <<EOS
[[servers]]
name = "$1"
host = "$1"
transport = "local"
url = "http://127.0.0.1:$2/mcp"
dir = "$T/dw"
backend = "$3"
loop = false
lanes = $4
speed = 1.0
heavy = $5
max_model_gb = $6
deny_models = [$7]
downloads = $8
EOS
}
{ sed -n '/^\[mcp\]/,/^plugin_subdir/p' "$HARNEST/targets/dw/profile.toml" \
    | sed "s#^source = .*#source = \"$T/src\"#; s#^plugin = .*#plugin = \"$T/plugin\"#"
  echo 'ticket_repo = "o/r"'
  server alpha "$p1" cuda 2 true 0 '' true
  server beta "$p2" mps 1 false 8 '' false
  server gamma "$p3" mps 1 true 0 '"h3*"' false
  sed -n '/^\[suite\]/,$p' "$HARNEST/targets/dw/profile.toml"
} > "$T/profile.toml"
# ticket_repo is a top-level key: put it first
{ echo 'ticket_repo = "o/r"'; grep -v '^ticket_repo' "$T/profile.toml"; } > "$T/profile2.toml"

ln -s "$HARNEST/tests/fake-gh.py" "$T/bin/gh"
echo '{"o/r": [], "h/r": []}' > "$T/board.json"
cat > "$T/bin/claude" <<'EOS'
#!/usr/bin/env bash
prompt="$2"
now() { python3 -c 'import time; print(time.time())'; }
if [[ "$prompt" == *"this order: "* ]]; then
  cases="${prompt#*this order: }"; cases="${cases%%. *}"
else
  cases=""
fi
ws="${prompt#*workspace is }"; ws="${ws%%;*}"
echo "start $(now) $HARNEST_TARGET $$ $ws [$cases]" >> "$FAKE_TIMELINE"
shift_args=("$@")
for i in "${!shift_args[@]}"; do
  [ "${shift_args[$i]}" = --mcp-config ] && url="$(jq -r .mcpServers.dw.url "${shift_args[$((i+1))]}")" &&
    echo "$HARNEST_TARGET $(jq -r '.mcpServers.dw.url + " " + .mcpServers.dw.headers.Authorization' "${shift_args[$((i+1))]}")" >> "$FAKE_TIMELINE.mcp"
done
# a chunk session's first case runs a workflow in its workspace, as the agent would
[ -n "$cases" ] && curl -s -X POST "$url" -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg ws "$ws" '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:"run_workflow",arguments:{workspace:$ws}}}')" >/dev/null
# the first session holding S-F005 goes silent: the watchdog stops it, and
# the session runner's retry runs it again
case " $cases " in *" S-F005 "*)
  if mkdir "$FAKE_TIMELINE.hung" 2>/dev/null; then
    printf '{"type":"system","subtype":"init","model":"claude-fake"}\n'; sleep 60; fi ;;
esac
# the first two sessions holding S-F001 die without a result: the session's
# own retry gets the second, and the fleet must queue the case again
case " $cases " in *" S-F001 "*)
  n=$(cat "$FAKE_TIMELINE.died" 2>/dev/null || echo 0)
  if [ "$n" -lt 2 ]; then echo $((n + 1)) > "$FAKE_TIMELINE.died"; echo "end $(now) $HARNEST_TARGET $$ $ws [$cases]" >> "$FAKE_TIMELINE"; exit 1; fi ;;
esac
text=""
for c in $cases; do
  text="${text}REGRESSION-CASE: $c\n"
done
sleep 0.4
for c in $cases; do
  case "$HARNEST_TARGET:$c" in
    *:S-F007) if mkdir "$FAKE_TIMELINE.skipped" 2>/dev/null; then   # the first server to try it lacks a fixture
                echo "$HARNEST_TARGET" > "$FAKE_TIMELINE.skipped/by"
                text="${text}REGRESSION-SKIP: S-F007 fixture qa-cast/x.wav\nREGRESSION-RESULT: S-F007 skip\n"
              else text="${text}REGRESSION-RESULT: S-F007 pass\n"; fi ;;
    *:S-F004)    text="${text}REGRESSION-RESULT: S-F004 fail #9\n" ;;
    *)           text="${text}REGRESSION-RESULT: $c pass\n" ;;
  esac
done
case " $cases " in *" S-F001 "*) echo "a case added by the run" >> regression-suite-smoke.md ;; esac
echo "end $(now) $HARNEST_TARGET $$ $ws [$cases]" >> "$FAKE_TIMELINE"
printf '{"type":"system","subtype":"init","model":"claude-fake"}\n'
jq -nc --arg t "$(printf '%b' "$text")" '{type:"assistant",message:{id:"m1",usage:{input_tokens:1},content:[{type:"text",text:$t}]}}'
printf '{"type":"result","subtype":"success","num_turns":2,"duration_ms":1000,"total_cost_usd":0.25,"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}\n'
EOS
chmod +x "$T/bin/claude"
export FAKE_TIMELINE="$T/timeline"; : > "$FAKE_TIMELINE"
fleet() { (cd "$T/h" && env HARNEST_PROFILE="$T/profile2.toml" FAKE_GH_BOARD="$T/board.json" SESSION_RETRY_PAUSE_SECS=0 \
           CASES_PER_SESSION=2 SESSION_STALL_SECS=3 "$@" python3 -m harness.drivers.fleet smoke) > "$T/fleet.out" 2>&1; }

# --- the plan
(cd "$T/h" && env HARNEST_PROFILE="$T/profile2.toml" python3 -m harness.drivers.fleet --plan smoke) > "$T/plan.out" 2>&1
eq  "plan: exits cleanly" 0 $?
has "plan: four lanes" "on 4 lane(s)" "$(cat "$T/plan.out")"

# --- the run
fleet DW_TOKEN_ALPHA=tok-alpha DW_TOKEN_BETA=tok-beta DW_TOKEN_GAMMA=tok-gamma
eq  "run: a failing case exits 1" 1 $?
# every lane's --mcp-config file names its own server: one shared file would
# hold the last server built
for s in "alpha $p1" "beta $p2" "gamma $p3"; do
  set -- $s
  eq  "run: $1's sessions connect to $1 with its token" "http://127.0.0.1:$2/mcp Bearer tok-$1" \
      "$(grep "^$1 " "$T/timeline.mcp" | cut -d' ' -f2- | sort -u)"
done
st="$T/h/logs/fleet/state.json"
case_of() { jq -r --arg c "$1" ".cases[\$c].$2" "$st"; }
eq  "run: done" "done" "$(jq -r .status "$st")"
eq  "  every case has an outcome" "" "$(jq -r '.cases | to_entries[] | select(.value.outcome | IN("queued","running","next")) | .key' "$st")"
eq  "  a failure keeps its issue" "fail #9" "$(case_of S-F004 outcome) $(case_of S-F004 issue)"
eq  "  heavy cases never on beta" "" "$(grep '^start .* beta ' "$T/timeline" | grep -E 'S-F005|S-F006|S-P001' || true)"
eq  "  h3 never on gamma" "" "$(grep '^start .* gamma ' "$T/timeline" | grep 'S-F006' || true)"
eq  "  a group shares a lane" "$(case_of S-F002 lane)" "$(case_of S-F003 lane)"
eq  "  every case passes or fails, none lost" "1 fail, 7 pass" \
    "$(jq -r '[.cases[].outcome] | group_by(.) | map("\(length) \(.[0])") | join(", ")' "$st")"
skipper="$(cat "$T/timeline.skipped/by")"
has "  a skipped case is re-queued on another server" "S-F007 skipped on $skipper; queued on" "$(jq -r '.events[].text' "$st")"
eq  "  and passes there" "pass" "$(case_of S-F007 outcome)"
eq  "  on a server that hadn't tried it" "" "$(case_of S-F007 server | grep -x "$skipper" || true)"
has "  a silent session is stopped by the watchdog" "no output for" "$(cat "$T/fleet.out")"
eq  "  and its case still passes" "pass" "$(case_of S-F005 outcome)"
has "  a case whose session died is queued again" "S-F001 had no answer (the session ended)" "$(jq -r '.events[].text' "$st")"
eq  "  and passes" "pass" "$(case_of S-F001 outcome)"
# the exclusive case ran with no other alpha session open
eq  "  the exclusive case ran alone on its server" "ok" "$(python3 - "$T/timeline" <<'EOF'
import sys
starts, spans = {}, []
for line in open(sys.argv[1]):
    kind, t, target, pid, _ws, rest = line.split(" ", 5)
    key = (target, pid)
    if kind == "start":
        starts[key] = float(t)
    else:
        spans.append((target, rest.strip(), starts.pop(key), float(t)))
ex = [s for s in spans if "S-P001" in s[1]]  # alpha or gamma: both may run heavy cases
if len(ex) != 1 or ex[0][1] != "[S-P001]":
    print("exclusive session not alone in its batch:", ex); sys.exit()
where, _, a, b = ex[0]
overlap = [s for s in spans if s[0] == where and s is not ex[0] and s[2] < b and s[3] > a]
print("ok" if not overlap else f"overlaps: {overlap}")
EOF
)"
# one sweep per lane that ran cases, in that lane's own workspace
eq  "  each lane swept its own workspace" "$(grep '^start' "$T/timeline" | grep -v ' \[\]$' | awk '{print $5}' | sort -u | tr '\n' ' ')" \
    "$(grep '^start' "$T/timeline" | grep ' \[\]$' | awk '{print $5}' | sort -u | tr '\n' ' ')"
eq  "  the cost is summed" "true" "$(jq '[.lanes[].cost] | add > 0' "$st")"
ok  "  the finished run is kept" test -s "$T/h/logs/fleet/runs/$(jq -r .id "$st").json"
# but a session the watchdog stopped and the runner retried keeps no times: they span both attempts
retried="$(grep '^start' "$T/timeline" | grep -m1 ' S-F005\| \[S-F005' | sed 's/.*\[//; s/\]//' | tr ' ' '\n' | sort | tr '\n' ' ')"
eq  "  every pass and fail is timed, but the retried session's" "$retried" \
    "$(jq -r '.cases | to_entries[] | select((.value.outcome | IN("pass","fail")) and .value.lane != "script" and (.value.secs | type) != "number") | .key' "$st" | sort | tr '\n' ' ')"
has "  the retried session held S-F005" "S-F005" "$retried"
(cd "$T/h" && env HARNEST_PROFILE="$T/profile2.toml" python3 -m harness.drivers.fleet --plan smoke) > "$T/plan2.out" 2>&1
has "  the next plan reads those times" "case(s) measured in" "$(cat "$T/plan2.out")"
has "  the suite edit is committed once" "regression: update smoke from" "$(git -C "$T/h" log -1 --format=%s)"
eq  "  locks released" "" "$(ls -d "$T/h"/logs/.driver.lock* 2>/dev/null || true)"
# each server's first lane in the level's workspace; alpha's second in its own, seeded from it
eq  "  workspaces: the level's, and alpha-2's own" "regression-smoke regression-smoke-alpha-2 " \
    "$(awk '/^start/ {print $5}' "$T/timeline" | sort -u | tr '\n' ' ')"
has "  alpha-2's workspace is created" 'alpha create_workspace {"name": "regression-smoke-alpha-2"}' "$(cat "$T/mcp-calls")"
has "  and seeded with the level's own assets" '"source": "regression-smoke", "destination": "regression-smoke-alpha-2", "assets": ["fixture.wav"]' "$(cat "$T/mcp-calls")"
eq  "  alpha-2's workspace is seeded before its first session runs there" "ok" "$(python3 - "$T/mcp-calls" <<'EOF'
import json, sys
first = {}
for n, line in enumerate(open(sys.argv[1])):
    host, name, args = line.split(" ", 2)
    ws = json.loads(args).get("name" if name == "create_workspace" else "workspace")
    first.setdefault((name, ws), n)
made, ran = first.get(("create_workspace", "regression-smoke-alpha-2")), first.get(("run_workflow", "regression-smoke-alpha-2"))
print("ok" if made is not None and ran is not None and made < ran else f"create={made} run={ran}")
EOF
)"

# --- a session that ends with cases unanswered (budget or turns ran out)
# One server, one lane, three cases in one session: the fake answers only
# the first of a three-case batch, then ends with its result (the usage: line).
cat > "$T/h/regression-suite-smoke.md" <<'EOS'
# tiny smoke
## Fixtures
none
### S-F001 — one
steps
### S-F002 — two
steps
### S-F003 — three
steps
EOS
(cd "$T/h" && python3 - <<'EOF'
import json
from harness import requirements as r
b = r.case_blocks("regression-suite-smoke.md")
json.dump({"version": 1, "cases": {c: {"workflows": [], "models": [], "assets": [], "load": "none",
           "hash": r.block_hash(b[c])} for c in b}}, open("regression-requirements.json", "w"))
EOF
)
git -C "$T/h" add -A && git -C "$T/h" -c user.name=t -c user.email=t@t commit -qm short
mkdir "$T/bin2"
cat > "$T/bin2/claude" <<'EOS'
#!/usr/bin/env bash
prompt="$2"
if [[ "$prompt" == *"this order: "* ]]; then
  cases="${prompt#*this order: }"; cases="${cases%%. *}"
else
  cases=""
fi
echo "start [$cases]" >> "$FAKE_TIMELINE.short"
set -- $cases
[ $# -eq 3 ] && set -- "$1"   # out of budget after the first case
text=""
for c in "$@"; do text="${text}REGRESSION-CASE: $c\nREGRESSION-RESULT: $c pass\n"; done
printf '{"type":"system","subtype":"init","model":"claude-fake"}\n'
jq -nc --arg t "$(printf '%b' "$text")" '{type:"assistant",message:{id:"m1",usage:{input_tokens:1},content:[{type:"text",text:$t}]}}'
printf '{"type":"result","subtype":"success","num_turns":2,"duration_ms":1000,"total_cost_usd":0.25,"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}\n'
EOS
chmod +x "$T/bin2/claude"
fleet PATH="$T/bin2:$PATH" FLEET_SERVERS=beta CASES_PER_SESSION=3 DW_TOKEN_BETA=tok-beta
rc=$?
# the two it never answered get a session of their own, on the same server
eq  "fleet: the unanswered cases run again" "[S-F001 S-F002 S-F003] [S-F002 S-F003] []" \
    "$(sed 's/^start //' "$FAKE_TIMELINE.short" | tr '\n' ' ' | sed 's/ $//')"
has "  queued again, saying why" "S-F002 had no answer (budget or turns ran out) on beta" "$(jq -r '.events[].text' "$st")"
eq  "  and the run exits 0" 0 "$rc"
eq  "  with every case passing" "pass pass pass" "$(case_of S-F001 outcome) $(case_of S-F002 outcome) $(case_of S-F003 outcome)"
eq  "  state says done" "done" "$(jq -r .status "$st")"

# --- a server that's down stops the run before it starts
kill $mcppid; wait $mcppid 2>/dev/null
fleet
eq  "down: refused" 1 $?
has "  naming the server" "no dw server answering" "$(cat "$T/fleet.out")"
finish
