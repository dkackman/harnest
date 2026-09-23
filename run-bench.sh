#!/usr/bin/env bash
# R1 replay benchmark (HARNESS-ROADMAP.md): re-runs the implementer on
# issues that were already fixed and verified, from the commit just before
# the real fix, and scores the result — so a prompt edit, model swap or
# alias move is judged by numbers instead of by feel.
#
#   ./run-bench.sh                          # every case in bench/cases
#   ./run-bench.sh 289 74                   # just these issues
#   IMPLEMENTER_MODEL=opus ./run-bench.sh   # another configuration
#   BENCH_PROMPT_REV=538f87f ./run-bench.sh # the implementer prompt as of a commit
#   BENCH_JOBS=3 ./run-bench.sh             # cases in parallel (no lem involved)
#   ./run-bench.sh --summary                # pass rate / cost / turns per label
#   BENCH_RESCORE=1 BENCH_LABEL=x ./run-bench.sh 289   # re-score a kept session, no new spend
#
# Standalone and offline: no gh, no ssh, no MCP, never touches lem or the
# agents' checkout. Each case gets a fresh clone holding only history up to
# the pre-fix commit (fetched by sha, so no later object — the fix included —
# is reachable), with no remote, and PYTHONPATH pointed at it because the
# shared venv's editable install otherwise imports SOURCE_DIR's code.
#
# Scores per case (one JSONL line in bench/results/results.jsonl):
#   new_failures  full pytest failures not already failing at the pre-fix commit
#   hidden        the real fix's test changes applied on top of the agent's
#                 tree: pass | fail | conflict | none (fix had no tests)
#   file_recall   share of the real fix's non-test files the agent touched
#   verdict       pass | partial | fail, from a fresh judge session comparing
#                 the agent's diff to the real fix and the tester's verify
#   cost/turns/ctx_peak/budget_hit, from the session's usage line
# bench/cases/<n>/ is frozen by bench/snapshot.py; see bench/README.md.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"   # only its venv and object store are read
BENCH="$REPO/bench"
LOGS="$REPO/logs/bench"
RESULTS="$BENCH/results/results.jsonl"
WORK="${BENCH_WORK:-${TMPDIR:-/tmp}/harnest-bench}"
PROVIDER="${PROVIDER:-anthropic}"
IMPLEMENTER_MODEL="${IMPLEMENTER_MODEL:-sonnet}"
IMPLEMENTER_PROVIDER="${IMPLEMENTER_PROVIDER:-$PROVIDER}"
# The judge must be strong and fixed across the configurations it compares;
# an exact id, not an alias, for the same reason TESTER_MODEL is one.
JUDGE_MODEL="${JUDGE_MODEL:-claude-opus-5-5}"
JUDGE_PROVIDER="${JUDGE_PROVIDER:-anthropic}"
# Live implementer sessions ran $1.29 median, $3.28 p90 including deploys,
# which a replay skips.
BENCH_BUDGET_USD="${BENCH_BUDGET_USD:-4}"
JUDGE_BUDGET_USD="${JUDGE_BUDGET_USD:-1}"
JUDGE_TIMEOUT_SECS="${JUDGE_TIMEOUT_SECS:-300}"
AUTOCOMPACT_TOKENS="${AUTOCOMPACT_TOKENS:-120000}"
BENCH_JOBS="${BENCH_JOBS:-1}"
BENCH_PROMPT_REV="${BENCH_PROMPT_REV:-}"   # empty = working tree

command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null     || { echo "jq not on PATH" >&2; exit 1; }
mkdir -p "$LOGS" "$WORK" "$(dirname "$RESULTS")"

. "$REPO/providers.sh"
IMPLEMENTER_EFFORT="${IMPLEMENTER_EFFORT:-$EFFORT}"

summary() {
  [ -s "$RESULTS" ] || { echo "no results yet: $RESULTS" >&2; return 0; }
  jq -rs --arg want "$*" '
    def pct(a; b): if b == 0 then "-" else "\((100 * a / b) | round)%" end;
    map(. as $r | select($want == "" or ($want | split(" ") | index($r.label)) != null))
    # a rescore appends a row; the latest row per (label, case) is the one that counts
    | group_by([.label, .issue]) | map(max_by(.at))
    | group_by(.label)[]
    | { label: .[0].label, n: length,
        pass: map(select(.verdict == "pass")) | length,
        partial: map(select(.verdict == "partial")) | length,
        clean: map(select(.new_failures == 0)) | length,
        hidden: map(select(.hidden == "pass")) | length,
        hidden_n: map(select(.hidden != "none")) | length,
        cost: (map(.cost) | add), turns: (map(.turns) | add / length | round),
        ctx: (map(.ctx_peak_k) | add / length | round),
        capped: map(select(.budget_hit)) | length }
    | "\(.label)\n  n=\(.n) pass=\(pct(.pass; .n)) partial=\(pct(.partial; .n)) no-new-failures=\(pct(.clean; .n)) hidden-tests=\(pct(.hidden; .hidden_n)) budget-capped=\(.capped)\n  cost=$\(.cost * 100 | round / 100) ($\(.cost / .n * 100 | round / 100)/case) turns=\(.turns)/case ctx_peak=\(.ctx)k/case"
  ' "$RESULTS"
}
[ "${1:-}" = --summary ] && { shift; summary "$@"; exit 0; }

# The prompt under test: this repo's IMPLEMENTER.agent.md at BENCH_PROMPT_REV
# (or the working tree), with the replay note appended. The note is the same
# for every configuration, so it cancels out of any comparison.
PROMPT_FILE="$WORK/.implementer-prompt.$$.md"
if [ -n "$BENCH_PROMPT_REV" ]; then
  git -C "$REPO" show "$BENCH_PROMPT_REV:agents/IMPLEMENTER.agent.md" > "$PROMPT_FILE"
  PROMPT_ID="$(git -C "$REPO" rev-parse --short "$BENCH_PROMPT_REV")"
else
  cp "$REPO/agents/IMPLEMENTER.agent.md" "$PROMPT_FILE"
  PROMPT_ID="$(git -C "$REPO" rev-parse --short HEAD)"
  git -C "$REPO" diff --quiet HEAD -- agents/IMPLEMENTER.agent.md || PROMPT_ID="$PROMPT_ID+dirty"
fi
cat "$BENCH/replay-note.md" >> "$PROMPT_FILE"
BENCH_LABEL="${BENCH_LABEL:-$IMPLEMENTER_PROVIDER/$IMPLEMENTER_MODEL@$PROMPT_ID}"

# Same auto-mode picture of the environment as a live session, plus deny
# rules that make the replay note enforced rather than requested: nothing
# can reach GitHub (where the real fix and its verify comment live), lem,
# or the web.
SETTINGS_FILE="$WORK/.implementer-settings.$$.json"
jq '.permissions.deny = ["Bash(gh:*)", "Bash(ssh:*)", "Bash(scp:*)", "Bash(git push:*)", "Bash(git fetch:*)",
                         "Bash(git pull:*)", "Bash(git remote:*)", "Bash(git clone:*)", "Bash(curl:*)",
                         "Bash(wget:*)", "WebFetch", "WebSearch"]' \
  "$REPO/agent-settings/implementer.json" > "$SETTINGS_FILE"
trap 'rm -f "$PROMPT_FILE" "$SETTINGS_FILE"' EXIT

resolve_model_env "$IMPLEMENTER_PROVIDER" "$IMPLEMENTER_MODEL" || exit 1
IMPL_ENV=(${MODEL_ENV[@]+"${MODEL_ENV[@]}"})
resolve_model_env "$JUDGE_PROVIDER" "$JUDGE_MODEL" || exit 1
JUDGE_ENV=(${MODEL_ENV[@]+"${MODEL_ENV[@]}"})
EFFORT_WORDS=(); read -r -a EFFORT_WORDS <<<"$(effort_flags "$IMPLEMENTER_PROVIDER" "$IMPLEMENTER_EFFORT")"

ts() { date '+%H:%M:%S'; }

# pytest_failures <dir> [paths...] — sorted failing/erroring test ids.
pytest_failures() {
  local dir="$1"; shift
  (cd "$dir" && PYTHONPATH="$dir" venv/bin/python -m pytest -q -rfE -p no:cacheprovider "$@" 2>&1 || true) \
    | sed -E -n 's/^(FAILED|ERROR) ([^ ]+).*/\2/p' | sort -u
}

# make_clone <prefix> <dir> — history up to <prefix> only, no remote.
make_clone() {
  local prefix="$1" dir="$2"
  rm -rf "$dir"; git init -q "$dir"
  git -C "$dir" fetch -q --no-tags "$SOURCE_DIR" "$prefix"
  git -C "$dir" checkout -q -b bench FETCH_HEAD
  git -C "$dir" config user.name "bench"; git -C "$dir" config user.email "bench@localhost"
  ln -s "$SOURCE_DIR/venv" "$dir/venv"
  printf 'venv\nHANDOFF.md\n' >> "$dir/.git/info/exclude"
}

cap() { head -c "$1"; }

run_case() {
  local n="$1" case="$BENCH/cases/$1"
  [ -r "$case/meta.json" ] || { echo "[bench:#$n] no case at $case" >&2; return 0; }
  local prefix; prefix="$(jq -r .prefix "$case/meta.json")"
  local out="$WORK/$(printf '%s' "$BENCH_LABEL" | tr '/@:+' '____')/$n"
  local dir="$out/repo" tag="[bench:#$n]"
  mkdir -p "$out"

  # Pre-fix failures, once per commit: this Mac fails some worker tests at
  # every commit, and those mustn't count against the agent.
  local base="$LOGS/baseline-$prefix.txt"
  if [ "${BENCH_RESCORE:-0}" = 1 ] && [ -s "$out/session.jsonl" ]; then
    echo "$tag $(ts) rescoring the existing session in $out"
    # Scoring mutates the tree (the real fix's tests go in), so every score
    # starts from the frozen agent result, never from a previous score.
    [ -s "$out/agent.sha" ] && git -C "$dir" reset -q --hard "$(cat "$out/agent.sha")" && git -C "$dir" clean -qfd
  else
  make_clone "$prefix" "$dir"
  if [ ! -f "$base" ]; then
    echo "$tag $(ts) baseline pytest at ${prefix:0:10}"
    pytest_failures "$dir" > "$base.tmp" && mv "$base.tmp" "$base"
  fi

  echo "$tag $(ts) session ($BENCH_LABEL)"
  (cd "$dir" && env ${IMPL_ENV[@]+"${IMPL_ENV[@]}"} PYTHONPATH="$dir" claude -p \
"Your role instructions are in your system prompt; this is a replay session (see its last section). Work ONLY issue #$n, then stop.

The issue as filed:

$(cat "$case/issue.md")

$(runtime_note implementer "$IMPLEMENTER_PROVIDER" "$IMPLEMENTER_MODEL")" \
    --model "$IMPLEMENTER_MODEL" ${EFFORT_WORDS[@]+"${EFFORT_WORDS[@]}"} \
    --autocompact "$AUTOCOMPACT_TOKENS" --max-budget-usd "$BENCH_BUDGET_USD" \
    --append-system-prompt-file "$PROMPT_FILE" \
    --strict-mcp-config "${ISOLATION_FLAGS[@]}" --tools "$IMPLEMENTER_TOOLS" \
    --settings "$SETTINGS_FILE" --permission-mode auto \
    "${STREAM_FLAGS[@]}" 2>&1 < /dev/null | tee "$out/session.jsonl" | render_stream bench) \
    > "$out/session.log" || true
  sleep_if_rate_limited "$out/session.log"
  fi
  local usage; usage="$(grep '^usage: ' "$out/session.log" | tail -n 1 || true)"
  local cost turns ctx
  cost="$(printf '%s' "$usage" | sed -E -n 's/.* cost=\$?([0-9.]+).*/\1/p')"
  turns="$(printf '%s' "$usage" | sed -E -n 's/.* turns=([0-9]+).*/\1/p')"
  ctx="$(printf '%s' "$usage" | sed -E -n 's/.* ctx_peak=([0-9.]+)k.*/\1/p')"
  local subtype; subtype="$(jq -Rr 'fromjson? | select(.type == "result") | .subtype' "$out/session.jsonl" | tail -n 1 || true)"

  # What the agent produced: committed and uncommitted, new files included.
  # Frozen as a commit (agent.sha) before any scoring touches the tree.
  local commits
  if [ ! -s "$out/agent.sha" ]; then
    commits="$(git -C "$dir" rev-list --count "$prefix..HEAD")"
    echo "$commits" > "$out/agent.commits"
    git -C "$dir" add -A
    git -C "$dir" diff --cached --quiet || git -C "$dir" commit -qm "bench: uncommitted agent work"
    git -C "$dir" rev-parse HEAD > "$out/agent.sha"
  fi
  commits="$(cat "$out/agent.commits")"
  git -C "$dir" diff "$prefix" "$(cat "$out/agent.sha")" > "$out/agent.patch"
  local recall
  recall="$(jq -r '.fix_files[] | select(startswith("tests/") | not)' "$case/meta.json" | sort > "$out/real.files"
            git -C "$dir" diff --name-only "$prefix" "$(cat "$out/agent.sha")" | sort > "$out/agent.files"
            r=$(wc -l < "$out/real.files"); h=$(comm -12 "$out/real.files" "$out/agent.files" | wc -l)
            [ "$r" -eq 0 ] && echo null || awk -v h="$h" -v r="$r" 'BEGIN{printf "%.2f", h/r}')"

  echo "$tag $(ts) scoring"
  local newfail
  newfail="$(comm -13 "$base" <(pytest_failures "$dir") | tee "$out/new-failures.txt" | wc -l | tr -d ' ')"

  # The real fix's tests against the agent's code: those test files go back
  # to their pre-fix state and take the real fix's test hunks, so the agent's
  # own edits to the same files are replaced (its other test files stay). A
  # fix that implements the same behavior under different names fails these
  # without being wrong, which is why this informs the judge, not the verdict.
  local hidden=none
  if [ -s "$case/tests.patch" ]; then
    local -a tfiles=(); while IFS= read -r f; do tfiles+=("$f"); done < <(jq -r '.test_files[]' "$case/meta.json")
    for f in "${tfiles[@]}"; do
      if git -C "$dir" cat-file -e "$prefix:$f" 2>/dev/null; then git -C "$dir" checkout -q "$prefix" -- "$f"; else rm -f "$dir/$f"; fi
    done
    if git -C "$dir" apply "$case/tests.patch" >/dev/null 2>&1; then
      local -a present=(); for f in "${tfiles[@]}"; do [ -e "$dir/$f" ] && present+=("$f"); done
      comm -13 "$base" <(pytest_failures "$dir" "${present[@]}") > "$out/hidden-failures.txt" || true
      if [ -s "$out/hidden-failures.txt" ]; then hidden=fail; else hidden=pass; fi
    else hidden=conflict; fi
  fi

  echo "$tag $(ts) judging"
  local jprompt="You are judging a replayed bug fix. An implementer agent was given the issue below at the commit just before the real fix, and produced the candidate diff. The real fix was verified by an independent tester over the live MCP interface. Decide whether the candidate would have passed that verification.

pass: fixes what the issue describes, as completely as the real fix does in substance (names and structure may differ).
partial: fixes some of it, or fixes it with a gap the tester would plausibly have bounced.
fail: does not fix it, is wrong, or breaks something else.
An escalation or needs-info in HANDOFF.md instead of a fix is 'pass' only if the issue genuinely required it, and the real fix shows otherwise here.

$(jq -r '"Case note: \(.note)"' "$case/meta.json")

=== ISSUE ===
$(cat "$case/issue.md" | cap 8000)

=== REAL FIX (verified) ===
$(cat "$case/fix.patch" | cap 60000)

=== TESTER'S LAST COMMENT ===
$(cat "$case/verify.md" | cap 4000)

=== CANDIDATE DIFF ($commits commit(s)) ===
$(cat "$out/agent.patch" | cap 60000)

=== CANDIDATE HANDOFF.md ===
$(cat "$dir/HANDOFF.md" 2>/dev/null | cap 4000)

=== MECHANICAL SIGNALS ===
new test failures vs pre-fix: $newfail
real fix's tests on candidate tree: $hidden
share of real fix's non-test files touched: $recall

End your answer with exactly one line of JSON: {\"verdict\": \"pass|partial|fail\", \"reason\": \"<one or two sentences>\"}"
  local jout
  # A judge call normally takes ~15 s; one hung for 10+ minutes on
  # 2026-09-23, so it is bounded. A timeout leaves verdict "error", which a
  # BENCH_RESCORE run replaces.
  jout="$(cd "$out" && env ${JUDGE_ENV[@]+"${JUDGE_ENV[@]}"} perl -e 'alarm shift; exec @ARGV' "$JUDGE_TIMEOUT_SECS" claude -p "$jprompt" --model "$JUDGE_MODEL" \
            --max-budget-usd "$JUDGE_BUDGET_USD" --strict-mcp-config "${ISOLATION_FLAGS[@]}" --tools "" \
            --output-format json < /dev/null 2>/dev/null || true)"
  printf '%s\n' "$jout" > "$out/judge.json"
  local verdict
  verdict="$(printf '%s' "$jout" | jq -r '.result // ""' 2>/dev/null | grep -o '{"verdict".*}' | tail -n 1 || true)"
  printf '%s' "$verdict" | jq -e .verdict >/dev/null 2>&1 || verdict=""
  [ -n "$verdict" ] || verdict='{"verdict":"error","reason":"judge produced no verdict line"}'

  jq -cn --arg label "$BENCH_LABEL" --argjson issue "$n" --arg kind "$(jq -r .kind "$case/meta.json")" \
    --arg model "$IMPLEMENTER_MODEL" --arg provider "$IMPLEMENTER_PROVIDER" --arg effort "$IMPLEMENTER_EFFORT" \
    --arg prompt "$PROMPT_ID" --arg judge "$JUDGE_MODEL" --arg at "$(date -u +%FT%TZ)" \
    --arg resolved "$(jq -Rr 'fromjson? | select(.subtype == "init") | .model' "$out/session.jsonl" | head -n 1 || true)" \
    --arg subtype "$subtype" --argjson commits "$commits" --argjson newfail "$newfail" \
    --arg hidden "$hidden" --argjson recall "$recall" --argjson v "$verdict" \
    --argjson cost "${cost:-0}" --argjson turns "${turns:-0}" --arg ctx "$ctx" \
    '{label: $label, issue: $issue, kind: $kind, model: $model, resolved_model: $resolved, provider: $provider,
      effort: $effort, prompt: $prompt, judge: $judge, at: $at,
      cost: $cost, turns: $turns, ctx_peak_k: ($ctx | tonumber? // null), budget_hit: ($subtype == "error_max_budget_usd"),
      result: $subtype, commits: $commits, new_failures: $newfail, hidden: $hidden, file_recall: $recall,
      verdict: $v.verdict, reason: $v.reason}' >> "$RESULTS"
  echo "$tag $(ts) $(tail -n 1 "$RESULTS" | jq -r '"\(.verdict) — new_failures=\(.new_failures) hidden=\(.hidden) recall=\(.file_recall) $\(.cost) \(.turns) turns"')"
}

if [ "${1:-}" = --one ]; then run_case "$2"; exit 0; fi

cases=("$@")
if [ "${#cases[@]}" -eq 0 ]; then
  for d in "$BENCH"/cases/*/; do cases+=("$(basename "$d")"); done
fi
echo "=== $(ts) bench: $BENCH_LABEL, ${#cases[@]} case(s), jobs=$BENCH_JOBS, work=$WORK ==="
if [ "$BENCH_JOBS" -le 1 ]; then
  for n in "${cases[@]}"; do run_case "$n"; done
else
  # Each child rebuilds its own prompt/settings files, so pass the resolved
  # label down to keep the rows of one run under one label.
  export BENCH_LABEL
  printf '%s\n' "${cases[@]}" | xargs -P "$BENCH_JOBS" -I{} "$0" --one {}
fi
summary "$BENCH_LABEL"
