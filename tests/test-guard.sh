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
# The owner rule asks how many owner labels an issue has: #9 has none.
stub_gh 'case "$*" in *"view 7"*) echo true ;; *"view 8"*) echo false ;; *"view 9"*) echo 0 ;; *) exit 1 ;; esac'

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
  row 2 $r "" $none 'gh issue comment 5 --body "<!-- harnest:release-waive 474 -->"'
  row 2 $r "" $none 'gh issue create --title "SE-F001 fails" --label owner:implementer,regression,security'
  row 2 $r "" $none 'gh issue edit 5 --add-label security'
  row 2 $r "" $none 'gh issue create --title x --label feature,owner:lead,status:plan-approved'
  row 2 $r "" $none 'gh issue create --title x --label release'
  row 2 $r "" $none 'gh issue create --title x -l bug,release-blocker'
  row 2 $r "" $none 'gh issue create --title x --label status:verified'
  row 2 $r "" $none 'gh issue create --title x --label status:fixed-pending-verify'
done
# unbalanced quotes: the fallback keeps the rules (spec B.1)
row 2 consumer "" $none 'gh issue edit 5 --add-label "status:verified" # it'"'"'s done'
row 2 implementer "" $none 'gh issue edit 5 --remove-label owner:don # don'"'"'t'
row 2 lead "" $none 'gh issue comment 5 --body "$(cat <<EOF
<!-- harnest:release-gate ci abc pass --> it'"'"'s
EOF
)"'
row 0 consumer "" $none 'echo it'"'"'s fine'
row 2 consumer "" $none 'gh issue comment 5 --body it'"'"'s'
row 2 lead "" $none '(gh issue edit 5 --add-label status:plan-approved) # it'"'"'s'
row 2 lead "" $none 'echo a & gh issue edit 5 --add-label status:plan-approved # it'"'"'s'
row 2 lead "" $none '/usr/bin/gh issue edit 5 --add-label "bug, status:plan-approved" # it'"'"'s'
row 0 consumer "" $none 'gh issue create --title "S-F001 fails" --label owner:implementer,regression'
row 0 consumer "" $none './scripts/file-advisory.sh --summary x --description-file y --severity high'
printf '%s\n' '<!-- harnest:release-gate regression abc pass -->' > "$T/marker.md"
row 2 consumer "" $none "gh issue comment 5 --body-file $T/marker.md"
row 0 consumer "" $none 'gh issue comment 5 --body "the release gates ran fine"'
# no role lifts a park; an unknown role is refused
row 2 consumer "" $none 'gh issue edit 7 --remove-label owner:don --add-label owner:tester'
row 2 consumer "" $none 'gh issue edit 7 --remove-label status:needs-approval'
row 2 curator "" $none 'gh issue edit 7 --remove-label status:needs-approval'
row 2 bogus "" $none 'gh issue list'
row 2 "" "" $none 'gh issue list'
rc=0; printf 'not json' | HARNEST_SESSION_KIND= python3 "$guard" implementer >/dev/null 2>&1 || rc=$?
eq "guard: a crash refuses, never passes" 2 "$rc"
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
  row 0 $r "" $none 'gh issue edit 9 --add-label owner:tester'
  row 2 $r "" $none 'gh issue edit 9 --add-label owner:tester,owner:don'
  row 2 $r "" $none 'gh issue edit 7 --add-label owner:tester'
  # the first issue vetted, the edit landing on a second: refused
  row 2 $r "" $none 'gh issue edit 9 5 --add-label owner:tester'
  row 2 $r "" $none 'gh issue edit 9 https://github.com/o/r/issues/5 --add-label owner:tester'
  row 2 $r "" $none 'gh issue edit --title 9 5 --add-label owner:tester'
  row 2 $r "" $none 'gh issue edit 8 7 --remove-label status:needs-approval'
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
root="$T/root"; mkdir -p "$root/regression-perf/mini-ai"
frow() {
  jq -n --arg t "$3" --arg p "$root/$4" '{tool_name: $t, tool_input: {file_path: $p}, cwd: "/tmp"}' \
    | HARNEST_ROOT="$root" HARNEST_TARGET="$2" HARNEST_ROLE="${5:-regression}" python3 "$guard" consumer >/dev/null 2>&1
  eq "consumer(${5:-regression})@$2 $3 $4" "$1" $?
}
frow 2 mini-ai Edit  regression-suite-smoke.md
frow 2 mini-ai Write regression-suite-mps.md
frow 2 mini-ai Edit  regression-perf/S-P001.jsonl
frow 2 mini-ai Write regression-perf/other/S-P001.jsonl
frow 0 mini-ai Write regression-perf/mini-ai/S-P001.jsonl
frow 0 mini-ai Edit  regression-perf/mini-ai/S-P001.jsonl
frow 0 mini-ai Write qa-bible.md
frow 0 lem   Edit  regression-suite-smoke.md
frow 0 ""    Edit  regression-perf/S-P001.jsonl
# the Mac loop's tester may add a case for a shared fix; not perf history
frow 0 mini-ai Edit  regression-suite-smoke.md tester
frow 2 mini-ai Write regression-perf/S-P001.jsonl tester
jq -n --arg p "/tmp/S-F001-local-issue.md" '{tool_name: "Write", tool_input: {file_path: $p}, cwd: "/tmp"}' \
  | HARNEST_ROOT="$root" HARNEST_TARGET=mini-ai HARNEST_TARGET_HOST=mini-ai python3 "$guard" consumer >/dev/null 2>&1
eq "consumer@mini-ai: a write outside the harness passes" 0 $?
jq -n --arg p "$root/regression-suite-smoke.md" '{tool_name: "Edit", tool_input: {file_path: $p}, cwd: "/tmp"}' \
  | HARNEST_ROOT="$root" HARNEST_TARGET=mini-ai HARNEST_TARGET_HOST=mini-ai python3 "$guard" implementer >/dev/null 2>&1
eq "the target rule is the consumer's only" 0 $?
# trow <expect> <command>: gh on the mini-ai target
trow() {
  jq -n --arg c "$2" --arg t "${3:-/nonexistent}" '{tool_name: "Bash", tool_input: {command: $c}, transcript_path: $t, cwd: "/tmp"}' \
    | HARNEST_ROOT="$root" HARNEST_TARGET=mini-ai HARNEST_TARGET_HOST=mini-ai HARNEST_ROLE=tester python3 "$guard" consumer >/dev/null 2>&1
  eq "consumer@mini-ai: $2" "$1" $?
}
# a new issue names its backend (one this server can observe), an owner,
# and no claim: claims are the driver's
printf 'body\n' > "$T/trow-body.md"  # a body file the guard can read (every role's body files are read)
trow 0 "gh issue create --title \"S-F070 fails\" --label owner:implementer,backend:mps,regression --body-file $T/trow-body.md"
trow 0 'gh issue create --title "S-F070 fails" -l owner:implementer -l backend:shared'
trow 2 'gh issue create --title "S-F070 fails" --label owner:implementer,regression'
trow 2 'gh issue create --title "S-F070 fails" --label owner:implementer,backend:cuda'
trow 2 'gh issue create --title "S-F070 fails" --label owner:implementer,backend:mps,target:mini-ai'
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
trow 0 'gh issue edit 5 --remove-label target:mini-ai --add-label target:lem'
trow 2 'gh issue edit 5 --add-label target:mini-ai'
trow 2 'gh issue edit 5 --add-label target:lem'
# the implementer on another target: ssh to its own test bed only, the cuda hand-over
irow() {
  jq -n --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}, cwd: "/tmp"}' \
    | HARNEST_TARGET=mini-ai HARNEST_TARGET_HOST=mini-ai python3 "$guard" implementer >/dev/null 2>&1
  eq "implementer@mini-ai: $2" "$1" $?
}
irow 2 'ssh lem uptime'
irow 2 'cd /x && ssh -o BatchMode=yes lem "~/diffusers-workflow/scripts/deploy.sh develop"'
irow 2 'FOO=1 ssh lem true'
irow 2 'rsync -a lem:/x /y'
irow 2 'scp lem:/x /y'
irow 0 'git push origin develop'
# on the Mac the driver deploys between sessions: a session's own MCP
# connection holds the old server open (#446, 2026-09-26)
irow 2 "ssh mini-ai '~/diffusers-workflow/scripts/deploy.sh develop'"
irow 2 'ssh -o BatchMode=yes mini-ai.lan "cd ~/diffusers-workflow && ./scripts/deploy.sh"'
# its own test bed is readable over ssh, as lem is from lem's loop
irow 0 'ssh mini-ai tail -200 ~/dw-serve.log'
irow 0 'ssh -o ConnectTimeout=8 don@mini-ai.lan git -C ~/diffusers-workflow log -1 --oneline'
irow 2 'ssh -o BatchMode=yes lem "tail ~/dw-serve.log"'
irow 2 'scp mini-ai:dw-serve.log /tmp/'
irow 2 'cd ~/src/dkackman/dw-mps-serve && ./scripts/deploy.sh develop'
irow 2 'bash scripts/deploy.sh develop'
row 0 implementer "" $none 'ssh lem "~/diffusers-workflow/scripts/deploy.sh develop"'
irow 0 'gh issue edit 5 --remove-label target:mini-ai --add-label target:lem'
irow 2 'gh issue edit 5 --add-label target:mini-ai'
# on lem nobody adds a claim or a verified-on label
row 2 implementer "" $none 'gh issue edit 5 --add-label target:lem'
row 2 consumer verify "$mcp_transcript" 'gh issue edit 5 --add-label status:verified,verified-on:mps'
row 0 implementer "" $none 'ssh lem uptime'
# rrow <expect> <command>: with the ticket repo named, as the driver sets it
rrow() {
  jq -n --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}, transcript_path: "/nonexistent", cwd: "/tmp"}' \
    | HARNEST_ROOT="$root" HARNEST_TARGET=mini-ai HARNEST_TARGET_HOST=mini-ai HARNEST_TICKET_REPO=o/r python3 "$guard" consumer >/dev/null 2>&1
  eq "consumer@mini-ai o/r: $2" "$1" $?
}
rrow 0 'gh issue create --repo o/r --title x --label owner:implementer,backend:mps,regression'
rrow 2 'gh issue create --title x --label owner:implementer,backend:mps,regression'
rrow 0 'gh issue create --repo dkackman/harnest --title x --label suite,status:needs-approval'
rrow 0 'gh issue create --repo dkackman/harnest --title x --label suite --label status:needs-approval'
rrow 2 'gh issue create --repo dkackman/harnest --title x --label suite,status:needs-approval,owner:implementer'
rrow 2 'gh issue create --repo dkackman/harnest --title x --label harness,status:needs-approval'
rrow 2 'gh issue create --repo other/repo --title x --label suite,status:needs-approval'
rrow 0 'gh issue comment 8 --repo o/r --body x'
rrow 2 'gh issue comment 8 --repo dkackman/harnest --body x'
rrow 0 'gh issue list --repo o/r --label target:mini-ai'

# --- dw's stabilization freeze (lib/freeze.py, freeze_gate): a real checkout
# with a throwaway origin, whose develop holds FREEZE and hot-zone.txt. The
# stub says #7 carries arch-approved, #8 doesn't.
for r in implementer lead consumer reviewer curator; do
  row 2 $r "" $none 'gh issue edit 5 --add-label arch-approved'
  row 2 $r "" $none 'gh issue create --title x --label bug,arch-approved'
  row 2 $r "" $none 'gh issue edit 5 --add-label arch-review'
done
# arch-review is the driver's; only the reviewer's verdict removes it, and an
# architecture review closes nothing
for r in implementer lead consumer; do
  row 2 $r "" $none 'gh issue edit 5 --remove-label arch-review'
done
row 0 reviewer arch $none 'gh issue edit 5 --remove-label arch-review'
row 0 reviewer arch $none 'gh issue edit 5 --remove-label arch-review --remove-label status:fixed-pending-verify --remove-label owner:tester --add-label owner:implementer'
row 2 reviewer arch $none 'gh issue close 5 --reason completed'
row 2 reviewer arch $none 'gh issue close 5 --reason "not planned"'
row 0 reviewer docs $none 'gh issue close 5 --reason completed'
row 0 implementer "" $none 'gh issue edit 5 --add-label stabilization'
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}" >/dev/null 2>&1; }
git init -q --bare "$T/origin.git"; git init -q -b develop "$T/seed"
mkdir -p "$T/seed/dw" "$T/seed/tests" "$T/seed/docs/stabilization"
echo frozen > "$T/seed/docs/stabilization/FREEZE"
printf '# Phase 0\ndw/realize.py\ndocs/stabilization/\n' > "$T/seed/docs/stabilization/hot-zone.txt"
echo a > "$T/seed/dw/realize.py"; echo a > "$T/seed/dw/runner.py"; echo a > "$T/seed/tests/test_a.py"
g "$T/seed" add -A; g "$T/seed" commit -m base; g "$T/seed" remote add origin "$T/origin.git"; g "$T/seed" push origin develop
git clone -q -b develop "$T/origin.git" "$T/work"
w="$T/work"
# branch <name> <file> <content>: a branch off origin/develop with one commit
branch() { g "$w" checkout -q -B "$1" origin/develop; mkdir -p "$w/$(dirname "$2")"; echo "$3" > "$w/$2"; g "$w" add -A; g "$w" commit -m "$1"; }
# hrow <expect> <issue> <label>: the hand-off, from the checkout's HEAD
hrow() {
  jq -n --arg c "gh issue edit $2 --remove-label owner:implementer --add-label owner:tester --add-label status:fixed-pending-verify" \
     --arg d "$w" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' \
    | python3 "$guard" implementer >/dev/null 2>&1
  eq "freeze hand-off #$2: $3" "$1" $?
}
# prow <expect> <HARNEST_ISSUE> <command>: a push, as the session carries it
prow() {
  jq -n --arg c "$3" --arg d "$w" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' \
    | HARNEST_ISSUE="$2" python3 "$guard" implementer >/dev/null 2>&1
  eq "freeze push (HARNEST_ISSUE=$2): $3" "$1" $?
}
branch fix-existing dw/runner.py b
hrow 0 8 "an edit to an existing, non-hot file"
g "$w" checkout -q -B develop fix-existing
prow 0 8 'git push origin HEAD'
g "$w" checkout -q fix-existing
prow 0 8 'git push origin HEAD'
branch fix-new dw/new_module.py x
hrow 2 8 "a new file under dw/"
hrow 0 7 "a new file under dw/, arch-approved"
g "$w" checkout -q -B develop fix-new
prow 2 8 'git push origin develop'
prow 2 8 'git -C . push origin fix-new:develop'
prow 0 7 'git push origin develop'
prow 0 "" 'git push origin develop'
prow 0 8 'git push origin fix-new'
prow 2 8 'git push origin HEAD'
prow 2 8 'git push'
# a PR merge into develop never shows up as a push: refused outright while
# frozen. The stub says PR 12's base is develop, PR 13's master.
stub_gh 'case "$*" in *"pr view 12"*) echo develop ;; *"pr view 13"*) echo master ;;
  *"view 7"*) echo true ;; *"view 8"*) echo false ;; *) exit 1 ;; esac'
prow 2 "" 'gh pr merge 12 --merge'
prow 2 "" 'gh api -X PUT repos/o/r/pulls/12/merge'
prow 2 "" 'gh pr merge 99 --squash'
prow 0 "" 'gh pr merge 13 --merge'
prow 0 "" 'gh api -X PUT /repos/o/r/pulls/13/merge'
prow 0 "" 'gh pr view 12'
branch fix-template workflows/templates/new.json '{}'
hrow 2 8 "a new workflows/ template, frozen"
branch fix-hot dw/realize.py b
hrow 2 8 "a hot-zone file"
hrow 2 7 "a hot-zone file, arch-approved"
branch fix-unfreeze docs/stabilization/FREEZE lifted
hrow 2 7 "editing the FREEZE file itself (hot zone)"
# the refactor lands a hot-zone change on develop; a branch cut before it
# merges it in, with only a tests/ change of its own
branch fix-merged tests/test_a.py b
echo refactored > "$T/seed/dw/realize.py"; g "$T/seed" commit -am refactor; g "$T/seed" push origin develop
g "$w" fetch -q origin; g "$w" merge -q --no-edit origin/develop
hrow 0 8 "merged a newer develop's hot-zone change, none of its own"
# the hot zone is read from origin/develop, not the session's commit: a branch
# cut before dw/runner.py went hot is refused once it is, and even its own
# copy of hot-zone.txt (without the entry) doesn't count
branch fix-late dw/runner.py c
printf '# Phase 0\ndw/realize.py\ndw/runner.py\ndocs/stabilization/\n' > "$T/seed/docs/stabilization/hot-zone.txt"
g "$T/seed" commit -am "runner goes hot"; g "$T/seed" push origin develop; g "$w" fetch -q origin
hrow 2 8 "a path that went hot on develop after the branch was cut"
# the freeze lifts when FREEZE leaves develop, with no harness change: new
# surface is ordinary work again, the hot zone stays for as long as
# hot-zone.txt does, and so does the PR-merge refusal it needs
g "$T/seed" rm -q docs/stabilization/FREEZE; g "$T/seed" commit -m lift; g "$T/seed" push origin develop
g "$w" checkout -q fix-new; hrow 0 8 "a new file under dw/, freeze lifted (no ratchet in this fixture)"
g "$w" checkout -q fix-template; hrow 0 8 "a new workflows/ template, freeze lifted"
g "$w" checkout -q fix-hot; hrow 2 8 "a hot-zone file, freeze lifted: the hot zone outlives it"
hrow 2 7 "  and arch-approved doesn't lift it"
g "$w" checkout -q -B develop fix-hot; prow 2 "" 'git push origin develop'
prow 2 "" 'gh pr merge 12 --merge'
ok "freeze.py active: lifted" bash -c "! python3 '$HARNEST/lib/freeze.py' active '$w'"
# with hot-zone.txt gone too, nothing here is gated
g "$T/seed" rm -q docs/stabilization/hot-zone.txt; g "$T/seed" commit -m "no hot zone"; g "$T/seed" push origin develop
g "$w" checkout -q fix-hot; hrow 0 8 "a former hot-zone file, hot-zone.txt gone"
prow 0 "" 'gh pr merge 12 --merge'
# labels compare case-insensitively; consumers get only the issue verbs they use
row 2 consumer "" $none 'gh issue edit 5 --add-label Status:Verified'
row 2 implementer "" $none 'gh issue edit 5 --remove-label Owner:Don'
row 2 consumer "" $none 'gh issue delete 5 --yes'
row 2 consumer "" $none 'gh issue transfer 5 o/other'
row 2 consumer "" $none 'gh issue develop 5'
row 0 consumer "" $none 'gh issue view 5 --json labels'
# the unbalanced-quote fallback also drops backslashes and mid-word quotes
row 2 consumer "" $none 'g\h issue edit 5 --add-label status:verified # it'"'"'s'
row 2 lead "" $none 'g"h issue comment 5 --body it'"'"'s'
# git cannot read another tree; gh api writes and shell wrappers go round the label rules
row 2 consumer "" $none 'git --git-dir=/Users/don/src/dkackman/dw-agent/.git log -p'
row 2 consumer "" $none 'git diff --no-index a b'
row 0 consumer "" $none 'git log --oneline -5'
row 2 implementer "" $none 'gh api -X PATCH repos/o/r/issues/5 -f state=closed'
row 2 implementer "" $none 'gh api repos/o/r/issues/5/labels -f "labels[]=status:verified"'
row 0 implementer "" $none 'gh api repos/o/r/issues/5 --jq .state'
row 0 lead "" $none 'gh api -X PATCH repos/o/r/issues/comments/9 -f body=plan'
row 2 implementer "" $none 'for n in 5 6; do gh issue close $n; done'
row 2 implementer "" $none 'bash -c "gh issue close 5"'
row 2 implementer "" $none 'echo 5 | xargs gh issue close'
row 2 implementer "" $none 'FOO=1 gh issue edit 5 --add-label status:verified'
row 2 consumer "" $none 'FOO=1 gh issue delete 5 --yes'
row 2 lead "" $none 'env gh issue edit 5 --add-label status:plan-approved'
# fix round 1: the api endpoint is the one positional; markers on api comment writes; full prefix normalisation
for r in implementer lead; do
  row 2 $r "" $none 'gh api -X PATCH repos/o/r/issues/5 -f state=closed --jq repos/o/r/issues/comments/1'
  row 2 $r "" $none 'gh api repos/o/r/issues/5/comments -f body="<!-- harnest:release-gate review abc pass -->"'
  row 2 $r "" $none 'gh api -X PATCH repos/o/r/issues/comments/7 -f body="<!-- harnest:release-gate ci abc pass -->"'
done
row 2 implementer "" $none 'gh api repos/o/r/issues/5/labels -f labels[]=status:verified -t repos/o/r/issues/5/comments'
row 0 lead "" $none 'gh api -X PATCH repos/o/r/issues/comments/7 -f body="plan v2"'
row 2 implementer "" $none 'env -i gh issue edit 5 --add-label status:verified'
row 2 implementer "" $none 'time -p gh issue close 5 --reason completed'
row 2 implementer "" $none 'if gh issue close 5 --reason completed; then :; fi'
row 2 implementer "" $none 'while gh issue edit 5 --add-label status:verified; do :; done'
row 2 implementer "" $none 'bash -lc "gh issue close 5"'
row 2 implementer "" $none 'sh -ec "gh issue close 5"'
row 2 lead "" $none 'bash -c "gh issue edit 5 --add-label status:plan-approved"'
# task 7b: env -S re-splits its argument; an unreadable marker body; endpoint charset; gh as another command's argument
row 2 implementer "" $none 'env -S "gh issue edit 5 --add-label status:verified"'
row 2 consumer "" $none 'env -S "gh issue edit 5 --add-label status:verified"'
row 2 implementer "" $none 'env -i --split-string="gh issue close 5"'
row 2 implementer "" $none 'env -S "echo hi"'
printf '%s\n' 'a plain comment' > "$T/plain.md"
row 2 implementer "" $none 'gh api repos/o/r/issues/5/comments -f body=@-'
row 2 implementer "" $none 'gh api repos/o/r/issues/5/comments --input -'
row 2 lead "" $none 'gh api -X PATCH repos/o/r/issues/comments/7 -F body=@/dev/stdin'
row 2 lead "" $none 'gh api -X PATCH repos/o/r/issues/comments/7 -f body=@/no/such/yet.md'
row 2 lead "" $none 'gh api -X PATCH repos/o/r/issues/comments/7 --input /dev/stdin'
row 0 lead "" $none "gh api -X PATCH repos/o/r/issues/comments/7 -F body=@$T/plain.md"
row 2 implementer "" $none 'gh issue comment 5 --body-file -'
row 2 lead "" $none 'gh issue comment 5 --body-file /nonexistent/x.md'
row 2 implementer "" $none 'gh issue create --title x -F /dev/stdin'
row 0 implementer "" $none "gh issue comment 5 --body-file $T/plain.md"
row 2 lead "" $none 'gh api -X PATCH "repos/o/r/issues/comments/7?x=1" -f body=plan'
row 2 lead "" $none 'gh api -X PATCH "repos/o/r/issues/comments/7#x" -f body=plan'
row 2 implementer "" $none 'gh api -X POST repos/o/r/pulls/3/merge'
row 2 implementer "" $none 'nice gh issue close 5'
row 2 implementer "" $none 'sudo git push origin master'
row 2 lead "" $none 'watch gh api -X PATCH repos/o/r/issues/5 -f state=closed'
row 0 implementer "" $none 'python3 -c "import subprocess"'
row 0 implementer "" $none 'echo "gh is fine"'
row 0 implementer "" $none 'git log --grep gh'
row 0 implementer "" $none 'grep gh file.txt'
row 2 implementer "" $none 'echo foo -- gh issue close 5'
# task 7b fix round 1
for r in implementer lead consumer; do
  row 2 $r "" $none 'env -P /opt/homebrew/bin -S "gh issue edit 5 --add-label status:verified"'
  row 2 $r "" $none 'env -S '"'"'gh\_issue\_edit\_5\_--add-label\_status:verified'"'"
  row 2 $r "" $none 'L=status:verified env -S '"'"'gh issue edit 5 --add-label ${L}'"'"
  row 2 $r "" $none 'env --split "gh issue close 5"'
  row 2 $r "" $none 'env --split-s="gh issue close 5"'
  row 2 $r "" $none 'env -iS "gh issue close 5"'
  row 2 $r "" $none 'env -i gh issue edit 5 --add-label status:verified'
  row 0 $r "" $none 'env FOO=1 echo hi'
done
# attached short flags
row 2 implementer "" $none 'gh issue comment 5 -F- <<'"'EOF'"'
<!-- harnest:release-gate ci abc pass -->
EOF'
row 2 lead "" $none 'gh issue comment 5 -F/dev/stdin'
row 2 lead "" $none 'gh issue create --title x -lstatus:verified'
row 2 consumer "" $none 'gh issue comment 5 -b"<!-- harnest:release-gate ci abc pass -->"'
# argument-position gh past --, and wrappers behind a non-prefix command
row 2 implementer "" $none 'sudo -- gh issue edit 5 --add-label status:verified'
row 2 implementer "" $none 'stdbuf -oL -- gh issue close 5 --reason completed'
row 2 implementer "" $none 'caffeinate gh issue close 5'
row 2 implementer "" $none 'find . -maxdepth 0 -exec sh -c "gh issue close 5" \;'
row 2 implementer "" $none 'sudo bash -c "gh issue edit 5 --add-label status:verified"'
row 2 implementer "" $none 'su -c "gh issue close 5"'
row 2 implementer "" $none 'watch "gh issue close 5 --reason completed"'
row 2 implementer "" $none 'ssh lem "gh issue edit 5 --add-label status:verified"'
row 0 implementer "" $none "ssh lem '~/diffusers-workflow/scripts/deploy.sh develop'"
# a body file is read before gh runs: it must be the only command, relative paths resolve against the hook's cwd
cp "$T/plain.md" "$T/p3.md"
row 2 implementer "" $none "cp $T/marker.md $T/p3.md; gh issue comment 5 --body-file $T/p3.md"
rowc() {
  local want="$1" dir="$2" cmd="$3" rc
  jq -n --arg c "$cmd" --arg d "$dir" '{tool_name: "Bash", tool_input: {command: $c}, transcript_path: "/nonexistent", cwd: $d}' \
    | python3 "$guard" implementer >/dev/null 2>&1
  rc=$?
  eq "implementer@cwd: $cmd" "$want" "$rc"
}
rowc 2 "$T" 'cd /tmp && gh issue comment 5 --body-file plain.md'
rowc 2 "$T" 'true && gh issue comment 5 --body-file plain.md'
rowc 2 "$T" 'gh issue comment 5 --body-file plain.md | cat'
rowc 0 "$T" 'gh issue comment 5 --body-file plain.md'
rowc 2 /tmp 'gh issue comment 5 --body-file plain.md'
rowc 2 "$T" 'gh issue comment 5 --body-file marker.md'
# endpoint charset, merge method
row 2 lead "" $none 'gh api -X PATCH "repos/o?x=/r/issues/comments/7" -f body=plan'
row 0 implementer "" $none 'gh api -X PUT /repos/o/r/pulls/13/merge'
row 2 implementer "" $none 'gh api -X POST /repos/o/r/pulls/13/merge'
# task 7b fix round 2
nl=$'\n'
for c in 'watch "{ gh issue close 5; }"' 'ssh host "( gh issue close 5 )"' 'watch "if true; then gh issue close 5; fi"' \
  'watch "! gh issue close 5"' 'ssh lem "echo \$(gh issue close 5 --reason completed)"' \
  'watch "true && GH_REPO=o/r gh issue close 5"' 'watch "command gh issue close 5"' 'watch "gh --repo o/r issue close 5"' \
  "watch \$'echo\\ngh issue close 5'" "ssh lem \"cd x${nl}gh issue close 5\"" 'ssh lem "cd x; git push origin develop"'; do
  row 2 implementer "" $none "$c"
done
row 0 implementer "" $none 'echo "gh is fine"'
row 2 implementer "" $none 'gh -R o/r issue edit 5 --add-label status:verified'
row 2 implementer "" $none 'gh --repo o/r issue close 5 --reason completed'
row 2 implementer "" $none 'gh --repo=o/r issue comment 5 --body "<!-- harnest:release-gate x -->"'
row 2 lead "" $none 'gh --hostname github.com api -X PATCH repos/o/r/issues/5 -f state=closed'
row 0 consumer "" $none 'gh -R o/r issue view 5'
cp "$T/marker.md" "$T/other.md"; cp "$T/plain.md" "$T/plain2.md"
rowc 2 "$T" 'gh issue comment 5 --body-file plain.md `cp marker.md plain.md`'
rowc 2 "$T" 'gh issue comment 5 --body-file plain.md --title "$(cp marker.md plain.md)x"'
rowc 2 "$T" "env --chdir=/tmp gh issue comment 5 --body-file plain.md"
rowc 2 "$T" "env -C /tmp gh issue comment 5 --body-file plain.md"
rowc 2 "$T" "gh issue comment 5 --body-file '~/x.md'"
rowc 2 "$T" "gh issue comment 5 --body-file=~/x.md"
rowc 0 "$T" "gh issue comment 5 --body-file plain.md 2>/dev/null"
rowc 0 "$T" "gh issue comment 5 --body-file plain.md 2>&1"
rowc 0 "$T" "gh issue comment 5 --body-file plain.md --title 'a -> b'"
rowc 2 "$T" "gh issue comment 5 --body-file plain.md > out.txt"
rowc 0 "$T" "cat > $T/c1.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 0 "$T" "cat >$T/c1.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 0 "$T" "tee $T/c1.md <<'EOF' >/dev/null${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 2 "$T" "cat > $T/c1.md <<'EOF'${nl}<!-- harnest:release-gate ci abc pass -->${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 2 "$T" "cat > $T/other2.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 2 "$T" "cat >> $T/plain.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/plain.md"
rowc 2 "$T" "cat > $T/c1.md <<'EOF'${nl}hello${nl}EOF${nl}cp other.md c1.md${nl}gh issue comment 5 --body-file $T/c1.md"
# task 7b fix round 3
row 2 implementer "" $none 'watch "g\h issue close 5"'
rowc 2 "$T" "cat > $T/c1.md <<'EOF'; cp marker.md $T/c1.md${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 2 "$T" "cat > $T/c1.md <<'EOF' && cp marker.md $T/c1.md${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
for b in '<!-- ${X:-harnest}:release-gate ci abc pass -->' '<!-- harnes${Z}t:release-gate ci abc pass -->' \
  "<!-- harnes\\${nl}t:release-gate ci abc pass -->" '<!-- ${HARNEST_ROOT##*/}:release-gate ci abc pass -->'; do
  rowc 2 "$T" "cat > $T/c1.md <<EOF${nl}$b${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
done
rowc 2 "$T" "cat > $T/c1.md <<\"EOF\"${nl}<!-- harnest:release-gate ci abc pass -->${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 0 "$T" "cat > $T/c1.md <<\"EOF\"${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 0 "$T" "cat > $T/c1.md <<'EOF'${nl}uses \`code\` spans and a literal \$(not run) and harnest:plan prose${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 2 "$T" "cat > $T/c1.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md --title \`id\`"
rowc 2 "$T" "cat > $T/c1.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md --title \"\$(id)\""
rowc 2 "$T" "cat > \`echo $T/c1.md\` <<'EOF'${nl}hello${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
# an apostrophe or a gh-looking line in a quoted heredoc body is data
rowc 0 "$T" "cat > $T/c1.md <<'EOF'${nl}it's done; gh issue close 5 is Don's${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 2 "$T" "cat > $T/c1.md <<EOF${nl}it's done${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
# the real hand-off shape: the body file, then a label edit, in one line
rowc 0 "$T" "gh issue comment 5 --body-file plain.md && gh issue edit 5 --remove-label owner:lead --add-label owner:tester"
rowc 0 "$T" "cat > $T/c1.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue edit 6 --add-label bug && gh issue comment 5 -R o/r -F $T/c1.md >/dev/null"
rowc 2 "$T" "gh issue edit 6 --add-label bug && cp marker.md plain.md && gh issue comment 5 --body-file plain.md"
rowc 2 "$T" "gh api -X GET repos/o/r/issues/5 -o plain.md && gh issue comment 5 --body-file plain.md"
# task 7b fix round 4: the heredoc cut is a shell-aware walk, not a regex over the whole line
rowc 2 "$T" "cat > $T/p.md <<'EOF'${nl}EOF${nl}gh issue edit 5 --add-label status:verified${nl}EOF"
rowc 2 "$T" "cat > $T/p.md <<'EOF'${nl}EOF${nl}gh issue comment 5 --body \"<!-- harnest:release-gate x -->\"${nl}EOF"
rowc 2 "$T" "cat <<EOF${nl}cat > /tmp/q <<'Q'${nl}EOF${nl}gh issue close 5 --reason completed${nl}Q"
rowc 2 "$T" "echo \"x${nl}cat > /tmp/q <<'Q'${nl}\"${nl}gh issue edit 5 --add-label status:verified${nl}Q"
rowc 2 "$T" "# x; cat > /tmp/q <<'Q'${nl}gh issue edit 5 --add-label status:verified${nl}Q"
rowc 2 "$T" "echo \; cat > /tmp/q <<'Q'${nl}gh issue edit 5 --add-label status:verified${nl}Q"
# "EOF " is not the delimiter line: bash reads the gh line as body, so nothing runs
rowc 0 "$T" "cat > $T/p.md <<'EOF'${nl}hi${nl}EOF ${nl}gh issue edit 5 --add-label status:verified${nl}EOF"
rowc 2 "$T" "cat > \"\$(cp marker.md c1.md)c1.md\" <<'EOF'${nl}hi${nl}EOF${nl}gh issue comment 5 --body-file c1.md"
rowc 2 "$T" "cat > /tmp/x\$(gh\${IFS}issue\${IFS}edit\${IFS}5\${IFS}--add-label\${IFS}status:verified) <<'EOF'${nl}hi${nl}EOF"
row 2 consumer "" $none "cat > /tmp/x\`gh issue close 5 --reason completed\` <<'EOF'${nl}hi${nl}EOF"
rowc 0 "$T" "true && cat > $T/c1.md <<'EOF'${nl}hi${nl}EOF${nl}echo done"
rowc 0 "$T" "cat > $T/c1.md <<'EOF'${nl}${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 0 "$T" "cat > $T/c1.md <<-'EOF'${nl}	hi${nl}	EOF${nl}gh issue comment 5 --body-file $T/c1.md"
rowc 0 "$T" "cat > $T/c1.md <<'EOF'${nl}uses \`code\` and \$(x)${nl}EOF${nl}gh issue comment 5 --body-file $T/c1.md && gh issue edit 5 --remove-label owner:implementer --add-label owner:tester"
# a command substitution runs inside double quotes and backticks too, for every role
for r in consumer curator reviewer; do
  row 2 $r "" $none 'echo `gh issue edit 5 --add-label status:plan-approved`'
  row 2 $r "" $none 'echo "$(gh issue edit 5 --add-label release)"'
  row 2 $r "" $none 'echo "`gh issue edit 5 --add-label status:plan-approved`"'
  row 2 $r "" $none 'echo "$(echo $(true); gh issue edit 5 --add-label status:plan-approved)"'
done
row 0 consumer "" $none 'echo "today is $(date +%F)"'
row 2 consumer "" $none 'echo "`gh issue edit 5 --add-label status:verified`"'
# ride-alongs beside a body file: plain gh issue comment|edit|close|reopen|view, no --web/--editor
rowc 2 "$T" "cat > c1.md <<'EOF'${nl}hello${nl}EOF${nl}GH_BROWSER=\"sh -c 'cp marker.md c1.md'\" gh issue view 5 --web && gh issue comment 5 -F c1.md"
rowc 2 "$T" "cat > c1.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue develop 5 --checkout --name evil && gh issue comment 5 -F c1.md"
rowc 2 "$T" "cat > c1.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue view 5 -w && gh issue comment 5 -F c1.md"
rowc 2 "$T" "cat > c1.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue comment 6 --editor && gh issue comment 5 -F c1.md"
rowc 2 "$T" "cat > c1.md <<'EOF'${nl}hello${nl}EOF${nl}nice gh issue view 5 && gh issue comment 5 -F c1.md"
rowc 2 "$T" "cat > c1.md <<'EOF'${nl}hello${nl}EOF${nl}./gh issue view 5 && gh issue comment 5 -F c1.md"
rowc 0 "$T" "cat > c1.md <<'EOF'${nl}hello${nl}EOF${nl}gh issue view 5 --json state && gh issue comment 5 -F c1.md && gh issue close 6 --reason \"not planned\""
# \$IFS word splitting: the guard reads one word, bash splits it
for r in implementer consumer; do
  row 2 $r "" $none 'gh${IFS}issue${IFS}close${IFS}5${IFS}--reason${IFS}completed'
  row 2 $r "" $none 'echo $(gh${IFS}issue${IFS}close${IFS}5${IFS}--reason${IFS}completed)'
  row 2 $r "" $none 'g${X}h issue close 5 --reason completed'
  row 2 $r "" $none 'gh$E issue close 5 --reason completed'
  row 2 $r "" $none 'echo ${IFS}x'
  row 0 $r "" $none 'echo "costs $3 in gh"'
done
row 0 lead "" $none 'gh api -X PATCH repos/o/r/issues/comments/7 -f body="plan v2"'
# task 7b fix round 5
# B: a quoted substitution with parentheses inside is not read: refused when the line has gh/git
for r in consumer curator reviewer; do
  row 2 $r "" $none 'echo "$( (gh issue edit 5 --add-label release) )"'
  row 2 $r "" $none 'echo "$(gh issue edit 5 --add-label release --title '"'(x)'"')"'
  row 2 $r "" $none 'echo "$(case x in x) gh issue edit 5 --add-label release;; esac)"'
done
for r in implementer lead consumer curator reviewer; do
  row 2 $r "" $none 'gh issue comment 5 --body "$(gh issue edit 5 --add-label release --title '"'(x)'"')"'
done
row 0 implementer "" $none "git commit -m 'fix \$(foo)'"
row 0 implementer "" $none "git commit -m 'fix \$(a (b))'"
row 0 consumer "" $none "echo '\$(x)'"
# X: an expansion that is the whole command word
for r in implementer consumer; do
  row 2 $r "" $none '${GH:-gh} issue close 5 --reason completed'
  row 2 $r "" $none 'G=gh; $G issue close 5 --reason completed'
  row 2 $r "" $none 'G="gh issue"; $G close 5 --reason completed'
  row 2 $r "" $none 'export G=/usr/bin/gh'
done
row 0 implementer "" $none '"$GIT" status'
row 0 implementer "" $none '$PY -m pytest -q'
# D: ANSI-C and locale quoting
for r in implementer lead consumer curator reviewer; do
  row 2 $r "" $none "\$'gh' issue close 5 --reason completed"
  row 2 $r "" $none '$"gh" issue close 5 --reason completed'
  row 2 $r "" $none "\$'\\x67h' issue edit 5 --add-label status:plan-approved"
  row 2 $r "" $none "gh issue edit 5 --add-label \$'status:verified'"
  row 2 $r "" $none "gh issue edit 5 --add-label status:\$'plan-approved'"
  row 2 $r "" $none "echo \"\$(\$'gh' issue edit 5 --add-label release)\""
done
row 0 consumer "" $none "printf \$'a\\tb\\n'"
row 0 consumer "" $none "gh issue comment 5 --body 'see \$'\"'\"'x'\"'\"''"
# brace expansion
for r in implementer lead consumer curator reviewer; do
  row 2 $r "" $none 'gh issue edit 5 --add-label={status:plan-approved,bug}'
  row 2 $r "" $none 'gh issue edit 5 --add-label status:plan-{approved,x}'
  row 2 $r "" $none 'gh issue edit 5 --add-label status:{a..b}'
  row 0 $r "" $none 'gh issue edit 5 --title "{a,b}"'
done
row 0 consumer "" $none "gh issue list --json number,title --jq '.[] | {n: .number, t: .title}'"
# $L indirection: an expansion stands in for a flag or a label only where a value or the issue number goes
for r in implementer consumer; do
  row 2 $r "" $none 'L="--add-label status:verified"; gh issue edit 5 $L'
  row 2 $r "" $none 'gh issue edit 5 ${=L}'
  row 2 $r "" $none 'gh issue edit 5 $=L'
  row 2 $r "" $none 'gh issue edit 5 --add-label $L'
  row 2 $r "" $none 'gh issue $V 5'
  row 2 $r "" $none 'L=status:verified; gh issue edit 5 --add-label "$L"'
  row 2 $r "" $none 'gh issue edit 5 --add-label "$(printf status:verified)"'
  row 2 $r "" $none 'gh issue edit 5 --add-label=$L'
  row 0 $r "" $none 'for n in 5 6; do gh issue view $n --json labels; done'
  row 0 $r "" $none 'gh issue view $n --json labels'
  row 2 $r "" $none 'gh issue create --repo $R --title "x $Y" --body x'
  row 2 $r "" $none 'gh issue comment 5 --repo $R --body "x $Y"'  # an unassigned $VAR in a body: the guard never read it
  row 0 $r "" $none 'gh -R $R issue view 5'
  row 0 $r "" $none 'gh issue view 5 --repo=$R --json labels > $OUT'
done
row 0 implementer "" $none 'gh api repos/$R/issues/5'
# "$(cat <<'EOF' ... EOF)" is literal text: read as the value it is
for r in implementer consumer; do
  row 0 $r "" $none "gh issue comment 5 --body \"\$(cat <<'EOF'${nl}it's (done), \"quoted\", \$x and \`code\`${nl}EOF${nl})\""
  row 2 $r "" $none "gh issue comment 5 --body \"\$(cat <<'EOF'${nl}<!-- harnest:release-gate ci abc pass -->${nl}EOF${nl})\""
  row 2 $r "" $none "gh issue edit 5 --add-label \"\$(cat <<'EOF'${nl}status:verified${nl}EOF${nl})\""
  row 2 $r "" $none "gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x (y)${nl}EOF${nl})\" && gh issue edit 5 --add-label status:plan-approved"
  row 2 $r "" $none "gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x (y)${nl}EOF${nl}gh issue edit 5 --add-label status:plan-approved${nl})\""
  row 2 $r "" $none "gh issue comment 5 --body \"\$(cat <<EOF${nl}x (y)${nl}EOF${nl})\" && gh issue edit 5 --add-label status:plan-approved"
done
row 0 implementer "" $none "git commit -m \"\$(cat <<'EOF'${nl}fix(x): #5 - a (b) \"c\"${nl}${nl}Co-Authored-By: x${nl}EOF${nl})\""
# what bash does not substitute is not an unread substitution
row 0 lead "" $none "gh api -X PATCH repos/o/r/issues/comments/7 -f body=\"\$(cat <<'EOF'${nl}plan v2 costs \$3 (see \"x\")${nl}EOF${nl})\""
row 0 implementer "" $none 'for n in 5 6; do o=$((n==5?6:5)); gh issue view $n --json labels; done'
row 0 implementer "" $none "./venv/bin/python - <<'EOF'${nl}print(\"\$(x (y))\", \$'z')${nl}EOF${nl}git status"
row 0 implementer "" $none "gh issue comment 5 --body 'Don'\"'\"'s \$(x (y)) and \`z\`'"
row 2 implementer "" $none "bash <<'EOF'${nl}echo \"\$( (gh issue edit 5 --add-label release) )\"${nl}EOF"
row 0 consumer "" $none 'for L in wontfix duplicate; do gh issue list --label $L --json number; done'
# a redefined cat makes the "$(cat <<'EOF' ...)" body a command: not rewritten, refused
for r in implementer consumer; do
  row 2 $r "" $none "cat() { bash; }; gh issue comment 5 --body \"\$(cat <<'EOF'${nl}gh issue edit 5 --add-label status:verified${nl}EOF${nl})\""
  row 2 $r "" $none "alias cat=bash${nl}gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
  row 2 $r "" $none "alias cat=bash${nl}gh issue comment 5 --title \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\" --body y"
  row 2 $r "" $none "PATH=/tmp/evil:\$PATH gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
done
# a body read from a file through a substitution is never checked: --body-file is
row 2 implementer "" $none "gh issue comment 5 --body \"\$(cat $T/marker.md)\""
row 2 implementer "" $none "gh issue comment 5 --body \"\$(<$T/marker.md)\""
row 2 implementer "" $none "B=\$(cat $T/marker.md); gh issue comment 5 --body \"\$B\""
row 2 consumer "" $none "B=\`cat $T/marker.md\`; gh issue comment 5 --body \"\$B\""
row 2 lead "" $none "gh api -X PATCH repos/o/r/issues/comments/7 -f body=\"\$(cat $T/marker.md)\""
row 2 implementer "" $none 'gh issue comment 5 --body "built $(date +%H:%M) at $(git rev-parse --short HEAD)"'
for r in implementer lead consumer; do
  row 2 $r "" $none 'gh issue comment 5 --body "$(printf x)"'
  row 2 $r "" $none 'gh issue comment 5 --body "$(echo hi)"'
  row 2 $r "" $none 'gh issue comment 5 --body "x `id`"'
  row 2 $r "" $none 'V=hello; gh issue comment 5 --body "$V"'
  row 2 $r "" $none 'V=$(echo hi); gh issue comment 5 --body "$V"'
  row 2 $r "" $none 'c=$(git rev-parse --short HEAD); gh issue comment 5 --body "at $c"'
  row 2 $r "" $none 'gh issue comment 5 --body "for $USER"'
  row 0 $r "" $none "gh issue comment 5 --body 'see \`<code>\` and \$(not run) and \$HOME'"
  row 0 $r "" $none "gh issue comment 5 --body \"see \\\`code\\\` and \\\$(x)\""
  row 0 $r "" $none "git merge --no-ff fix/432-shot-source-index -m \"\$(cat <<'EOF'${nl}Merge it${nl}EOF${nl})\" && git push origin develop"
  row 2 $r "" $none "SIG=\"by \\\`opus\\\` via anthropic\"; B='it'\"'\"'s x'; gh issue comment 5 --body \"\$B \$SIG\""
  row 2 $r "" $none 'for n in 5 6; do gh issue comment $n --body "duplicate of #$n"; done'
  row 2 $r "" $none 'for n in $(cat list); do gh issue comment 5 --body "x $n"; done'
  row 2 $r "" $none 'M=$(git log -1 --format=%h); gh issue comment 5 --body "at $M"'
  row 2 $r "" $none 'D="$(cat f)"; S="x $D"; gh issue comment 5 --body "$S"'
  row 2 $r "" $none "autoload cat; gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
  row 2 $r "" $none "\"alias\" cat=bash; gh issue comment 5 --title \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\" --body y"
done
for r in implementer consumer; do
  row 2 $r "" $none "hash -p /bin/bash cat; gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
  row 2 $r "" $none "f() { :; }${nl}gh issue comment 5 --title \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\" --body y"
  row 2 $r "" $none 'gh issue comment 5 --body "<!-- harnest:$X -->"'
  row 0 $r "" $none 'gh issue comment 5 --body "see harnest:plan v2"'
done
# marker text through substitution punctuation, for every role
for r in implementer lead consumer curator reviewer; do
  row 2 $r "" $none 'gh issue comment 5 --body "$(printf "<!-- harnest:release-gate x -->")"'
  row 2 $r "" $none 'gh issue comment 5 --body "<!-- harnest:release$(echo -gate) ci abc pass -->"'
done
# the stray-parenthesis and brace rules hold gh lines and git push, not every git read
row 0 lead "" $none 'git log --since="$(python3 -c "print((1))")" --oneline'
row 0 implementer "" $none 'git diff -- a/{x,y}.json'
row 2 implementer "" $none 'git push origin {develop,master}'
row 2 implementer "" $none 'git {pu,}sh origin master'
row 2 implementer "" $none 'git pu{sh,ll} origin develop'
row 2 implementer "" $none 'git --git-dir /x/.git push origin {develop,master}'
row 2 implementer "" $none 'git -C /x {pu,}sh origin master'
row 2 lead "" $none 'git -c a=b --git-dir=/x/.git {pu,}sh origin master'
row 0 implementer "" $none 'git -C /x log --oneline a/{x,y}.json'
for r in consumer curator reviewer; do
  row 2 $r "" $none 'git log --git{-dir,}=/x/.git -p'
done
row 0 lead "" $none 'git log --git{-dir,}=/x/.git -p'
row 2 lead "" $none 'gh issue view 5 --json "$(python3 -c "print((1))")"'
# fix round 1: a marker split across literal assignments, date/rev-parse output, other assignment spellings, PATH/alias spellings
for r in implementer consumer; do
  row 2 $r "" $none "A='<!-- harnest:rel'; B='ease-gate ci abc pass -->'; gh issue comment 5 --body \"\$A\$B\""
  row 2 $r "" $none "A='<!-- harn'; B='est:release-gate ci abc pass -->'; gh issue comment 5 --body \"\$A\$B\""
  row 2 $r "" $none 'A=harn; gh issue comment 5 --body "<!-- ${A}est:release-gate ci abc pass -->"'
  row 2 $r "" $none 'E=; gh issue comment 5 --body "harnest${E}:release-gate ci abc pass"'
  row 2 $r "" $none 'for A in harn; do gh issue comment 5 --body "${A}est:release-gate x"; done'
  row 2 $r "" $none 'gh issue comment 5 --body "<!-- $(date +harn)est:rel$(date +ease)-gate ci abc pass -->"'
  row 2 $r "" $none 'gh issue comment 5 --body "harnest$(date +):release-gate ci abc pass"'
  row 2 $r "" $none 'gh issue comment 5 --body "on $(git rev-parse --sq-quote x)"'
  row 2 $r "" $none 'gh issue comment 5 --body "at $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(git rev-parse --abbrev-ref HEAD)"'
  row 2 $r "" $none "set -- \"\$(cat $T/marker.md)\"; gh issue comment 5 --body \"\$1\""
  row 2 $r "" $none 'gh issue comment 5 --body "$1"'
  row 2 $r "" $none "A=x; A+=\"\$(cat $T/marker.md)\"; gh issue comment 5 --body \"\$A\""
  row 2 $r "" $none "A=x; read -r A < $T/marker.md; gh issue comment 5 --body \"\$A\""
  row 2 $r "" $none "N=X; X=\$(cat $T/marker.md); gh issue comment 5 --body \"\${!N}\""
  row 2 $r "" $none 'A=x; gh issue comment 5 --body "${A:-y}"'
  row 2 $r "" $none 'V=hello; gh issue comment 5 --body "x $V"'
  row 2 $r "" $none 'TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ"); gh issue comment 5 --body "at $TS"'
  row 2 $r "" $none "read \"PATH\" <<< /tmp/evil; gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
  row 2 $r "" $none 'A="harn"; gh issue comment 5 --body "$A""est:release-gate x"'
  row 2 $r "" $none 'A=harn; A=x; gh issue comment 5 --body "${A}est:release-gate x"'
  row 2 $r "" $none 'A=harn; B="${A}est"; gh issue comment 5 --body "<!-- $B:release-gate x -->"'
  row 2 $r "" $none "read PATH <<< /tmp/evil; gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
  row 2 $r "" $none "for PATH in /tmp/evil; do gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\"; done"
  row 2 $r "" $none "printf -v PATH /tmp/evil; gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
  row 2 $r "" $none "P=P; export \${P}ATH=/tmp/evil; gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
  row 2 $r "" $none "A=ali; \${A}as cat=bash${nl}gh issue comment 5 --body \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
done
# fix round 2: a body or title is literal, a quoted heredoc, or --body-file; assigners keep a heredoc live
h="\"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
for r in implementer consumer; do
  row 0 $r "" $none 'gh issue comment 5 --body "literal text"'
  row 0 $r "" $none 'gh issue comment 5 --body "plain text with a \$ sign"'
  row 0 $r "" $none "gh issue create --title $h --body y"
  row 2 $r "" $none 'gh issue create --title "x $Y" --body y'
  row 2 $r "" $none 'gh issue create -t "x `id`" --body y'
  row 2 $r "" $none 'gh issue comment 5 --body "built $(date +%H:%M)"'
  row 2 $r "" $none "{ read PATH <<< /tmp/evil; }; gh issue comment 5 --body $h"
  row 2 $r "" $none "command read -r PATH <<< /tmp/evil; gh issue comment 5 --body $h"
  row 2 $r "" $none "if read PATH <<< /tmp/evil; then :; fi; gh issue comment 5 --body $h"
  row 2 $r "" $none "while read -r PATH; do :; done < /tmp/p; gh issue comment 5 --body $h"
  row 2 $r "" $none "N=PA; read \"\${N}TH\" <<< /tmp/evil; gh issue comment 5 --body $h"
  row 2 $r "" $none "N=PA; printf -v \"\${N}TH\" /tmp/evil; gh issue comment 5 --body $h"
  row 2 $r "" $none ": \"\${PATH::=/tmp/evil} x\"; gh issue comment 5 --body $h"
done
# a long command without a heredoc is read in well under the hook timeout
long="echo $(printf 'word%.0s ' $(seq 1 5000)) $(printf 'x%.0s' $(seq 1 25000))"
start=$(python3 -c 'import time; print(time.time())')
row 0 consumer "" $none "$long"
eq "a 50 KB command is read in under a second" 1 "$(python3 -c "import time; print(int(time.time() - $start < 1.0))")"
# fix round 3: the heredoc rewrite only for a gh call alone on its line (other gh issue calls aside)
hi="\"\$(cat <<'EOF'${nl}hi${nl}EOF${nl})\""
for r in implementer consumer; do
  row 2 $r "" $none "N=PA; M=\${N}TH; : \${(P)M::=/tmp/evil}; gh issue comment 5 --body $h"
  row 2 $r "" $none "echo \\\"a b\\\" ; read PATH <<< /tmp/evil; gh issue comment 5 --body $h"
  row 2 $r "" $none "cd /x && gh issue comment 5 --body $hi"
  row 2 $r "" $none "gh issue comment 5 --body $hi | tee /tmp/x"
  row 2 $r "" $none "# note${nl}gh issue comment 5 --body $hi"
  row 0 $r "" $none "gh issue comment 5 --body $hi && gh issue edit 5 --remove-label owner:implementer --add-label owner:tester"
  row 0 $r "" $none "gh issue comment 5 --body $hi"
  row 0 $r "" $none "gh issue comment 5 --body $hi 2>&1"
  row 2 $r "" $none "gh issue comment 5 --body $hi 2>&1 | tail -1"
  row 0 $r "" $none "gh issue edit 5 --remove-label owner:implementer --add-label owner:tester && \\${nl}gh issue comment 5 --body $hi"
  row 2 $r "" $none "gh issue comment 5 --body x *(e:'gh issue edit 5 --add-label status:verified':)"
  row 2 $r "" $none "gh issue comment 5 --body x ?(+evil)"
done
# a git heredoc is read as literal only when every other segment is a plain git word or a gh issue ride-along
row 0 implementer "" $none "git commit -m \"\$(cat <<'EOF'${nl}it's (done)${nl}EOF${nl})\" && git push origin feature"
row 2 implementer "" $none "cat() { bash; }; git commit -m \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
row 0 implementer "" $none 'git add *.py'
row 0 consumer "" $none 'gh issue list --search "x (y)"'
# a body file the guard cannot read, for every role
printf 'hello\n' > "$T/plain3.md"
for r in consumer reviewer; do
  row 2 $r "" $none "gh issue comment 5 --body-file <(cat $T/marker.md)"
  row 2 $r "" $none "gh issue comment 5 --body-file =(cat $T/marker.md)"
  row 2 $r "" $none "gh issue comment 5 --body-file /dev/stdin"
done
row 0 consumer "" $none "gh issue comment 5 --body-file $T/plain3.md"
# a line continuation (backslash-newline) joins a line; it is not a word
for r in implementer consumer; do
  row 0 $r "" $none "cat > $T/cv.md <<'EOF'${nl}ok${nl}EOF${nl}gh issue comment 5 --body-file $T/cv.md && \\${nl}gh issue edit 5 --add-label bug"
done
# fix round 4: an escaped backslash (\\) ends a line; only an unescaped one continues it
for r in implementer consumer; do
  row 2 $r "" $none "echo \\\\${nl}gh issue edit 5 --add-label status:verified"
  row 2 $r "" $none "echo \\\\${nl}gh issue close 5 --reason completed"
  row 2 $r "" $none "# note \\\\${nl}gh issue edit 5 --add-label status:verified"
  row 2 $r "" $none "echo 'a \\\\'${nl}gh issue edit 5 --add-label status:verified"
  row 2 $r "" $none "gh issue edit 5 \\${nl}--add-label status:verified"
  row 2 $r "" $none "gh issue edit 5 --add-label sta\\${nl}tus:verified"
  row 2 $r "" $none "echo x \\${nl}; gh issue close 5 --reason completed"
  row 0 $r "" $none "gh issue comment 5 --body 'a \\${nl}b'"
  row 0 $r "" $none "gh issue comment 5 --body \"a \\${nl}b\""
done
row 2 implementer "" $none "echo \\\\${nl}git push --force origin master"
row 2 implementer "" $none "echo \\\\\\\\${nl}git push --force origin master"
# fix round 4: a git heredoc stays live (and is refused) with any sibling but a plain git word or gh issue ride-along
for r in implementer consumer; do
  row 2 $r "" $none "cat() { bash; }; git commit -m \"\$(cat <<'EOF'${nl}gh issue edit 5 --add-label status:verified${nl}EOF${nl})\""
  row 2 $r "" $none "cat() { bash; }; git commit -m \"\$(cat <<'EOF'${nl}git push --force origin master${nl}EOF${nl})\""
  row 2 $r "" $none "cd /x && git commit -m \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
  row 2 $r "" $none "PATH=/tmp/evil git commit -m \"\$(cat <<'EOF'${nl}x${nl}EOF${nl})\""
done
row 0 implementer "" $none "git commit -m \"\$(cat <<'EOF'${nl}it's (done)${nl}EOF${nl})\" && git push origin develop"
row 0 implementer "" $none "git add -A && git commit -m \"\$(cat <<'EOF'${nl}fix(mcp): #5 - x${nl}EOF${nl})\" && git push origin feature && gh issue comment 5 --body $hi"
row 0 implementer "" $none "git merge --no-ff feature -m \"\$(cat <<'EOF'${nl}merge${nl}EOF${nl})\" && git push origin develop"
# fix round 4: a bare assignment, or a prefixed gh call, is a sibling that keeps a heredoc live
for r in implementer consumer; do
  row 2 $r "" $none "PATH=/tmp/evil; gh issue comment 5 --body $hi"
  row 2 $r "" $none "PATH=/tmp/evil${nl}gh issue comment 5 --body $hi"
  row 2 $r "" $none "PATH=/tmp/evil gh issue view 5; gh issue comment 5 --body $hi"
  # fix round 4: an expansion in the gh segment itself (outside the heredoc body) keeps it live
  row 2 $r "" $none "gh issue comment \${PATH::=/tmp/evil} --body $hi"
  row 2 $r "" $none "gh \${PATH::=/tmp/evil}issue comment 5 --body $hi"
  row 2 $r "" $none "gh issue comment 5 --body $hi \${PATH::=/tmp/evil}"
  # fix round 4: zsh applies a qualifier to a literal name, with any delimiter: no unquoted ( after a word
  row 2 $r "" $none "gh issue comment 5 --body x /tmp(e{gh issue edit 5 --add-label status:verified})"
  row 2 $r "" $none "gh issue comment 5 --body x /tmp(e:'gh issue edit 5 --add-label status:verified':)"
  row 2 $r "" $none "gh issue view 5 /tmp(N)"
  row 2 $r "" $none "c() { gh issue comment 5 --body hi; }"
  row 0 $r "" $none 'gh issue list --search "x (y)"'
  row 0 $r "" $none "gh pr view 5 --json files -q '.files[]'"
done
row 0 implementer "" $none "git log --grep='fix(x)'"
row 0 consumer "" $none "gh issue comment 5 --body 'see \`fn(x)\` and (a)'"
row 0 lead "" $none 'git log --since="$(python3 -c "print((1))")" --oneline'
row 2 implementer "" $none 'gh issue view $(echo /tmp(N))'
row 0 implementer "" $none 'for b in $(git branch --list); do echo "$b"; done'
row 0 implementer "" $none 'if (( 1 > 0 )); then git status; fi'
# fix round 5: a backtick inside double quotes on a gh/git line runs before gh or git sees the word
for r in implementer consumer; do
  row 2 $r "" $none "gh issue view 5 --json \"\`echo /tmp(e:'gh issue edit 5 --add-label status:verified':)\`\""
  row 2 $r "" $none "gh issue view 5 --json \"\`echo /tmp(e{'gh issue edit 5 --add-label status:verified'})\`\""
  row 2 $r "" $none "git log --format=\"\`echo /tmp(e{touch /tmp/pwn})\`\""
  row 2 $r "" $none "gh issue comment 5 --body \"uses \`x\`\""
  row 0 $r "" $none "gh issue comment 5 --body 'uses \`x\`'"
  row 0 $r "" $none "gh issue comment 5 --body \"\$(cat <<'EOF'${nl}uses \`code\` spans${nl}EOF${nl})\""
  row 0 $r "" $none "gh issue edit 5 --remove-label owner:implementer --add-label owner:tester && gh issue comment 5 --body \"\$(cat <<'EOF'${nl}Fixed in \`abc123\` on develop; \`validate_workflow()\` now warns.${nl}EOF${nl})\""
done
row 0 implementer "" $none "git commit -m \"\$(cat <<'EOF'${nl}fix: \`x\` -> \`y\`${nl}EOF${nl})\" && git push origin develop"
# fix round 5: a ride-along sibling is fully literal too; a comment ends at its newline, backslash or not
for r in implementer consumer; do
  row 2 $r "" $none "gh issue comment 5 --body $hi && gh issue view \${PATH::=/tmp/evil}"
  row 2 $r "" $none "gh issue view \${PATH::=/tmp/evil} && gh issue comment 5 --body $hi"
  row 2 $r "" $none "# note \\${nl}gh issue edit 5 --add-label status:verified"
  row 0 $r "" $none "# note \\${nl}echo hi"
  row 0 $r "" $none "# note \\${nl}gh issue view 5"
done
finish
