#!/usr/bin/env bash
# Cut a diffusers-workflow release in stages (roadmap R14 item 2). Don runs
# each stage; the script records what passed on the release issue, so a stage
# can be rerun or resumed, and `cut` refuses until every gate has passed on
# the exact commit it merges.
#
#   ./run-release.sh 0.5.0 freeze             # open the release issue: the loop now moves only release-blockers
#   ./run-release.sh 0.5.0 check              # board clear, lem on develop, master merges cleanly
#   ./run-release.sh 0.5.0 review             # four read-only reviews of master...develop; blockers become issues
#   ./run-release.sh 0.5.0 notes              # draft the release notes onto a branch for Don to merge
#   ./run-release.sh 0.5.0 gates              # CI + CodeQL, preflight, regression (the loop must be stopped)
#   ./run-release.sh 0.5.0 gates preflight    # just one
#   ./run-release.sh 0.5.0 accept regression "filed #470-#472, all suite drift"
#   ./run-release.sh 0.5.0 accept check --waive 474,497 "stage 1 ships alone; v2 in 0.6"
#   ./run-release.sh 0.5.0 status             # what has passed on which commit
#   ./run-release.sh 0.5.0 cut --next 0.6.0-alpha.1   # PR, CI, merge, tag, notes, reopen develop, lift the freeze
#
# The usual order is freeze, check, review (the loop fixes what it files),
# notes, then stop the loop (touch logs/stop-after-cycle) and run gates and
# cut. Every gate is keyed to the full origin/develop commit it ran on. A fix
# after gates moves develop, and cut then asks for the gates again on the new
# commit - or for `accept <gate> <reason>`, which records that Don took an
# earlier run as good enough. Two things save most of that:
# - review, security and regression carry forward by themselves across
#   commits release_carry_ok allows (the notes merge for all three; a
#   verified release-blocker's fix for review and security);
# - `accept check --waive <n>,...` waives a known problem for the rest of
#   the release, so check passes on the next commit without another accept.
# ci and preflight are automatic, so they always rerun.
#
# Security findings from `review` never reach the public tracker: each is
# filed as a private draft security advisory (scripts/file-advisory.sh, R14
# item 3), and the release issue gets only their count. `cut` refuses while
# one is a blocker, unless `accept security` says otherwise.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"
# A detached worktree of SOURCE_DIR the release works in - review reads it,
# preflight runs in it - so neither SOURCE_DIR's branch nor Don's own
# checkout is ever touched. Reset to the commit under test each time.
RELEASE_TREE="${RELEASE_TREE:-$HOME/src/dkackman/dw-agent-release}"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
TICKET_OWNER="${TICKET_OWNER:-dkackman}"
HARNESS_REPO="${HARNESS_REPO:-dkackman/harnest}"   # where suite-drift requests go
LOGS="$REPO/logs"
PROVIDER="${PROVIDER:-anthropic}"
# Review and notes are judgment on the whole release, so they run on the
# tester's strong model by default, as the lead and curator do.
RELEASE_MODEL="${RELEASE_MODEL:-${TESTER_MODEL:-claude-opus-5-5}}"
RELEASE_PROVIDER="${RELEASE_PROVIDER:-${TESTER_PROVIDER:-$PROVIDER}}"
# Per area; the 0.4.0 review ran four areas at about 630k subagent tokens.
RELEASE_REVIEW_BUDGET_USD="${RELEASE_REVIEW_BUDGET_USD:-8}"
RELEASE_NOTES_BUDGET_USD="${RELEASE_NOTES_BUDGET_USD:-3}"
# Security and complete gated 0.4.0. model-specific is opt-in and GPU-heavy.
RELEASE_REGRESSION_LEVELS="${RELEASE_REGRESSION_LEVELS:-security complete}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"
AUTOCOMPACT_TOKENS="${AUTOCOMPACT_TOKENS:-120000}"

usage() { sed -n 's/^#   \(\.\/run-release\.sh.*\)/  \1/p' "$0" >&2; exit 1; }
version="${1:-}"; stage="${2:-}"
[ -n "$version" ] && [ -n "$stage" ] || usage
version="${version#v}"
shift 2
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' \
  || { echo "not a version: $version" >&2; exit 1; }

[ -d "$SOURCE_DIR" ] || { echo "SOURCE_DIR not found: $SOURCE_DIR" >&2; exit 1; }
for tool in gh jq git python3; do
  command -v "$tool" >/dev/null || { echo "$tool not on PATH" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated" >&2; exit 1; }
mkdir -p "$LOGS"
. "$REPO/providers.sh"

# A release is gated on what lem runs: its check reads lem's commit, and
# its regression gate runs the levels there. DW_TARGET=local is for
# run-regression.sh by hand (harnest#15).
[ "$DW_TARGET" = lem ] || { echo "run-release.sh runs against lem only; DW_TARGET=$DW_TARGET is for run-regression.sh" >&2; exit 1; }
. "$REPO/lib/release.sh"
RELEASE_EFFORT="${RELEASE_EFFORT:-$EFFORT}"
# shellcheck disable=SC2034  # read by run_claude_session (providers.sh)
LAST_SESSION="$LOGS/.last-session.release"
WORK="$LOGS/release-$version"
mkdir -p "$WORK"
ts() { date '+%H:%M:%S'; }
say() { echo "[release $version] $*" | tee -a "$LOGS/loop.log"; }
die() { say "$*"; exit 1; }

# The open issue labeled `release` whose title names this version.
release_issue() {
  gh issue list --repo "$TICKET_REPO" --state open --label release --limit 20 \
    --json number,title --jq ".[] | select(.title | test(\"(^|[^0-9.])$(printf '%s' "$version" | sed 's/[.]/\\\\./g')([^0-9.]|\$)\")) | .number" \
    | head -n 1
}
need_release_issue() {
  # GitHub's issue list lags a just-created issue by a few seconds
  local tries=0
  REL="$(release_issue)"
  while [ -z "$REL" ] && [ "$tries" -lt 3 ]; do sleep 5; tries=$((tries + 1)); REL="$(release_issue)"; done
  [ -n "$REL" ] || die "no open issue labeled 'release' names $version: run '$0 $version freeze' first"
}
develop_sha() {
  git -C "$SOURCE_DIR" fetch -q origin master develop >/dev/null 2>&1 || true
  git -C "$SOURCE_DIR" rev-parse origin/develop
}
gate_results() {
  gh issue view "$REL" --repo "$TICKET_REPO" --json comments | release_gate_results
}
# record <gate> <sha> <result> <text>
record() {
  gh issue comment "$REL" --repo "$TICKET_REPO" --body "$(release_marker "$1" "$2" "$3")
**$1: $3** on \`${2:0:10}\` ($(date '+%Y-%m-%d %H:%M')). $4" >/dev/null
  say "$1: $3 on ${2:0:10}"
}
# carry_forward <sha>: records `carried` on <sha> for each carryable gate
# not already good there whose last pass or acceptance is on an ancestor,
# when release_carry_ok allows every commit since.
RELEASE_CARRY_GATES="review security regression"
carry_forward() {
  local sha="$1" results gate from lines ok bad
  results="$(gate_results)"
  ok="$(gh issue list --repo "$TICKET_REPO" --state closed --label release-blocker --limit 200 --json number,labels \
    --jq '[.[] | select(any(.labels[]; .name == "status:verified" or .name == "status:reviewed")) | .number] | map(tostring) | join(" ")' 2>/dev/null || true)"
  for gate in $RELEASE_CARRY_GATES; do
    printf '%s\n' "$results" | release_gate_ok "$gate" "$sha" && continue
    from="$(printf '%s\n' "$results" | awk -v g="$gate" '$1 == g && ($3 == "pass" || $3 == "accepted" || $3 == "carried") { s = $2 } END { print s }')"
    [ -n "$from" ] && [ "$from" != "$sha" ] || continue
    git -C "$SOURCE_DIR" merge-base --is-ancestor "$from" "$sha" 2>/dev/null || continue
    lines="$(git -C "$SOURCE_DIR" log --format='%H%x09%P%x09%s' "$from..$sha" | while IFS=$'\t' read -r c parents subj; do
      printf '%s\t%s\t%s\t%s\n' "$c" "$(echo "$parents" | wc -w | tr -d ' ')" "$subj" \
        "$(git -C "$SOURCE_DIR" diff-tree --no-commit-id --name-only -r "$c" | tr '\n' ' ' | sed 's/ $//')"
    done)"
    if bad="$(printf '%s\n' "$lines" | release_carry_ok "$gate" "$ok")"; then
      record "$gate" "$sha" carried "Carried from \`${from:0:10}\`: every commit since is the release notes or a verified release-blocker's fix$([ "$gate" = regression ] && echo " (regression: the notes only)").
$(printf '%s\n' "$lines" | awk -F'\t' '{ print "- " substr($1, 1, 10) " " $3 }')"
    else
      say "$gate: not carried from ${from:0:10}; it needs a run or an accept on ${sha:0:10} ($(printf '%s\n' "$bad" | head -3 | tr '\n' ';' | sed 's/;$//'))"
    fi
  done
}

# tree_at <sha>: RELEASE_TREE, detached at <sha>, clean
tree_at() {
  if [ ! -e "$RELEASE_TREE/.git" ]; then
    git -C "$SOURCE_DIR" worktree add --detach "$RELEASE_TREE" "$1" >/dev/null 2>&1 \
      || die "could not create the release worktree $RELEASE_TREE"
  fi
  git -C "$RELEASE_TREE" checkout -q --detach "$1" \
    && git -C "$RELEASE_TREE" reset -q --hard "$1" \
    && git -C "$RELEASE_TREE" clean -qfd -e venv -e node_modules \
    || die "could not reset $RELEASE_TREE to ${1:0:10}"
}

# loop_holder: prints who holds lem's driver lock when a live process
# other than this one does (the gates hold it themselves).
loop_holder() {
  local holder
  holder="$(cat "$LOGS/.driver.lock/owner" 2>/dev/null || true)"
  if [ -n "$holder" ] && [ "${holder%% *}" != "$$" ] && kill -0 "${holder%% *}" 2>/dev/null; then printf '%s\n' "$holder"; fi
}
# lem_at <sha>: prints what lem runs and succeeds when that is <sha>. When
# lem is behind and no loop holds the lock, deploys develop first: merging
# the release notes moves develop after the loop has stopped, and nothing
# else would redeploy it. A running loop redeploys develop itself each cycle.
lem_at() {
  local sha="$1" lem
  lem="$(deployed_head)"
  case "$lem" in *" @ "*) [ "${sha#"${lem##* @ }"}" = "$sha" ] || { echo "$lem"; return 0; } ;; esac
  if [ -z "$(loop_holder)" ]; then
    say "lem runs $lem, not origin/develop ${sha:0:10}: deploying develop" >&2
    deploy_target >&2 || true
    lem="$(deployed_head)"
    case "$lem" in *" @ "*) [ "${sha#"${lem##* @ }"}" = "$sha" ] || { echo "$lem"; return 0; } ;; esac
  fi
  echo "$lem"; return 1
}

stage_freeze() {
  REL="$(release_issue)"
  if [ -n "$REL" ]; then say "already frozen: #$REL"; return 0; fi
  REL="$(gh issue create --repo "$TICKET_REPO" --title "Release $version" \
    --label release --label owner:don \
    --body "Release freeze for $version (roadmap R14). While this is open, the agent loop moves only issues labeled \`release-blocker\`, and the tester's standing task is held. \`run-release.sh $version <stage>\` records each gate here; \`cut\` closes it." \
    | sed -n 's|.*/issues/\([0-9][0-9]*\)$|\1|p')"
  [ -n "$REL" ] || die "could not open the release issue"
  say "frozen: #$REL opened"
}

stage_check() {
  need_release_issue
  local sha problems="" board lem started unfinished waived
  sha="$(develop_sha)"
  board="$(classify_issues)" || die "could not read the issue board"
  started="$(gh issue list --repo "$TICKET_REPO" --state open --limit 300 --json number,subIssuesSummary \
    --jq '[.[] | select((.subIssuesSummary.completed // 0) > 0) | .number] | join(" ")')" \
    || die "could not read the features' stages"
  problems="$(printf '%s\n' "$board" | release_board_problems "$REL" "$started")"
  unfinished="$(git -C "$SOURCE_DIR" log --format='%h %s' origin/master..origin/develop \
    | release_open_with_commits "$(printf '%s\n' "$board" | cut -f1 | tr '\n' ' ')" \
        "$(printf '%s\n' "$problems" | sed -n 's/^#\([0-9][0-9]*\) .*/\1/p' | tr '\n' ' ')")"
  problems="$problems${problems:+${unfinished:+$'\n'}}$unfinished"
  waived="$(gh issue view "$REL" --repo "$TICKET_REPO" --json comments | release_waivers)"
  if [ -n "$waived" ] && [ -n "$problems" ]; then
    problems="$(printf '%s\n' "$problems" | release_drop_waived "$waived")"
  fi
  lem="$(lem_at "$sha")" \
    || problems="$problems${problems:+$'\n'}lem runs $lem, not origin/develop ${sha:0:10}"
  git -C "$SOURCE_DIR" merge-tree --write-tree origin/master origin/develop >/dev/null 2>&1 \
    || problems="$problems${problems:+$'\n'}origin/develop does not merge cleanly into origin/master"
  if [ -z "$problems" ]; then
    record check "$sha" pass "Board clear, lem on develop, and master merges cleanly.${waived:+ Waived: $(printf '#%s ' $waived | sed 's/ $//').}"
  else
    printf '%s\n' "$problems" | sed 's/^/  /'
    record check "$sha" fail "$(printf '\n%s\n' "$problems" | sed 's/^#/- #/; s/^\([a-z]\)/- \1/')"
    return 1
  fi
}

gate_ci() {
  local sha="$1" wf id conclusion failed=""
  for wf in ci.yml codeql.yml; do
    id="$(gh run list --repo "$TICKET_REPO" --workflow "$wf" --commit "$sha" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
    if [ -z "$id" ]; then
      gh workflow run "$wf" --repo "$TICKET_REPO" --ref develop >/dev/null || { failed="$failed $wf(dispatch)"; continue; }
      local tries=0
      while [ -z "$id" ] && [ "$tries" -lt 20 ]; do
        sleep 15; tries=$((tries + 1))
        id="$(gh run list --repo "$TICKET_REPO" --workflow "$wf" --commit "$sha" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
      done
      [ -n "$id" ] || { failed="$failed $wf(no-run)"; continue; }
    fi
    gh run watch "$id" --repo "$TICKET_REPO" --exit-status >/dev/null 2>&1 || true
    conclusion="$(gh run view "$id" --repo "$TICKET_REPO" --json conclusion --jq .conclusion)"
    [ "$conclusion" = success ] || failed="$failed $wf($conclusion)"
    say "ci: $wf run $id: $conclusion"
  done
  if [ -z "$failed" ]; then record ci "$sha" pass "CI and CodeQL succeeded on this commit."
  else record ci "$sha" fail "Failed:$failed."; return 1; fi
}

gate_preflight() {
  local sha="$1" log="$WORK/preflight-${1:0:10}.log" rc=0 dirty
  tree_at "$sha"
  ln -sfn "$SOURCE_DIR/venv" "$RELEASE_TREE/venv"
  ln -sfn "$SOURCE_DIR/ui/node_modules" "$RELEASE_TREE/ui/node_modules"
  # A fixture server left on e2e's port by an earlier run fails every spec
  local stale
  stale="$(lsof -tiTCP:8971 -sTCP:LISTEN 2>/dev/null || true)"
  [ -z "$stale" ] || kill $stale 2>/dev/null || true
  say "preflight: running in $RELEASE_TREE (log $log)"
  (cd "$RELEASE_TREE" && PATH="$SOURCE_DIR/venv/bin:$PATH" DW_E2E_PYTHON="$SOURCE_DIR/venv/bin/python" \
     scripts/preflight.sh) > "$log" 2>&1 || rc=$?
  # preflight's ruff steps rewrite files and still succeed; CI's check would fail on them
  dirty="$(git -C "$RELEASE_TREE" status --porcelain --untracked-files=no)"
  if [ "$rc" -eq 0 ] && [ -z "$dirty" ]; then
    record preflight "$sha" pass "$(grep -E 'passed|All preflight' "$log" | tail -4 | sed 's/^/    /')"
  else
    record preflight "$sha" fail "exit $rc$([ -n "$dirty" ] && printf '; ruff rewrote files:\n%s' "$dirty"). Log: $log"
    return 1
  fi
}

gate_regression() {
  local sha="$1" lem start level filed drift rc=0
  lem="$(lem_at "$sha")" || { record regression "$sha" fail "lem runs $lem, not ${sha:0:10}, and deploying develop did not change that."; return 1; }
  start="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  for level in $RELEASE_REGRESSION_LEVELS; do
    say "regression: $level on ${sha:0:10}"
    "$REPO/run-regression.sh" "$level" >> "$WORK/regression-${sha:0:10}.log" 2>&1 || rc=$?
  done
  # Every regression filed during the gate blocks, whichever server filed
  # it or holds it: a backend:mps regression blocks a release too (Don,
  # 2026-09-26; harnest#15).
  filed="$(gh issue list --repo "$TICKET_REPO" --state all --label regression --search "created:>=$start" \
    --json number,title --jq '.[] | "- #\(.number) \(.title)"')"
  # Stale suite text goes to the harness repo as a suite request, not a
  # ticket (agents/regression/core.md): listed, never counted
  drift="$(gh issue list --repo "$HARNESS_REPO" --state all --label suite --search "created:>=$start" \
    --json number,title --jq '.[] | "- '"$HARNESS_REPO"'#\(.number) \(.title)"' 2>/dev/null || true)"
  drift="${drift:+

Suite drift, filed as suite requests for the curator (not counted):
$drift}"
  if [ "$rc" -eq 0 ] && [ -z "$filed" ]; then
    record regression "$sha" pass "Levels: $RELEASE_REGRESSION_LEVELS, lem $lem. No tickets filed.$drift"
  else
    record regression "$sha" fail "Levels: $RELEASE_REGRESSION_LEVELS, lem $lem, exit $rc. Filed:
$filed$drift

Suite drift is not a blocker: \`run-release.sh $version accept regression <why>\` records that."
    return 1
  fi
}

stage_gates() {
  need_release_issue
  local sha holder results gates="${1:-ci preflight regression}" gate failed=0
  sha="$(develop_sha)"
  holder="$(loop_holder)"
  if [ -n "$holder" ]; then
    die "the driver lock is held by '${holder#* }' (pid ${holder%% *}): the regression gate needs lem to itself. Stop it with 'touch logs/stop-after-cycle' and rerun."
  fi
  # Held for the whole stage, not checked once: a loop started between
  # preflight and regression would otherwise redeploy lem under the gate.
  # run-regression.sh runs under it (HARNEST_HELD_LOCK).
  acquire_driver_lock run-release
  export HARNEST_HELD_LOCK="$$ run-release"
  carry_forward "$sha"
  results="$(gate_results)"
  for gate in $gates; do
    if [ "${RELEASE_FORCE:-0}" != 1 ] && printf '%s\n' "$results" | release_gate_ok "$gate" "$sha"; then
      say "$gate: already passed on ${sha:0:10} (RELEASE_FORCE=1 to rerun)"; continue
    fi
    case "$gate" in
      ci) gate_ci "$sha" || failed=1 ;;
      preflight) gate_preflight "$sha" || failed=1 ;;
      regression) gate_regression "$sha" || failed=1 ;;
      *) die "unknown gate: $gate (ci, preflight, regression)" ;;
    esac
  done
  return "$failed"
}

# run_review_session <kind> <tag> <budget> <instructions>
run_release_session() {
  local kind="$1" tag="$2" budget="$3" instructions="$4" prompt_file
  prompt_file="$(role_prompt release "$kind" "$LOGS/.prompt.release.$kind.md")" || return 1
  resolve_model_env "$RELEASE_PROVIDER" "$RELEASE_MODEL" || return 1
  session_flags "$RELEASE_PROVIDER" "$RELEASE_MODEL" "$RELEASE_EFFORT" "$budget" || return 1
  SESSION_HEADER="release $version: $tag" run_claude_session "release:$tag" release "$RELEASE_TREE" "$prompt_file" \
    "Tickets are GitHub Issues on $TICKET_REPO. $instructions Your working directory is a detached worktree of the diffusers-workflow source at the release candidate, origin/develop $(git -C "$RELEASE_TREE" rev-parse --short HEAD); read it, never edit it. Then stop.

$(runtime_note release "$RELEASE_PROVIDER" "$RELEASE_MODEL")" \
    "${SESSION_FLAGS[@]}" "${ISOLATION_FLAGS_RELEASE[@]}" --tools "$RELEASE_TOOLS" "${RELEASE_PERMISSION_FLAGS[@]}"
}

REVIEW_AREAS="security engine mcp-and-docs templates-ui-packaging"

stage_review() {
  need_release_issue
  local sha area out bad="" findings="$WORK/findings.json" filed="" blockers=0 sec=0 secblock=0 base
  sha="$(develop_sha)"
  tree_at "$sha"
  base="$(git -C "$SOURCE_DIR" merge-base origin/master "$sha")"
  for area in $REVIEW_AREAS; do
    out="$WORK/review-$area-${sha:0:10}.json"
    if [ -s "$out" ] && release_findings_valid "$out" && [ "${RELEASE_FORCE:-0}" != 1 ]; then
      say "review: $area already done on ${sha:0:10}"; continue
    fi
    rm -f "$out"
    run_release_session review "review:$area" "$RELEASE_REVIEW_BUDGET_USD" \
      "This is a REVIEW session for area '$area' of release $version: the whole diff ${base:0:10}..${sha:0:10} (master...develop). Write your findings, as your role instructions say, to exactly this file: $out" || true
    release_findings_valid "$out" || bad="$bad $area"
  done
  if [ -n "$bad" ]; then
    record review "$sha" fail "No valid findings file for:$bad. Rerun \`review\` (areas already done are kept)."
    return 1
  fi
  jq -s 'add' "$WORK"/review-*-"${sha:0:10}".json > "$findings"
  # Security findings go to private draft advisories, never the public
  # tracker (R14 item 3). A blocker is filed high, a follow-up low; Don
  # reassesses either in the advisory.
  sec="$(jq '[.[] | select(.security)] | length' "$findings")"
  secblock="$(jq '[.[] | select(.security and .severity == "blocker")] | length' "$findings")"
  local j=0 advisories="" adv_desc="$WORK/advisory.md" adv_url severity
  while [ "$j" -lt "$sec" ]; do
    jq -r --argjson j "$j" --arg v "$version" --arg s "${sha:0:10}" --arg m "$RELEASE_MODEL" \
      '[.[] | select(.security)][$j] | "Found by the \($v) release review on develop \($s) (\(.area), \(.severity)), model \($m).\n\n**Where:** \(.file)\n\n\(.detail)"' \
      "$findings" > "$adv_desc"
    severity="$(jq -r --argjson j "$j" '[.[] | select(.security)][$j] | if .severity == "blocker" then "high" else "low" end' "$findings")"
    adv_url="$(TICKET_REPO="$TICKET_REPO" SOURCE_DIR="$SOURCE_DIR" "$REPO/scripts/file-advisory.sh" \
      --summary "$version review: $(jq -r --argjson j "$j" '[.[] | select(.security)][$j].title' "$findings")" \
      --description-file "$adv_desc" --severity "$severity")" \
      || { cp "$findings" "$WORK/security-unfiled.json"; die "review: could not file a security advisory; the findings are in $WORK/security-unfiled.json, not on GitHub"; }
    advisories="$advisories ${adv_url##*/}"
    j=$((j + 1))
  done
  rm -f "$adv_desc"
  local i=0 n title body labels existing
  n="$(jq '[.[] | select(.security | not)] | length' "$findings")"
  # A counter, not seq: BSD seq counts down, so `seq 0 -1` is "0 -1"
  while [ "$i" -lt "$n" ]; do
    title="$(jq -r --argjson i "$i" '[.[] | select(.security | not)][$i] | "[\(.area)] \(.title)"' "$findings")"
    body="$(jq -r --argjson i "$i" --arg v "$version" --arg m "$RELEASE_MODEL" '[.[] | select(.security | not)][$i] |
      "Found by the \($v) release review (\(.area), \(.severity)), model \($m).\n\n**Where:** \(.file)\n\n\(.detail)"' "$findings")"
    labels="owner:implementer"
    if [ "$(jq -r --argjson i "$i" '[.[] | select(.security | not)][$i].severity' "$findings")" = blocker ]; then
      labels="$labels,release-blocker"; blockers=$((blockers + 1))
    fi
    existing="$(gh issue list --repo "$TICKET_REPO" --state open --search "in:title \"$title\"" --json number,title \
      --jq ".[] | select(.title == $(jq -Rn --arg t "$title" '$t')) | .number" | head -n 1)"
    if [ -n "$existing" ]; then filed="$filed #$existing(existing)"; i=$((i + 1)); continue; fi
    filed="$filed $(gh issue create --repo "$TICKET_REPO" --title "$title" --body "$body" --label "$labels" | sed -n 's|.*/issues/\([0-9][0-9]*\)$|#\1|p')"
    i=$((i + 1))
  done
  record review "$sha" pass "Areas: $REVIEW_AREAS. Filed:${filed:- nothing} ($blockers blocker(s)). Security: $sec finding(s), $secblock blocker(s), filed as private draft advisories."
  [ -z "$advisories" ] || say "review: draft advisories:$advisories"
  if [ "$secblock" -eq 0 ]; then record security "$sha" pass "No security blocker."
  else record security "$sha" fail "$secblock security blocker(s), in private draft advisories. Fix them out of band, then rerun review or \`accept security\`."; fi
}

stage_notes() {
  need_release_issue
  local sha tag since issues out="$WORK/notes.md" wt branch="release/$version-notes"
  sha="$(develop_sha)"
  tree_at "$sha"
  tag="$(git -C "$SOURCE_DIR" describe --tags --abbrev=0 origin/master)"
  # From when the last release was published, not its tag's commit: issues
  # closed between the two are in that release's notes (0.5.0's list carried
  # two dozen of 0.4.0's)
  since="$(gh release view "$tag" --repo "$TICKET_REPO" --json publishedAt --jq .publishedAt 2>/dev/null)" \
    || since="$(git -C "$SOURCE_DIR" log -1 --format=%cI "$tag")"
  issues="$(gh issue list --repo "$TICKET_REPO" --state closed --limit 300 --search "closed:>=$since reason:completed" \
    --json number,title,labels --jq '.[] | "#\(.number) [\([.labels[].name] | join(","))] \(.title)"')"
  printf '%s\n' "$issues" > "$WORK/closed-since-$tag.txt"
  # What ships without a closed issue: PRs merged into develop (0.5.0's
  # Mac support was one), and open issues develop carries commits for
  gh pr list --repo "$TICKET_REPO" --state merged --base develop --limit 200 --search "merged:>=$since" \
    --json number,title --jq '.[] | "PR #\(.number) \(.title)"' > "$WORK/merged-prs-since-$tag.txt" || true
  git -C "$SOURCE_DIR" log --format='%h %s' "$tag..$sha" \
    | release_open_with_commits "$(gh issue list --repo "$TICKET_REPO" --state open --limit 300 --json number --jq '[.[].number] | join(" ")')" \
    > "$WORK/open-with-commits.txt" || true
  rm -f "$out"
  run_release_session notes notes "$RELEASE_NOTES_BUDGET_USD" \
    "This is a NOTES session for release $version: draft its section of docs/RELEASING.md. The last release is $tag. What shipped since then is listed one per line in three files: the issues closed as completed in $WORK/closed-since-$tag.txt, the pull requests merged into develop in $WORK/merged-prs-since-$tag.txt, and the issues still open whose commits are in this candidate in $WORK/open-with-commits.txt (describe what their commits ship, and say they are unfinished). Write the section body (no heading) to exactly this file: $out" || true
  [ -s "$out" ] || die "notes: the session wrote nothing to $out"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/release-notes.XXXXXX")"
  git -C "$SOURCE_DIR" worktree add -q --detach "$wt" "$sha"
  release_insert_notes "$wt/docs/RELEASING.md" "$version" "$out"
  git -C "$wt" commit -qm "docs: $version release notes (drafted by run-release.sh notes)" -- docs/RELEASING.md
  git -C "$wt" push -q -f origin "HEAD:refs/heads/$branch"
  git -C "$SOURCE_DIR" worktree remove --force "$wt"
  say "notes: drafted on branch $branch - edit it, then merge it into develop: https://github.com/$TICKET_REPO/compare/develop...$branch"
}

stage_accept() {
  need_release_issue
  local gate="${1:-}" why sha waive="" n markers=""
  shift || true
  if [ "${1:-}" = --waive ]; then
    [ "$gate" = check ] || die "--waive is for check: it names the issues check stops reporting"
    waive="$(printf '%s' "${2:-}" | tr -c '0-9' ' ')"; shift 2 || true
    [ -n "${waive// /}" ] || die "usage: $0 $version accept check --waive <n>[,<n>...] <why>"
  fi
  why="${1:-}"
  [ -n "$gate" ] && [ -n "$why" ] || die "usage: $0 $version accept <gate> [--waive <n>,...] <why>"
  case " $RELEASE_GATES_FOR_CUT " in *" $gate "*) ;; *) die "no gate '$gate' ($RELEASE_GATES_FOR_CUT)" ;; esac
  sha="$(develop_sha)"
  if [ -n "${waive// /}" ]; then
    for n in $waive; do markers="$markers$(release_waive_marker "$n")"$'\n'; done
    gh issue comment "$REL" --repo "$TICKET_REPO" --body "$markers**check waives $(printf '#%s ' $waive | sed 's/ $//')** for the rest of $version: $why" >/dev/null
    say "check: waived $(printf '#%s ' $waive | sed 's/ $//') for the rest of the release"
  fi
  record "$gate" "$sha" accepted "Accepted by Don: $why"
}

stage_status() {
  need_release_issue
  local sha results waived
  sha="$(develop_sha)"
  carry_forward "$sha"
  results="$(gate_results)"
  echo "Release $version: issue #$REL, origin/develop ${sha:0:10}"
  local gate state
  for gate in $RELEASE_GATES_FOR_CUT; do
    state="$(printf '%s\n' "$results" | awk -v g="$gate" -v s="$sha" '$1 == g && $2 == s { r = $3 } END { print r }')"
    if [ -z "$state" ]; then
      state="$(printf '%s\n' "$results" | awk -v g="$gate" '$1 == g { r = $3 " on " substr($2, 1, 10) } END { print (r ? "not run here; last " r : "not run") }')"
    fi
    printf '  %-11s %s\n' "$gate" "$state"
  done
  waived="$(gh issue view "$REL" --repo "$TICKET_REPO" --json comments | release_waivers)"
  [ -z "$waived" ] || printf '  %-11s %s\n' waived "$(printf '#%s ' $waived | sed 's/ $//') (check ignores them)"
  printf '  %-11s %s\n' notes "$(git -C "$SOURCE_DIR" show "$sha:docs/RELEASING.md" 2>/dev/null | grep -q "^### $version\$" && echo present || echo "missing on develop")"
  echo "  open release-blockers: $(gh issue list --repo "$TICKET_REPO" --state open --label release-blocker --json number --jq '[.[].number | "#\(.)"] | join(" ")')"
  local flags
  flags="$(cd "$LOGS" && ls stop-after-cycle* 2>/dev/null | tr '\n' ' ' || true)"
  [ -z "$flags" ] || echo "  stop flags: $flags(cut removes them)"
}

stage_cut() {
  need_release_issue
  local next="" sha missing blockers pr notes_file tag="v$version" master_wt tries
  [ "${1:-}" = --next ] && next="${2:-}"
  [ -n "$next" ] || die "usage: $0 $version cut --next <version develop opens next>"
  sha="$(develop_sha)"
  carry_forward "$sha"
  missing="$(gate_results | release_missing_gates "$sha")"
  [ -z "$missing" ] || die "cut: not passed or accepted on ${sha:0:10}: $missing (see '$0 $version status')"
  blockers="$(gh issue list --repo "$TICKET_REPO" --state open --label release-blocker --json number --jq '[.[].number | "#\(.)"] | join(" ")')"
  [ -z "$blockers" ] || die "cut: open release-blockers: $blockers"
  notes_file="$WORK/release-notes.md"
  git -C "$SOURCE_DIR" show "$sha:docs/RELEASING.md" > "$WORK/RELEASING.md"
  release_notes_section "$WORK/RELEASING.md" "$version" > "$notes_file"
  [ -s "$notes_file" ] || die "cut: docs/RELEASING.md on develop has no '### $version' section (run notes, merge its branch)"

  # Each step checks the real state first, so a cut that stopped part way is
  # rerun, not repaired by hand.
  if git -C "$SOURCE_DIR" merge-base --is-ancestor "$sha" origin/master; then
    say "cut: ${sha:0:10} is already on master"
  else
    pr="$(gh pr list --repo "$TICKET_REPO" --base master --head develop --state open --json number --jq '.[0].number // empty')"
    if [ -z "$pr" ]; then
      pr="$(gh pr create --repo "$TICKET_REPO" --base master --head develop --title "Release $version" \
        --body "$(printf 'Release %s, cut by run-release.sh from develop @ %s. Gates on the release issue #%s.\n\n' "$version" "${sha:0:10}" "$REL"; cat "$notes_file")" \
        | sed -n 's|.*/pull/\([0-9][0-9]*\)$|\1|p')"
      [ -n "$pr" ] || die "cut: could not open the PR"
    fi
    say "cut: PR #$pr - waiting for its checks"
    # A PR opened a moment ago has no checks registered yet, and
    # `gh pr checks` says so and fails rather than waiting
    tries=0
    until [ "$(gh pr checks "$pr" --repo "$TICKET_REPO" --json name --jq length 2>/dev/null || echo 0)" -gt 0 ]; do
      tries=$((tries + 1)); [ "$tries" -le 20 ] || die "cut: no checks registered on PR #$pr after 5 minutes"
      sleep 15
    done
    gh pr checks "$pr" --repo "$TICKET_REPO" --watch --fail-fast >/dev/null 2>&1 \
      || die "cut: PR #$pr checks did not pass"
    # No --delete-branch: the ruleset protects develop, and it is the head
    gh pr merge "$pr" --repo "$TICKET_REPO" --merge >/dev/null || die "cut: could not merge PR #$pr"
    git -C "$SOURCE_DIR" fetch -q origin master
    say "cut: PR #$pr merged"
  fi

  if git -C "$SOURCE_DIR" ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    say "cut: $tag already tagged"
  else
    master_wt="$WORK/master"
    [ -e "$master_wt/.git" ] || git -C "$SOURCE_DIR" worktree add -q "$master_wt" master 2>/dev/null \
      || git -C "$SOURCE_DIR" worktree add -q -B master "$master_wt" origin/master
    git -C "$master_wt" pull -q --ff-only origin master
    (cd "$master_wt" && scripts/release.sh "$version" --next "$next") || die "cut: release.sh failed (rerun cut: it resumes)"
    git -C "$SOURCE_DIR" worktree remove --force "$master_wt" || true
  fi

  tries=0
  until gh release view "$tag" --repo "$TICKET_REPO" >/dev/null 2>&1; do
    tries=$((tries + 1)); [ "$tries" -le 60 ] || die "cut: no GitHub release for $tag after 30 minutes (check the tag's CI, then rerun cut)"
    sleep 30
  done
  gh release edit "$tag" --repo "$TICKET_REPO" --notes-file "$notes_file" >/dev/null
  say "cut: $tag published with its notes"
  gh issue close "$REL" --repo "$TICKET_REPO" --reason completed \
    --comment "Released as $tag (https://github.com/$TICKET_REPO/releases/tag/$tag); develop reopened as $next. Freeze lifted." >/dev/null
  say "cut: #$REL closed - the freeze is lifted"
  # A stop flag touched for the freeze would stop the next loop after one
  # cycle (0.5.0 left logs/stop-after-cycle.local behind)
  local flag
  for flag in "$LOGS"/stop-after-cycle*; do
    [ -e "$flag" ] || continue
    rm -f "$flag"; say "cut: removed ${flag#"$REPO/"}, left from the freeze"
  done
}

# main: in a function, called with exit on the same line, so an edit to this
# file mid-run can't make bash resume at a stale offset.
main() {
case "$stage" in
  freeze) stage_freeze ;;
  check) stage_check ;;
  gates) stage_gates "$*" ;;
  review) stage_review ;;
  notes) stage_notes ;;
  accept) stage_accept "$@" ;;
  status) stage_status ;;
  cut) stage_cut "$@" ;;
  *) usage ;;
esac
}

main "$@"; exit
