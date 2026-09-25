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
done
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
finish
