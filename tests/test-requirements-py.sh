#!/usr/bin/env bash
# The requirements generator (harness/drivers/requirements.py) end to end,
# offline: a fake claude that answers REQUIREMENT lines for the cases in its
# prompt, a fake curl for the primary's health, a copy of the harness as its
# own repo. What it writes is read back from regression-requirements.json.
. "$(dirname "$0")/lib.sh"

mkdir "$T/h"
(cd "$HARNEST" && tar cf - --exclude ./logs --exclude ./.git --exclude ./.env .) | (cd "$T/h" && tar xf -)
rm -f "$T/h/regression-requirements.json"
cat > "$T/h/regression-suite-smoke.md" <<'EOS'
# tiny smoke
## Fixtures
none
### S-F001 — validate only
steps
### S-F002 — an image
steps
### S-F003 — something odd
steps
### S-F004 — the agent forgets this one
steps
EOS
git -C "$T/h" init -q && git -C "$T/h" add -A && git -C "$T/h" -c user.name=t -c user.email=t@t commit -qm h
printf '#!/usr/bin/env bash\necho "develop @ abc1234"\n' > "$T/bin/ssh"
printf '#!/usr/bin/env bash\ncat >/dev/null; echo '"'"'{"status":"ok","device":"cuda","hostname":"lem"}'"'"'\n' > "$T/bin/curl"
# claude: answers for the case IDs in its prompt ($2); S-F002 as SD 1.5, S-F003
# as unknown, S-F004 not at all, plus one malformed line and one for a case
# it wasn't given
cat > "$T/bin/claude" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
echo "$2" >> "$FAKE_PROMPTS"
text=""
for id in $(printf '%s' "$2" | grep -o 'case id="[A-Z]*-[A-Z][0-9]*"' | grep -o '[A-Z]*-[A-Z][0-9]*'); do
  case "$id" in
    S-F001) text="$text"'REQUIREMENT: {"case": "S-F001", "workflows": [], "models": [], "assets": [], "load": "none", "note": ""}\n' ;;
    S-F002) text="$text"'REQUIREMENT: {"case": "S-F002", "workflows": ["templates/text-to-image"], "models": ["sd15"], "assets": ["asset:qa-cast/a.wav"], "load": "light", "note": ""}\n' ;;
    S-F003) text="$text"'REQUIREMENT: {"case": "S-F003", "workflows": [], "models": [], "assets": [], "load": "unknown", "note": "cannot tell"}\n' ;;
  esac
done
text="$text"'REQUIREMENT: {not json}\nREQUIREMENT: {"case": "C-F999", "workflows": [], "models": [], "assets": [], "load": "none", "note": ""}\n'
printf '{"type":"system","subtype":"init","model":"claude-fake"}\n'
jq -nc --arg t "$(printf '%b' "$text")" '{type: "assistant", message: {id: "m1", usage: {input_tokens: 1}, content: [{type: "text", text: $t}]}}'
printf '{"type":"result","subtype":"success","num_turns":2,"duration_ms":1000,"total_cost_usd":0.01,"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1,"output_tokens":1}}\n'
EOS
chmod +x "$T/bin/ssh" "$T/bin/curl" "$T/bin/claude"
export FAKE_ARGS="$T/args" FAKE_PROMPTS="$T/prompts"
gen() { (cd "$T/h" && env SESSION_RETRY_PAUSE_SECS=0 "$@" python3 -m harness.drivers.requirements smoke) > "$T/gen.out" 2>&1; }
side() { jq -r "$1" "$T/h/regression-requirements.json"; }

: > "$FAKE_PROMPTS"
gen REQUIREMENTS_CASES_PER_SESSION=3
eq  "generator: exits cleanly" 0 $?
eq  "  two sessions for four cases at three a session" 2 "$(grep -c '^Answer with exactly' "$FAKE_PROMPTS" | tr -d ' ')"
eq  "  answers recorded" "S-F001 S-F002" "$(side '.cases | keys | join(" ")')"
eq  "  as given, asset: prefix dropped" "light templates/text-to-image sd15 qa-cast/a.wav" \
    "$(side '.cases["S-F002"] | [.load, .workflows[0], .models[0], .assets[0]] | join(" ")')"
eq  "  attributed to the model the session ran on" "anthropic/claude-fake" "$(side '.cases["S-F001"].by')"
has "  unknown is logged, not recorded" "S-F003: unknown (cannot tell); primary only" "$(cat "$T/gen.out")"
has "  a missing answer too" "S-F004: no answer; primary only" "$(cat "$T/gen.out")"
has "  a malformed line is reported" "unparseable: REQUIREMENT: {not json}" "$(cat "$T/gen.out")"
has "  a case it wasn't given is refused" "not a case this session was given" "$(cat "$T/gen.out")"
eq  "  committed" "requirements: smoke" "$(git -C "$T/h" log -1 --format=%s | cut -c1-19)"
has "  under the model's trailer" "Co-Authored-By: Claude (claude-fake) <noreply@anthropic.com>" "$(git -C "$T/h" log -1 --format=%b)"
# the session is read-only: only ToolSearch and read-only dw tools
args="$(cat "$FAKE_ARGS")"
has "  only ToolSearch among built-in tools" "--tools
ToolSearch" "$args"
has "  read-only dw tools allowed" "mcp__dw__get_workflow" "$args"
eq  "  no run, shell or file tool allowed" "" "$(printf '%s\n' "$args" | grep -E '^(mcp__dw__run_workflow|mcp__dw__delete_|Bash|Read|Edit|Write)' || true)"
# the entries the fleet reads are current
(cd "$T/h" && python3 -c "
from harness import requirements as r
side = r.load_sidecar(); b = r.case_blocks('regression-suite-smoke.md')
print(' '.join(c for c in b if r.need_for(c, b[c], side).known))") > "$T/known"
eq  "  the fleet sees them as current" "S-F001 S-F002" "$(cat "$T/known")"

# a rerun asks only about cases without a current entry
: > "$FAKE_PROMPTS"
gen
eq  "rerun: only the cases still unknown" "S-F003 S-F004" "$(grep -o 'case id="[A-Z]*-[A-Z][0-9]*"' "$FAKE_PROMPTS" | grep -o '[A-Z]*-[A-Z][0-9]*' | tr '\n' ' ' | sed 's/ $//')"
# editing a case stales its entry
sed -i '' 's/^### S-F001 — validate only/### S-F001 — validate only, now with more/' "$T/h/regression-suite-smoke.md"
(cd "$T/h" && python3 -m harness.drivers.requirements --dry-run smoke) > "$T/dry.out"
has "an edited case is asked about again" "S-F001 S-F003 S-F004" "$(cat "$T/dry.out")"

# a stopped generator takes its session down with it
cat > "$T/bin/claude" <<EOS
#!/usr/bin/env bash
echo \$\$ > "$T/claude.pid"
sleep 60
EOS
chmod +x "$T/bin/claude"; rm -f "$T/claude.pid"
(cd "$T/h" && exec env SESSION_RETRY_PAUSE_SECS=0 python3 -m harness.drivers.requirements --force smoke) > "$T/stop.out" 2>&1 &
genpid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/claude.pid" ] && break; sleep 1; done
kill "$genpid"; wait "$genpid" 2>/dev/null
sleep 1
fails "stopped: its session doesn't outlive it" kill -0 "$(cat "$T/claude.pid")"

# no primary answering: refused before any session
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bin/curl"; : > "$FAKE_PROMPTS"
gen
eq  "no server: refused" 1 $?
has "  saying so" "no dw server answering at http://lem:8765/mcp" "$(cat "$T/gen.out")"
eq  "  before any session" "" "$(cat "$FAKE_PROMPTS")"
finish
