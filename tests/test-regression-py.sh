#!/usr/bin/env bash
# The Python regression driver (harness/drivers/regression.py, R8) against
# run-regression.sh: the same scenarios as test-drivers.sh's section 7, run
# by both drivers over the same fixtures, with the same assertions, and
# then each scenario's output diffed between the two (timestamps and pids
# normalized). Remove the bash half when the shim replaces run-regression.sh.
. "$(dirname "$0")/lib.sh"

# --- fixtures, as test-drivers.sh builds them
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
mkdir -p "$T/seed/plugins/dw"; echo x > "$T/seed/plugins/dw/README"
git -C "$T/seed" add -A; git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm seed
git -C "$T/seed" push -q origin HEAD:develop 2>/dev/null
git clone -q -b develop "$T/origin.git" "$T/src"
sha="$(git -C "$T/src" rev-parse HEAD)"

mkdir "$T/h"
(cd "$HARNEST" && tar cf - --exclude ./logs --exclude ./.git --exclude ./.env .) | (cd "$T/h" && tar xf -)
cat > "$T/h/regression-suite-tiny.md" <<'EOS'
# tiny suite
## Fixtures
none
### S-F001 — first
steps, with a fenced example that is not a case:
```
### S-F999 — an example heading
```
### S-F002 — second
steps
EOS
cat > "$T/h/regression-suite-tinymem.md" <<'EOM'
# tiny suite with a memory-heavy case
## Fixtures
none
### S-F001 — first
steps
### S-F079 — 8192 squared
steps
EOM
git -C "$T/h" init -q && git -C "$T/h" add -A && git -C "$T/h" -c user.name=t -c user.email=t@t commit -qm h

ln -s "$HARNEST/tests/fake-gh.py" "$T/bin/gh"
echo '{"o/r": [], "h/r": []}' > "$T/board.json"
printf '%s\n' "${sha:0:9}" > "$T/lem-head"
cat > "$T/bin/ssh" <<EOS
#!/usr/bin/env bash
case "\$*" in
  *mini-ai*) echo "develop @ \$(cat "$T/mini-head" 2>/dev/null || echo 0000000)" ;;
  *) echo "develop @ \$(cat "$T/lem-head")" ;;
esac
EOS
cat > "$T/bin/claude" <<'EOS'
#!/usr/bin/env bash
echo "claude $*" | cut -c1-200 >> "$FAKE_CLAUDE_LOG"
[ -z "${FAKE_CLAUDE_DO:-}" ] || eval "$FAKE_CLAUDE_DO" >/dev/null
echo '{"type":"system","subtype":"init","model":"claude-fake"}'
echo '{"type":"result","subtype":"success","num_turns":2,"duration_ms":1000,"total_cost_usd":0.01,"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}'
EOS
chmod +x "$T/bin/ssh" "$T/bin/claude"
export FAKE_CLAUDE_LOG="$T/claude-calls" FAKE_GH_LOG="$T/gh-calls"
mini_health() { printf '#!/usr/bin/env bash\necho '"'"'{"status":"ok","device":"mps","hostname":"%s"}'"'"'\n' "${1:-mini-ai.lan}" > "$T/bin/curl"; chmod +x "$T/bin/curl"; }

# reg <impl> <out> [VAR=value ...] -- <driver args>: one run of a driver,
# from a clean log directory, its stdout+stderr in $T/<impl>/<out>.
reg() {
  local impl="$1" out="$2"; shift 2
  local -a vars=()
  while [ "$1" != -- ]; do vars+=("$1"); shift; done; shift
  local -a cmd=(./run-regression.sh)
  [ "$impl" = bash ] || cmd=(python3 -m harness.drivers.regression)
  mkdir -p "$T/$impl"
  (cd "$T/h" && env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman SOURCE_DIR="$T/src" \
     SESSION_RETRY_PAUSE_SECS=0 DW_TOKEN=tok ${vars[@]+"${vars[@]}"} "${cmd[@]}" "$@") > "$T/$impl/$out" 2>&1
}
# norm <file>: what the two drivers may differ in, made equal
norm() { sed -E -e 's/[0-9]{2}:[0-9]{2}:[0-9]{2}/HH:MM:SS/g' -e "s#$T#T#g" -e 's/[0-9]+ run-(loop|regression)/PID run-\1/g' -e 's/\.mcp\.[0-9]+(\.[A-Za-z0-9_]+)?\.json/.mcp.PID.json/g' "$1"; }
# sent_mcp <args file>: the --mcp-config file a session was handed, read back
# (a driver removes its file at exit, so the fake claude copies it: cap_mcp)
cat > "$T/cap-mcp.sh" <<'EOS'
#!/usr/bin/env bash
# cap-mcp.sh <dest> <claude args...>: save the file --mcp-config names
dest="$1"; shift
while [ "$#" -gt 0 ]; do [ "$1" = --mcp-config ] && cp "$2" "$dest"; shift; done
EOS
chmod +x "$T/cap-mcp.sh"
sent_mcp() { cat "${1%.args}.mcp"; }
calls() { grep -c 'claude -p' "$FAKE_CLAUDE_LOG"; }

cp "$T/h/regression-suite-tiny.md" "$T/tiny.md"
for impl in bash py; do
  rm -rf "$T/h/logs"; mkdir -p "$T/h/logs"
  # each driver starts from the same suite: the chunk prompt carries its text
  cp "$T/tiny.md" "$T/h/regression-suite-tiny.md"
  git -C "$T/h" -c user.name=t -c user.email=t@t commit -qm "tiny suite, as written" -- regression-suite-tiny.md >/dev/null 2>&1 || true
  : > "$FAKE_CLAUDE_LOG"

  # --- lem: two cases, one per session
  reg "$impl" lem.out PLUGIN_TREE="$T/plugin" CASES_PER_SESSION=1 -- smoke regression-suite-tiny.md
  eq  "$impl lem: exits cleanly" 0 $?
  eq  "$impl lem: two chunks and a sweep" 3 "$(calls)"
  has "$impl lem: the level header names lem's commit" "target=lem, head=develop @ " "$(grep 'regression run (' "$T/h/logs/loop.log" | tail -1)"
  has "$impl lem: chunk sessions are labelled" "[regression:smoke.2 of 2] usage:" "$(cat "$T/$impl/lem.out")"
  has "$impl lem: the sweep is labelled" "[regression:smoke.sweep] usage:" "$(cat "$T/$impl/lem.out")"
  cp "$T/h/logs/loop.log" "$T/$impl/lem.loop.log"; cp "$FAKE_CLAUDE_LOG" "$T/$impl/lem.calls"
  cp "$T/h/logs/.prompt.regression.chunk.md" "$T/$impl/lem.prompt.chunk.md"
  for c in S-F001 S-F002; do tail -1 "$T/h/regression-results/$c.jsonl" | jq -c 'del(.ts)'; done > "$T/$impl/lem.results"
  fails "$impl lem: no line for a fenced heading" test -e "$T/h/regression-results/S-F999.jsonl"
  has "$impl lem: a case it was handed and never answered is unreported" '"case":"S-F002","outcome":"unreported"' "$(cat "$T/$impl/lem.results")"

  # --- lem: a dirty suite is committed before the run, under no model's name
  echo "an edit made by hand" >> "$T/h/regression-suite-tiny.md"
  reg "$impl" dirty.out PLUGIN_TREE="$T/plugin" CASES_PER_SESSION=0 -- smoke regression-suite-tiny.md
  # (the run's own commit, of its results, follows it)
  eq  "$impl lem: hand edit committed" "regression: capture suite edits of unknown origin made outside a regression run" \
      "$(git -C "$T/h" log -1 --format=%s -- regression-suite-tiny.md)"
  has "$impl lem: under a neutral trailer" "Co-Authored-By: unknown (edited outside a regression run) <noreply@localhost>" \
      "$(git -C "$T/h" log -1 --format=%b -- regression-suite-tiny.md)"
  has "$impl lem: the run's results are its own commit" "regression-results/S-F001.jsonl" "$(git -C "$T/h" show --name-only --format= HEAD)"

  # --- lem: an edit during the run is committed under the model that ran
  : > "$FAKE_CLAUDE_LOG"
  reg "$impl" edit.out PLUGIN_TREE="$T/plugin" CASES_PER_SESSION=0 \
      FAKE_CLAUDE_DO="echo case >> '$T/h/regression-suite-tiny.md'" -- smoke regression-suite-tiny.md
  has "$impl lem: the run's edit is committed" "regression: update smoke suite from " "$(git -C "$T/h" log -1 --format=%s)"
  has "  under the model the session resolved to" "Co-Authored-By: Claude (claude-fake) <noreply@anthropic.com>" \
      "$(git -C "$T/h" log -1 --format=%b)"
  has "  naming the model label" "run (anthropic/claude-sonnet-5-5)" "$(git -C "$T/h" log -1 --format=%s)"

  # --- mini-ai: one whole-level session, with lem's lock held
  mini_health
  printf '%s\n' "${sha:0:7}" > "$T/mini-head"
  mkdir -p "$T/h/logs/.driver.lock"; echo "$$ run-loop" > "$T/h/logs/.driver.lock/owner"
  echo "dirty" >> "$T/h/regression-suite-tiny.md"
  before_head="$(git -C "$T/h" rev-parse HEAD)"
  : > "$FAKE_CLAUDE_LOG"
  reg "$impl" mini.out PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=0 \
      FAKE_CLAUDE_DO='printf "%s" "$2" > "$FAKE_PROMPT"; printf "%s\n" "$@" > "$FAKE_PROMPT.args"; echo "${HARNEST_TARGET:-unset}" > "$FAKE_PROMPT.target"' \
      FAKE_PROMPT="$T/$impl/mini-prompt" -- smoke regression-suite-tiny.md
  eq  "$impl mini-ai: runs while lem's lock is held" 0 $?
  eq  "$impl mini-ai: one whole-level session" 1 "$(calls)"
  has "$impl mini-ai: header names the target and its checkout" "target=mini-ai, head=develop @ ${sha:0:7}" "$(grep 'regression run (' "$T/h/logs/loop.mini-ai.log" | tail -1)"
  sysprompt="$(cat "$T/h/logs/.prompt.regression.mini-ai.whole.md")"
  has "$impl mini-ai: prompt names the server it asked" "the mini-ai server (mps on mini-ai.lan) is running develop @ " "$(cat "$T/$impl/mini-prompt")"
  has "$impl mini-ai: system prompt moves perf history" "regression-perf/mini-ai/<case>.jsonl" "$sysprompt"
  has "$impl mini-ai: system prompt forbids suite edits" "The suite files. Every case in them runs on lem" "$sysprompt"
  eq  "$impl mini-ai: the guard is told the target" "mini-ai" "$(cat "$T/$impl/mini-prompt.target")"
  has "$impl mini-ai: skip and differ counts are logged" "case(s) skipped" "$(cat "$T/$impl/mini.out")"
  eq  "$impl mini-ai: no suite commit, only its own results" "regression-results/mini-ai/S-F001.jsonl regression-results/mini-ai/S-F002.jsonl" \
      "$(git -C "$T/h" diff --name-only "$before_head" HEAD | tr '\n' ' ' | sed 's/ $//')"
  has "$impl mini-ai: header tags the level for the curator" "level=smoke.mini-ai," "$(grep 'regression run (' "$T/h/logs/loop.mini-ai.log" | tail -1)"
  has "$impl mini-ai: sessions are labelled for retro" "[regression-mini-ai:smoke] usage:" "$(cat "$T/$impl/mini.out")"
  has "$impl mini-ai: plugin is its own worktree's" "--plugin-dir
$T/plugin-mini/plugins/dw" "$(cat "$T/$impl/mini-prompt.args")"
  ok  "$impl mini-ai: its own log" test -s "$T/h/logs/regression.mini-ai.log"
  eq  "$impl mini-ai: the lem lock is left as it was" "$$ run-loop" "$(cat "$T/h/logs/.driver.lock/owner")"
  git -C "$T/h" checkout -q -- regression-suite-tiny.md
  cp "$T/h/logs/loop.mini-ai.log" "$T/$impl/mini.loop.log"; cp "$T/$impl/mini-prompt.args" "$T/$impl/mini.args"
  cp "$T/h/logs/.prompt.regression.mini-ai.whole.md" "$T/$impl/mini.prompt.whole.md"

  # --- mini-ai: memory-heavy cases are never handed out
  : > "$FAKE_CLAUDE_LOG"
  reg "$impl" mem.out PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=1 -- smoke regression-suite-tinymem.md
  eq  "$impl mini-ai: held-back case runs no session (one chunk + sweep)" 2 "$(calls)"
  has "$impl mini-ai: the held-back case is logged as skipped" "REGRESSION-SKIP: S-F079 memory" "$(cat "$T/$impl/mem.out")"
  has "$impl mini-ai: and counted" "1 case(s) skipped" "$(cat "$T/$impl/mem.out")"
  eq  "$impl mini-ai: only S-F001 is handed out" "" "$(grep 'session .*: .*S-F079' "$T/h/logs/loop.mini-ai.log" || true)"
  rm -rf "$T/h/logs/.driver.lock"

  # --- mini-ai: preflight
  printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bin/curl"
  : > "$FAKE_CLAUDE_LOG"
  reg "$impl" down.out PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=0 -- smoke regression-suite-tiny.md
  eq  "$impl mini-ai: no server answering stops it" 1 $?
  has "$impl mini-ai: and says so, and how to start it" "no dw server answering at http://mini-ai:8765/mcp (DW_TARGET=mini-ai): scripts/testbed.sh mini-ai start" "$(cat "$T/$impl/down.out")"
  eq  "$impl mini-ai: before any session" 0 "$(calls)"
  mini_health lem
  reg "$impl" wrong.out PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=0 -- smoke regression-suite-tiny.md
  eq  "$impl mini-ai: another host answering stops it" 1 $?
  has "  and says which" "is lem, not mini-ai" "$(cat "$T/$impl/wrong.out")"

  # --- bad knobs fail before anything runs
  reg "$impl" level.out -- nosuch
  eq  "$impl: an unknown level is refused" 1 $?
  has "  naming the levels" "unknown level 'nosuch' (expected: smoke, complete, model-specific, security, all)" "$(cat "$T/$impl/level.out")"
  reg "$impl" target.out DW_TARGET=local -- smoke
  eq  "$impl: an unknown target is refused" 1 $?
  # the Python driver also knows minid (regression only; not in target_row)
  has "  naming the targets" "DW_TARGET must be one of: lem mini-ai" "$(cat "$T/$impl/target.out")"
  has "  and what was asked" "(got 'local')" "$(cat "$T/$impl/target.out")"
  reg "$impl" model.out PLUGIN_TREE="$T/plugin" REGRESSION_MODEL=qwen3:32b -- smoke regression-suite-tiny.md
  eq  "$impl: a non-Claude model under anthropic is refused" 1 $?
  has "  saying why" "is not an Anthropic model name" "$(cat "$T/$impl/model.out")"
  reg "$impl" chunk.out PLUGIN_TREE="$T/plugin" CASES_PER_SESSION=x -- smoke regression-suite-tiny.md
  eq  "$impl: a bad CASES_PER_SESSION is refused" 1 $?
  : > "$FAKE_CLAUDE_LOG"
  reg "$impl" token.out PLUGIN_TREE="$T/plugin" DW_TOKEN= -- smoke regression-suite-tiny.md
  eq  "$impl: no token in the environment is refused" 1 $?
  has "  naming the variable to set" "set DW_TOKEN_LEM (or DW_TOKEN) in the environment" "$(cat "$T/$impl/token.out")"
  eq  "  before any session" 0 "$(calls)"
  mini_health
  reg "$impl" ptok.out PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=0 DW_TOKEN_MINI_AI=minitok DW_TOKEN=lemtok \
      FAKE_CLAUDE_DO='printf "%s\n" "$@" > "$FAKE_PROMPT.args"; "'"$T"'/cap-mcp.sh" "$FAKE_PROMPT.mcp" "$@"' FAKE_PROMPT="$T/$impl/ptok" -- smoke regression-suite-tiny.md
  has "$impl: a server's own token wins over DW_TOKEN" "Bearer minitok" "$(sent_mcp "$T/$impl/ptok.args")"
  printf '# secrets\nDW_TOKEN_MINI_AI="filetok"\nPROVIDER=ollama\n' > "$T/secrets.env"
  reg "$impl" ftok.out PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=0 DW_TOKEN='' HARNEST_ENV_FILE="$T/secrets.env" \
      FAKE_CLAUDE_DO='printf "%s\n" "$@" > "$FAKE_PROMPT.args"; "'"$T"'/cap-mcp.sh" "$FAKE_PROMPT.mcp" "$@"' FAKE_PROMPT="$T/$impl/ftok" -- smoke regression-suite-tiny.md
  eq  "$impl: the token can come from the secrets file alone" 0 $?
  has "  and is the one sent" "Bearer filetok" "$(sent_mcp "$T/$impl/ftok.args")"
  has "  a knob in it is ignored, saying so" "'PROVIDER' ignored: only DW_TOKEN and DW_TOKEN_* are read from it" "$(cat "$T/$impl/ftok.out")"
  reg "$impl" etok.out PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=0 DW_TOKEN_MINI_AI=envtok HARNEST_ENV_FILE="$T/secrets.env" \
      FAKE_CLAUDE_DO='printf "%s\n" "$@" > "$FAKE_PROMPT.args"; "'"$T"'/cap-mcp.sh" "$FAKE_PROMPT.mcp" "$@"' FAKE_PROMPT="$T/$impl/etok" -- smoke regression-suite-tiny.md
  has "$impl: the environment wins over the file" "Bearer envtok" "$(sent_mcp "$T/$impl/etok.args")"

  # --- the lock: a run waits on the mini-ai loop's lock, not lem's
  mini_health
  mkdir "$T/h/logs/.driver.lock.mini-ai"; echo "$$ run-loop" > "$T/h/logs/.driver.lock.mini-ai/owner"
  if [ "$impl" = bash ]; then cmd=(./run-regression.sh); else cmd=(python3 -m harness.drivers.regression); fi
  (cd "$T/h" && exec env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman SOURCE_DIR="$T/src" \
     PLUGIN_TREE="$T/plugin-mini" DW_TARGET=mini-ai CASES_PER_SESSION=0 DW_TOKEN=tok "${cmd[@]}" smoke regression-suite-tiny.md) > "$T/$impl/wait.out" 2>&1 &
  regpid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q waiting "$T/$impl/wait.out" 2>/dev/null && break; sleep 1; done
  kill "$regpid" 2>/dev/null; wait "$regpid" 2>/dev/null
  has "$impl: waits on the mini-ai loop" "waiting for '$$ run-loop'" "$(cat "$T/$impl/wait.out")"
  eq  "$impl: stopped while waiting, it leaves the holder's lock alone" "$$ run-loop" "$(cat "$T/h/logs/.driver.lock.mini-ai/owner")"
  rm -rf "$T/h/logs/.driver.lock.mini-ai"
  rm -f "$T/bin/curl"
done

# --- the same output, line for line
for f in lem.out lem.loop.log lem.calls lem.prompt.chunk.md lem.results mini.out mini.loop.log mini.args mini.prompt.whole.md \
         mem.out down.out wrong.out level.out model.out chunk.out token.out ptok.args ftok.args etok.args; do
  d="$(diff <(norm "$T/bash/$f") <(norm "$T/py/$f") | head -10)"
  eq "parity: $f" "" "$d"
done

# --- a session the driver stops is stopped with it
mkdir -p "$T/h/logs"
cat > "$T/bin/claude" <<EOS
#!/usr/bin/env bash
echo \$\$ > "$T/claude.pid"
sleep 60
EOS
chmod +x "$T/bin/claude"
(cd "$T/h" && exec env FAKE_GH_BOARD="$T/board.json" TICKET_REPO=o/r TICKET_OWNER=dkackman SOURCE_DIR="$T/src" \
   PLUGIN_TREE="$T/plugin" CASES_PER_SESSION=0 DW_TOKEN=tok python3 -m harness.drivers.regression smoke regression-suite-tiny.md) > "$T/stop.out" 2>&1 &
regpid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/claude.pid" ] && break; sleep 1; done
kill "$regpid"; wait "$regpid" 2>/dev/null
sleep 1
fails "py: a stopped driver's session doesn't outlive it" kill -0 "$(cat "$T/claude.pid")"
fails "  and its lock is released" test -d "$T/h/logs/.driver.lock"

finish
