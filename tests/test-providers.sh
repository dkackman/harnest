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
finish
