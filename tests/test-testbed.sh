#!/usr/bin/env bash
# scripts/testbed.sh offline: a fake ssh that records each call and a fake
# curl for health. No host is reached.
. "$(dirname "$0")/lib.sh"
tb="$HARNEST/scripts/testbed.sh"
printf '#!/usr/bin/env bash\necho "ssh $*" >> "%s"\ncase "$*" in *rev-parse*) echo "develop @ abc1234" ;; esac\n' "$T/ssh-calls" > "$T/bin/ssh"
printf '#!/usr/bin/env bash\necho '"'"'{"status":"ok","device":"mps","hostname":"mini-ai.lan"}'"'"'\n' > "$T/bin/curl"
chmod +x "$T/bin/ssh" "$T/bin/curl"
last() { tail -1 "$T/ssh-calls"; }

out="$("$tb" mini-ai status)"
eq  "status: exits 0 while it serves" 0 $?
has "status: the commit it serves" "mini-ai (mini-ai): develop @ abc1234" "$out"
has "status: and its health" "serving: mps on mini-ai.lan at http://mini-ai:8765/mcp" "$out"
"$tb" mini-ai update >/dev/null
has "update: deploy.sh develop, on the host" "mini-ai ~/diffusers-workflow/scripts/deploy.sh develop" "$(last)"
"$tb" mini-ai update feat/x >/dev/null
has "update: a named branch" "deploy.sh feat/x" "$(last)"
"$tb" mini-ai update --force >/dev/null
has "update: --force passes through" "deploy.sh develop --force" "$(last)"
"$tb" mini-ai start >/dev/null
has "start: deploy.sh with no branch (the checkout as it is)" "scripts/deploy.sh " "$(last)"
"$tb" mini-ai stop >/dev/null
has "stop: SIGTERM to the port's listener only" "kill -TERM" "$(cat "$T/ssh-calls")"
"$tb" mini-ai logs 5 >/dev/null
has "logs: tail of the server log" "tail -n 5 ~/dw-serve.log" "$(last)"
"$tb" lem status >/dev/null
has "lem is a test bed too" "BatchMode=yes lem cd ~/diffusers-workflow" "$(cat "$T/ssh-calls")"
# a live driver on the target holds its lock: no restart under it
mkdir -p "$LOGS/.driver.lock.mini-ai"; echo "$$ run-loop" > "$LOGS/.driver.lock.mini-ai/owner"
n="$(wc -l < "$T/ssh-calls")"
for v in update start stop; do
  out="$("$tb" mini-ai $v 2>&1)"; eq "$v: refused under a live run-loop" 1 $?
done
has "  saying who holds it" "run-loop (pid $$) holds mini-ai's driver lock" "$out"
eq  "  before any ssh" "$n" "$(wc -l < "$T/ssh-calls")"
ok  "  --force overrides" "$tb" mini-ai update --force
ok  "status is fine under a lock" "$tb" mini-ai status
rm -rf "$LOGS/.driver.lock.mini-ai"
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bin/curl"
out="$("$tb" mini-ai status)"
eq  "status: exits 1 when it doesn't answer" 1 $?
has "  and says so" "not answering at http://mini-ai:8765/mcp" "$out"
fails "an unknown target" "$tb" nope status
fails "an unknown verb" "$tb" mini-ai reboot
fails "no verb" "$tb" mini-ai
finish
