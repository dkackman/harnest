#!/usr/bin/env bash
# launchd schedules for the two standalone proposal drivers (README,
# "Running it"): the retro (./run-retro.sh, weekly, Monday 06:00) and the
# approval digest (./run-digest.sh, daily 07:00). Each job cds to this
# checkout and skips, saying so, when logs/.driver.lock is absent: no loop
# is running, so there is nothing new to retro or to digest.
#
#   scripts/install-schedules.sh             # write both plists
#   scripts/install-schedules.sh --load      # write them and load them into launchd
#   scripts/install-schedules.sh --uninstall [--load]   # remove them (and unload)
#
# The plists go to ~/Library/LaunchAgents (com.harnest.retro.plist,
# com.harnest.digest.plist). launchctl is called only with --load, so a
# plain install or uninstall changes files and nothing else. A job's output
# is appended to logs/schedule-<name>.log. PATH is the one this script ran
# under, since launchd's own has neither claude nor gh. Rerunning rewrites
# the plists in place.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS="$HOME/Library/LaunchAgents"

mode=install load=0
for a in "$@"; do
  case "$a" in
    --uninstall) mode=uninstall ;;
    --load) load=1 ;;
    *) echo "usage: $0 [--uninstall] [--load]" >&2; exit 2 ;;
  esac
done

xml() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# plist <name> <driver> <calendar dict body>
plist() {
  local name="$1" driver="$2" when="$3" cmd
  cmd="cd $(printf '%q' "$REPO") || exit 1
if [ ! -e logs/.driver.lock ]; then echo \"\$(date '+%F %T') $name: skipped, no loop running (logs/.driver.lock absent)\"; exit 0; fi
echo \"\$(date '+%F %T') $name: start\"
exec ./$driver"
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.harnest.$name</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>$(printf '%s' "$cmd" | xml)</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$(printf '%s' "$REPO" | xml)</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$(printf '%s' "$PATH" | xml)</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
$when
  </dict>
  <key>StandardOutPath</key>
  <string>$(printf '%s' "$REPO/logs/schedule-$name.log" | xml)</string>
  <key>StandardErrorPath</key>
  <string>$(printf '%s' "$REPO/logs/schedule-$name.log" | xml)</string>
</dict>
</plist>
EOF
}

retro_when='    <key>Weekday</key>
    <integer>1</integer>
    <key>Hour</key>
    <integer>6</integer>
    <key>Minute</key>
    <integer>0</integer>'
digest_when='    <key>Hour</key>
    <integer>7</integer>
    <key>Minute</key>
    <integer>0</integer>'

for job in "retro run-retro.sh" "digest run-digest.sh"; do
  name="${job% *}" driver="${job#* }"
  f="$AGENTS/com.harnest.$name.plist"
  if [ "$mode" = uninstall ]; then
    [ "$load" = 1 ] && launchctl bootout "gui/$(id -u)/com.harnest.$name" 2>/dev/null || true
    if [ -e "$f" ]; then rm -f "$f"; echo "removed $f"; else echo "not installed: $f"; fi
    continue
  fi
  mkdir -p "$AGENTS" "$REPO/logs"
  when="$retro_when"; [ "$name" = digest ] && when="$digest_when"
  plist "$name" "$driver" "$when" > "$f.tmp" && mv "$f.tmp" "$f"
  echo "wrote $f"
  if [ "$load" = 1 ]; then
    launchctl bootout "gui/$(id -u)/com.harnest.$name" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$f"
    echo "loaded com.harnest.$name"
  fi
done
if [ "$mode" = install ] && [ "$load" = 0 ]; then
  echo "not loaded: rerun with --load, or: launchctl bootstrap gui/\$(id -u) <plist>"
fi
