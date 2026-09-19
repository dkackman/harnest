# Agent Context-Cost Reduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut every agent session's per-turn context by ~25k tokens (≈25–35% of session cost) without changing what any role can do, and file the two server-side follow-ups the logs point at.

**Architecture:** Every driver already launches `claude -p` with a per-role flag array (`TESTER_FLAGS`, `IMPLEMENTER_FLAGS`, `REGRESSION_FLAGS`, `RESEARCH_FLAGS`). Three additions go into those arrays: `--setting-sources project,local` (stop inheriting Don's user-level plugins, hooks and memory), `--tools <role list>` (stop shipping ~20k tokens of built-in tool schemas the role is denied anyway), and `--effort` (which user settings used to supply and now must be explicit). The role prompt moves from a `Read` tool result into `--append-system-prompt-file`. The implementer's auto-mode classifier environment, previously inherited from user settings, becomes a harness-owned `--settings` file. Two GitHub `idea` issues capture the dw-server-side levers (the `wait_for_job` 55 s cap; `list_*` payload sizes).

**Tech Stack:** bash (zsh-compatible, `set -e` drivers), `claude` CLI ≥ the version that has `--setting-sources`/`--tools`/`--effort`/`--append-system-prompt-file`, `gh`, `python3` for log analysis.

**Spec:** No separate spec doc. The measurements this plan rests on (taken 2026-09-19 from `logs/*.jsonl`) are in "Context" below; the plan argues from them.

## Global Constraints

- No agent ever runs with `--dangerously-skip-permissions` (CLAUDE.md "Permissions").
- Keep the tester/regression/researcher isolation asymmetry intact: no change may give a consumer role code/box access or let the implementer self-verify.
- Keep `owner:*` / `status:*` label prefixes; ticket protocol unchanged.
- `providers.sh` is sourced by all three drivers; anything shared by two drivers lives there, not in a driver.
- Every `claude -p` session stays under `--max-budget-usd` and `--autocompact` as today.
- Non-Anthropic providers (`ollama`, `gateway`) must keep working: don't pass a flag they can't take unless gated on provider.
- Commit messages end with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

## Context (measured)

- Cost in `grep usage: logs/loop.log` is dominated by `cache_read`, i.e. Σ(context per turn). Turn-1 context is 50k (tester), 56k (implementer), 36k (regression) before any work.
- Measured on haiku, one-word prompt, cwd = this repo:
  `as today` 41.6k / 91 tools / 94 skills → `--setting-sources project,local` 43.9k / 88 / 55 → `+ --strict-mcp-config` 42.6k / 28 / 55 → `+ --tools "Bash,Read,Edit,Write,Glob,Grep,ToolSearch,Skill,TodoWrite"` **22.1k** / 9 / 55.
- Under `--setting-sources project,local`: zero SessionStart hooks fire, `plugins: []`. Today every session gets ~12.5 KB from hooks (superpowers preamble 3.5 KB, `remember` memory dump 8–9 KB), and the `remember` plugin captures the agents' sessions *into* `.remember/today-*.md`, which is re-injected into every later session (see the `S-F009–S-F024 regression-smoke` entries there). `SessionStart:compact` re-injects on every autocompact too (570 KB total in implementer.jsonl).
- Built-in tools actually used across all logged sessions: tester/regression → `mcp__dw__*`, Bash, Read, Edit, Write, Grep, ToolSearch, Skill (Glob: never, but cheap and in the prompts). Implementer additionally: Agent (5), WebFetch (1), WebSearch (1), Skill (2: superpowers TDD/debugging). Researcher: WebFetch by role prompt.
- User settings (`~/.claude/settings.json`) currently supply `effortLevel: medium` and `autoMode.environment` to every agent session. Both vanish under `--setting-sources project,local` and must be supplied explicitly.
- Verified end-to-end: `--setting-sources project,local` + `--tools …` + real `--mcp-config` + `--plugin-dir` → dw connects, `dw:*` skills load, sonnet calls `get_server_info` at 31.8k base ctx.
- `wait_for_job`: 477 calls in regression.jsonl, up to 17 polls per job, agents already pass the max `timeout_seconds=55`; the cap is `MAX_WAIT_SECONDS = 55` in `dw_mcp/diagnose.py:23`. Each poll is a full-context turn.
- Median result sizes: `list_workflows` 13.6 KB (55 KB unfiltered), `list_assets` 13.9 KB, `list_workspaces` 10.8 KB.

## File Structure

- Create `measure-base-ctx.sh` — one-shot measurement of turn-1 context for a given flag set (the "reason is measured" tool for this change and any later tuning).
- Modify `providers.sh` — add `ISOLATION_FLAGS`, per-role `*_TOOLS` strings, `effort_flags`, `EFFORT` defaults; drop `Agent` from `CONSUMER_PERMISSION_FLAGS`.
- Create `agent-settings/implementer.json` — the auto-mode classifier environment for the implementer (replaces the inherited user-level one).
- Modify `run-loop.sh` — wire the new flags into `TESTER_FLAGS`/`IMPLEMENTER_FLAGS`, add per-role effort knobs, pass role prompt via `--append-system-prompt-file`, reword session prompts.
- Modify `run-regression.sh`, `run-research.sh` — same wiring.
- Modify `CLAUDE.md` — document the new knobs and the reason.

---

### Task 0: Baseline measurement script

**Files:**
- Create: `measure-base-ctx.sh`

**Interfaces:**
- Produces: `./measure-base-ctx.sh <label> [claude flags...]` prints one line `<label>: turn1 ctx=NN.Nk tools=N skills=N`. Later tasks run it to verify their effect.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# measure-base-ctx.sh <label> [claude flags...]
# Prints the turn-1 context (input + cache read + cache write tokens), the
# number of tools and the number of skills a `claude -p` session starts with
# under the given flags. Runs a one-word prompt on haiku, so it costs well
# under a cent. This is how the driver flag sets are tuned: the number that
# matters for cost is what every turn of a session carries, and this is it.
#
#   ./measure-base-ctx.sh baseline
#   ./measure-base-ctx.sh lean --setting-sources project,local --tools "Bash,Read"
set -euo pipefail
label="$1"; shift
claude -p "Reply with the single word ok." --model haiku \
  --output-format stream-json --verbose --no-session-persistence "$@" \
  2>/dev/null < /dev/null | python3 -c '
import sys, json
label = sys.argv[1]; tools = skills = None
for line in sys.stdin:
    try: e = json.loads(line)
    except ValueError: continue
    if e.get("type") == "system" and e.get("subtype") == "init":
        tools = len(e.get("tools", [])); skills = len(e.get("slash_commands", []))
    if e.get("type") == "assistant":
        u = e["message"].get("usage", {})
        ctx = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
        print(f"{label}: turn1 ctx={ctx/1000:.1f}k tools={tools} skills={skills}")
        break
' "$label"
```

- [ ] **Step 2: Make it executable and record the baseline**

Run: `chmod +x measure-base-ctx.sh && ./measure-base-ctx.sh baseline`
Expected: a line like `baseline: turn1 ctx=41.6k tools=91 skills=94` (numbers within a few k of these).

- [ ] **Step 3: Commit**

```bash
git add measure-base-ctx.sh
git commit -m "drivers: add measure-base-ctx.sh, turn-1 context for a flag set

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 1: Isolation, tool and effort flags in providers.sh

**Files:**
- Modify: `providers.sh` (the `CONSUMER_PERMISSION_FLAGS` / `RESEARCHER_PERMISSION_FLAGS` block, ~lines 270–315)

**Interfaces:**
- Produces (globals every driver may use after sourcing):
  - `ISOLATION_FLAGS` array: `(--setting-sources project,local)`
  - `CONSUMER_TOOLS`, `RESEARCHER_TOOLS`, `IMPLEMENTER_TOOLS` strings (comma-separated, the value for `--tools`)
  - `EFFORT` default `medium`
  - `effort_flags <provider> <effort>` → echoes `--effort <effort>` for `anthropic`, nothing otherwise (Ollama/gateway don't take it)
- Changes: `CONSUMER_PERMISSION_FLAGS` no longer lists `Agent` (never used by a consumer role; it would be absent from the tool set anyway).

- [ ] **Step 1: Add the block after `RESEARCHER_PERMISSION_FLAGS`**

Insert immediately after the closing `)` of `RESEARCHER_PERMISSION_FLAGS`:

```bash
# Context every session carries on every turn, and doesn't need. Measured
# 2026-09-19 (measure-base-ctx.sh): a session started with ~42k tokens
# before its first tool call, ~20k of it built-in tool schemas the role is
# denied anyway (Artifact, Workflow, Agent, Monitor, ...), plus ~12 KB from
# user-level SessionStart hooks - the superpowers preamble and the remember
# plugin's dump of Don's own session memory, which was also *capturing* the
# agents' sessions back into .remember/ and re-injecting them everywhere.
# Cost here is cache_read = context x turns, so this is ~25k tokens off
# every turn of a 30-100 turn session.
#
# --setting-sources project,local: no user-level settings, so no user
# plugins, hooks, memory or MCP servers reach an unattended agent. The dw
# plugin still arrives via --plugin-dir; project settings (the source
# checkout's .claude/) still apply to the implementer. Two things the user
# level used to supply are now passed explicitly: effort (effort_flags) and
# the implementer's auto-mode environment (run-loop.sh, --settings).
ISOLATION_FLAGS=(--setting-sources project,local)

# --tools: the built-in tools a role gets *schemas* for. Everything a role
# actually used across every logged session, and nothing else. MCP tools
# are unaffected (they come from --mcp-config as deferred names).
CONSUMER_TOOLS="Bash,Read,Edit,Write,Glob,Grep,ToolSearch,Skill,TodoWrite"
RESEARCHER_TOOLS="Bash,Read,Glob,Grep,ToolSearch,WebFetch,TodoWrite"
IMPLEMENTER_TOOLS="Bash,Read,Edit,Write,Glob,Grep,ToolSearch,Skill,Agent,WebFetch,WebSearch,TodoWrite"

# Effort was inherited from ~/.claude/settings.json (effortLevel: medium)
# until ISOLATION_FLAGS cut that off; `medium` is therefore the default that
# preserves what every logged session ran at. One knob per role in the
# drivers (IMPLEMENTER_EFFORT etc.), all defaulting to this.
EFFORT="${EFFORT:-medium}"

# effort_flags <provider> <effort>
# The --effort words for a session, or nothing: the flag is an Anthropic
# request parameter and a non-anthropic provider gets nothing it can't take.
effort_flags() {
  local provider="$1" effort="$2"
  case "$effort" in
    low|medium|high|xhigh|max) ;;
    *) echo "run: effort must be one of low|medium|high|xhigh|max, got '$effort'" >&2; return 1 ;;
  esac
  [ "$provider" = anthropic ] && printf -- '--effort %s' "$effort"
  return 0
}
```

- [ ] **Step 2: Drop `Agent` from the consumer allowlist**

In `CONSUMER_PERMISSION_FLAGS`, change
```bash
    "mcp__dw__*" "ToolSearch" "Skill" "Agent" "TodoWrite"
```
to
```bash
    "mcp__dw__*" "ToolSearch" "Skill" "TodoWrite"
```

- [ ] **Step 3: Verify the block sources cleanly and effort_flags behaves**

Run:
```bash
bash -c 'source ./providers.sh; echo "[$(effort_flags anthropic medium)] [$(effort_flags ollama medium)]"; effort_flags anthropic silly; echo "rc=$?"; echo "${ISOLATION_FLAGS[@]}" "$CONSUMER_TOOLS"'
```
Expected: `[--effort medium] []`, then the `effort must be one of` error and `rc=1`, then `--setting-sources project,local Bash,Read,...`. (`providers.sh` reads `PROVIDER` and, for the ollama/gateway branches, `OLLAMA_*`/`GW_*`; with `PROVIDER` unset it defaults to anthropic and sources cleanly — `REPO`/`LOGS` are only used by functions, not at source time.)

- [ ] **Step 4: Measure the consumer flag set**

Run:
```bash
./measure-base-ctx.sh consumer "${ISOLATION_FLAGS[@]}" --tools "$CONSUMER_TOOLS" --strict-mcp-config --mcp-config '{"mcpServers":{}}'
```
(with `ISOLATION_FLAGS`/`CONSUMER_TOOLS` sourced as in Step 3, or spelled out.)
Expected: `consumer: turn1 ctx≈22k tools=9`.

- [ ] **Step 5: Commit**

```bash
git add providers.sh
git commit -m "providers: ISOLATION_FLAGS, per-role --tools lists, effort_flags

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Implementer auto-mode environment as a harness-owned settings file

The implementer runs `--permission-mode auto`; the classifier reads `autoMode.environment` from settings, which today comes from Don's user settings (and describes `/Users/don/testing/11`, a stale trusted repo). Under `ISOLATION_FLAGS` it would get none. Supply one that describes this loop.

**Files:**
- Create: `agent-settings/implementer.json`

**Interfaces:**
- Produces: `agent-settings/implementer.json`, passed by run-loop.sh as `--settings "$REPO/agent-settings/implementer.json"` (Task 3).

- [ ] **Step 1: Confirm `--settings` is honoured alongside `--setting-sources project,local`**

Run (from this repo):
```bash
claude -p 'Run exactly: echo isolation-ok' --model haiku --output-format stream-json --verbose --no-session-persistence \
  --setting-sources project,local --permission-mode dontAsk --tools Bash \
  --settings '{"permissions":{"allow":["Bash(echo isolation-ok)"]}}' 2>/dev/null </dev/null \
  | grep -o '"content":"isolation-ok[^"]*"' | head -1
```
Expected: `"content":"isolation-ok\n"` (the allow entry from `--settings` let the command run under `dontAsk`). If nothing prints, `--settings` is being dropped with the user source; stop and report — Task 3 must then pass the environment another way (`--append-system-prompt` is not it; the classifier reads settings).

- [ ] **Step 2: Write the settings file**

```json
{
  "autoMode": {
    "environment": [
      "### Org-wide",
      "- **Organization**: dkackman (personal GitHub account); one maintainer",
      "- **Repository visibility**: dkackman/diffusers-workflow is PUBLIC on GitHub. Issue comments and commits pushed there are public.",
      "- **Source control**: the trusted repo is the diffusers-workflow checkout this session starts in and its `origin` remote (github.com/dkackman/diffusers-workflow). Work on feature branches merged to `develop`; never commit to or push `master`.",
      "- **Default / protected branches**: `master` is the release branch and is protected by convention (never pushed to by an agent); `develop` is the integration branch.",
      "- **CI/CD deploy targets**: none. Deployment is a manual restart of the dw server on the LAN host `lem` over ssh (see below).",
      "- **Sensitive remote targets**: the host `lem` is the only remote box. `ssh lem` for git pull / service restart / reading logs / running the server's tests is routine. Anything that deletes user data on lem outside the dw workspaces, changes lem's system configuration, or touches a host other than lem is not.",
      "- **Network posture**: LAN only. Outbound network is expected for `gh` (GitHub API), `git` to origin, `pip`/`uv` package installs and Hugging Face model downloads on lem. Posting data anywhere else is exfiltration.",
      "- **Secrets management**: none configured. The dw server dev token is `xyz` and not secret; anything else that looks like a credential must not leave the machine.",
      "- **Sensitive data locations**: none in this repo. Generated media under dw workspaces is test output.",
      "### User-specific",
      "- **Primary use of Claude Code**: this session is the unattended implementer agent of an implementer/tester loop (see the harness repo's CLAUDE.md). It fixes one GitHub issue per session, runs the test suite, pushes a branch, deploys to lem, and hands the issue to the tester with a comment. There is no human watching; a denial comes back as a tool result.",
      "- **Routine and approved**: editing source in the checkout, `git add/commit/push` on a feature branch, `git merge` into `develop`, `gh issue view/comment/edit/close`, `pytest`, `uv`/`pip` installs into the project venv, `ssh lem` to pull/restart/inspect the dw service.",
      "- **Never**: force-pushes, history rewrites, branch deletion on origin, pushes to `master`, `rm -rf` outside the checkout or the project venv, modifying `~/.claude`, `~/.ssh`, shell rc files, or any credential store."
    ]
  }
}
```

- [ ] **Step 3: Validate it parses**

Run: `python3 -c 'import json; json.load(open("agent-settings/implementer.json")); print("ok")'`
Expected: `ok`

- [ ] **Step 4: Commit**

```bash
git add agent-settings/implementer.json
git commit -m "implementer: harness-owned auto-mode environment for the classifier

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Wire the flags into run-loop.sh (tester + implementer + triage)

**Files:**
- Modify: `run-loop.sh` — knob block (~lines 77–94), `TESTER_FLAGS`/`IMPLEMENTER_FLAGS` (~lines 128–150), `run_agent` (~lines 156–195), session prompts in `implementer_pass`/`tester_pass` (~lines 231–300), header comment (lines 5–18)

**Interfaces:**
- Consumes: `ISOLATION_FLAGS`, `CONSUMER_TOOLS`, `IMPLEMENTER_TOOLS`, `EFFORT`, `effort_flags` (Task 1); `agent-settings/implementer.json` (Task 2).
- Changes `run_agent`'s signature: `run_agent <role> <tag> <budget_usd> <cwd> <provider> <model> <effort> <prompt-file> <prompt> [extra flags...]` — two new positional args (`effort`, `prompt-file`) before `prompt`.

- [ ] **Step 1: Add per-role effort knobs**

After the `TRIAGE_PROVIDER=` line (~86) add:
```bash
# Per-role effort (--effort). Defaults to EFFORT (providers.sh, `medium` -
# what every session ran at while it was inherited from user settings).
# Triage follows the tester's, like its model does.
IMPLEMENTER_EFFORT="${IMPLEMENTER_EFFORT:-$EFFORT}"
TESTER_EFFORT="${TESTER_EFFORT:-$EFFORT}"
TRIAGE_EFFORT="${TRIAGE_EFFORT:-$TESTER_EFFORT}"
```
Note: the effort knobs must be defined *after* `. "$REPO/providers.sh"` (line 108), since `EFFORT` comes from there — so put them right after that line, not in the model-knob block at 77–86. Then, directly after the three `validate_fallback_model … || exit 1` lines (116–118), add one validation per effort so a typo fails before any session:
```bash
for e in "$IMPLEMENTER_EFFORT" "$TESTER_EFFORT" "$TRIAGE_EFFORT"; do
  effort_flags anthropic "$e" >/dev/null || exit 1
done
```
(`effort_flags` prints only for `anthropic`; validation is the same for every provider.)

- [ ] **Step 2: Extend the flag arrays**

Replace the `TESTER_FLAGS` and `IMPLEMENTER_FLAGS` definitions with:
```bash
TESTER_FLAGS=(
  "${MCP_FLAGS[@]}"
  --plugin-dir "$PLUGIN_DIR"
  "${ISOLATION_FLAGS[@]}"
  --tools "$CONSUMER_TOOLS"
  "${CONSUMER_PERMISSION_FLAGS[@]}"
)
# The implementer's shell surface can't be enumerated without breaking a
# cycle the first time it needs sed or pip, so it runs under the auto-mode
# classifier instead: routine work is approved, destructive or exfiltrating
# actions are denied (a headless session never prompts; a denial comes back
# to the agent as a tool result and it routes around or stops). The
# classifier's picture of the environment used to come from Don's user
# settings; ISOLATION_FLAGS cuts those off, so the harness supplies its own.
IMPLEMENTER_FLAGS=(
  "${MCP_FLAGS[@]}"
  "${ISOLATION_FLAGS[@]}"
  --tools "$IMPLEMENTER_TOOLS"
  --settings "$REPO/agent-settings/implementer.json"
  --permission-mode auto
)
```
(Keep the existing comment above `TESTER_FLAGS`; the comment above `IMPLEMENTER_FLAGS` is replaced by the one shown.)

- [ ] **Step 3: Teach `run_agent` effort and the system-prompt file**

Change the signature line and body:
```bash
# run_agent <role> <tag> <budget_usd> <cwd> <provider> <model> <effort> <prompt-file> <prompt> [extra claude flags...]
# One fresh claude -p session. <role> picks the role prompt's runtime note
# and the per-role log file; <tag> (e.g. "#145", "triage", "task") is what
# distinguishes the sessions of one cycle in loop.log. <prompt-file> is the
# role prompt (agents/<ROLE>.agent.md), appended to the system prompt so it
# is in the cached prefix from turn one rather than a 12-16 KB tool result
# the agent has to Read first. Streams the agent's output to the terminal,
# its own log, and the combined log.
run_agent() {
  local role="$1" tag="$2" budget="$3" dir="$4" provider="$5" model="$6" effort="$7" prompt_file="$8" prompt="$9"; shift 9
```
and, after the `fallback` array is built, add:
```bash
  local -a effort_words=()
  read -r -a effort_words <<<"$(effort_flags "$provider" "$effort")"
```
and change the `claude -p` line to:
```bash
      claude -p "$full_prompt" \
      --model "$model" ${fallback[@]+"${fallback[@]}"} ${effort_words[@]+"${effort_words[@]}"} "${limits[@]}" \
      --append-system-prompt-file "$prompt_file" \
      "${STREAM_FLAGS[@]}" "$@" 2>&1 < /dev/null | render_stream "$role") \
```

- [ ] **Step 4: Update every `run_agent` call site and prompt**

There are six calls. For each, insert the effort and prompt-file args after the model, and reword "Follow the role instructions at $AGENTS/X.agent.md" → "Your role instructions are in your system prompt (they are the contents of $AGENTS/X.agent.md; follow them exactly)". Concretely:

Triage:
```bash
    run_agent implementer triage "$TRIAGE_BUDGET_USD" "$SOURCE_DIR" "$TRIAGE_PROVIDER" "$TRIAGE_MODEL" "$TRIAGE_EFFORT" "$AGENTS/IMPLEMENTER.agent.md" \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER; issues filed by any other login are not yours to work. This is a TRIAGE session: your role instructions are in your system prompt (the contents of $AGENTS/IMPLEMENTER.agent.md); follow its 'Triage session' section for exactly these issues: $(printf '#%s ' "${queue[@]}"). Do not fix anything in this session. Then stop." \
      "${IMPLEMENTER_FLAGS[@]}"
```
Implementer per issue:
```bash
    run_agent implementer "#$n" "$IMPLEMENTER_BUDGET_USD" "$SOURCE_DIR" "$IMPLEMENTER_PROVIDER" "$IMPLEMENTER_MODEL" "$IMPLEMENTER_EFFORT" "$AGENTS/IMPLEMENTER.agent.md" \
      "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER; issues filed by any other login are not yours to work. Your role instructions are in your system prompt (the contents of $AGENTS/IMPLEMENTER.agent.md); follow them exactly for this session, working ONLY issue #$n — plus any issue a \`triage:\` comment on #$n tells you to batch with it. Then stop." \
      "${IMPLEMENTER_FLAGS[@]}"
```
Tester verify / handoff / answer / task: same pattern — `"$TESTER_EFFORT" "$AGENTS/TESTER.agent.md"` after `"$TESTER_MODEL"`, and in each prompt replace `Follow the role instructions at $AGENTS/TESTER.agent.md exactly for this session:` with `Your role instructions are in your system prompt (the contents of $AGENTS/TESTER.agent.md); follow them exactly for this session:`. The task-session prompt keeps its `advance the standing task in $AGENTS/TESTER_TASK.agent.md` wording — that file is still read as a file, only in task sessions.

- [ ] **Step 5: Update the header comment**

In the usage block at the top (lines 5–18) add, after the `TRIAGE_MODEL=` example:
```bash
#   TESTER_EFFORT=high ./run-loop.sh    # per-role --effort; defaults medium (EFFORT)
```

- [ ] **Step 6: Syntax check and dry-run the flag arrays**

Run: `bash -n run-loop.sh && echo syntax-ok`
Expected: `syntax-ok`

Then verify the tester flag set live (this is the same check that passed in the analysis, now driven by the real arrays):
```bash
bash -c '
set -e; cd /Users/don/testing/iterate
source ./providers.sh
PLUGIN_DIR=$HOME/src/dkackman/diffusers-workflow/plugins/dw
# TESTER_FLAGS exactly as run-loop.sh now defines it
TESTER_FLAGS=(--mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"http://lem:8765/mcp\",\"headers\":{\"Authorization\":\"Bearer xyz\"}}}}" --strict-mcp-config --plugin-dir "$PLUGIN_DIR" "${ISOLATION_FLAGS[@]}" --tools "$CONSUMER_TOOLS" "${CONSUMER_PERMISSION_FLAGS[@]}")
claude -p "Call the dw get_server_info tool and reply with just the accelerator name and the dw version." \
  --model sonnet --output-format stream-json --verbose --no-session-persistence \
  --append-system-prompt-file agents/TESTER.agent.md \
  "${TESTER_FLAGS[@]}" 2>/dev/null </dev/null \
  | python3 -c "
import sys,json
for line in sys.stdin:
    try: e=json.loads(line)
    except ValueError: continue
    if e.get(\"type\")==\"system\" and e.get(\"subtype\")==\"init\": print(\"tools\", len(e[\"tools\"]), \"mcp\", [(m[\"name\"],m[\"status\"]) for m in e[\"mcp_servers\"]], \"dw skills\", [s for s in e[\"slash_commands\"] if s.startswith(\"dw:\")])
    if e.get(\"type\")==\"system\" and \"hook\" in e.get(\"subtype\",\"\"): print(\"UNEXPECTED HOOK\", e.get(\"hook_name\"))
    if e.get(\"type\")==\"assistant\":
        u=e[\"message\"][\"usage\"]; ctx=u.get(\"input_tokens\",0)+u.get(\"cache_read_input_tokens\",0)+u.get(\"cache_creation_input_tokens\",0)
        for c in e[\"message\"][\"content\"]:
            if c[\"type\"]==\"text\": print(f\"ctx={ctx/1000:.1f}k\", c[\"text\"][:120])
"'
```
Expected: `tools 66 mcp [('dw','connected')] dw skills ['dw:ltx-2-5', ...]`, no `UNEXPECTED HOOK` line, a `ctx≈35k` line naming `cuda` and the dw version. Diff the `TESTER_FLAGS` line in the scratch command against run-loop.sh's definition before trusting the result — the point is that the exact array contents work.

- [ ] **Step 7: Commit**

```bash
git add run-loop.sh
git commit -m "run-loop: isolate agent sessions from user settings, trim tool schemas, explicit effort

Every session carried ~25k tokens/turn it never used: built-in tool
schemas denied by the allowlist, and user-level SessionStart hooks
(superpowers preamble, remember's memory dump - which was also capturing
agent sessions into Don's memory). Role prompt now rides in the system
prompt instead of a Read result.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Wire the flags into run-regression.sh and run-research.sh

**Files:**
- Modify: `run-regression.sh` (knobs ~line 65, `REGRESSION_FLAGS` ~158, `run_session` ~166–182, header ~17)
- Modify: `run-research.sh` (knobs ~33, `RESEARCH_FLAGS` ~54, `run_session` ~61–77, header ~7)

**Interfaces:**
- Consumes: `ISOLATION_FLAGS`, `CONSUMER_TOOLS`, `RESEARCHER_TOOLS`, `EFFORT`, `effort_flags` (Task 1).

- [ ] **Step 1: run-regression.sh knobs and validation**

After `REGRESSION_PROVIDER=` add:
```bash
REGRESSION_EFFORT="${REGRESSION_EFFORT:-$EFFORT}"   # --effort; medium unless set
```
After the existing `resolve_model_env "$REGRESSION_PROVIDER" "$REGRESSION_MODEL" || exit 1` line add:
```bash
effort_flags anthropic "$REGRESSION_EFFORT" >/dev/null || exit 1
EFFORT_FLAGS=(); read -r -a EFFORT_FLAGS <<<"$(effort_flags "$REGRESSION_PROVIDER" "$REGRESSION_EFFORT")"
```

- [ ] **Step 2: run-regression.sh flags and session**

Replace `REGRESSION_FLAGS` with:
```bash
REGRESSION_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
  --plugin-dir "$PLUGIN_DIR"
  "${ISOLATION_FLAGS[@]}"
  --tools "$CONSUMER_TOOLS"
  "${CONSUMER_PERMISSION_FLAGS[@]}"
)
```
In `run_session`, change the prompt's `Follow the role instructions at $AGENTS/REGRESSION.agent.md exactly for this run, with these overrides:` to `Your role instructions are in your system prompt (the contents of $AGENTS/REGRESSION.agent.md); follow them exactly for this run, with these overrides:` and the flags line to:
```bash
    --model "$REGRESSION_MODEL" ${FALLBACK_FLAGS[@]+"${FALLBACK_FLAGS[@]}"} ${EFFORT_FLAGS[@]+"${EFFORT_FLAGS[@]}"} \
    --append-system-prompt-file "$AGENTS/REGRESSION.agent.md" \
    "${STREAM_FLAGS[@]}" "${REGRESSION_FLAGS[@]}" 2>&1 | render_stream regression) \
```
Header: after the `REGRESSION_MODEL=sonnet` example add `#   REGRESSION_EFFORT=high ./run-regression.sh   # --effort; defaults medium`.

- [ ] **Step 3: run-research.sh — same three edits**

Knobs: `RESEARCH_EFFORT="${RESEARCH_EFFORT:-$EFFORT}"` after `RESEARCH_PROVIDER=`; validation + `EFFORT_FLAGS` after `resolve_model_env`, exactly as Step 1 with `RESEARCH_` names.
Flags:
```bash
RESEARCH_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
  "${ISOLATION_FLAGS[@]}"
  --tools "$RESEARCHER_TOOLS"
  "${RESEARCHER_PERMISSION_FLAGS[@]}"
)
```
Prompt: `Follow the role instructions at $AGENTS/RESEARCHER.agent.md exactly for this run,` → `Your role instructions are in your system prompt (the contents of $AGENTS/RESEARCHER.agent.md); follow them exactly for this run,`. Flags line gains `${EFFORT_FLAGS[@]+"${EFFORT_FLAGS[@]}"}` and `--append-system-prompt-file "$AGENTS/RESEARCHER.agent.md"` the same way. Header gains `#   RESEARCH_EFFORT=high ./run-research.sh   # --effort; defaults medium`.

- [ ] **Step 4: Syntax check both**

Run: `bash -n run-regression.sh && bash -n run-research.sh && echo syntax-ok`
Expected: `syntax-ok`

- [ ] **Step 5: Live check the researcher flag set**

The researcher's cwd is the source checkout and it has no `Edit`; confirm it can still read source and call a discovery tool:
```bash
cd ~/src/dkackman/diffusers-workflow && claude -p "Read the first 5 lines of dw_mcp/diagnose.py, then call the dw list_guides tool, and reply with the first line of the file and the number of guides." \
  --model sonnet --output-format stream-json --verbose --no-session-persistence \
  --setting-sources project,local --tools "Bash,Read,Glob,Grep,ToolSearch,WebFetch,TodoWrite" \
  --permission-mode dontAsk --allowedTools "mcp__dw__list_guides" "ToolSearch" "Read" \
  --strict-mcp-config --mcp-config '{"mcpServers":{"dw":{"type":"http","url":"http://lem:8765/mcp","headers":{"Authorization":"Bearer xyz"}}}}' \
  2>/dev/null </dev/null | grep -o '"text":"[^"]\{0,160\}' | tail -2
```
Expected: a text reply quoting the file's first line and a guide count; no denial text.

- [ ] **Step 6: Commit**

```bash
git add run-regression.sh run-research.sh
git commit -m "regression/research: same session isolation, tool trim and explicit effort as run-loop

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Document in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` — the `providers.sh` bullet under "What this is", the "Running" code block, and the "Permissions" section.

- [ ] **Step 1: providers.sh bullet**

In the `providers.sh —` bullet, after the sentence ending `…and \`commit_suite_changes\` (commits only \`regression-suite-*.md\` and \`regression-perf/\`).` add:
```
  It also holds what every session leaves *out*: `ISOLATION_FLAGS`
  (`--setting-sources project,local` — no user-level plugins, hooks, memory or MCP
  servers reach an unattended agent; measured 2026-09-19, those were ~12 KB of
  SessionStart hook text per session, and the `remember` plugin was capturing agent
  sessions into Don's own memory and re-injecting them), the per-role `--tools`
  lists (`CONSUMER_TOOLS`/`RESEARCHER_TOOLS`/`IMPLEMENTER_TOOLS` — only the built-in
  tools a role has ever used; the ~20k tokens of Artifact/Workflow/Agent/... schemas
  a role is denied anyway no longer ride on every turn), and `effort_flags` with the
  `EFFORT` default (`medium`, what sessions ran at while it was inherited from user
  settings; per-role `*_EFFORT` knobs in each driver). `measure-base-ctx.sh` is how
  a flag set's turn-1 context is measured before and after a change like this.
```

- [ ] **Step 2: Running block**

Add to the `## Running` code block:
```sh
TESTER_EFFORT=high REGRESSION_EFFORT=high ./run-loop.sh   # per-role --effort (default medium)
./measure-base-ctx.sh lean --setting-sources project,local --tools "$CONSUMER_TOOLS"  # turn-1 context of a flag set
```

- [ ] **Step 3: Permissions section**

In the Implementer bullet, after `…denies destructive or exfiltrating actions.` add: `The classifier's picture of the environment (trusted repo, \`lem\`, what "routine" means here) is \`agent-settings/implementer.json\`, passed via \`--settings\`; it used to be inherited from user settings and described a different checkout.`

Also amend the "Both roles see MCP tools as deferred names…" paragraph's neighbour in "Running": after `…which an unattended agent must not hold.` add `The same paragraph of flags now also drops user-level settings entirely (\`ISOLATION_FLAGS\`) — the implementer's own \`--append-system-prompt-file\` role prompt and \`--settings\` file are what it runs on.`

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: session isolation, --tools trim, effort knobs, measure-base-ctx

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: File the two dw-server follow-ups as `idea` issues

These are the turn-count and payload-size levers; they live in `dkackman/diffusers-workflow`, so the researcher agent picks them up (`idea` → `owner:researcher`).

**Files:** none in this repo.

- [ ] **Step 1: Check the labels exist**

Run: `gh label list --repo dkackman/diffusers-workflow --search idea; gh label list --repo dkackman/diffusers-workflow --search owner:researcher`
Expected: both listed. If `idea` is missing: `gh label create idea --repo dkackman/diffusers-workflow --description "An idea for the researcher agent to disposition"`.

- [ ] **Step 2: File the wait_for_job issue**

```bash
gh issue create --repo dkackman/diffusers-workflow --label idea --label owner:researcher \
  --title "idea: let wait_for_job block for the whole job when the MCP client allows it" \
  --body "$(cat <<'EOF'
## Idea

`wait_for_job` clamps every call to `MAX_WAIT_SECONDS = 55` (`dw_mcp/diagnose.py:23`) on the assumption that an MCP client won't hold a tool call open longer. Claude Code will: its per-call limit is the `MCP_TOOL_TIMEOUT` environment variable (milliseconds), and the harness drivers can set it to e.g. 30 minutes.

## Why it matters

Measured in the harness's `logs/regression.jsonl` (2026-09-19): 477 `wait_for_job` calls, up to 17 polls on one job, with agents already passing the maximum `timeout_seconds=55`. Every poll is a full-context model turn — at ~130k context on Opus that is roughly $0.08 per poll, so a 15-minute LTX job costs about $1.30 in polling alone, and the polls are what push a chunked regression session toward its autocompact threshold.

## Proposal to assess

- Make the cap configurable: `DW_MCP_MAX_WAIT_SECONDS` env var (default stays 55 so unknown clients are unaffected).
- Honour `timeout_seconds` up to that cap; keep `timeout_capped`/`timeout_applied_seconds` in the reply so a caller can tell what it got.
- Harness side (iterate repo, not this one): set `MCP_TOOL_TIMEOUT` slightly above the server cap in `run-loop.sh` / `run-regression.sh`, and update the tool description so the agent budgets one call per job instead of one per 55 s.
- Check whether the streamable-HTTP transport or any proxy between the harness and `lem` has its own idle timeout that would cut a multi-minute call.

Source: tester-side cost analysis (Opus 5 via anthropic), 2026-09-19.
EOF
)"
```

- [ ] **Step 3: File the payload-size issue**

```bash
gh issue create --repo dkackman/diffusers-workflow --label idea --label owner:researcher \
  --title "idea: slim list_workspaces / list_assets / list_workflows default payloads" \
  --body "$(cat <<'EOF'
## Idea

Three listing tools return far more than a listing. Median result sizes across the harness's regression sessions (`logs/regression.jsonl`, 2026-09-19):

| tool | calls | median | max |
|---|---|---|---|
| `list_workspaces` | 33 | 10.8 KB | 17 KB |
| `list_assets` | 40 | 13.9 KB | 16 KB |
| `list_workflows` | 50 | 13.6 KB | 55 KB (no filter) |

`list_workspaces` in particular is a list of names plus which one is current; 10 KB per call means it is carrying per-workspace detail nobody asked for. These are called 30–50× per regression level, and every byte stays in context for the rest of the session (see #101 for the general point).

## Proposal to assess

- `list_workspaces`: names + current + counts only by default; a `detail=true` (or a per-workspace `get_workspace`) for the rest.
- `list_assets`: the same shape as the compact `list_workflows` listing — name, kind, size, shared flag — with metadata behind a `detail` flag or `get_asset`.
- `list_workflows` with no filter: consider a hard cap with a `truncated: true` marker and a hint to filter by `shape`, instead of 55 KB.
- Keep the security suite's expectations in mind: nothing here should change what a listing *reveals*, only how much of it arrives unasked.

Source: tester-side cost analysis (Opus 5 via anthropic), 2026-09-19.
EOF
)"
```

- [ ] **Step 4: Verify both are on the board**

Run: `gh issue list --repo dkackman/diffusers-workflow --label idea --label owner:researcher --json number,title`
Expected: both titles listed with numbers.

---

### Task 7: Acceptance — one real cycle, before/after

**Files:** none.

- [ ] **Step 1: Capture the "before" numbers**

Run: `grep usage: logs/loop.log | tail -20 > /tmp/usage-before.txt; cat /tmp/usage-before.txt`
Expected: the last 20 session usage lines (ctx_peak 60–170k, cache_read in the millions).

- [ ] **Step 2: Run one cycle**

Run: `MAX_CYCLES=1 ./run-loop.sh 2>&1 | tail -40`
(Acts on whatever issues are currently owned; if the board is empty this only proves the drivers start. In that case also run `CASES_PER_SESSION=3 ./run-regression.sh smoke` for a partial regression level — that spends a few dollars.)
Expected: sessions start and finish; no `session failed` lines; `logs/tester.log` / `logs/implementer.log` show no `· ctx=` first-turn value above ~35k; no permission denials for tools in the role's list (`grep -i "denied\|not allowed" logs/tester.log logs/implementer.log | tail`).

- [ ] **Step 3: Compare**

Run: `grep usage: logs/loop.log | tail -20`
Expected: for comparable sessions (same role, similar turn counts), `ctx_peak` roughly 20–25k lower and `cache_read`/`cost` proportionally lower than the matching lines in `/tmp/usage-before.txt`. Report the actual numbers, not the expectation.

- [ ] **Step 4: Check the remember loop is closed**

Run: `tail -5 .remember/now.md .remember/today-$(date +%F).md 2>/dev/null`
Expected: no new entries written by the agent sessions during the cycle (entries from Don's own interactive sessions are fine).

- [ ] **Step 5: Verify per the verification-before-completion skill, then report**

No commit — this task produces evidence, not code. Report the before/after `usage:` lines and the denial grep result.

---

### Task 8: Disable auto-memory for agent sessions (found during Task 7)

Measured during acceptance: with everything above in place, a sonnet implementer session still started at 51.8k, 13k above the haiku figure for the same flags. The difference is Claude Code's **auto-memory** — `~/.claude/projects/-Users-don-src-dkackman-diffusers-workflow/memory/` holds 58 files / 131 KB and its `MEMORY.md` (9.7 KB) is loaded into every sonnet/opus session there. Worse, files named `implementer-cycle-2026-09-12*.md` show the implementer agent has been *writing* into Don's project memory — the same feedback loop `remember` had. `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` takes the same session to 43.3k and closes the loop. `--setting-sources` does not cover it (auto-memory is not a settings source), so it is an environment variable, exported once where every driver already gets its shared environment.

**Files:**
- Modify: `providers.sh` — next to `ISOLATION_FLAGS`
- Modify: `CLAUDE.md` — the `providers.sh` bullet sentence about `ISOLATION_FLAGS`

- [ ] **Step 1: Export the variable in providers.sh**

Directly after the `ISOLATION_FLAGS=(--setting-sources project,local)` line add:
```bash
# Auto-memory is not a settings source, so --setting-sources doesn't touch
# it: a sonnet/opus session in the source checkout still loaded
# ~/.claude/projects/<checkout>/memory/MEMORY.md (9.7 KB, ~8k tokens with
# the memory instructions), and the implementer had been *writing* there
# too (implementer-cycle-*.md files in Don's project memory). Every
# driver inherits this from sourcing providers.sh.
export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
```

- [ ] **Step 2: Verify**

Run (from the source checkout, sonnet, a few cents):
```bash
cd ~/src/dkackman/diffusers-workflow && source /Users/don/testing/iterate/providers.sh && MCP='{"mcpServers":{"dw":{"type":"http","url":"http://lem:8765/mcp","headers":{"Authorization":"Bearer xyz"}}}}' && claude -p "Reply with the single word ok." --model sonnet --output-format stream-json --verbose --no-session-persistence "${ISOLATION_FLAGS[@]}" --tools "$IMPLEMENTER_TOOLS" --strict-mcp-config --mcp-config "$MCP" --settings /Users/don/testing/iterate/agent-settings/implementer.json --permission-mode auto --append-system-prompt-file /Users/don/testing/iterate/agents/IMPLEMENTER.agent.md 2>/dev/null </dev/null | python3 -c "
import sys,json
for line in sys.stdin:
    try: e=json.loads(line)
    except ValueError: continue
    if e.get('type')=='assistant':
        u=e['message']['usage']; print('ctx=%.1fk'%((u.get('input_tokens',0)+u.get('cache_read_input_tokens',0)+u.get('cache_creation_input_tokens',0))/1000)); break
"
```
Expected: `ctx≈43k` (was 51.8k without the export). Also `env -i HOME=$HOME PATH=$PATH bash -c 'source ./providers.sh; echo $CLAUDE_CODE_DISABLE_AUTO_MEMORY'` from the harness repo prints `1`.

- [ ] **Step 3: Document**

In CLAUDE.md's `providers.sh` bullet, after the sentence ending `…re-injecting them),` insert: `\`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1\` exported alongside it (auto-memory isn't a settings source; the implementer had been reading *and writing* Don's project memory under the source checkout),`.

- [ ] **Step 4: Commit**

```bash
git add providers.sh CLAUDE.md
git commit -m "providers: disable auto-memory for agent sessions

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Out of scope (noted, not done here)

- This repo's `CLAUDE.md` (14 KB) and the dw repo's `CLAUDE.md` (39 KB, ~10k tokens on every implementer turn) still load into every session. Cutting them needs `--bare` (API-key only, no OAuth) or a rewritten `--system-prompt`; worth its own look once the numbers above are in.
- The implementer called `ScheduleWakeup` 12× to wait on background pytest runs — polling inside a session, which CLAUDE.md says no agent does. Cheap in tokens (noop wakeups), but a role-prompt fix ("run pytest in the foreground with a timeout") is a separate change.
- Dropping superpowers from the implementer removes the two skills it invoked (`test-driven-development`, `systematic-debugging`). If they were pulling weight, `--plugin-dir ~/.claude/plugins/cache/claude-plugins-official/superpowers/<ver>` puts them back explicitly without the hook preamble — but check a few implementer sessions first.
