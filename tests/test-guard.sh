#!/usr/bin/env bash
# agent-settings/hooks/guard.py as a table: role, session kind, command,
# and whether the guard lets it through (0) or refuses it (2). Every rule
# in the guard's docstring has a row. The hand-off gate is not here: it
# needs a checkout with a test suite.
. "$(dirname "$0")/lib.sh"
guard="$HARNEST/agent-settings/hooks/guard.py"
mcp_transcript="$T/with-mcp.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__dw__get_job"}]}}' > "$mcp_transcript"
# The needs-approval rule asks GitHub whether owner:don is on the issue:
# #7 has it, #8 doesn't.
stub_gh 'case "$*" in *"view 7"*) echo true ;; *"view 8"*) echo false ;; *) exit 1 ;; esac'

# row <expect> <role> <kind> <transcript> <command>
row() {
  local want="$1" role="$2" kind="$3" tr="$4" cmd="$5" rc
  jq -n --arg c "$cmd" --arg t "$tr" '{tool_name: "Bash", tool_input: {command: $c}, transcript_path: $t, cwd: "/tmp"}' \
    | HARNEST_SESSION_KIND="$kind" python3 "$guard" "$role" >/dev/null 2>&1
  rc=$?
  eq "$role${kind:+/$kind}: $cmd" "$want" "$rc"
}
none=/nonexistent
# every role: approval is Don's
for r in implementer lead consumer curator reviewer; do
  row 2 $r "" $none 'gh issue edit 5 --add-label status:plan-approved'
  row 2 $r "" $none 'gh issue edit 5 --add-label release-blocker'
  row 2 $r "" $none 'gh issue edit 5 --add-label bug,release'
  row 2 $r "" $none 'gh issue comment 5 --body "<!-- harnest:release-gate ci abc pass -->"'
  row 2 $r "" $none 'gh issue create --title "SE-F001 fails" --label owner:implementer,regression,security'
  row 2 $r "" $none 'gh issue edit 5 --add-label security'
done
row 0 consumer "" $none 'gh issue create --title "S-F001 fails" --label owner:implementer,regression'
row 0 consumer "" $none './scripts/file-advisory.sh --summary x --description-file y --severity high'
printf '%s\n' '<!-- harnest:release-gate regression abc pass -->' > "$T/marker.md"
row 2 consumer "" $none "gh issue comment 5 --body-file $T/marker.md"
row 0 consumer "" $none 'gh issue comment 5 --body "the release gates ran fine"'
# implementer and lead: closes, verified, parks, owners
for r in implementer lead; do
  row 2 $r "" $none 'gh issue close 5'
  row 2 $r "" $none 'gh issue close 5 --reason completed'
  row 0 $r "" $none 'gh issue close 5 --reason "not planned"'
  row 2 $r "" $none 'gh issue edit 5 --add-label status:verified'
  row 2 $r "" $none 'gh issue edit 5 --remove-label owner:don --add-label owner:implementer'
  row 2 $r "" $none 'gh issue edit 7 --remove-label status:needs-approval'
  row 0 $r "" $none 'gh issue edit 8 --remove-label status:needs-approval'
  row 2 $r "" $none 'gh issue edit 9 --remove-label status:needs-approval'
  row 2 $r "" $none 'gh issue edit 5 --add-label owner:tester'
  row 2 $r "" $none 'gh issue edit 5 --remove-label owner:x --add-label owner:tester,owner:don'
  row 0 $r "" $none 'gh issue edit 5 --remove-label owner:implementer --add-label owner:tester --add-label status:fixed-pending-verify'
  row 0 $r "" $none 'gh issue comment 5 --body "closing as completed later: gh issue close 5"'
done
# implementer only: pushes
row 2 implementer "" $none 'git push origin master'
row 2 implementer "" $none 'git push -f origin develop'
row 2 implementer "" $none 'git push origin +develop'
row 2 implementer "" $none 'git push origin :old-branch'
row 0 implementer "" $none 'git push origin develop'
row 0 lead "" $none 'git push origin master'
# consumer: verifying needs an MCP call; a handoff may close but not verify
row 2 consumer verify $none 'gh issue close 5 --reason completed'
row 0 consumer verify "$mcp_transcript" 'gh issue close 5 --reason completed'
row 2 consumer verify $none 'gh issue edit 5 --add-label status:verified'
row 0 consumer verify "$mcp_transcript" 'gh issue edit 5 --add-label status:verified'
row 0 consumer handoff $none 'gh issue close 5 --reason completed'
row 2 consumer handoff $none 'gh issue edit 5 --add-label status:verified'
row 0 consumer verify $none 'gh issue close 5 --reason "not planned"'
row 2 consumer verify $none 'gh issue edit 5 --add-label owner:implementer'
# curator: may escalate with a bare add, may never lift Don's owner
row 0 curator "" $none 'gh issue edit 4 --repo dkackman/harnest --add-label owner:don'
row 2 curator "" $none 'gh issue edit 4 --repo dkackman/harnest --remove-label owner:don'
row 0 curator "" $none 'gh issue close 4 --repo dkackman/harnest --reason completed'
# reviewer: closes a docs-only fix as completed with no MCP call, but never
# claims one (status:verified), and lifts no park
row 0 reviewer docs $none 'gh issue close 5 --reason completed'
row 0 reviewer docs $none 'gh issue edit 5 --remove-label status:fixed-pending-verify --remove-label docs-review --add-label status:reviewed'
row 2 reviewer docs $none 'gh issue edit 5 --add-label status:verified'
row 2 reviewer docs $none 'gh issue edit 5 --remove-label owner:don --add-label owner:implementer'
row 2 reviewer docs $none 'gh issue edit 7 --remove-label status:needs-approval'
row 2 reviewer docs $none 'gh issue edit 5 --add-label owner:implementer'
row 0 reviewer docs $none 'gh issue edit 5 --remove-label status:fixed-pending-verify --remove-label docs-review --remove-label owner:tester --add-label owner:implementer'
# not Bash: never looked at
jq -n '{tool_name: "Read", tool_input: {file_path: "/x"}}' | python3 "$guard" implementer >/dev/null 2>&1
eq "non-Bash tool passes" 0 $?

# --- a consumer on a server other than lem (HARNEST_TARGET; harnest#15)
# frow <expect> <target> <tool> <path, relative to a fake harness root> [role]
# role is HARNEST_ROLE: regression (the default) or tester
root="$T/root"; mkdir -p "$root/regression-perf/local"
frow() {
  jq -n --arg t "$3" --arg p "$root/$4" '{tool_name: $t, tool_input: {file_path: $p}, cwd: "/tmp"}' \
    | HARNEST_ROOT="$root" HARNEST_TARGET="$2" HARNEST_ROLE="${5:-regression}" python3 "$guard" consumer >/dev/null 2>&1
  eq "consumer(${5:-regression})@$2 $3 $4" "$1" $?
}
frow 2 local Edit  regression-suite-smoke.md
frow 2 local Write regression-suite-mps.md
frow 2 local Edit  regression-perf/S-P001.jsonl
frow 2 local Write regression-perf/other/S-P001.jsonl
frow 0 local Write regression-perf/local/S-P001.jsonl
frow 0 local Edit  regression-perf/local/S-P001.jsonl
frow 0 local Write qa-bible.md
frow 0 lem   Edit  regression-suite-smoke.md
frow 0 ""    Edit  regression-perf/S-P001.jsonl
# the Mac loop's tester may add a case for a shared fix; not perf history
frow 0 local Edit  regression-suite-smoke.md tester
frow 2 local Write regression-perf/S-P001.jsonl tester
jq -n --arg p "/tmp/S-F001-local-issue.md" '{tool_name: "Write", tool_input: {file_path: $p}, cwd: "/tmp"}' \
  | HARNEST_ROOT="$root" HARNEST_TARGET=local python3 "$guard" consumer >/dev/null 2>&1
eq "consumer@local: a write outside the harness passes" 0 $?
jq -n --arg p "$root/regression-suite-smoke.md" '{tool_name: "Edit", tool_input: {file_path: $p}, cwd: "/tmp"}' \
  | HARNEST_ROOT="$root" HARNEST_TARGET=local python3 "$guard" implementer >/dev/null 2>&1
eq "the target rule is the consumer's only" 0 $?
# trow <expect> <command>: gh on the local target
trow() {
  jq -n --arg c "$2" --arg t "${3:-/nonexistent}" '{tool_name: "Bash", tool_input: {command: $c}, transcript_path: $t, cwd: "/tmp"}' \
    | HARNEST_ROOT="$root" HARNEST_TARGET=local HARNEST_ROLE=tester python3 "$guard" consumer >/dev/null 2>&1
  eq "consumer@local: $2" "$1" $?
}
# a new issue names its backend (one this server can observe), an owner,
# and no claim: claims are the driver's
trow 0 'gh issue create --title "S-F070 fails" --label owner:implementer,backend:mps,regression --body-file /tmp/x'
trow 0 'gh issue create --title "S-F070 fails" -l owner:implementer -l backend:shared'
trow 2 'gh issue create --title "S-F070 fails" --label owner:implementer,regression'
trow 2 'gh issue create --title "S-F070 fails" --label owner:implementer,backend:cuda'
trow 2 'gh issue create --title "S-F070 fails" --label owner:implementer,backend:mps,target:local'
trow 2 'gh issue create --title "S-F070 fails" --label owner:don,owner:implementer,backend:mps'
trow 2 'gh issue create --title "S-F070 fails" --label owner:implementer,backend:mps,backend:shared'
# comments: the stub says #7 carries the asked-for label (target:lem here),
# #8 doesn't, and anything else is a gh failure
trow 2 'gh issue comment 7 --body "fails here too"'
trow 0 'gh issue comment 8 --body "also fails on local"'
trow 2 'gh issue comment 9 --body "gh cannot say"'
# a verification here says where it was verified; a claim moves only to lem
trow 2 'gh issue edit 5 --add-label status:verified' "$mcp_transcript"
trow 0 'gh issue edit 5 --add-label status:verified --add-label verified-on:mps' "$mcp_transcript"
trow 0 'gh issue edit 5 --remove-label target:local --add-label target:lem'
trow 2 'gh issue edit 5 --add-label target:local'
trow 2 'gh issue edit 5 --add-label target:lem'
# the implementer on the local target: no ssh anywhere, the cuda hand-over
irow() {
  jq -n --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}, cwd: "/tmp"}' \
    | HARNEST_TARGET=local python3 "$guard" implementer >/dev/null 2>&1
  eq "implementer@local: $2" "$1" $?
}
irow 2 'ssh lem uptime'
irow 2 'cd /x && ssh -o BatchMode=yes lem "~/diffusers-workflow/scripts/deploy.sh develop"'
irow 2 'FOO=1 ssh lem true'
irow 2 'rsync -a lem:/x /y'
irow 2 'scp lem:/x /y'
irow 0 'git push origin develop'
irow 0 'gh issue edit 5 --remove-label target:local --add-label target:lem'
irow 2 'gh issue edit 5 --add-label target:local'
# on lem nobody adds a claim or a verified-on label
row 2 implementer "" $none 'gh issue edit 5 --add-label target:lem'
row 2 consumer verify "$mcp_transcript" 'gh issue edit 5 --add-label status:verified,verified-on:mps'
row 0 implementer "" $none 'ssh lem uptime'
# rrow <expect> <command>: with the ticket repo named, as the driver sets it
rrow() {
  jq -n --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}, transcript_path: "/nonexistent", cwd: "/tmp"}' \
    | HARNEST_ROOT="$root" HARNEST_TARGET=local HARNEST_TICKET_REPO=o/r python3 "$guard" consumer >/dev/null 2>&1
  eq "consumer@local o/r: $2" "$1" $?
}
rrow 0 'gh issue create --repo o/r --title x --label owner:implementer,backend:mps,regression'
rrow 2 'gh issue create --title x --label owner:implementer,backend:mps,regression'
rrow 2 'gh issue create --repo dkackman/harnest --title x --label suite,status:needs-approval'
rrow 0 'gh issue comment 8 --repo o/r --body x'
rrow 2 'gh issue comment 8 --repo dkackman/harnest --body x'
rrow 0 'gh issue list --repo o/r --label target:local'
finish
