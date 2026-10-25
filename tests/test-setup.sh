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
# --- scripts/install-schedules.sh: launchd plists for the retro and the
# digest, written under a throwaway HOME (never the real LaunchAgents) from
# a copy of the script in a stub checkout, with launchctl stubbed to a log
mkdir -p "$T/r/scripts" "$T/home"
cp "$HARNEST/scripts/install-schedules.sh" "$T/r/scripts/"
for d in run-retro.sh run-digest.sh; do printf '#!/usr/bin/env bash\necho "%s ran in $PWD" >> "%s"\n' "$d" "$T/ran" > "$T/r/$d"; chmod +x "$T/r/$d"; done
printf '#!/usr/bin/env bash\necho "launchctl $*" >> "%s"\n' "$T/launchctl" > "$T/bin/launchctl"; chmod +x "$T/bin/launchctl"
sched() { HOME="$T/home" "$T/r/scripts/install-schedules.sh" "$@" 2>&1; }
la="$T/home/Library/LaunchAgents"
out="$(sched)"
eq  "schedules: install exits cleanly" 0 $?
has "schedules: says it is not loaded" "not loaded" "$out"
ok  "schedules: the retro plist parses" plutil -lint "$la/com.harnest.retro.plist"
ok  "schedules: the digest plist parses" plutil -lint "$la/com.harnest.digest.plist"
x() { plutil -extract "$2" raw -o - "$la/com.harnest.$1.plist" 2>/dev/null; }
eq  "schedules: retro is weekly, Monday" 1 "$(x retro StartCalendarInterval.Weekday)"
eq  "  at 06:00" "6:0" "$(x retro StartCalendarInterval.Hour):$(x retro StartCalendarInterval.Minute)"
eq  "schedules: digest is daily (no weekday)" "" "$(x digest StartCalendarInterval.Weekday)"
eq  "  at 07:00" "7:0" "$(x digest StartCalendarInterval.Hour):$(x digest StartCalendarInterval.Minute)"
eq  "schedules: launchctl is not called without --load" "" "$(cat "$T/launchctl" 2>/dev/null)"
# the job itself: skips with no loop lock, runs the driver in the checkout with one
job="$(x retro ProgramArguments.2)"
out="$(cd / && bash -c "$job")"
has "schedules: no loop lock, the retro skips" "skipped, no loop running" "$out"
eq  "  and runs nothing" "" "$(cat "$T/ran" 2>/dev/null)"
mkdir -p "$T/r/logs/.driver.lock"
(cd / && bash -c "$job") >/dev/null
(cd / && bash -c "$(x digest ProgramArguments.2)") >/dev/null
has "schedules: with the loop lock, the retro runs in the checkout" "run-retro.sh ran in $T/r" "$(cat "$T/ran")"
has "  and the digest" "run-digest.sh ran in $T/r" "$(cat "$T/ran")"
ok  "schedules: a rerun rewrites in place" sched
out="$(sched --uninstall)"
eq  "schedules: uninstall exits cleanly" 0 $?
eq  "schedules: uninstall leaves nothing" "" "$(ls -A "$la")"
eq  "schedules: and calls no launchctl" "" "$(cat "$T/launchctl" 2>/dev/null)"
finish
