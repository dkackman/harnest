#!/usr/bin/env bash
# The implementer's hand-off gate (guard.py handoff_gate) on a fixture dw checkout: the
# UI's Playwright e2e (harnest#298), relative to the session's base commit like pytest.
# npm and the venv's python are stubs: npm's e2e writes the JSON report Playwright would,
# failing the titles listed in the tree's own ui/e2e-fails, so base and HEAD differ by
# what each commit holds. No browser, no server.
. "$(dirname "$0")/lib.sh"
guard="$HARNEST/agent-settings/hooks/guard.py"
stub_gh 'exit 1'
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}" >/dev/null 2>&1; }

# --- stubs: npm (logs each call to $NPM_LOG) and the venv python (pytest: nothing fails)
mkdir -p "$T/bin"
cat > "$T/bin/npm" <<'EOF'
#!/bin/bash
# npm run --silent <script> [-- --reporter=json]
script="$3"
echo "$script $(basename "$(dirname "$PWD")")" >> "$NPM_LOG"
case "$script" in
  check|lint|test|build) [ -e "BREAK_$script" ] && { echo "$script broke"; exit 1; }; exit 0 ;;
  e2e)
    [ -e e2e-noreport ] && { echo "Error: no Chromium"; exit 1; }
    python3 - "$PLAYWRIGHT_JSON_OUTPUT_FILE" <<'PY'
import json, os, sys
fails = [l.strip() for l in open("e2e-fails")] if os.path.exists("e2e-fails") else []
fails = [f for f in fails if f]
specs = [{"title": t, "tests": [{"status": "unexpected" if t in fails else "expected"}]}
         for t in ["opens the editor", "saves a workflow", "shows the event log"] + fails]
seen, uniq = set(), []
for s in specs:
    if s["title"] not in seen:
        seen.add(s["title"]); uniq.append(s)
doc = {"suites": [{"title": "journeys.spec.ts", "specs": [], "suites": [{"title": "editor", "specs": uniq}]}]}
json.dump(doc, open(sys.argv[1], "w"))
sys.exit(1 if fails else 0)
PY
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T/bin/npm"
export PATH="$T/bin:$PATH" NPM_LOG="$T/npm.log"

# --- the fixture: origin + a clone, base commit with a ui/ that has e2e
git init -q --bare -b develop "$T/origin.git"
s="$T/seed"
mkdir -p "$s/ui" "$s/dw"
echo "export default {}" > "$s/ui/playwright.config.ts"
echo '{}' > "$s/ui/package.json"
echo a > "$s/ui/app.ts"; echo a > "$s/dw/x.txt"
printf 'venv/\nui/node_modules/\n' > "$s/.gitignore"
git init -q -b develop "$s"; g "$s" add -A; g "$s" commit -m base
g "$s" remote add origin "$T/origin.git"; g "$s" push origin develop
w="$T/work"
git clone -q -b develop "$T/origin.git" "$w"
mkdir -p "$w/venv/bin" "$w/ui/node_modules"
printf '#!/bin/bash\nexit 0\n' > "$w/venv/bin/python"; chmod +x "$w/venv/bin/python"
base="$(git -C "$w" rev-parse HEAD)"
gitdir="$(git -C "$w" rev-parse --absolute-git-dir)"

# change <branch> <file> <content>: a commit on a branch off the base
change() { g "$w" checkout -q -B "$1" "$base"; printf '%s\n' "$3" > "$w/$2"; g "$w" add -A; g "$w" commit -m "$1"; }
# hand <expect> <what>: the hand-off, from the checkout's HEAD; its stderr in $err
hand() {
  : > "$NPM_LOG"
  err="$(jq -n --arg d "$w" '{tool_name: "Bash", tool_input: {command: "gh issue edit 5 --remove-label owner:implementer --add-label owner:tester --add-label status:fixed-pending-verify"}, cwd: $d}' \
    | HARNEST_BASE_COMMIT="$base" python3 "$guard" implementer 2>&1 >/dev/null)"
  eq "hand-off: $2" "$1" $?
}
calls() { grep -c "^$1 $2\$" "$NPM_LOG"; }

change ui-pass ui/app.ts b
hand 0 "a ui/ change whose e2e passes"
eq "  HEAD is built and run once" "1 1" "$(calls build work) $(calls e2e work)"
eq "  a green HEAD needs no base run" 0 "$(calls e2e harnest-base-tree)"
hand 0 "the same tree again: stamped, nothing rerun"
eq "  no npm call" 0 "$(wc -l < "$NPM_LOG" | tr -d ' ')"

change ui-break ui/e2e-fails "saves a workflow"
hand 2 "a ui/ change that breaks an e2e test"
has "  names the test" "journeys.spec.ts > editor > saves a workflow" "$err"
has "  says it passes on the base" "pass on ${base:0:10}" "$err"
eq "  a failing HEAD runs the base once" "1 1" "$(calls build harnest-base-tree) $(calls e2e harnest-base-tree)"
ok "  the base's failures are kept per base commit" test -f "$gitdir/harnest-base-e2e-$base"
ok "  the base worktree is gone" test ! -e "$gitdir/harnest-base-tree"
change ui-break2 ui/e2e-fails "opens the editor"
hand 2 "another failing HEAD on the same base"
eq "  the base is not rerun (kept)" 0 "$(calls e2e harnest-base-tree)"

change dw-only dw/x.txt b
hand 0 "no ui/ change: no e2e"
eq "  no build or e2e" 0 "$(grep -c 'build\|e2e' "$NPM_LOG")"

change ui-noreport ui/e2e-noreport x
hand 2 "HEAD cannot run e2e where the base could"
has "  says it ran on the base" "ran on ${base:0:10} but not on HEAD" "$err"

change ui-build ui/BREAK_build x
hand 2 "HEAD's build fails"
has "  names the build" "npm run build" "$err"

# a base that already fails a test: the same failure on HEAD is not this work's
g "$s" checkout -q develop; printf 'shows the event log\n' > "$s/ui/e2e-fails"; g "$s" add -A; g "$s" commit -m "red develop"
g "$s" push origin develop; g "$w" fetch -q origin
base="$(git -C "$w" rev-parse origin/develop)"
change red-same ui/app.ts c
hand 0 "the base's own failure, still failing on HEAD"
change red-new ui/app.ts d
printf 'shows the event log\nopens the editor\n' > "$w/ui/e2e-fails"; g "$w" commit -am more
hand 2 "a new failure on a red base"
has "  names only the new one" "editor > opens the editor" "$err"
case "$err" in *"shows the event log"*) _report 1 "  not the base's" ;; *) _report 0 "  not the base's" ;; esac

# a base that cannot run e2e at all (no Chromium there): skipped, as the checks skip
g "$s" rm -q ui/e2e-fails; echo x > "$s/ui/e2e-noreport"; g "$s" add -A; g "$s" commit -m "no browser"
g "$s" push origin develop; g "$w" fetch -q origin
base="$(git -C "$w" rev-parse origin/develop)"
change unrunnable ui/app.ts e
hand 0 "a base that cannot run e2e: skipped"
eq "  kept as unrunnable" UNRUNNABLE "$(cat "$gitdir/harnest-base-e2e-$base")"

# two hand-offs on one box take turns on the port lock
g "$s" rm -q ui/e2e-noreport; g "$s" commit -m "browser back"; g "$s" push origin develop; g "$w" fetch -q origin
base="$(git -C "$w" rev-parse origin/develop)"
change locked ui/app.ts f
python3 -c 'import fcntl, sys, time; f = open("/tmp/harnest-dw-e2e.lock", "a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[1], "w").close(); time.sleep(3)' "$T/held" &
holder=$!
for _ in $(seq 1 50); do [ -e "$T/held" ] && break; python3 -c 'import time; time.sleep(0.1)'; done
t0=$(date +%s)
hand 0 "waits for another hand-off's e2e to finish"
ok "  it waited" test $(( $(date +%s) - t0 )) -ge 2
wait "$holder" 2>/dev/null
finish
