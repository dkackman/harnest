#!/usr/bin/env bash
# The shared helpers in providers.sh: session outcome checks on canned
# logs, the stream renderer against a golden file, model/provider/effort
# validation, ONLY_ISSUES filtering, the no-progress ledger, handoff_count,
# park_external_issues and the driver lock, with gh stubbed throughout.
. "$(dirname "$0")/lib.sh"
export TICKET_REPO=o/r TICKET_OWNER=me
. "$HARNEST/providers.sh"

# --- session outcomes
printf 'usage: turns=3\n' > "$T/done"
printf 'usage: turns=3\nresult: error_max_budget_usd x\n' > "$T/cut"
printf 'rate-limit: status=rejected type=five_hour\nusage: turns=1\n' > "$T/rejected"
printf 'hello\n' > "$T/died"
# expected exit codes of session_died, session_ok, session_ran
for pair in "done:1 0 0" "cut:1 1 0" "rejected:1 1 1" "died:0 1 1"; do
  f="${pair%%:*}"
  session_died "$T/$f"; d=$?; session_ok "$T/$f"; o=$?; session_ran "$T/$f"; r=$?
  eq "outcome $f (died ok ran)" "${pair#*:}" "$d $o $r"
done
printf 'rate-limit: status=rejected type=five_hour overage=false resets=x resets_epoch=%s\n' "$(( $(date +%s) - 3600 ))" > "$T/past"
start=$(date +%s); sleep_if_rate_limited "$T/past"; eq "a reset in the past doesn't sleep" 0 $(( $(date +%s) - start ))
printf 'rate-limit: status=rejected type=x overage=false resets=1970 resets_epoch=0\nusage: turns=1\n' > "$T/rl"
eq "rate limit: a missing reset sleeps the fallback" "sleeping 1s" "$(RATE_LIMIT_FALLBACK_SECS=1 sleep_if_rate_limited "$T/rl" | grep -o 'sleeping 1s')"
printf 'rate-limit: status=rejected type=x overage=false\nusage: turns=1\n' > "$T/rl-none"
eq "rate limit: no resets_epoch at all sleeps the fallback too" "sleeping 0s" "$(RATE_LIMIT_FALLBACK_SECS=0 sleep_if_rate_limited "$T/rl-none" | grep -o 'sleeping 0s')"
RATE_LIMIT_FALLBACK_SECS=0 sleep_if_rate_limited "$T/rl" >/dev/null; eq "rate limit: returns 1 when it slept" 1 $?
sleep_if_rate_limited "$T/done"; eq "rate limit: returns 0 when not rejected" 0 $?

# --- renderer
eq "stream renders to the golden text" "$(cat "$HARNEST/tests/fixtures/stream.expected")" \
   "$(render_stream golden < "$HARNEST/tests/fixtures/stream.jsonl")"
eq "raw events are kept" "$(wc -l < "$HARNEST/tests/fixtures/stream.jsonl" | tr -d ' ')" "$(wc -l < "$LOGS/golden.jsonl" | tr -d ' ')"

# --- models, providers, effort
ok    "anthropic takes a Claude alias" resolve_model_env anthropic opus
fails "anthropic refuses an Ollama tag" resolve_model_env anthropic qwen2.5:32b
fails "ollama refuses a Claude alias" resolve_model_env ollama sonnet
fails "ollama needs a context size" env -u OLLAMA_CONTEXT_TOKENS bash -c ". '$HARNEST/providers.sh'; resolve_model_env ollama qwen"
fails "gateway needs a base url" env -u GW_BASE_URL bash -c ". '$HARNEST/providers.sh'; resolve_model_env gateway x"
fails "unknown provider" resolve_model_env bedrock opus
ok    "effort medium" effort_flags anthropic medium
fails "effort nonsense" effort_flags anthropic extreme
eq    "effort under ollama is dropped" "" "$(effort_flags ollama high)"
eq    "fallback flags" "--fallback-model sonnet" "$(fallback_model_flags anthropic sonnet)"
fails "fallback must suit the provider" fallback_model_flags ollama sonnet

# --- the MCP house rules ride in every tester kind that calls the dw tools
for k in verify spec task; do
  has "house rules: tester $k loads them" "## MCP house rules" "$(cat "$(role_prompt tester $k "$T/rp-$k.md")")"
done
for k in handoff answer closures; do
  fails "house rules: tester $k does not" grep -q "## MCP house rules" "$(role_prompt tester $k "$T/rp-$k.md")"
done
eq "house rules: the Python port loads the same fragments" "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from harness import prompts; print(" ".join(prompts.FRAGMENTS["tester:verify"] + prompts.FRAGMENTS["tester:spec"] + prompts.FRAGMENTS["tester:task"]))' "$HARNEST")" \
  "core verify cases mcp-rules core spec cases mcp-rules core closures task cases standing-task mcp-rules"

# --- the consumer's Write and Edit are allowed only where it writes: the
# suite files, perf history, the bible and /tmp. dontAsk denies the rest
# (an allowlisted script, the guard hook, the drivers).
cflags="$(printf '"%s" ' "${CONSUMER_PERMISSION_FLAGS[@]}")"
for p in 'regression-suite-*.md' 'regression-perf/**' qa-bible.md '/tmp/**' '//tmp/**' '/private/tmp/**' '//private/tmp/**'; do
  has "consumer flags allow Write/Edit on $p" "\"Write($p)\" \"Edit($p)\"" "$cflags"
done
has "consumer flags allow the perf-check wrapper" '"Bash(./scripts/perf-check.sh *)"' "$cflags"
fails "consumer flags: no perf-check.py spelling" grep -qF 'perf-check.py' <<< "$cflags"
fails "consumer flags: no bare Write" grep -qF '"Write" ' <<< "$cflags"
fails "consumer flags: no bare Edit" grep -qF '"Edit" ' <<< "$cflags"
eq "consumer flags: Write/Edit on nothing else" 14 "$(grep -oE '"(Write|Edit)\([^)]*\)"' <<< "$cflags" | wc -l | tr -d ' ')"

# --- ONLY_ISSUES
rows=$'5\tq\t-\tr\n7\tq\t12\tr\n9\tq\t-\tr'
eq "no filter keeps all" "5 7 9" "$(printf '%s\n' "$rows" | only_issues_filter | cut -f1 | xargs)"
eq "filter by number or parent" "5 7" "$(printf '%s\n' "$rows" | ONLY_ISSUES="5, 12" only_issues_filter | cut -f1 | xargs)"

# --- no-progress ledger
stub_gh 'echo "OPEN|owner:lead,stage|"'
fp="$(issue_fingerprint o/r 5)"
NO_PROGRESS_PARK_AFTER=2 note_progress o/r 5 "$fp" t lead:build
eq "one unchanged session is counted" "1" "$(cut -f3 "$LOGS/progress.tsv")"
NO_PROGRESS_PARK_AFTER=2 note_progress o/r 5 "$fp" t lead:decompose
eq "another kind counts separately" "2" "$(wc -l < "$LOGS/progress.tsv" | tr -d ' ')"
has "nothing parked yet" "" "$(grep 'issue edit' "$GH_CALLS" || true)"
NO_PROGRESS_PARK_AFTER=2 note_progress o/r 5 "$fp" t lead:build >/dev/null
has "second unchanged build parks with Don" "issue edit 5 --repo o/r --remove-label owner:lead --add-label owner:don --add-label status:needs-approval" "$(cat "$GH_CALLS")"
NO_PROGRESS_PARK_AFTER=2 note_progress o/r 5 "OPEN|other|" t lead:decompose
eq "a change resets that kind's count" "0" "$(grep -c ':lead:decompose' "$LOGS/progress.tsv" || true)"

# --- handoff_count: hand-offs since the last reopen, or Don's last hand-back
stub_gh 'printf "%s\n" labeled labeled reopened labeled'
eq "hand-offs since the last reopen" "1" "$(handoff_count 5)"
stub_gh 'printf "%s\n" labeled labeled labeled labeled handback'
eq "Don's hand-back starts the count again (#499 was re-parked without a session)" "0" "$(handoff_count 5)"
stub_gh 'printf "%s\n" labeled labeled handback labeled'
eq "and hand-offs after it count" "1" "$(handoff_count 5)"
# the jq itself, over a real-shaped timeline (the stub above prints what it emits)
ev='[{"event":"labeled","label":{"name":"status:fixed-pending-verify"}},{"event":"labeled","label":{"name":"owner:don"}},
     {"event":"labeled","label":{"name":"status:fixed-pending-verify"}},{"event":"unlabeled","label":{"name":"owner:don"}},
     {"event":"labeled","label":{"name":"status:fixed-pending-verify"}},{"event":"unlabeled","label":{"name":"owner:lead"}}]'
printf '%s\n' "$ev" > "$T/events.json"
stub_gh 'while [ $# -gt 0 ]; do [ "$1" = --jq ] && q="$2"; shift; done; jq -r "$q" "'"$T"'/events.json"'
eq "the timeline query: one hand-off after Don's hand-back" "1" "$(handoff_count 5)"
stub_gh 'exit 1'
eq "gh failure counts as zero, and returns 0" "0" "$(handoff_count 5)"

# --- park_external_issues
: > "$GH_CALLS"
stub_gh 'case "$1 $2" in
  "issue list") echo "[{\"number\":3,\"author\":{\"login\":\"x\"},\"labels\":[{\"name\":\"owner:implementer\"}],\"comments\":[]},
                     {\"number\":4,\"author\":{\"login\":\"x\"},\"labels\":[{\"name\":\"owner:implementer\"}],\"comments\":[{\"author\":{\"login\":\"me\"},\"body\":\"Parked for human review: filed by @x\"}]}]" ;;
esac'
park_external_issues >/dev/null
has "a new outside issue is parked" "issue edit 3 --repo o/r --remove-label owner:implementer --add-label owner:don" "$(cat "$GH_CALLS")"
eq  "one Don handed back is left alone" "" "$(grep 'edit 4' "$GH_CALLS" || true)"
stub_gh 'exit 1'
ok "a gh failure is logged, not fatal" park_external_issues

# --- mcp_config_file: the dw --mcp-config in a private file, built by jq
f="$(mcp_config_file "http://x/\"q" 't"k')"
eq  "mcp config: valid json with odd characters" 't"k' "$(jq -r '.mcpServers.dw.headers.Authorization' "$f" | sed 's/^Bearer //')"
eq  "mcp config: the url survives a quote" 'http://x/"q' "$(jq -r '.mcpServers.dw.url' "$f")"
eq  "mcp config: private" "600" "$(stat -f %Lp "$f")"
eq  "mcp config: under the logs dir, named by pid" "$LOGS/.mcp.$$.json" "$f"

# a live driver's file survives another call (however old); a dead one's is swept
sleep 30 & livepid=$!
echo '{}' > "$LOGS/.mcp.$livepid.json"; touch -t 202001010000 "$LOGS/.mcp.$livepid.json"
echo '{}' > "$LOGS/.mcp.999999.json"
mcp_config_file u t >/dev/null
ok  "mcp config: a live pid's file survives the sweep" test -e "$LOGS/.mcp.$livepid.json"
fails "mcp config: a dead pid's file is swept" test -e "$LOGS/.mcp.999999.json"
kill "$livepid" 2>/dev/null; rm -f "$LOGS/.mcp.$livepid.json"

# --- the driver lock
lock_test() {
  bash -c '. "$1/providers.sh"; acquire_driver_lock t; cat "$LOGS/.driver.lock/owner"' _ "$HARNEST"
}
mkdir "$LOGS/.driver.lock"; echo "999999 dead" > "$LOGS/.driver.lock/owner"
has "a dead holder's lock is taken over" " t" "$(lock_test)"
mkdir "$LOGS/.driver.lock"; touch -t 202601010000 "$LOGS/.driver.lock"
has "an ownerless old lock is taken over" " t" "$(lock_test)"
eq  "the lock is released at exit" "" "$(ls -d "$LOGS/.driver.lock" 2>/dev/null)"

# --- TERM stops the driver and its claude child; no takeover over a live child
mkdir -p "$T/term-bin"
printf '#!/usr/bin/env bash\necho "claude $*" >> "%s"\nsleep 30.1\n' "$T/term-calls" > "$T/term-bin/claude"
chmod +x "$T/term-bin/claude"
session_driver() { # a driver holding the lock, in a session with the fake claude
  PATH="$T/term-bin:$PATH" exec bash -c '. "$1/providers.sh"; LAST_SESSION="$LOGS/.last-term"; MODEL_LABEL=x
    acquire_driver_lock term; run_claude_session term term /tmp /dev/null prompt; echo "after session"' _ "$HARNEST"
}
session_driver > "$T/term.out" 2>&1 &
drv=$!
for _ in $(seq 50); do pgrep -f 'sleep 30.1' >/dev/null && break; sleep 0.1; done
ok  "TERM: the fake claude is running" pgrep -f 'sleep 30.1'
kill -TERM "$drv"
for _ in $(seq 50); do pgrep -f 'sleep 30.1' >/dev/null || [ -d "$LOGS/.driver.lock" ] || break; sleep 0.1; done
eq  "TERM: no claude child is left" "" "$(pgrep -f 'sleep 30.1')"
eq  "TERM: the lock is released" "" "$(ls -d "$LOGS/.driver.lock" 2>/dev/null)"
wait "$drv"; eq "TERM: the driver exits 143" 143 "$?"
fails "TERM: the driver stopped, not carried on" grep -q "after session" "$T/term.out"
pkill -f 'sleep 30.1' 2>/dev/null
# --- a session that ignores TERM is KILLed after SESSION_KILL_SECS
printf '#!/usr/bin/env bash\ntrap "" TERM\nsleep 30.7\n' > "$T/term-bin/claude"
chmod +x "$T/term-bin/claude"
SESSION_KILL_SECS=1 session_driver > "$T/term2.out" 2>&1 &
drv=$!
for _ in $(seq 50); do pgrep -f 'sleep 30.7' >/dev/null && break; sleep 0.1; done
ok  "session KILL: the stubborn fake claude is running" pgrep -f 'sleep 30.7'
t0=$(date +%s); kill -TERM "$drv"
wait "$drv"; rc=$?; t1=$(date +%s)
eq  "session KILL: the driver exits 143" 143 "$rc"
ok  "session KILL: within the bound" [ "$((t1 - t0))" -lt 10 ]
eq  "session KILL: the session is gone" "" "$(pgrep -f 'sleep 30.7')"
has "session KILL: says it killed it" "ignored TERM for 1s" "$(cat "$T/term2.out")"
eq  "session KILL: the lock is released" "" "$(ls -d "$LOGS/.driver.lock" 2>/dev/null)"
pkill -f 'sleep 30.7' 2>/dev/null

# --- a nested driver that ignores TERM is KILLed after CHILD_DRIVER_KILL_SECS
# (the driver is a file: the masked-TERM child's quoting doesn't survive a bash -c string)
printf '%s\n' '. "$HARNEST/providers.sh"; driver_traps' \
  'run_child_driver bash -c '"'"'trap "" TERM; sleep 30.6'"'"'; echo "after child"' > "$T/stubborn.sh"
HARNEST="$HARNEST" CHILD_DRIVER_KILL_SECS=1 bash "$T/stubborn.sh" > "$T/stubborn.out" 2>&1 &
drv=$!
for _ in $(seq 50); do pgrep -f 'sleep 30.6' >/dev/null && break; sleep 0.1; done
ok  "child KILL: the stubborn child is running" pgrep -f 'sleep 30.6'
t0=$(date +%s); kill -TERM "$drv"
wait "$drv"; rc=$?; t1=$(date +%s)
eq  "child KILL: the driver exits 143" 143 "$rc"
ok  "child KILL: within the bound, not the child's lifetime" [ "$((t1 - t0))" -lt 10 ]
eq  "child KILL: the child is gone" "" "$(pgrep -f 'sleep 30.6')"
has "child KILL: says it killed the child" "ignored TERM for 1s" "$(cat "$T/stubborn.out")"
pkill -f 'sleep 30.6' 2>/dev/null
# a holder killed outright (KILL) leaves its claude session running: wait for it
mkdir "$LOGS/.driver.lock"; echo "999999 dead" > "$LOGS/.driver.lock/owner"
set -m; sleep 30.2 & orphan=$!; set +m
echo "$orphan" > "$LOGS/.driver.lock/session.999999"
bash -c '. "$1/providers.sh"; acquire_driver_lock t; echo took' _ "$HARNEST" > "$T/takeover.out" 2>&1 &
waiter=$!
sleep 1.5
eq  "takeover: refused while the old holder's claude runs" "999999 dead" "$(cat "$LOGS/.driver.lock/owner" 2>/dev/null)"
has "  and says why" "still running" "$(cat "$T/takeover.out")"
pkill -P "$waiter" 2>/dev/null; kill "$waiter" "$orphan" 2>/dev/null; wait "$waiter" "$orphan" 2>/dev/null
rm -rf "$LOGS/.driver.lock"

# --- server targets (harnest#15): every target is an ssh host in target_row
tgt() { # tgt <target> <snippet>: providers.sh sourced under DW_TARGET=<target>
  env DW_TARGET="$1" DW_URL="${TGT_URL:-}" bash -c '. "$1/providers.sh"; resolve_target || exit 1; eval "$2"' _ "$HARNEST" "$2" 2>&1
}
# ssh: records each call; answers the head query; a deploy echoes, or fails with FAKE_SSH_FAIL
cat > "$T/bin/ssh" <<EOS
#!/usr/bin/env bash
echo "ssh \$*" >> "$T/ssh-calls"
case "\$*" in *deploy.sh*) [ -z "\${FAKE_SSH_FAIL:-}" ] || { echo dirty; exit 1; }; echo "deploy \${*: -1}" ;; *rev-parse*) echo "develop @ abc1234" ;; esac
EOS
chmod +x "$T/bin/ssh"
eq  "lem keeps its names and URL" "|lem|~/diffusers-workflow|http://lem:8765/mcp" "$(tgt lem 'echo "$TARGET_SUFFIX|$TARGET_HOST|$TARGET_DIR|$DW_URL"')"
# the token: the server's own variable, else DW_TOKEN, else refused; never a default
eq  "token: each server has its own variable" "DW_TOKEN_LEM DW_TOKEN_MINI_AI" "$(tgt lem token_var) $(tgt mini-ai token_var)"
eq  "token: the server's own wins" "m" "$(DW_TOKEN_MINI_AI=m DW_TOKEN=d tgt mini-ai 'resolve_token; echo "$DW_TOKEN"')"
eq  "token: DW_TOKEN is the fallback" "d" "$(DW_TOKEN_MINI_AI=m DW_TOKEN=d tgt lem 'resolve_token; echo "$DW_TOKEN"')"
has "token: none is refused, naming the variable" "set DW_TOKEN_LEM (or DW_TOKEN)" "$(DW_TOKEN='' tgt lem 'resolve_token || echo refused')"
has "  and fails" "refused" "$(DW_TOKEN='' tgt lem 'resolve_token || echo refused')"
eq  "mini-ai gets its own suffix, host and URL" ".mini-ai|mini-ai|http://mini-ai:8765/mcp" "$(tgt mini-ai 'echo "$TARGET_SUFFIX|$TARGET_HOST|$DW_URL"')"
eq  "an explicit DW_URL on the host wins" "http://mini-ai.lan:9000/mcp" "$(TGT_URL=http://mini-ai.lan:9000/mcp tgt mini-ai 'echo "$DW_URL"')"
has "a leftover lem DW_URL is refused" "needs a DW_URL on mini-ai" "$(TGT_URL=http://lem:8765/mcp tgt mini-ai 'echo ran')"
has "so is localhost: the server isn't on this machine" "needs a DW_URL on mini-ai" "$(TGT_URL=http://localhost:8765/mcp tgt mini-ai 'echo ran')"
eq  "url_host strips scheme, port and path" "lem|::1|localhost" "$(tgt lem 'echo "$(url_host http://lem:8765/mcp)|$(url_host "http://[::1]:8765/mcp")|$(url_host http://localhost/mcp)"')"
eq  "short_host drops the domain and case" "mac-mini" "$(tgt lem 'short_host Mac-mini.lan')"
has "an unknown target is refused, naming the known ones" "must be one of: lem mini-ai" "$(tgt cuda2 'echo ran')"
has "local is retired" "must be one of: lem mini-ai" "$(tgt local 'echo ran')"
eq  "head comes from the target's checkout, over ssh" "develop @ abc1234" "$(tgt mini-ai deployed_head)"
has "  on its host" "ssh -o ConnectTimeout=8 -o BatchMode=yes mini-ai cd ~/diffusers-workflow" "$(cat "$T/ssh-calls")"
eq  "the mini-ai lock is its own" "run-x" "$(tgt mini-ai 'acquire_driver_lock run-x; cut -d" " -f2 "$LOGS/.driver.lock.mini-ai/owner"')"
eq  "lem's lock is untouched by a mini-ai run" "" "$(ls -d "$LOGS/.driver.lock" 2>/dev/null)"
printf '#!/usr/bin/env bash\necho "curl $*" >> "%s"\necho '"'"'{"status":"ok","device":"mps","hostname":"mini-ai.lan"}'"'"'\n' "$T/curl-calls" > "$T/bin/curl"; chmod +x "$T/bin/curl"
eq  "health reports device and host" "mps on mini-ai.lan" "$(tgt mini-ai target_health)"
has "health asks the base URL, not /mcp" "http://mini-ai:8765/api/health" "$(cat "$T/curl-calls")"
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bin/curl"
fails "health fails when nothing answers" env DW_TARGET=mini-ai bash -c '. "$1/providers.sh"; resolve_target; target_health' _ "$HARNEST"
has "preflight says how to start it" "scripts/testbed.sh mini-ai start" "$(tgt mini-ai 'target_preflight && echo ran')"
health() { printf '#!/usr/bin/env bash\necho '"'"'{"status":"ok","device":"mps","hostname":"%s"}'"'"'\n' "$1" > "$T/bin/curl"; chmod +x "$T/bin/curl"; }
health "mini-ai.lan"
eq  "preflight passes when the target's host answers" "ok|mps on mini-ai.lan" "$(tgt mini-ai 'target_preflight && echo "ok|$TARGET_HEALTH"')"
health "lem"
has "preflight refuses another host answering (a tunnel to lem)" "is lem, not mini-ai" "$(tgt mini-ai 'target_preflight && echo ran')"
rm -f "$T/bin/curl"
eq  "lem commits suites, perf and results" "regression-suite-*.md regression-perf regression-results" "$(tgt lem suite_commit_paths)"
eq  "mini-ai commits only its own perf and results" "regression-perf/mini-ai regression-results/mini-ai" "$(tgt mini-ai suite_commit_paths)"
eq  "the mini-ai loop also commits a tester's shared case" "regression-suite-*.md regression-perf/mini-ai regression-results/mini-ai" "$(tgt mini-ai 'SUITE_EDITS=1; suite_commit_paths')"
mkdir -p "$LOGS/.driver.lock"; echo "$$ run-loop" > "$LOGS/.driver.lock/owner"
eq  "but leaves suite files to lem's loop while it runs (it may be mid-edit)" "regression-perf/mini-ai regression-results/mini-ai" "$(tgt mini-ai 'SUITE_EDITS=1; suite_commit_paths')"
rm -rf "$LOGS/.driver.lock"
has "lem's regression runtime note lists suite edits" "a suite-file edit" "$(tgt lem 'runtime_note regression anthropic sonnet')"
eq  "a mini-ai one does not" "" "$(tgt mini-ai 'runtime_note regression anthropic sonnet' | grep 'suite-file' || true)"
eq  "no target note for lem" "" "$(tgt lem 'target_note regression "cuda on lem"')"
note="$(tgt mini-ai 'target_note regression "mps on mini-ai.lan"')"
has "the note moves perf history" "regression-perf/mini-ai/<case>.jsonl" "$note"
has "the note files with a backend label" "\`owner:implementer\` and \`backend:mps\`" "$note"
has "the note never comments on lem's issues" "Never comment on a \`target:lem\` issue" "$note"
inote="$(tgt mini-ai 'target_note implementer "mps on mini-ai.lan"')"
has "implementer note leaves the deploy to the driver" "The driver deploys" "$inote"
has "implementer note names the test bed's host" "MPS test bed on host \`mini-ai\`" "$inote"
has "implementer note reads the server over ssh" "ssh mini-ai git -C ~/diffusers-workflow log" "$inote"
has "implementer note hands cuda to lem" "--remove-label target:mini-ai --add-label target:lem" "$inote"
eq  "implementer note leaves no placeholder" "" "$(printf '%s' "$inote" | grep -o '{{[A-Z_]*}}' || true)"
tnote="$(tgt mini-ai 'target_note tester "mps on mini-ai.lan"')"
has "tester note requires verified-on:mps" "\`verified-on:mps\` next to \`status:verified\`" "$tnote"
has "tester note limits suite edits to shared fixes" "Proposed case (mps level, harnest#16)" "$tnote"
has "tester note comments before the hand-over (the guard refuses comments on target:lem)" "comment what's missing first" "$tnote"
eq  "tester note leaves no placeholder" "" "$(printf '%s' "$tnote" | grep -o '{{[A-Z_]*}}' || true)"
has "the note keeps the suite files lem's" "The suite files. Every case in them runs on lem" "$note"
has "the note names the server" "(mps on mini-ai.lan, http://mini-ai:8765/mcp)" "$note"
eq  "the note leaves no placeholder" "" "$(printf '%s' "$note" | grep -o '{{[A-Z]*}}' || true)"

# --- per-target resources for the loop (harnest#15 part 2)
eq  "mini-ai: its own loop log" "$LOGS/loop.mini-ai.log" "$(tgt mini-ai 'echo "$LOOP_LOG"')"
eq  "lem: the loop log is unchanged" "$LOGS/loop.log" "$(tgt lem 'echo "$LOOP_LOG"')"
eq  "target_default picks the target's value" "a|b" "$(tgt lem 'target_default a b')|$(tgt mini-ai 'target_default a b')"
has "lem: deploy over ssh, unchanged" "ssh -o ConnectTimeout=8 -o BatchMode=yes lem '~/diffusers-workflow/scripts/deploy.sh develop'" "$(tgt lem deploy_cmd)"
has "mini-ai: deploy over ssh the same way" "ssh -o ConnectTimeout=8 -o BatchMode=yes mini-ai '~/diffusers-workflow/scripts/deploy.sh develop'" "$(tgt mini-ai deploy_cmd)"
eq  "lem: server name" "lem" "$(tgt lem server_name)"
eq  "mini-ai: server name" "the mini-ai server (mps on mini-ai.lan)" "$(tgt mini-ai 'TARGET_HEALTH="mps on mini-ai.lan"; server_name')"
ok  "mini-ai: deploy_target runs it" tgt mini-ai deploy_target
has "mini-ai: and logs it" "[loop:deploy] deploy ~/diffusers-workflow/scripts/deploy.sh develop" "$(cat "$LOGS/loop.mini-ai.log")"
fails "mini-ai: a failed deploy fails" env FAKE_SSH_FAIL=1 DW_TARGET=mini-ai bash -c '. "$1/providers.sh"; resolve_target; deploy_target' _ "$HARNEST"
rm -f "$T/bin/ssh"
# claim_issue: a clean claim holds; a tie goes to the claim the events show first
# The stub answers an issue view from $T/views/<n>: one line per call (the
# pre-check, then the read-back), the last line repeating.
mkdir -p "$T/views"
# An events call answers from $T/events/<n>, already in the --jq's
# "<event> <label>" form; none there means the events couldn't be read.
mkdir -p "$T/events"
stub_gh 'case "$1 $2" in "issue view") f="'"$T"'/views/$3"; c="$f.n"; k=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo $k > "$c"; l=$(sed -n "${k}p" "$f"); [ -n "$l" ] || l=$(tail -1 "$f"); printf "%s\n" $l ;; "api --paginate") n=$(echo "$3" | cut -d/ -f5); cat "'"$T"'/events/$n" 2>/dev/null || exit 1 ;; *) exit 0 ;; esac'
printf 'none\ntarget:mini-ai\n' > "$T/views/5"
ok    "claim: an unclaimed issue is held" tgt mini-ai 'TICKET_REPO=o/r claim_issue 5'
printf 'none\ntarget:mini-ai target:lem\n' > "$T/views/6"
fails "claim: a tie the events can't settle is yielded" env DW_TARGET=mini-ai bash -c '. "$1/providers.sh"; resolve_target; TICKET_REPO=o/r claim_issue 6' _ "$HARNEST"
has   "claim: the yielded claim is removed" "gh issue edit 6 --repo o/r --remove-label target:mini-ai" "$(cat "$GH_CALLS")"
printf 'none\ntarget:lem target:mini-ai\n' > "$T/views/7"
fails "claim: lem yields an unsettled tie too" tgt lem 'TICKET_REPO=o/r claim_issue 7'
has   "claim: lem removes its own" "gh issue edit 7 --repo o/r --remove-label target:lem" "$(cat "$GH_CALLS")"
# a tie the events settle: both loops reach the same answer, so neither livelocks
printf 'none\ntarget:lem target:mini-ai\n' > "$T/views/10"
printf 'labeled target:mini-ai\nlabeled target:lem\n' > "$T/events/10"
: > "$GH_CALLS"
ok    "claim: the first claim keeps a tie" tgt mini-ai 'TICKET_REPO=o/r claim_issue 10'
eq    "claim: and keeps its label" "" "$(grep 'remove-label' "$GH_CALLS" || true)"
rm -f "$T/views/10.n"
fails "claim: the later claim yields it" tgt lem 'TICKET_REPO=o/r claim_issue 10'
has   "claim: and removes its own" "gh issue edit 10 --repo o/r --remove-label target:lem" "$(cat "$GH_CALLS")"
# an earlier claim, since released, doesn't count: lem's re-add is the later one
printf 'none\ntarget:lem target:mini-ai\n' > "$T/views/11"
printf 'labeled target:lem\nunlabeled target:lem\nlabeled target:mini-ai\nlabeled target:lem\n' > "$T/events/11"
ok    "claim: a released claim's old event doesn't count" tgt mini-ai 'TICKET_REPO=o/r claim_issue 11'
# a label on the issue its events don't show yet: yield
printf 'none\ntarget:lem target:mini-ai\n' > "$T/views/12"
printf 'labeled target:mini-ai\n' > "$T/events/12"
fails "claim: a label the events don't show yet is yielded" tgt mini-ai 'TICKET_REPO=o/r claim_issue 12'
printf 'target:mini-ai\n' > "$T/views/8"
fails "claim: an issue another loop holds is skipped" tgt lem 'TICKET_REPO=o/r claim_issue 8'
eq    "claim: without adding a label" "" "$(grep 'issue edit 8' "$GH_CALLS" || true)"
printf 'target:lem\n' > "$T/views/9"
ok    "claim: a loop keeps its own earlier claim" tgt lem 'TICKET_REPO=o/r claim_issue 9'
# lem_loop_running: only a live run-loop holder counts
mkdir -p "$LOGS/.driver.lock"
echo "$$ run-loop" > "$LOGS/.driver.lock/owner"
ok    "lem loop: a live run-loop holds lem's lock" tgt mini-ai lem_loop_running
echo "$$ run-regression" > "$LOGS/.driver.lock/owner"
fails "lem loop: a regression run is not the loop" env DW_TARGET=mini-ai bash -c '. "$1/providers.sh"; resolve_target; lem_loop_running' _ "$HARNEST"
echo "999999 run-loop" > "$LOGS/.driver.lock/owner"
fails "lem loop: a dead holder" env DW_TARGET=mini-ai bash -c '. "$1/providers.sh"; resolve_target; lem_loop_running' _ "$HARNEST"
rm -rf "$LOGS/.driver.lock"

# --- suite commits are serialized
git init -q "$T/hr"; echo x > "$T/hr/regression-suite-a.md"; mkdir "$T/hr/regression-perf"; echo "{}" > "$T/hr/regression-perf/S-P001.jsonl"
git -C "$T/hr" add -A; git -C "$T/hr" -c user.name=t -c user.email=t@t commit -qm init
echo y >> "$T/hr/regression-suite-a.md"
commit_test() { REPO="$T/hr" bash -c '. "$1/providers.sh"; git -C "$REPO" config user.name t; git -C "$REPO" config user.email t@t; commit_suite_changes "suite: y" n n@x' _ "$HARNEST"; }
mkdir "$LOGS/.suite-commit.lock"; touch -t 202601010000 "$LOGS/.suite-commit.lock"
ok  "a stale commit lock is taken over" commit_test
eq  "the suite change was committed" "suite: y" "$(git -C "$T/hr" log -1 --format=%s)"
eq  "the commit lock is released" "" "$(ls -d "$LOGS/.suite-commit.lock" 2>/dev/null)"
ok  "nothing dirty is a no-op" commit_test

# --- the board snapshot cache: one snapshot per TTL per driver tree, gone
# after an invalidation, never another process tree's, never with TTL 0
stub_gh 'echo x >> "'"$T"'/snap-calls"; case "$*" in *"--json number,title"*) echo "[{\"number\": 1, \"labels\": []}]" ;; *) echo "[]" ;; esac'
snaps() { wc -l < "$T/snap-calls" | tr -d ' '; }
: > "$T/snap-calls"; snapshot_invalidate
issue_snapshot >/dev/null; issue_snapshot >/dev/null
eq  "snapshot: a second read within the TTL is the cache" 4 "$(snaps)"
eq  "snapshot: the cached board is the board" 1 "$(issue_snapshot | jq '.issues | length')"
eq  "snapshot: no cache field leaks to callers" null "$(issue_snapshot | jq -c '.cache')"
snapshot_invalidate; issue_snapshot >/dev/null
eq  "snapshot: invalidate forces a fresh read" 8 "$(snaps)"
HARNEST_SNAPSHOT_OWNER=other issue_snapshot >/dev/null
eq  "snapshot: another driver tree reads its own" 12 "$(snaps)"
SNAPSHOT_TTL_SECS=0 issue_snapshot >/dev/null
eq  "snapshot: TTL 0 never caches" 16 "$(snaps)"
issue_snapshot >/dev/null; still_ready 1 implementer:fix
eq  "snapshot: still_ready reads a fresh board" 24 "$(snaps)"
finish
