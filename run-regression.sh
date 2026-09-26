#!/usr/bin/env bash
# Runs the regression agent once per requested level against the live dw MCP
# server. Standalone — not part of the implementer/tester alternation in
# run-loop.sh. Each level has its own suite file and workspace, so a run
# never mixes fixtures or timings across levels:
#   smoke           regression-suite-smoke.md           regression-smoke
#   complete        regression-suite-complete.md        regression-complete
#   model-specific  regression-suite-model-specific.md  regression-model-specific
#   security        regression-suite-security.md        regression-security
#
#   ./run-regression.sh                      # smoke only (the default)
#   ./run-regression.sh complete             # smoke, then complete
#   ./run-regression.sh model-specific       # model-specific only
#   ./run-regression.sh security             # security only (hostile-input probes, opt-in)
#   ./run-regression.sh all                  # smoke, complete, model-specific, security
#   ./run-regression.sh smoke my-suite.md    # override the suite file for just that level
#   REGRESSION_MODEL=opus ./run-regression.sh     # defaults to sonnet
#   REGRESSION_EFFORT=high ./run-regression.sh   # --effort; defaults medium
#   PROVIDER=ollama REGRESSION_MODEL=qwen2.5:32b ./run-regression.sh   # a non-Anthropic model
#   CASES_PER_SESSION=3 ./run-regression.sh  # split each level into 3-case sessions
#   REGRESSION_BUDGET_USD=0 ./run-regression.sh  # no per-session cap (default $6)
#
# Waits for run-loop.sh if it is running (logs/.driver.lock), and stops the
# run when a session reports the MCP server unreachable (REGRESSION-ABORT).
#   DW_URL=... DW_TOKEN=... ./run-regression.sh
#   tail -f logs/regression.log              # watch from another terminal
#
# Another server (harnest#15). DW_TARGET=local runs against a dw server this
# machine runs out of DW_LOCAL_DIR (the Mac, MPS), which you start by hand:
#   DW_TARGET=local ./run-regression.sh smoke
#   tail -f logs/regression.local.log
# It takes its own lock (logs/.driver.lock.local), so it runs alongside the
# loop against lem; its session state and logs carry a .local suffix; it
# loads the plugin from DW_LOCAL_DIR, the copy that server serves; its perf
# readings go to regression-perf/local/; and what it files goes to owner:don
# with target:local, since the loop can only reproduce and verify on lem
# (target_note in providers.sh).
#
# Model/provider resolution lives in providers.sh — see its header for the
# supported providers and the per-provider knobs (OLLAMA_*, GW_*).
#
# A suite-file override gets its own workspace derived from its filename
# (stripping a leading "regression-suite-" and trailing ".md"), never the
# level's canonical workspace — so a one-off custom suite can't delete
# fixtures the real smoke/complete/model-specific/security suite depends on.
#
# regression-suite-*.md (and regression-perf/, the per-case measurement log)
# is a second channel the tester writes to directly (see its role prompt's
# "Adding a case" step), not just this script.
# run-loop.sh commits the tester's edits under the tester's identity; as a
# fallback, before the first level runs, this script commits anything still
# dirty under a neutral "unknown origin" trailer, and after each level it
# commits that level's run under the regression model's own trailer.
#
# Run it by hand, from cron, or wrapped with the `loop` skill for a recurring
# cadence — it does not loop or sleep internally.
#
# Chunked runs. A suite file is 40-50 KB, and one session exercising all of
# its cases fills a small (64k) context window part-way through; Claude Code
# then auto-compacts, the summary drops the suite text, the agent re-reads
# the whole file to recover, and the window is full again three turns later
# ("autocompact is thrashing"). CASES_PER_SESSION=N sidesteps that in the
# driver rather than trusting the model to read sparingly: the level is run
# as a series of separate sessions, each given N consecutive case IDs to
# exercise and told to read only those sections, followed by one last
# session that does the final sweep alone. When the provider declares a
# window under 120k tokens the default is 3; otherwise (including Anthropic,
# which declares no window here) it's 8 — a full suite's tool-call output
# alone can clear Claude Code's 120k autocompact threshold before the last
# case, so an unset CASES_PER_SESSION never means "one session per level."
# Set it to 0 explicitly to force that (e.g. to watch autocompact thrash).

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"          # the agents' clone (see run-loop.sh)
PLUGIN_TREE="${PLUGIN_TREE:-$HOME/src/dkackman/dw-agent-plugin}"  # origin/develop, shared with run-loop.sh (lem target only)
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
LOGS="$REPO/logs"
PROVIDER="${PROVIDER:-anthropic}"  # where that model lives: anthropic|ollama|gateway
# sonnet, not opus, since 2026-09-21: a smoke run on each, same day, same
# chunks - opus $32.64 / 699 turns, sonnet $17.85 / 799 turns, and sonnet's
# three new issues (#310-#312) were all real, one of them a wrong literal
# the opus run had committed to the suite an hour earlier. Regression is
# execution of a written case, so the "keep the judging roles strong" rule
# (CLAUDE.md "Running") costs more here than it buys; the tester stays on
# opus.
REGRESSION_MODEL="${REGRESSION_MODEL:-sonnet}"
REGRESSION_PROVIDER="${REGRESSION_PROVIDER:-$PROVIDER}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"   # optional; passed as --fallback-model
CASES_PER_SESSION="${CASES_PER_SESSION:-}"  # cases per session; empty = pick from the context window (see header); 0 = one session per level
# Per-session --max-budget-usd (0 = none) and autocompact point, as in
# run-loop.sh. 116 chunk sessions to 2026-09-22: median $2.10, p90 $4.59,
# max $9.41 - the cap sits above a normal chunk and stops a runaway one.
# A capped chunk loses its remaining cases for this run, not the suite.
REGRESSION_BUDGET_USD="${REGRESSION_BUDGET_USD:-6}"
AUTOCOMPACT_TOKENS="${AUTOCOMPACT_TOKENS:-120000}"
DW_URL="${DW_URL:-}"           # empty: the target's own (resolve_target)
# On a target other than lem, cases the driver never hands the agent: each
# can take a 64 GB unified-memory machine down with the session running it
# (S-F079 SD 1.5 at 8192x8192, which OOMs a 24 GB card; C-F005's H3 arm;
# C-F007 and C-F023 near 61 GB of host RSS; C-F047 tens of GB). Not left to
# the agent's reading of target.md: one misjudged case is an outage.
TARGET_SKIP_CASES="${TARGET_SKIP_CASES:-S-F079 C-F005 C-F007 C-F023 C-F047}"
DW_TOKEN="${DW_TOKEN:-xyz}"

LEVEL="${1:-smoke}"
SUITE_OVERRIDE="${2:-}"

# Each entry is "level:override-or-empty". `complete` also runs `smoke`
# first (smoke is a prerequisite, per every suite file's own header); the
# override, if given, applies only to the level named on the command line,
# never to a prerequisite pulled in alongside it.
case "$LEVEL" in
  smoke)          RUN_SPECS=("smoke:$SUITE_OVERRIDE") ;;
  complete)       RUN_SPECS=("smoke:" "complete:$SUITE_OVERRIDE") ;;
  model-specific) RUN_SPECS=("model-specific:$SUITE_OVERRIDE") ;;
  security)       RUN_SPECS=("security:$SUITE_OVERRIDE") ;;
  all)
    [ -n "$SUITE_OVERRIDE" ] && { echo "a suite-file override is ambiguous with level 'all' — run one level at a time to override its file" >&2; exit 1; }
    RUN_SPECS=("smoke:" "complete:" "model-specific:" "security:")
    ;;
  *)
    echo "unknown level '$LEVEL' (expected: smoke, complete, model-specific, security, all)" >&2
    exit 1
    ;;
esac

[ -d "$SOURCE_DIR" ] || { echo "SOURCE_DIR not found: $SOURCE_DIR" >&2; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
command -v gh >/dev/null     || { echo "gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null     || { echo "jq not on PATH" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated" >&2; exit 1; }
mkdir -p "$LOGS"

. "$REPO/providers.sh"

resolve_target || exit 1
# lem's name for everything is the one it always had; another target's
# carries TARGET_SUFFIX, so a lem run and a local run never share a log,
# a last-session file or a prompt file.
LOGNAME_REGRESSION="regression$TARGET_SUFFIX"
# Log prefix: [regression:smoke.2] on lem, [regression-local:smoke.2] here.
RPFX="regression${TARGET_SUFFIX:+-$DW_TARGET}"
SERVER="lem" TARGET_HEALTH=""
if [ "$DW_TARGET" != lem ]; then
  # A server answers at DW_URL, and it is this machine, not lem through a
  # tunnel. Nothing below runs otherwise.
  target_preflight || exit 1
  SERVER="the $DW_TARGET server ($TARGET_HEALTH)"
  # model-specific loads H3 (~50 GB) and full-size LTX: on a 64 GB unified
  # memory machine that is an outage, not a result. It runs only when named.
  [ "$LEVEL" = all ] && RUN_SPECS=("smoke:" "complete:" "security:")
  # What the agent files must carry this label, and gh refuses one that
  # doesn't exist.
  gh label create "target:$DW_TARGET" --repo "$TICKET_REPO" --force --color 5319e7 \
    --description "Found against a non-lem server (DW_TARGET=$DW_TARGET); Don triages" >/dev/null 2>&1 || true
  mkdir -p "$REPO/regression-perf/$DW_TARGET"
fi
# guard.py reads it: on another target, lem's suite and perf files are off
# limits and a new issue goes to owner:don + target:<target>.
SESSION_ENV=(HARNEST_TARGET="$DW_TARGET" HARNEST_TICKET_REPO="$TICKET_REPO")

# Never alongside run-loop.sh on the same target: an implementer deploy
# restarts the server mid-case, and both drivers keep per-session state
# under logs/.
acquire_driver_lock run-regression
LAST_SESSION="$LOGS/.last-session.$LOGNAME_REGRESSION"
if [ "$DW_TARGET" = lem ]; then
  PLUGIN_DIR="$PLUGIN_TREE/plugins/dw"
  refresh_plugin_tree "$SOURCE_DIR" "$PLUGIN_TREE" >/dev/null \
    || { echo "could not create/refresh the plugin worktree $PLUGIN_TREE from $SOURCE_DIR" >&2; exit 1; }
else
  # What a hand-run server serves is its own checkout, branch and all. The
  # shared worktree is lem's: resetting it here would swap the lem
  # tester's skills mid-cycle.
  PLUGIN_DIR="$DW_LOCAL_DIR/plugins/dw"
fi
[ -d "$PLUGIN_DIR" ] || { echo "dw plugin source not found: $PLUGIN_DIR" >&2; exit 1; }

# --effort; medium unless set. Defaults to EFFORT (providers.sh).
REGRESSION_EFFORT="${REGRESSION_EFFORT:-$EFFORT}"

# Reject a bad model/provider (or fallback) before touching the ticket board
# or the workspace. session_flags keeps the flags in an array, so a name
# like opus[1m] is never glob-expanded on the claude command line.
resolve_model_env "$REGRESSION_PROVIDER" "$REGRESSION_MODEL" || exit 1
session_flags "$REGRESSION_PROVIDER" "$REGRESSION_MODEL" "$REGRESSION_EFFORT" "$REGRESSION_BUDGET_USD" || exit 1

# Chunk by default always, sized to the provider's declared window (see the
# header) — a small window (e.g. a 64k Ollama model) gets 3 cases per
# session, everything else (including Anthropic, which declares no window
# here) gets 8. An explicit CASES_PER_SESSION wins either way, so a 200k
# model can be forced whole (0) to watch autocompact thrash, or chunked
# tighter/looser than the default.
if [ -z "$CASES_PER_SESSION" ]; then
  if [ -n "$MODEL_CONTEXT_TOKENS" ] && [ "$MODEL_CONTEXT_TOKENS" -lt 120000 ]; then
    CASES_PER_SESSION=3
  else
    CASES_PER_SESSION=8
  fi
fi
case "$CASES_PER_SESSION" in
  ''|*[!0-9]*) echo "CASES_PER_SESSION must be a whole number, got '$CASES_PER_SESSION'" >&2; exit 1 ;;
esac


ts() { date '+%H:%M:%S'; }

default_suite_file() {
  case "$1" in
    smoke)          echo "regression-suite-smoke.md" ;;
    complete)       echo "regression-suite-complete.md" ;;
    model-specific) echo "regression-suite-model-specific.md" ;;
    security)       echo "regression-suite-security.md" ;;
  esac
}

# Derives a workspace name from a suite file's basename so an override file
# never shares a workspace (and thus a Fixtures list) with the canonical
# suite for that level.
workspace_for_suite_file() {
  local base; base="$(basename "$1" .md)"
  case "$base" in
    regression-suite-*) echo "regression-${base#regression-suite-}" ;;
    *)                  echo "regression-$base" ;;
  esac
}

# Same isolation as the tester in run-loop.sh: this repo has no MCP config of
# its own, so dw is handed explicitly and --strict-mcp-config keeps it the
# only server visible. --plugin-dir loads the dw plugin live from the source
# checkout so skill fixes are covered without a reinstall. The permission
# allowlist (providers.sh) is the same fence the tester runs behind.
REGRESSION_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
  --plugin-dir "$PLUGIN_DIR"
  "${ISOLATION_FLAGS[@]}"
  --tools "$CONSUMER_TOOLS"
  "${CONSUMER_PERMISSION_FLAGS[@]}"
)

# run_session <level> <suite_file> <workspace> <tag> <kind> <instructions>
# One `claude -p` invocation of the regression agent. <kind> (whole, chunk,
# sweep) picks its system prompt: role_prompt in providers.sh. <instructions> is the
# run-specific paragraph that follows the standard override preamble; <tag>
# is appended to the log prefix ("[regression:smoke.2]") so a chunked run's
# sessions are distinguishable in loop.log.
run_session() {
  local level="$1" suite_file="$2" workspace="$3" tag="$4" kind="$5" instructions="$6" prompt_file
  prompt_file="$(role_prompt regression "$kind" "$LOGS/.prompt.$LOGNAME_REGRESSION.$kind.md")" \
    || { echo "[$RPFX:$level$tag] no role prompt for '$kind'" | tee -a "$LOGS/loop.log"; return 0; }
  # On another server, its rules (agents/regression/target.md) join the
  # system prompt, after the role's own, so they read as the last word.
  [ -z "$TARGET_SUFFIX" ] || { printf '\n'; target_note "$TARGET_HEALTH"; } >> "$prompt_file"
  # One fresh session, retried once if it dies, asleep through a rejected
  # rate limit (run_claude_session in providers.sh).
  run_claude_session "regression${TARGET_SUFFIX:+-$DW_TARGET}:$level$tag" "$LOGNAME_REGRESSION" "$REPO" "$prompt_file" \
    "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to file/comment on them. Your role instructions for this kind of session are in your system prompt; follow them exactly, with these specifics: suite file is $suite_file; level is '$level'; workspace is $workspace; $SERVER is running ${head:-unknown} - name that commit in anything you file or comment.${TARGET_SUFFIX:+ The Target section at the end of your system prompt applies to this whole run.} $instructions Then stop.

$(runtime_note regression "$REGRESSION_PROVIDER" "$REGRESSION_MODEL")" \
    "${SESSION_FLAGS[@]}" "${REGRESSION_FLAGS[@]}"
  # What target.md tells an agent on another server to list rather than file
  # A leading bullet or backtick is tolerated: a model writes a list as one.
  # A case ID must follow, so "REGRESSION-SKIP: none" is not a skip.
  LEVEL_SKIPS=$((LEVEL_SKIPS + $(grep -cE '^[-*` ]*REGRESSION-SKIP:[[:space:]]*[A-Z]+-[A-Z][0-9]' "$LAST_SESSION" 2>/dev/null || true)))
  LEVEL_DIFFERS=$((LEVEL_DIFFERS + $(grep -cE '^[-*` ]*REGRESSION-DIFFERS:[[:space:]]*[A-Z]+-[A-Z][0-9]' "$LAST_SESSION" 2>/dev/null || true)))
}

# session_aborted
# True when the session just run ended with the role prompt's abort line
# (REGRESSION-ABORT: ...), which it prints when the MCP server is
# unreachable. Without this the driver launched every remaining chunk into
# a down server, and each one could file its own "MCP unreachable" issue.
session_aborted() {
  grep -q '^REGRESSION-ABORT:' "$LAST_SESSION" 2>/dev/null
}

# script_cases <suite_file>
# IDs of the cases whose prose block carries a `runner: script` line and that
# have a contract/cases/<ID>.json: those run through contract/run.py (R6), a
# plain MCP client with no LLM, before any agent session. The agent never
# executes them; it only files what the report says failed. The suite line is
# what makes a case script-run, so which cases graduate is a suite edit, and
# goes through the same approval as any other.
script_cases() {
  awk '/^### / { id = ""; if (match($0, /^### [A-Z]+-[A-Z][0-9]+ /)) id = substr($0, 5, RLENGTH - 5) }
       /^runner: script[[:space:]]*$/ && id != "" { print id; id = "" }' "$1" \
  | while read -r id; do [ -f "$REPO/contract/cases/$id.json" ] && echo "$id"; done
}

run_level() {
  local level="$1" suite_arg="$2" suite_file workspace

  if [ -n "$suite_arg" ]; then
    case "$suite_arg" in
      /*) suite_file="$suite_arg" ;;
      *)  suite_file="$REPO/$suite_arg" ;;
    esac
  else
    suite_file="$REPO/$(default_suite_file "$level")"
  fi
  [ -f "$suite_file" ] || { echo "suite file not found: $suite_file" >&2; exit 1; }
  workspace="$(workspace_for_suite_file "$suite_file")"

  if ! grep -q '^### ' "$suite_file"; then
    echo "$(ts) $level${TARGET_SUFFIX}: $(basename "$suite_file") has no cases yet, skipping" | tee -a "$LOGS/loop.log"
    return 0
  fi

  local -a script_ids=()
  local script_note="" id
  while read -r id; do [ -n "$id" ] && script_ids+=("$id"); done < <(script_cases "$suite_file")
  if [ "${#script_ids[@]}" -gt 0 ]; then
    local report
    report="$(python3 "$REPO/contract/run.py" --url "$DW_URL" --token "$DW_TOKEN" "${script_ids[@]}" 2>&1 || true)"
    echo "[$RPFX:$level] script cases: $(printf '%s' "$report" | jq -r '"\(.passed // 0) passed, \(.failed // 0) failed, \(.errors // 0) errored\(if .error then " - " + .error else "" end)"' 2>/dev/null || echo "report unreadable")" | tee -a "$LOGS/loop.log"
    script_note="

These cases ran as scripts before this session (contract/run.py, a plain MCP client; see 'runner: script' on each): ${script_ids[*]}. Do not execute them. Their report:
$report
For each case whose status is fail or error, report it ('Reporting a failure' in the role instructions) exactly as for a case you ran yourself, quoting its failures; a pass needs nothing. An error with 'server unreachable' is the MCP-unreachable case, not a per-case failure."
  fi

  # Which commit this level ran against, in its header line and in every
  # session's prompt, so a filing names it too
  local head
  head="$(deployed_head)"
  # Another target's header and session lines carry its tag (smoke.local),
  # so run-curate.sh's per-chunk cost table, which reads lem's runs out of
  # loop.log, neither counts them nor mixes their sessions into lem's.
  local tag="$level$TARGET_SUFFIX" held="" id
  LEVEL_SKIPS=0 LEVEL_DIFFERS=0
  if [ -n "$TARGET_SUFFIX" ]; then
    for id in $TARGET_SKIP_CASES; do
      grep -q "^### $id " "$suite_file" || continue
      held="$held $id"
      LEVEL_SKIPS=$((LEVEL_SKIPS + 1))
      echo "[$RPFX:$level] REGRESSION-SKIP: $id memory (TARGET_SKIP_CASES: not run on this server)" | tee -a "$LOGS/loop.log"
    done
  fi
  if [ "$CASES_PER_SESSION" -eq 0 ]; then
    echo "=== $(ts) regression run ($MODEL_LABEL, level=$tag, suite=$suite_file, workspace=$workspace, target=$DW_TARGET, head=$head) ===" | tee -a "$LOGS/loop.log"
    run_session "$level" "$suite_file" "$workspace" "" whole \
      "Exercise every case in the suite file against the $workspace workspace, file or comment on issues for failures and performance regressions, add any cases worth adding, then do the final sweep.${held:+ Never run these cases on this server, whatever the suite says; the driver already counted them as skipped:$held.}$script_note"
  else
    # Case IDs in file order, from the `### <ID> — title` headings. The
    # regex is the same shape every suite uses (S-F001, SE-P001, ...); a
    # heading that doesn't match isn't a case and is skipped.
    local ids=() chunk=() seen=0 total=0 session=0
    while read -r id; do
      case " ${script_ids[*]:-} " in *" $id "*) continue ;; esac   # run by contract/run.py above
      case "$held " in *" $id "*) continue ;; esac                 # TARGET_SKIP_CASES, above
      ids+=("$id")
    done < <(sed -n 's/^### \([A-Z][A-Z]*-[A-Z][0-9][0-9]*\) .*/\1/p' "$suite_file")
    total=${#ids[@]}
    echo "=== $(ts) regression run ($MODEL_LABEL, level=$tag, suite=$suite_file, workspace=$workspace, target=$DW_TARGET, head=$head, $total cases in sessions of $CASES_PER_SESSION) ===" | tee -a "$LOGS/loop.log"
    for id in ${ids[@]+"${ids[@]}"}; do
      chunk+=("$id"); seen=$((seen + 1))
      if [ "${#chunk[@]}" -eq "$CASES_PER_SESSION" ] || [ "$seen" -eq "$total" ]; then
        session=$((session + 1))
        echo "--- $(ts) $tag session $session: ${chunk[*]} ---" | tee -a "$LOGS/loop.log"
        run_session "$level" "$suite_file" "$workspace" ".$session" chunk \
          "This is one chunk of a chunked run: this session exercises ONLY these cases, in this order: ${chunk[*]}. Do not read the suite file in full — read its header (everything above the first '### ' heading, which includes the Fixtures section), then only those cases' sections. Skip the final sweep; a separate session does it after every case has run."
        chunk=()
        if session_aborted; then
          echo "[$RPFX:$level] session $session aborted (MCP unreachable); skipping the rest of this level and the sweep" | tee -a "$LOGS/loop.log"
          break
        fi
      fi
    done
    if ! session_aborted; then
      echo "--- $(ts) $tag session $((session + 1)): final sweep ---" | tee -a "$LOGS/loop.log"
      run_session "$level" "$suite_file" "$workspace" ".sweep" sweep \
        "This is the final sweep of a chunked run: every case was already exercised in earlier sessions. Do only the final sweep against the $workspace workspace — read the suite file's header (everything above the first '### ' heading, which includes the Fixtures section), not the cases.$script_note"
    fi
  fi

  [ -z "$TARGET_SUFFIX" ] \
    || echo "[$RPFX:$level] $LEVEL_SKIPS case(s) skipped, $LEVEL_DIFFERS expectation(s) differ on this server (REGRESSION-SKIP / REGRESSION-DIFFERS lines above)" | tee -a "$LOGS/loop.log"
  # The trailer names the id the model alias actually resolved to.
  co_author_for "$REGRESSION_PROVIDER" "$(resolved_model "$LOGNAME_REGRESSION" "$REGRESSION_MODEL")"
  commit_suite_changes "regression: update $level suite from $(ts) run ($MODEL_LABEL${TARGET_SUFFIX:+, target $DW_TARGET})"
  # An unreachable server fails every later level the same way.
  if session_aborted; then
    echo "[$RPFX] stopping: MCP unreachable" | tee -a "$LOGS/loop.log"
    exit 1
  fi
}

# main: in a function, and called with `exit` on the same line, so bash has
# parsed all of it before it runs, and editing this file mid-run can't make
# bash resume at a stale byte offset. An edit takes effect at the next start.
main() {
# Fallback only: run-loop.sh commits the tester's own suite edits under the
# tester's identity, so anything still dirty here is of unknown origin (a
# hand edit between runs, or a cycle that died before committing). It is
# committed so this run's commit stays attributable to this run — but under a
# neutral name, never the regression model, which didn't write it.
# On another server this commit would take lem's files, which a run here
# never writes, and the loop's tester may be mid-edit in them.
[ -n "$TARGET_SUFFIX" ] \
  || commit_suite_changes "regression: capture suite edits of unknown origin made outside a regression run" \
       "unknown (edited outside a regression run)" "noreply@localhost"

for spec in "${RUN_SPECS[@]}"; do
  run_level "${spec%%:*}" "${spec#*:}"
done
}

main "$@"; exit
