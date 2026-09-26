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

# --- handoff_count: hand-offs since the last reopen
stub_gh 'printf "%s\n" labeled labeled reopened labeled'
eq "hand-offs since the last reopen" "1" "$(handoff_count 5)"
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

# --- the driver lock
lock_test() {
  bash -c '. "$1/providers.sh"; acquire_driver_lock t; cat "$LOGS/.driver.lock/owner"' _ "$HARNEST"
}
mkdir "$LOGS/.driver.lock"; echo "999999 dead" > "$LOGS/.driver.lock/owner"
has "a dead holder's lock is taken over" " t" "$(lock_test)"
mkdir "$LOGS/.driver.lock"; touch -t 202601010000 "$LOGS/.driver.lock"
has "an ownerless old lock is taken over" " t" "$(lock_test)"
eq  "the lock is released at exit" "" "$(ls -d "$LOGS/.driver.lock" 2>/dev/null)"

# --- server targets (harnest#15)
git init -q "$T/dwlocal"
git -C "$T/dwlocal" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
git -C "$T/dwlocal" checkout -q -b feat/mps
echo a > "$T/dwlocal/f"; git -C "$T/dwlocal" add f; git -C "$T/dwlocal" -c user.name=t -c user.email=t@t commit -qm two
tgt() { # tgt <target> <snippet>: providers.sh sourced under DW_TARGET=<target>
  env DW_TARGET="$1" DW_LOCAL_DIR="$T/dwlocal" DW_URL="${TGT_URL:-}" bash -c '. "$1/providers.sh"; resolve_target || exit 1; eval "$2"' _ "$HARNEST" "$2" 2>&1
}
eq  "lem keeps the lock name a running loop holds" "|http://lem:8765/mcp" "$(tgt lem 'echo "$TARGET_SUFFIX|$DW_URL"')"
eq  "local gets its own suffix and localhost" ".local|http://localhost:8765/mcp" "$(tgt local 'echo "$TARGET_SUFFIX|$DW_URL"')"
eq  "an explicit local DW_URL wins" "http://127.0.0.1:9000/mcp" "$(TGT_URL=http://127.0.0.1:9000/mcp tgt local 'echo "$DW_URL"')"
eq  "this machine's own name is local" "http://$(hostname):8765/mcp" "$(TGT_URL="http://$(hostname):8765/mcp" tgt local 'echo "$DW_URL"')"
has "a leftover lem DW_URL is refused" "needs a DW_URL on this machine" "$(TGT_URL=http://lem:8765/mcp tgt local 'echo ran')"
eq  "url_host strips scheme, port and path" "lem|::1|localhost" "$(tgt lem 'echo "$(url_host http://lem:8765/mcp)|$(url_host "http://[::1]:8765/mcp")|$(url_host http://localhost/mcp)"')"
eq  "short_host drops the domain and case" "mac-mini" "$(tgt lem 'short_host Mac-mini.lan')"
has "an unknown target is refused" "must be lem or local" "$(tgt cuda2 'echo ran')"
has "a DW_LOCAL_DIR that isn't a checkout is refused" "not a git checkout" "$(env DW_TARGET=local DW_LOCAL_DIR="$T/nope" bash -c '. "$1/providers.sh"; resolve_target' _ "$HARNEST" 2>&1)"
eq  "local head is unknown until a deploy records one" "unknown" "$(tgt local deployed_head)"
echo "develop @ abc1234" > "$LOGS/.deployed.local"
eq  "local head is what the last deploy recorded" "develop @ abc1234" "$(tgt local deployed_head)"
rm -f "$LOGS/.deployed.local"
eq  "the local lock is its own" "run-x" "$(tgt local 'acquire_driver_lock run-x; cut -d" " -f2 "$LOGS/.driver.lock.local/owner"')"
eq  "lem's lock is untouched by a local run" "" "$(ls -d "$LOGS/.driver.lock" 2>/dev/null)"
printf '#!/usr/bin/env bash\necho "curl $*" >> "%s"\necho '"'"'{"status":"ok","device":"mps","hostname":"mac"}'"'"'\n' "$T/curl-calls" > "$T/bin/curl"; chmod +x "$T/bin/curl"
eq  "health reports device and host" "mps on mac" "$(tgt local target_health)"
has "health asks the base URL, not /mcp" "http://localhost:8765/api/health" "$(cat "$T/curl-calls")"
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bin/curl"
fails "health fails when nothing answers" env DW_TARGET=local DW_LOCAL_DIR="$T/dwlocal" bash -c '. "$1/providers.sh"; resolve_target; target_health' _ "$HARNEST"
me="$(hostname)"
health() { printf '#!/usr/bin/env bash\necho '"'"'{"status":"ok","device":"mps","hostname":"%s"}'"'"'\n' "$1" > "$T/bin/curl"; chmod +x "$T/bin/curl"; }
health "$me"
eq  "preflight passes when this machine answers" "ok|mps on $me" "$(tgt local 'target_preflight && echo "ok|$TARGET_HEALTH"')"
health "lem"
has "preflight refuses lem behind a localhost tunnel" "is lem, not this machine" "$(tgt local 'target_preflight && echo ran')"
rm -f "$T/bin/curl"
has "preflight refuses when nothing answers" "no dw server answering" "$(tgt local 'target_preflight && echo ran')"
eq  "lem commits suites and perf" "regression-suite-*.md regression-perf" "$(tgt lem suite_commit_paths)"
eq  "local commits only its own perf" "regression-perf/local" "$(tgt local suite_commit_paths)"
eq  "the local loop also commits a tester's shared case" "regression-suite-*.md regression-perf/local" "$(tgt local 'SUITE_EDITS=1; suite_commit_paths')"
mkdir -p "$LOGS/.driver.lock"; echo "$$ run-loop" > "$LOGS/.driver.lock/owner"
eq  "but leaves suite files to lem's loop while it runs (it may be mid-edit)" "regression-perf/local" "$(tgt local 'SUITE_EDITS=1; suite_commit_paths')"
rm -rf "$LOGS/.driver.lock"
has "lem's regression runtime note lists suite edits" "a suite-file edit" "$(tgt lem 'runtime_note regression anthropic sonnet')"
eq  "a local one does not" "" "$(tgt local 'runtime_note regression anthropic sonnet' | grep 'suite-file' || true)"
eq  "no target note for lem" "" "$(tgt lem 'target_note regression "cuda on lem"')"
note="$(tgt local 'target_note regression "mps on mac"')"
has "the local note moves perf history" "regression-perf/local/<case>.jsonl" "$note"
has "the local note files with a backend label" "\`owner:implementer\` and \`backend:mps\`" "$note"
has "the local note never comments on lem's issues" "Never comment on a \`target:lem\` issue" "$note"
inote="$(tgt local 'target_note implementer "mps on mac"')"
has "implementer note leaves the deploy to the driver" "The driver deploys" "$inote"
has "implementer note names the serving clone" "git -C $T/dwlocal log -1" "$inote"
has "implementer note hands cuda to lem" "--remove-label target:local --add-label target:lem" "$inote"
eq  "implementer note leaves no placeholder" "" "$(printf '%s' "$inote" | grep -o '{{[A-Z_]*}}' || true)"
tnote="$(tgt local 'target_note tester "mps on mac"')"
has "tester note requires verified-on:mps" "\`verified-on:mps\` next to \`status:verified\`" "$tnote"
has "tester note limits suite edits to shared fixes" "Proposed case (mps level, harnest#16)" "$tnote"
has "tester note comments before the hand-over (the guard refuses comments on target:lem)" "comment what's missing first" "$tnote"
eq  "tester note leaves no placeholder" "" "$(printf '%s' "$tnote" | grep -o '{{[A-Z_]*}}' || true)"
has "the local note keeps the suite files lem's" "The suite files. Every case in them runs on lem" "$note"
has "the local note names the server" "(mps on mac, http://localhost:8765/mcp)" "$note"
eq  "the local note leaves no placeholder" "" "$(printf '%s' "$note" | grep -o '{{[A-Z]*}}' || true)"

# --- per-target resources for the loop (harnest#15 part 2)
eq  "local: its own loop log" "$LOGS/loop.local.log" "$(tgt local 'echo "$LOOP_LOG"')"
eq  "lem: the loop log is unchanged" "$LOGS/loop.log" "$(tgt lem 'echo "$LOOP_LOG"')"
eq  "target_default picks the target's value" "a|b" "$(tgt lem 'target_default a b')|$(tgt local 'target_default a b')"
dc="$(tgt local deploy_cmd)"
has "local: deploy runs the harness's recording wrapper" "$HARNEST/scripts/deploy-local.sh" "$dc"
has "local: deploy points at the serving clone" "DW_DIR=$T/dwlocal " "$dc"
has "local: deploy binds loopback only" "DW_HOST=127.0.0.1" "$dc"
has "local: deploy uses the local workspace" "DW_WORKSPACE=$HOME/dw-mps-workspace" "$dc"
has "local: deploy uses the URL's port" "DW_PORT=9000" "$(TGT_URL=http://127.0.0.1:9000/mcp tgt local deploy_cmd)"
eq  "local: no ssh in the deploy" "" "$(printf '%s' "$dc" | grep -o ssh || true)"
has "lem: deploy over ssh" "ssh -o ConnectTimeout=8 -o BatchMode=yes lem" "$(tgt lem deploy_cmd)"
eq  "lem: server name" "lem" "$(tgt lem server_name)"
eq  "local: server name" "the local server (mps on mac)" "$(tgt local 'TARGET_HEALTH="mps on mac"; server_name')"
printf '#!/usr/bin/env bash\necho "deploy $*"\n' > "$T/dwlocal-deploy"; chmod +x "$T/dwlocal-deploy"
mkdir -p "$T/dwlocal/scripts"; cp "$T/dwlocal-deploy" "$T/dwlocal/scripts/deploy.sh"
ok  "local: deploy_target runs it" tgt local deploy_target
has "local: and logs it" "[loop:deploy] deploy develop" "$(cat "$LOGS/loop.local.log")"
eq  "local: a deploy records what it deployed" "$(git -C "$T/dwlocal" branch --show-current) @ $(git -C "$T/dwlocal" rev-parse --short HEAD)" "$(tgt local deployed_head)"
rm -f "$LOGS/.deployed.local"
printf '#!/usr/bin/env bash\necho dirty; exit 1\n' > "$T/dwlocal/scripts/deploy.sh"
fails "local: a failed deploy fails" env DW_TARGET=local DW_LOCAL_DIR="$T/dwlocal" bash -c '. "$1/providers.sh"; resolve_target; deploy_target' _ "$HARNEST"
eq  "local: and records nothing" "unknown" "$(tgt local deployed_head)"
rm -rf "$T/dwlocal/scripts"
# claim_issue: a clean claim holds; a tie with lem is lost and the label removed
# The stub answers an issue view from $T/views/<n>: one line per call (the
# pre-check, then the read-back), the last line repeating.
mkdir -p "$T/views"
stub_gh 'case "$1 $2" in "issue view") f="'"$T"'/views/$3"; c="$f.n"; k=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo $k > "$c"; l=$(sed -n "${k}p" "$f"); [ -n "$l" ] || l=$(tail -1 "$f"); printf "%s\n" $l ;; *) exit 0 ;; esac'
printf 'none\ntarget:local\n' > "$T/views/5"
ok    "claim: an unclaimed issue is held" tgt local 'TICKET_REPO=o/r claim_issue 5'
printf 'none\ntarget:local target:lem\n' > "$T/views/6"
fails "claim: a tie at read-back is yielded" env DW_TARGET=local DW_LOCAL_DIR="$T/dwlocal" bash -c '. "$1/providers.sh"; resolve_target; TICKET_REPO=o/r claim_issue 6' _ "$HARNEST"
has   "claim: the yielded claim is removed" "gh issue edit 6 --repo o/r --remove-label target:local" "$(cat "$GH_CALLS")"
printf 'none\ntarget:lem target:local\n' > "$T/views/7"
fails "claim: lem yields a tie too (the other loop may already be working it)" tgt lem 'TICKET_REPO=o/r claim_issue 7'
has   "claim: lem removes its own" "gh issue edit 7 --repo o/r --remove-label target:lem" "$(cat "$GH_CALLS")"
printf 'target:local\n' > "$T/views/8"
fails "claim: an issue another loop holds is skipped" tgt lem 'TICKET_REPO=o/r claim_issue 8'
eq    "claim: without adding a label" "" "$(grep 'issue edit 8' "$GH_CALLS" || true)"
printf 'target:lem\n' > "$T/views/9"
ok    "claim: a loop keeps its own earlier claim" tgt lem 'TICKET_REPO=o/r claim_issue 9'
# lem_loop_running: only a live run-loop holder counts
mkdir -p "$LOGS/.driver.lock"
echo "$$ run-loop" > "$LOGS/.driver.lock/owner"
ok    "lem loop: a live run-loop holds lem's lock" tgt local lem_loop_running
echo "$$ run-regression" > "$LOGS/.driver.lock/owner"
fails "lem loop: a regression run is not the loop" env DW_TARGET=local DW_LOCAL_DIR="$T/dwlocal" bash -c '. "$1/providers.sh"; resolve_target; lem_loop_running' _ "$HARNEST"
echo "999999 run-loop" > "$LOGS/.driver.lock/owner"
fails "lem loop: a dead holder" env DW_TARGET=local DW_LOCAL_DIR="$T/dwlocal" bash -c '. "$1/providers.sh"; resolve_target; lem_loop_running' _ "$HARNEST"
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
finish
