# Researcher Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fourth, standalone Claude Code agent — the researcher — that
turns an "idea" GitHub Issue into reject / propose-to-implementer / ask-Don,
run outside the implementer/tester alternation via a new `run-research.sh`,
one fresh session per issue.

**Architecture:** Extend the existing multi-agent harness with a third
isolation shape (read-only source checkout + read-only `dw` MCP + `gh`, no
write/SSH). Reuse existing ticket-protocol conventions (`wontfix`,
`status:needs-approval`, `owner:*`) rather than inventing new ones. Move the
one piece of logic two drivers now need (`park_external_issues`) into the
shared `providers.sh`.

**Tech Stack:** Bash (`run-research.sh`, `providers.sh`), Markdown role
prompt (`agents/RESEARCHER_AGENT.md`), GitHub Issues/labels/templates via
`gh`, no application code changes (this repo has no build/lint/test step —
verification here is `bash -n`/`shellcheck` plus a real `gh`-backed smoke
test).

**Spec:** `docs/superpowers/specs/2026-09-14-researcher-agent-design.md`

## Global Constraints

- No `--dangerously-skip-permissions`, ever (CLAUDE.md "Permissions").
- The researcher is **read-only** against source: no `Edit`/`Write` on
  `SOURCE_DIR`, no `git` write subcommands, no `ssh lem`.
- `RESEARCH_MODEL` defaults to **`sonnet`** (not `$MODEL`); `RESEARCH_PROVIDER`
  defaults to `$PROVIDER`, same as every other per-role override.
- Reuse existing labels/statuses for disposition — no new `status:*` values.
- `owner` stays "exactly one of `owner:implementer`/`owner:tester`/
  `owner:don`/`owner:researcher` at a time" — every place that invariant is
  stated or relied on (CLAUDE.md, `park_external_issues`, any status-board
  query) must reflect the fourth value.
- Labels/template are created directly on `dkackman/diffusers-workflow`
  (default branch `master`) via `gh`, since these are repo metadata, not
  application code — no PR needed for label creation; the template file is
  added with a plain commit to `master`, matching how `mcp-ticket.md` already
  lives there.

---

### Task 1: GitHub labels + idea issue template

**Files:**
- Create (in the **`dkackman/diffusers-workflow`** repo, not this one):
  `.github/ISSUE_TEMPLATE/idea-ticket.md`
- No file in this repo changes in this task.

**Interfaces:**
- Produces: the `idea` and `owner:researcher` labels must exist on
  `dkackman/diffusers-workflow` before any later task's smoke test files an
  issue.

- [ ] **Step 1: Create the two labels**

```bash
gh label create idea --repo dkackman/diffusers-workflow \
  --description "An idea for the researcher agent to assess" --color "C5DEF5"
gh label create owner:researcher --repo dkackman/diffusers-workflow \
  --description "Researcher's turn to act" --color "5319E7"
```

- [ ] **Step 2: Verify they exist**

Run: `gh label list --repo dkackman/diffusers-workflow --search owner:researcher`
Run: `gh label list --repo dkackman/diffusers-workflow --search idea`
Expected: one row each, matching the name/color/description just set.

- [ ] **Step 3: Write the idea issue template**

Mirror `mcp-ticket.md`'s shape (front-matter + body + trailing HTML comment
pointing at the doc that explains the label scheme), swapped for an idea's
fields instead of a bug's repro fields. Clone/pull the source repo first if
your local checkout isn't current:

```bash
cd ~/src/dkackman/diffusers-workflow && git checkout master && git pull
```

Write `~/src/dkackman/diffusers-workflow/.github/ISSUE_TEMPLATE/idea-ticket.md`:

```markdown
---
name: MCP agent-loop idea
about: An idea for a new capability or change, for the researcher agent to assess (see CLAUDE.md in the iterate repo) — not for bug reports, use "Bug report" for those.
title: ""
labels: ["idea", "owner:researcher"]
---

**idea:** what capability or change this is proposing

**motivation:** why this would be worth having

**links:** any prior art, reference docs, upstream libraries, or related issues

<!--
The researcher agent reads this, researches the codebase and any links
above, and assesses complexity, feasibility, and value. It then either
rejects the idea (wontfix + reason), proposes a concrete plan to the
implementer (owner:implementer, ready to work), or parks it for human input
(owner:don + status:needs-approval). See CLAUDE.md in the iterate repo
("Ticket protocol") for the full label scheme.
-->
```

- [ ] **Step 4: Commit and push directly to master**

```bash
cd ~/src/dkackman/diffusers-workflow
git add .github/ISSUE_TEMPLATE/idea-ticket.md
git commit -m "docs: add idea issue template for the researcher agent"
git push origin master
```

- [ ] **Step 5: Verify the template is live**

Run: `gh api repos/dkackman/diffusers-workflow/contents/.github/ISSUE_TEMPLATE/idea-ticket.md --jq .name`
Expected: `idea-ticket.md`

---

### Task 2: Move `park_external_issues` into `providers.sh`

**Files:**
- Modify: `run-loop.sh:142-163` (remove the function definition, keep the
  call site)
- Modify: `providers.sh` (add the function; append it after
  `commit_suite_changes`)

**Interfaces:**
- Produces: `park_external_issues()` — a bash function taking no arguments,
  reading `TICKET_REPO`, `TICKET_OWNER`, `LOGS` from the caller's
  environment (same contract `commit_suite_changes` already uses for
  `REPO`/`LOGS`). Any driver that sources `providers.sh` and sets those three
  variables can call it.

- [ ] **Step 1: Read the current definition**

It's already shown above (from `run-loop.sh:142-163`) — copy it verbatim,
changing nothing about its behavior in this step.

- [ ] **Step 2: Add it to `providers.sh`**

Append after `commit_suite_changes` (end of file), with a guard clause
matching that function's style:

```bash
# park_external_issues
# Guardrail: an open issue filed by anyone other than TICKET_OWNER is parked
# with the human (owner:don + status:needs-approval) before any driver's
# agent sees it. Every unattended role runs as TICKET_OWNER's gh login, so
# its own filings pass; what this catches is a third party filing on the
# public repo, which no unattended agent may pick up as ordinary work.
# role-specific triage steps (e.g. the implementer's) repeat the check for
# anything filed mid-run; this is the enforced copy, shared by every driver
# that calls it. Already-parked issues are left alone. Needs TICKET_REPO,
# TICKET_OWNER, and LOGS set by the caller.
park_external_issues() {
  : "${TICKET_REPO:?park_external_issues: TICKET_REPO must be set by the driver}"
  : "${TICKET_OWNER:?park_external_issues: TICKET_OWNER must be set by the driver}"
  : "${LOGS:?park_external_issues: LOGS must be set by the driver}"
  gh issue list --repo "$TICKET_REPO" --state open --limit 200 \
    --json number,author,labels \
  | jq -r --arg me "$TICKET_OWNER" '.[]
      | select(.author.login != $me)
      | select(([.labels[].name] | index("status:needs-approval")) == null)
      | [(.number|tostring), .author.login,
         ([.labels[].name | select(startswith("owner:") or startswith("status:"))] | join(","))]
      | @tsv' \
  | while IFS=$'\t' read -r n author labels; do
      remove=()
      IFS=',' read -ra present <<< "$labels"
      for l in "${present[@]+"${present[@]}"}"; do
        [ -n "$l" ] && [ "$l" != "owner:don" ] && remove+=(--remove-label "$l")
      done
      gh issue edit "$n" --repo "$TICKET_REPO" ${remove[@]+"${remove[@]}"} \
        --add-label owner:don --add-label status:needs-approval >/dev/null \
      && gh issue comment "$n" --repo "$TICKET_REPO" --body "Parked for human review: filed by @$author, not by @$TICKET_OWNER. The agent loop only acts on issues from @$TICKET_OWNER unasked; a human will triage this and hand it off if it should enter the loop." >/dev/null \
      && echo "[loop] parked #$n (filed by @$author) as owner:don + status:needs-approval" | tee -a "$LOGS/loop.log" \
      || echo "[loop] failed to park #$n (filed by @$author)" | tee -a "$LOGS/loop.log"
    done
}
```

- [ ] **Step 3: Remove the definition from `run-loop.sh`, keep the call**

Delete lines 142-163 of `run-loop.sh` (the function body) but leave the
comment immediately above it if it still reads correctly standalone, and
leave `park_external_issues` called where it already is (inside the `while
true; do` loop, before `before="$(status_board)"`). `run-loop.sh` already
sources `providers.sh` earlier, so no new `source`/`.` line is needed.

- [ ] **Step 4: Syntax-check both files**

Run: `bash -n run-loop.sh && bash -n providers.sh`
Expected: no output, exit 0.

- [ ] **Step 5: Shellcheck both files**

Run: `shellcheck run-loop.sh providers.sh`
Expected: no new warnings introduced by this change (pre-existing warnings,
if any, are out of scope for this task).

- [ ] **Step 6: Functional check against the real repo**

Run:
```bash
cd /Users/don/testing/iterate
REPO="$PWD" LOGS="$PWD/logs" TICKET_REPO="dkackman/diffusers-workflow" TICKET_OWNER="dkackman" \
  bash -c '. ./providers.sh; mkdir -p "$LOGS"; park_external_issues; echo OK'
```
Expected: `OK` printed, no error; `logs/loop.log` gets a `[loop] parked #N
...` line only if an externally-filed unparked issue currently exists (fine
either way — the point is it runs without error).

- [ ] **Step 7: Commit**

```bash
git add run-loop.sh providers.sh
git commit -m "refactor: share park_external_issues via providers.sh

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Researcher permission flags, model default, and runtime note in `providers.sh`

**Files:**
- Modify: `providers.sh` (add `RESEARCHER_PERMISSION_FLAGS`, extend
  `runtime_note`)

**Interfaces:**
- Consumes: nothing new from earlier tasks.
- Produces:
  - `RESEARCHER_PERMISSION_FLAGS` — a bash array, same shape as
    `CONSUMER_PERMISSION_FLAGS`, for `run-research.sh` (Task 5) to splice
    into its `claude` invocation.
  - `runtime_note researcher <provider> <model>` — a fourth valid `role`
    argument, alongside `implementer`/`tester`/`regression`.

- [ ] **Step 1: Add `RESEARCHER_PERMISSION_FLAGS` next to `CONSUMER_PERMISSION_FLAGS`**

```bash
# Permission flags for the researcher: read-only against the source
# checkout (Read/Glob/Grep/git-read only — no Edit/Write, no git writes, no
# ssh, no curl), read-only dw MCP discovery calls, and gh for issue
# management. Distinct from CONSUMER_PERMISSION_FLAGS (which allows Edit/
# Write for the suite files the tester/regression agent maintain) and from
# the implementer's --permission-mode auto: the researcher assesses, it
# never implements, and it has no durable file of its own to edit.
RESEARCHER_PERMISSION_FLAGS=(
  --permission-mode dontAsk
  --allowedTools
    "mcp__dw__list_workflows" "mcp__dw__list_guides" "mcp__dw__list_pipelines"
    "mcp__dw__list_classes" "mcp__dw__list_tasks" "mcp__dw__get_server_info"
    "mcp__dw__get_schema" "mcp__dw__get_guide" "mcp__dw__get_class"
    "mcp__dw__get_pipeline_signature" "ToolSearch" "WebFetch" "TodoWrite"
    "Read" "Glob" "Grep"
    "Bash(gh *)" "Bash(date *)" "Bash(file *)"
    "Bash(git log *)" "Bash(git status*)" "Bash(git diff *)" "Bash(git show *)" "Bash(git blame *)"
)
```

- [ ] **Step 2: Extend `runtime_note`'s role case**

Modify the `case "$role" in` block:

```bash
  case "$role" in
    implementer) examples="a ticket hand-off comment, a wontfix or needs-info reason, a regression case you propose in a hand-off" ;;
    tester)      examples="a verification comment, a bounce, a new issue, a regression-suite edit" ;;
    regression)  examples="an issue body, a comment on an existing issue, a suite-file edit" ;;
    researcher)  examples="a research/proposal comment, a reject reason, a question parked for Don" ;;
    *) echo "run: runtime_note: unknown role '$role' (implementer|tester|regression|researcher)" >&2; return 1 ;;
  esac
```

Also update the doc-comment above `runtime_note` (currently "Roles:
implementer, tester, regression.") to add `researcher`.

- [ ] **Step 3: Syntax-check**

Run: `bash -n providers.sh`
Expected: no output, exit 0.

- [ ] **Step 4: Shellcheck**

Run: `shellcheck providers.sh`
Expected: no new warnings.

- [ ] **Step 5: Functional check**

Run:
```bash
bash -c '. ./providers.sh; runtime_note researcher anthropic sonnet'
```
Expected: prints the four-line note, first line reading `Runtime: you are
the researcher agent, running as model 'sonnet' via the 'anthropic'`.

Run:
```bash
bash -c '. ./providers.sh; runtime_note bogus anthropic sonnet; echo "exit=$?"'
```
Expected: stderr `run: runtime_note: unknown role 'bogus' ...`, `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add providers.sh
git commit -m "feat: add researcher permission flags and runtime note

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: `agents/RESEARCHER_AGENT.md` role prompt

**Files:**
- Create: `agents/RESEARCHER_AGENT.md`

**Interfaces:**
- Consumes: nothing programmatic — this is a prompt file `run-research.sh`
  (Task 5) will point a `claude -p` session at by path.
- Produces: the researcher's full per-issue procedure, referenced by
  `run-research.sh`'s prompt text as `$AGENTS/RESEARCHER_AGENT.md`.

- [ ] **Step 1: Write the file**

```markdown
# Role: Researcher Agent — diffusers-workflow MCP (read-only)

You turn one "idea" GitHub Issue into a disposition: reject it, propose a
concrete plan for the implementer to run with (or send to Don), or ask Don
directly for input. You are read-only against the `diffusers-workflow`
codebase — you have the same source checkout the Implementer Agent uses
(`Read`/`Grep`/`Glob`, `git log`/`blame`/`show`/`diff`/`status`), but you
never `Edit`/`Write` it, never run a write `git` subcommand, and never SSH
into `lem`. You assess; you do not implement. A proposal you write is input
to the implementer's own judgment, not a decision already made — the
implementer still independently triages and decides run-with-it vs.
`status:needs-approval` for whatever you hand it, exactly as it would for a
fix it found itself.

You also get read-only discovery access to the live `dw` MCP server
(`list_workflows`, `list_guides`, `list_pipelines`, `list_classes`,
`list_tasks`, `get_server_info`, `get_schema`, `get_guide`, `get_class`,
`get_pipeline_signature`) so you can check whether an idea already exists as
a workflow instead of guessing from source alone. You never call anything
that creates, modifies, or deletes a job, workspace, asset, model, prompt,
or workflow.

Tickets are GitHub Issues on the `dkackman/diffusers-workflow` repo (the
repo name is given in your prompt). Use the `gh` CLI for all of it. Labels:
`idea` marks an idea ticket; `owner` is exactly one of `owner:implementer` /
`owner:tester` / `owner:don` / `owner:researcher` at a time; `status:*`
prefixes and `wontfix`/`duplicate` (GitHub's built-in labels) work exactly
as they do for the implementer/tester loop — see the "Ticket protocol"
section of CLAUDE.md in this repo for the full scheme. You are given exactly
one issue number per invocation — the driver script runs you once per idea,
each a fresh session, specifically so your context never accumulates across
issues.

## Your run, this invocation

1. `gh issue view <n> --comments` to read the issue you were given.
2. Triage before researching:
   - **Still yours?** Confirm it still carries `idea` + `owner:researcher`
     with no `status:*` label. If a human or another session has already
     moved it on, stop — do not act on an issue you don't currently own.
   - **Filed by someone else?** `gh issue view <n> --json author --jq
     .author.login`. If the login is not the repo owner named in your
     prompt, the driver's `park_external_issues` should already have
     relabeled it before you were invoked — if you somehow see one anyway,
     park it yourself (`owner:don` + `status:needs-approval`, drop
     `owner:researcher`, comment why) and stop.
   - **Duplicate idea, or already shipped?** `gh issue list --repo <repo>
     --state all --search "<keywords>"` (closed issues are still canonical
     — a prior rejection or an already-fixed idea is still the reference).
     Check the live catalog (`list_workflows`, etc.) and the source tree for
     whether this already exists. If it's a duplicate of another open or
     closed issue, comment `duplicate of #NN`, add `duplicate`, set
     `owner:tester`... no — **for a duplicate idea, set `owner:researcher`
     stays wrong; instead**: add `duplicate`, comment `duplicate of #NN`,
     and `gh issue close <n> --reason "not planned"` (no owner handoff
     needed once closed). If it's already shipped, comment saying so with
     the evidence (commit/workflow name) and close the same way.
3. Research what's left:
   - Read the relevant source (`Read`/`Grep`/`Glob` under your `SOURCE_DIR`
     checkout) and its history (`git log`/`git blame`/`git show`) for
     related code, prior attempts, or comments explaining why something is
     the way it is.
   - Follow any links in the issue body via `WebFetch` (docs, papers,
     upstream library references, related issues).
   - Check the live `dw` catalog for overlap or a close existing capability.
4. Write **one** comment with your assessment, short and concrete (no prose
   padding — a fresh implementer session depends on this being
   self-explanatory), covering:
   - **Feasibility:** can this be built against the current codebase/server,
     and what would have to change.
   - **Complexity:** S/M/L, with the one or two things that drive it.
   - **Value:** who benefits and how much, in concrete terms — not "would be
     nice."
   - **Recommendation:** reject / propose to implementer / ask Don, with the
     one-sentence reason.
5. Disposition, matching what you just recommended:
   - **Reject:** add `wontfix`, `gh issue close <n> --reason "not planned"`.
     The reasoning is already in your assessment comment from step 4 — don't
     repeat it in a second comment.
   - **Propose to implementer:** remove `owner:researcher`, add
     `owner:implementer`. Add no `status:*` label — this makes it a fresh,
     ready-to-work ticket, same as any bug report with no status label. Your
     step-4 comment *is* the proposal; do not also write a separate one.
   - **Ask Don:** remove `owner:researcher`, add `owner:don` +
     `status:needs-approval`. Your step-4 comment already states the
     question implicitly via Feasibility/Value — if what you need from Don
     isn't clear from that alone, add one line to the comment (edit it, or a
     short follow-up) naming exactly what decision you need.
6. Never close an issue as `completed`/`verified` — that verb belongs to the
   tester's own real MCP verification, not to research. Never touch an
   issue that isn't currently `owner:researcher`. Never edit source,
   `regression-suite-*.md`, or `qa-bible.md` — those aren't yours to write,
   and an idea shouldn't be recorded as a regression case before anything is
   even built.
7. Don't poll or wait inside the session. One issue, one disposition, then
   exit — the driver (`run-research.sh`) gives you a fresh session per
   issue, not a loop to run yourself.

## Guardrails

- If `gh` or the `dw` MCP server is unreachable, don't guess at a
  disposition — comment what failed and stop; the next invocation of you
  (on the same issue, since you never dispositioned it) will retry.
- If an idea is already partially addressed by an in-flight implementer
  ticket, say so in your comment and set `owner:don` +
  `status:needs-approval` rather than guessing whether they're the same
  scope — that judgment call belongs to a human or to the implementer's own
  duplicate-detection, not to you re-deriving it from two issue bodies.
- Keep your assessment comment concrete: name files, functions, or workflow
  IDs you actually looked at, not "the relevant code."
```

- [ ] **Step 2: Proofread against the spec**

Re-read `docs/superpowers/specs/2026-09-14-researcher-agent-design.md`'s
"agents/RESEARCHER_AGENT.md (new file)" section and confirm every numbered
point there (triage, research, assess, disposition, guardrails, runtime
note) is represented above. Fix the file if anything is missing — the
duplicate-idea disposition wording above was corrected inline during
drafting (an earlier draft incorrectly said `owner:tester` for a duplicate,
copied from the implementer's bug-duplicate flow, which doesn't apply here
since the researcher has no tester to hand a duplicate off to); make sure
the version you write doesn't reintroduce that mistake.

- [ ] **Step 3: Commit**

```bash
git add agents/RESEARCHER_AGENT.md
git commit -m "feat: add researcher agent role prompt

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `run-research.sh` driver

**Files:**
- Create: `run-research.sh` (executable)

**Interfaces:**
- Consumes: `providers.sh`'s `resolve_model_env`, `validate_fallback_model`,
  `fallback_model_flags`, `runtime_note`, `park_external_issues`,
  `RESEARCHER_PERMISSION_FLAGS` (Tasks 2-3); `agents/RESEARCHER_AGENT.md`
  (Task 4, referenced by path in the prompt, not sourced).
- Produces: `logs/research.log`, `logs/loop.log` entries prefixed
  `[researcher:#N]`.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Runs the researcher agent once per open "idea" issue awaiting research.
# Standalone — not part of the implementer/tester alternation in
# run-loop.sh, same category as run-regression.sh.
#
#   ./run-research.sh                       # research every open idea awaiting research
#   RESEARCH_MODEL=opus ./run-research.sh   # this agent only; defaults to sonnet, not $MODEL
#   PROVIDER=ollama MODEL=qwen2.5:32b ./run-research.sh
#   DW_URL=... DW_TOKEN=... ./run-research.sh
#   tail -f logs/research.log               # watch from another terminal
#
# Model/provider resolution lives in providers.sh. RESEARCH_MODEL defaults
# to "sonnet" specifically, not $MODEL: deep feasibility judgment is
# expected to land with the implementer pass (and, where parked, with Don)
# — the research pass itself is triage-weight, so it gets the cheaper
# default while staying overridable like every other role.
#
# Unlike run-regression.sh's "one session per level," this driver gives
# each *issue* its own fresh claude -p session: the whole point is that
# issue #10's session never carries the context cost of issues #1-9, since
# nothing about a prior issue's research is relevant to the next one. All
# state that needs to survive between issues already lives on GitHub.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/diffusers-workflow}"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
TICKET_OWNER="${TICKET_OWNER:-dkackman}"
AGENTS="$REPO/agents"
LOGS="$REPO/logs"
MODEL="${MODEL:-opus}"
PROVIDER="${PROVIDER:-anthropic}"
RESEARCH_MODEL="${RESEARCH_MODEL:-sonnet}"        # NOT $MODEL — see header
RESEARCH_PROVIDER="${RESEARCH_PROVIDER:-$PROVIDER}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"
DW_URL="${DW_URL:-http://192.168.1.194:8765/mcp}"
DW_TOKEN="${DW_TOKEN:-xyz}"

[ -d "$SOURCE_DIR" ] || { echo "SOURCE_DIR not found: $SOURCE_DIR" >&2; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
command -v gh >/dev/null     || { echo "gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null     || { echo "jq not on PATH" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated" >&2; exit 1; }
mkdir -p "$LOGS"

. "$REPO/providers.sh"

resolve_model_env "$RESEARCH_PROVIDER" "$RESEARCH_MODEL" || exit 1
fb_words="$(fallback_model_flags "$RESEARCH_PROVIDER" "$FALLBACK_MODEL")" || exit 1
FALLBACK_FLAGS=(); [ -z "$fb_words" ] || read -r -a FALLBACK_FLAGS <<<"$fb_words"

ts() { date '+%H:%M:%S'; }

RESEARCH_FLAGS=(
  --mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authorization\":\"Bearer $DW_TOKEN\"}}}}"
  --strict-mcp-config
  "${RESEARCHER_PERMISSION_FLAGS[@]}"
)

# run_session <issue_number>
# One `claude -p` invocation of the researcher agent, scoped to exactly one
# issue, run from SOURCE_DIR (Read/Grep/git need real paths against the
# checkout — same cwd the implementer uses, but read-only).
run_session() {
  local n="$1"
  (cd "$SOURCE_DIR" && env ${MODEL_ENV[@]+"${MODEL_ENV[@]}"} claude -p \
    "Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$TICKET_OWNER. Follow the role instructions at $AGENTS/RESEARCHER_AGENT.md exactly for this run, researching and dispositioning ONLY issue #$n. Then stop.

$(runtime_note researcher "$RESEARCH_PROVIDER" "$RESEARCH_MODEL")" \
    --model "$RESEARCH_MODEL" ${FALLBACK_FLAGS[@]+"${FALLBACK_FLAGS[@]}"} \
    "${RESEARCH_FLAGS[@]}" 2>&1) \
    | tee -a "$LOGS/research.log" \
    | sed -u "s/^/[researcher:#$n] /" \
    | tee -a "$LOGS/loop.log" \
    || echo "[researcher:#$n] run failed" | tee -a "$LOGS/loop.log"
}

park_external_issues

mapfile -t issues < <(
  gh issue list --repo "$TICKET_REPO" --state open --limit 200 \
    --label idea --label owner:researcher --json number --jq '.[].number'
)

if [ "${#issues[@]}" -eq 0 ]; then
  echo "$(ts) no idea issues awaiting research" | tee -a "$LOGS/loop.log"
  exit 0
fi

echo "=== $(ts) research run ($MODEL_LABEL, ${#issues[@]} issue(s): ${issues[*]}) ===" | tee -a "$LOGS/loop.log"
for n in "${issues[@]}"; do
  echo "--- $(ts) researching #$n ---" | tee -a "$LOGS/loop.log"
  run_session "$n"
done
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x run-research.sh`

- [ ] **Step 3: Syntax-check**

Run: `bash -n run-research.sh`
Expected: no output, exit 0.

- [ ] **Step 4: Shellcheck**

Run: `shellcheck run-research.sh`
Expected: no warnings (fix any before proceeding — this is a new file, so
there's no "pre-existing" excuse).

- [ ] **Step 5: Dry structural check (no issues exist yet, so this exercises the empty path)**

Run: `./run-research.sh`
Expected: prints `... no idea issues awaiting research` and exits 0 (Task 1
created the labels but no issue has them yet).

- [ ] **Step 6: Commit**

```bash
git add run-research.sh
git commit -m "feat: add run-research.sh driver for the researcher agent

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: CLAUDE.md documentation

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- None — documentation only.

- [ ] **Step 1: Add a bullet for the researcher in the file-overview section**

In the bulleted list of files (currently ending with the
`REGRESSION_AGENT.md` / `run-regression.sh` bullet, right before the
"Tickets live as **GitHub Issues**..." paragraph), add a new bullet:

```markdown
- `agents/RESEARCHER_AGENT.md` / `run-research.sh` — a fourth, standalone
  agent (not part of the implementer/tester alternation, and not the
  regression agent) that turns an `idea`-labeled GitHub Issue into a
  disposition: reject it (`wontfix`), propose a concrete plan to the
  implementer (`owner:implementer`, ready to work), or park it for Don's
  input (`owner:don` + `status:needs-approval`). It is read-only against the
  `diffusers-workflow` source checkout (no write, no SSH to `lem`) plus
  read-only `dw` MCP discovery calls and `gh` for issue management — a third
  isolation shape distinct from both the implementer's full access and the
  tester/regression agent's MCP-consumer-only fence. `./run-research.sh`
  gives each open idea issue its own fresh session (never one long session
  across issues, to keep context from accumulating across a batch), by
  default on `sonnet` regardless of `$MODEL` — deep feasibility judgment is
  expected to land with the implementer pass and, where parked, Don.
```

- [ ] **Step 2: Update the ticket-protocol invariant list**

In the "Ticket protocol" section, find the line:

```markdown
- `owner` is a label, exactly one of `owner:implementer` / `owner:tester` /
  `owner:don` at a time — whoever's turn it is to act next.
```

Replace with:

```markdown
- `owner` is a label, exactly one of `owner:implementer` / `owner:tester` /
  `owner:don` / `owner:researcher` at a time — whoever's turn it is to act
  next. An `idea`-labeled issue starts as `owner:researcher`; the researcher
  agent (see above) moves it to `owner:implementer` (proposal ready to
  work) or `owner:don` + `status:needs-approval` (parked for input), or
  closes it `wontfix`, same conventions the implementer/tester already use.
```

- [ ] **Step 3: Update the "Permissions" section**

After the existing two bullets (tester/regression agent's
`--permission-mode dontAsk` fence; implementer's `--permission-mode auto`),
add a third:

```markdown
- Researcher: `--permission-mode dontAsk` + `RESEARCHER_PERMISSION_FLAGS`
  (`providers.sh`) — read-only against the `diffusers-workflow` source
  checkout (`Read`/`Grep`/`Glob`, read-only `git`) plus read-only `dw` MCP
  discovery calls and `gh`. No `Edit`/`Write` on source, no write `git`
  subcommands, no `ssh`, no `curl`. A third isolation shape: unlike the
  tester/regression agent it does see source, and unlike the implementer it
  can never change it.
```

- [ ] **Step 4: Verify the doc renders sensibly**

Run: `grep -n "owner:researcher\|RESEARCHER_AGENT\|run-research.sh" CLAUDE.md`
Expected: at least 4 matches, one in each section touched above.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document the researcher agent in CLAUDE.md

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: End-to-end smoke test

**Files:** none modified — this task only verifies Tasks 1-6 work together
against the real `dkackman/diffusers-workflow` repo and the real `dw` MCP
server.

**Interfaces:** none new.

- [ ] **Step 1: File a throwaway idea issue using the new template**

```bash
gh issue create --repo dkackman/diffusers-workflow \
  --title "[smoke-test] researcher agent dry run" \
  --label idea --label owner:researcher \
  --body "**idea:** this is a throwaway issue to smoke-test the new researcher agent driver end to end.

**motivation:** verify run-research.sh picks it up, researches it, and dispositions it.

**links:** none"
```

Note the returned issue number as `<n>`.

- [ ] **Step 2: Run the driver for real**

Run: `./run-research.sh`
Expected: log output shows `researching #<n>`, and the session completes
without a `run failed` line in `logs/loop.log`.

- [ ] **Step 3: Verify disposition happened**

Run: `gh issue view <n> --repo dkackman/diffusers-workflow --json state,labels,comments --jq '{state, labels: [.labels[].name], comments: [.comments[].body]}'`
Expected: the issue is no longer `idea` + `owner:researcher` with no status
— it's been closed `wontfix` (most likely, given it's a synthetic
smoke-test idea with no real merit) or moved to
`owner:implementer`/`owner:don`+`status:needs-approval`, and there's an
assessment comment covering Feasibility/Complexity/Value/Recommendation.

- [ ] **Step 4: Clean up if the issue is still open**

If step 3 shows anything other than closed, close it by hand with a note
that it was a smoke test:

```bash
gh issue close <n> --repo dkackman/diffusers-workflow \
  --comment "Smoke test complete, closing manually." --reason "not planned"
```

- [ ] **Step 5: Re-run the empty-path check**

Run: `./run-research.sh`
Expected: `no idea issues awaiting research` (confirms the driver doesn't
re-pick-up a closed/reassigned issue).

- [ ] **Step 6: No commit** — this task only exercises already-committed
code against live infrastructure; nothing in the repo changes.

---

## Self-Review Notes

- **Spec coverage:** every section of the spec (ticket protocol additions,
  access/isolation, role prompt, driver, `providers.sh` changes, CLAUDE.md
  changes) maps to Tasks 1-6; Task 7 covers the spec's implicit
  "does it actually work" requirement that a design doc doesn't state as a
  section but the whole point of the harness demands.
- **Placeholder scan:** none — every step has literal commands/file
  contents.
- **Type/name consistency:** `RESEARCHER_PERMISSION_FLAGS` (Task 3) is the
  exact name `run-research.sh` (Task 5) references; `runtime_note
  researcher` (Task 3) is the exact call `run-research.sh` (Task 5) makes;
  `park_external_issues` (Task 2) takes no arguments and is called
  identically from both drivers.
- Task 4's role-prompt draft caught and fixed its own bug during drafting
  (duplicate-idea disposition incorrectly borrowing the implementer's
  `owner:tester` handoff) — Task 4 Step 2 exists specifically to make sure
  whoever executes this plan doesn't reintroduce it.
