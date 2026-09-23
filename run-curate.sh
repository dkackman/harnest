#!/usr/bin/env bash
# Suite curation (HARNESS-ROADMAP.md R5): one session per regression level
# that reads the suite file, its regression-perf/ history and what its
# recent runs cost, and files a single issue of proposed moves, merges, contradictions, stale references and
# retirements, on the harness repo (the suites live there), labeled
# suite + status:needs-approval. It never edits a suite; a human applies what
# they approve. Case history — the failures and fixes a case cites — stays
# on the ticket repo, which the curator searches but never files on.
#
#   ./run-curate.sh                 # every level that is due
#   ./run-curate.sh smoke           # one level
#   CURATE_FORCE=1 ./run-curate.sh smoke    # even if curated recently
#   CURATE_EVERY_DAYS=7             # how often a level is due (default 7)
#
# A level is skipped while an open "curation: <level> suite" issue on the
# harness repo is still waiting for Don: a second would only repeat the first. Run it from
# cron or the loop skill; it never loops itself. No driver lock: it makes no
# MCP calls and never touches lem.
#
# Budgets per level are proposals, not measurements; they are what the
# curator measures the recent runs against. Smoke ran ~40 min / $17-18 on
# sonnet per run as of 2026-09-22, which is not "fast and fundamental".

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"   # searched for case history
HARNESS_REPO="${HARNESS_REPO:-dkackman/harnest}"            # where proposals are filed
AGENTS="$REPO/agents"
LOGS="$REPO/logs"
PROVIDER="${PROVIDER:-anthropic}"
# Judgment work over a 50-240 KB file: overlap and contradiction are what a
# weak model misses, and a session runs weekly at most.
CURATE_MODEL="${CURATE_MODEL:-claude-opus-5-5}"
CURATE_PROVIDER="${CURATE_PROVIDER:-$PROVIDER}"
CURATE_BUDGET_USD="${CURATE_BUDGET_USD:-6}"
CURATE_EVERY_DAYS="${CURATE_EVERY_DAYS:-7}"
CURATE_FORCE="${CURATE_FORCE:-0}"
CURATE_RUNS="${CURATE_RUNS:-3}"     # recent runs per level in the chunk table
AUTOCOMPACT_TOKENS="${AUTOCOMPACT_TOKENS:-120000}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"
# level budgets: minutes and USD for one full run of that level on the
# regression agent's default model
BUDGET_smoke="${CURATE_BUDGET_SMOKE:-30 13}"
BUDGET_complete="${CURATE_BUDGET_COMPLETE:-60 20}"
BUDGET_model_specific="${CURATE_BUDGET_MODEL_SPECIFIC:-60 12}"
BUDGET_security="${CURATE_BUDGET_SECURITY:-15 6}"

command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
command -v gh >/dev/null     || { echo "gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null     || { echo "jq not on PATH" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated" >&2; exit 1; }
mkdir -p "$LOGS"

. "$REPO/providers.sh"
CURATE_EFFORT="${CURATE_EFFORT:-$EFFORT}"

resolve_model_env "$CURATE_PROVIDER" "$CURATE_MODEL" || exit 1
EFFORT_FLAGS=(); read -r -a EFFORT_FLAGS <<<"$(effort_flags "$CURATE_PROVIDER" "$CURATE_EFFORT")"
fb_words="$(fallback_model_flags "$CURATE_PROVIDER" "$FALLBACK_MODEL")" || exit 1
FALLBACK_FLAGS=(); [ -z "$fb_words" ] || read -r -a FALLBACK_FLAGS <<<"$fb_words"
LIMIT_FLAGS=(--autocompact "$AUTOCOMPACT_TOKENS")
[ "$CURATE_BUDGET_USD" = 0 ] || LIMIT_FLAGS+=(--max-budget-usd "$CURATE_BUDGET_USD")
LAST_SESSION="$LOGS/.last-session.curate"

# Read-only on this repo (no Edit/Write: a suite changes only when a human
# applies an approved proposal), gh issue for searching history and filing
# the one issue, no MCP.
CURATE_FLAGS=(
  --strict-mcp-config
  "${ISOLATION_FLAGS[@]}"
  --tools "Bash,Read,Glob,Grep,ToolSearch,TodoWrite"
  --permission-mode dontAsk
  --allowedTools "Read" "Glob" "Grep" "ToolSearch" "TodoWrite" "Bash(gh issue *)" "Bash(date *)" "Bash(wc *)"
)

ts() { date '+%H:%M:%S'; }

# chunk_table <level> <runs>
# From loop.log: for the last <runs> runs of <level>, one row per session —
# run, session, cost, wall seconds, turns, and the case IDs it ran. Cost is
# only known per session, so it stays per chunk.
chunk_table() {
  awk -v L="$1" '
    index($0, "regression run (") && index($0, "level=" L ",") { run++ }
    $0 ~ "^--- [0-9:]+ " L " session [0-9]+: " {
      s = $0; sub("^--- [0-9:]+ " L " session ", "", s)
      n = s; sub(":.*", "", n)
      ids = s; sub("^[0-9]+: ", "", ids); sub(" ---$", "", ids)
      chunk[run "," n] = ids
    }
    index($0, "[regression:" L ".") == 1 && index($0, "] usage:") {
      k = $0; sub("^\\[regression:" L "\\.", "", k); sub("\\].*", "", k)
      c = $0; sub(".* cost=\\$", "", c); sub(" .*", "", c)
      d = $0; sub(".* duration=", "", d); sub("s .*", "", d)
      t = $0; sub(".* turns=", "", t); sub(" .*", "", t)
      print run "\t" k "\t" c "\t" d "\t" t "\t" (k == "sweep" ? "(final sweep)" : chunk[run "," k])
    }' "$LOGS/loop.log" 2>/dev/null \
  | awk -F'\t' -v keep="$2" '{ rows[NR] = $0; r[NR] = $1; last = $1 } END {
      for (i = 1; i <= NR; i++) if (r[i] > last - keep) print rows[i] }' \
  | awk -F'\t' 'BEGIN { print "run\tsession\tcost_usd\twall_s\tturns\tcases" }
      { print; tot[$1] += $3; wall[$1] += $4 }
      END { for (k in tot) printf "run %s total: $%.2f, %d min (sessions run back to back)\n", k, tot[k], wall[k] / 60 }'
}

run_level() {
  local level="$1" file="$REPO/regression-suite-$1.md" prefix budget
  case "$level" in
    smoke) prefix=S ;; complete) prefix=C ;; model-specific) prefix=M ;; security) prefix=SE ;;
    *) echo "unknown level '$level' (smoke|complete|model-specific|security)" >&2; return 1 ;;
  esac
  [ -r "$file" ] || { echo "[curate:$level] no suite file $file" >&2; return 0; }
  local bvar="BUDGET_${level//-/_}"; budget="${!bvar}"
  local stamp="$LOGS/.curated-$level"

  if [ "$CURATE_FORCE" != 1 ] && [ -f "$stamp" ] \
     && [ -n "$(find "$stamp" -mtime -"$CURATE_EVERY_DAYS" 2>/dev/null)" ]; then
    echo "[curate:$level] curated within $CURATE_EVERY_DAYS days, skipping" | tee -a "$LOGS/loop.log"; return 0
  fi
  local waiting
  waiting="$(gh issue list --repo "$HARNESS_REPO" --state open --search "\"curation: $level suite\" in:title" \
               --json number,title --jq ".[] | select(.title | startswith(\"curation: $level suite\")) | .number" | head -n 1)"
  if [ -n "$waiting" ] && [ "$CURATE_FORCE" != 1 ]; then
    echo "[curate:$level] #$waiting is still waiting for Don, skipping" | tee -a "$LOGS/loop.log"; return 0
  fi

  local perf; perf="$(cd "$REPO" && ls regression-perf/"$prefix"-*.jsonl 2>/dev/null | tr '\n' ' ')"
  local attempt
  for attempt in 1 2; do
    : > "$LAST_SESSION"
    echo "=== $(ts) curate: $level ($MODEL_LABEL) ===" | tee -a "$LOGS/loop.log"
    (cd "$REPO" && env ${MODEL_ENV[@]+"${MODEL_ENV[@]}"} claude -p \
"Your role instructions are in your system prompt (the contents of $AGENTS/CURATOR.agent.md). Curate ONLY the $level level this session, then stop.

File the proposal issue on: $HARNESS_REPO (labels: suite, status:needs-approval)
Search case history (failures, fixes, cited issues) on: $TICKET_REPO
Suite file: regression-suite-$level.md (case IDs $prefix-*)
Sibling suites: $(cd "$REPO" && ls regression-suite-*.md | grep -v "regression-suite-$level.md" | tr '\n' ' ')
regression-perf files for this level: ${perf:-none}
Level budget for one full run: $(set -- $budget; echo "$1 minutes and \$$2")

Recent runs of this level (from logs/loop.log, as of $(date '+%F %H:%M')):
$(chunk_table "$level" "$CURATE_RUNS")

$(runtime_note curator "$CURATE_PROVIDER" "$CURATE_MODEL" 2>/dev/null || printf 'Runtime: you are the curator agent, running as model %s via the %s provider. Name that model and provider in the issue you file.' "$CURATE_MODEL" "$CURATE_PROVIDER")" \
      --model "$CURATE_MODEL" ${FALLBACK_FLAGS[@]+"${FALLBACK_FLAGS[@]}"} ${EFFORT_FLAGS[@]+"${EFFORT_FLAGS[@]}"} "${LIMIT_FLAGS[@]}" \
      --append-system-prompt-file "$AGENTS/CURATOR.agent.md" \
      "${STREAM_FLAGS[@]}" "${CURATE_FLAGS[@]}" 2>&1 < /dev/null | render_stream curate) \
      | tee -a "$LOGS/curate.log" "$LAST_SESSION" \
      | sed -u "s/^/[curate:$level] /" \
      | tee -a "$LOGS/loop.log" \
      || echo "[curate:$level] run failed" | tee -a "$LOGS/loop.log"
    sleep_if_rate_limited "$LAST_SESSION"
    session_died "$LAST_SESSION" || break
    [ "$attempt" -eq 1 ] || break
    echo "[curate:$level] session ended without a result; retrying once in ${SESSION_RETRY_PAUSE_SECS}s" | tee -a "$LOGS/loop.log"
    sleep "$SESSION_RETRY_PAUSE_SECS"
  done
  session_died "$LAST_SESSION" || touch "$stamp"
}

# The labels the proposals carry; idempotent.
gh label create suite --repo "$HARNESS_REPO" --color 0e8a16 --description "Proposed change to a regression suite" --force >/dev/null 2>&1 || true
gh label create status:needs-approval --repo "$HARNESS_REPO" --color d93f0b --description "Waiting for Don" --force >/dev/null 2>&1 || true

levels=("$@")
[ "${#levels[@]}" -gt 0 ] || levels=(smoke complete model-specific security)
for l in "${levels[@]}"; do run_level "$l"; done
