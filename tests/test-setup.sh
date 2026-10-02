#!/usr/bin/env bash
# scripts/setup-mac-loop.sh offline: a bare origin with a develop branch and
# an install.sh that only makes venv/bin/activate. It makes the implementer's
# clone only; the test bed is set up on its own host. Run twice: the second
# run changes nothing.
. "$(dirname "$0")/lib.sh"
setup="$HARNEST/scripts/setup-mac-loop.sh"
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
printf '#!/usr/bin/env bash\nmkdir -p venv/bin; echo "# venv" > venv/bin/activate; echo "install in $PWD" >> "%s"\n' "$T/installs" > "$T/seed/install.sh"
git -C "$T/seed" add -A; git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm seed
git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
run_setup() {
  env DW_ORIGIN_URL="$T/origin.git" SOURCE_DIR="$T/agent-mps" \
    "$setup" "$@" 2>&1
}
out="$(run_setup --dry-run)"
eq  "setup: dry run exits cleanly" 0 $?
has "setup: dry run says what it would clone" "would clone" "$out"
eq  "setup: dry run makes nothing" "" "$(ls -d "$T/agent-mps" 2>/dev/null)"
out="$(run_setup)"
eq  "setup: exits cleanly" 0 $?
eq  "setup: the implementer clone is on develop" "develop" "$(git -C "$T/agent-mps" branch --show-current)"
ok  "setup: the implementer clone has a venv" test -f "$T/agent-mps/venv/bin/activate"
has "setup: names the next step, the test bed" "scripts/testbed.sh mini-ai status" "$out"
has "  then a cycle against it" "DW_TARGET=mini-ai SHARED_PASSES=1 MAX_CYCLES=1 ./run-loop.sh" "$out"
eq  "setup: one install, the implementer's (the test bed is set up on its host)" 1 "$(wc -l < "$T/installs" | tr -d ' ')"
head1="$(git -C "$T/agent-mps" rev-parse HEAD)"
out="$(run_setup)"
eq  "setup: a rerun exits cleanly" 0 $?
has "setup: a rerun says what is already there" "already there" "$out"
eq  "setup: a rerun installs nothing" 1 "$(wc -l < "$T/installs" | tr -d ' ')"
eq  "setup: a rerun leaves the clone" "$head1" "$(git -C "$T/agent-mps" rev-parse HEAD)"
finish
