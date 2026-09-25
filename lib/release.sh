# lib/release.sh: the pure parts of run-release.sh (roadmap R14 item 2), kept
# apart so tests/test-release.sh can run them offline. Sourced after
# providers.sh; nothing here calls gh, git or ssh.
#
# State lives on the release issue as marker comments, one per gate result:
#
#   <!-- harnest:release-gate <gate> <sha> <result> -->
#
# gate    check | ci | preflight | regression | review | notes | security
# sha     the full origin/develop commit it ran against
# result  pass | fail | accepted
#
# `accepted` is Don's decision recorded by `run-release.sh <v> accept`: a gate
# that failed or ran on an earlier commit, taken as good enough for this one.
# A later marker for the same gate and commit replaces an earlier one.

RELEASE_GATES_FOR_CUT="check ci preflight regression review notes security"

# release_marker <gate> <sha> <result>
release_marker() {
  printf '<!-- harnest:release-gate %s %s %s -->\n' "$1" "$2" "$3"
}

# release_gate_results
# stdin: the release issue's comments as `gh issue view --json comments`
# gives them. stdout: "<gate> <sha> <result>" per gate and commit, the latest
# marker winning.
release_gate_results() {
  jq -r '.comments[]?.body' \
    | sed -n 's/^<!-- harnest:release-gate \([a-z-]*\) \([0-9a-f]*\) \([a-z]*\) -->.*/\1 \2 \3/p' \
    | awk '{ key = $1 " " $2; last[key] = $3; if (!(key in order)) { order[key] = ++n; keys[n] = key } }
           END { for (i = 1; i <= n; i++) print keys[i], last[keys[i]] }'
}

# release_gate_ok <gate> <sha>
# stdin: release_gate_results output. True when the gate passed, or was
# accepted, on exactly this commit.
release_gate_ok() {
  awk -v g="$1" -v s="$2" '$1 == g && $2 == s && ($3 == "pass" || $3 == "accepted") { ok = 1 } END { exit !ok }'
}

# release_missing_gates <sha>
# stdin: release_gate_results output. stdout: each gate cut needs that has
# not passed or been accepted on <sha>, space-separated.
release_missing_gates() {
  local results gate missing=""
  results="$(cat)"
  for gate in $RELEASE_GATES_FOR_CUT; do
    printf '%s\n' "$results" | release_gate_ok "$gate" "$1" || missing="$missing $gate"
  done
  printf '%s\n' "${missing# }"
}

# release_board_problems <release_issue>
# stdin: classify_issues rows (number, queue, parent, reason; tab-separated).
# stdout: one line per reason the board isn't ready to release. Work in
# flight - a fix waiting on verification or review, a feature stage being
# built, an issue no queue will pick up - lands in the release half-done.
# Issues held by the freeze, or with Don, are not in flight.
release_board_problems() {
  awk -F'\t' -v rel="$1" '
    $1 == rel { next }
    $2 == "tester:verify" || $2 == "reviewer:docs" { print "#" $1 " waits on verification (" $2 ")"; next }
    $2 == "lead:build" || ($2 == "wait" && $4 == "building") { print "#" $1 " is a feature being built"; next }
    $2 == "stranded" { print "#" $1 " is stranded: " $4; next }
    $2 == "implementer:fix" || $2 == "tester:handoff" || $2 == "tester:answer" || $2 == "tester:spec" { print "#" $1 " is open work in " $2 " (a release-blocker)"; next }
  '
}

# release_findings_valid <file>
# A review session's findings: a JSON array of objects with area, severity
# (blocker | follow-up), security (bool), title, file, detail. True when the
# file is exactly that; an empty array is valid (the area is clean).
release_findings_valid() {
  jq -e 'type == "array" and all(.[];
          type == "object"
          and (.area | type == "string")
          and (.severity == "blocker" or .severity == "follow-up")
          and (.security | type == "boolean")
          and (.title | type == "string" and length > 0)
          and (.file | type == "string")
          and (.detail | type == "string" and length > 0))' "$1" >/dev/null 2>&1
}

# release_insert_notes <releasing_md> <version> <section_file>
# Puts "### <version>" plus the section's body under "## Unreleased" in
# docs/RELEASING.md, replacing an existing "### <version>" section (a
# redraft) rather than adding a second one. The section file holds the body
# only, without the heading.
release_insert_notes() {
  python3 - "$1" "$2" "$3" <<'PYEOF'
import re, sys
path, version, section = sys.argv[1], sys.argv[2], open(sys.argv[3]).read().strip("\n")
text = open(path).read()
block = f"### {version}\n\n{section}\n\n"
existing = re.compile(r"^### " + re.escape(version) + r"\n.*?(?=^### |^## |\Z)", re.M | re.S)
if existing.search(text):
    text = existing.sub(lambda m: block, text, count=1)
else:
    unreleased = re.search(r"^## Unreleased\n", text, re.M)
    if not unreleased:
        sys.exit("no '## Unreleased' heading in " + path)
    rest = text[unreleased.end():]
    first = re.search(r"^### |^## ", rest, re.M)
    at = unreleased.end() + (first.start() if first else len(rest))
    text = text[:at] + block + text[at:]
open(path, "w").write(text)
PYEOF
}

# release_notes_section <releasing_md> <version>
# stdout: the body of the "### <version>" section, for the PR and release.
release_notes_section() {
  awk -v h="### $2" '
    $0 == h { on = 1; next }
    on && (/^### / || /^## /) { exit }
    on { print }
  ' "$1" | sed -e '/./,$!d'
}
