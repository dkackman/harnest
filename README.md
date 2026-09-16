# iterate

Two Claude Code agents improving [an MCP server](https://github.com/dkackman/diffusers-workflow) by arguing through [GitHub Issues](https://github.com/dkackman/diffusers-workflow/issues),
plus a third agent that runs a standing regression suite against it on its own schedule.

One agent — the **implementer** — has the source, SSH to the box where the
server runs, and the authority to change things. The other — the **tester** —
has none of that. It only ever talks to the server as an MCP consumer, the way
a real user would, and reports what it finds. A shell script runs them in
strict alternation. The only channel between them is GitHub Issues on
`dkackman/diffusers-workflow`.

The point of the asymmetry is that the tester can't be fooled by the code. It
can only be convinced by the interface. Fixes that read correctly but don't
behave correctly get bounced.

A separate, standalone **regression agent** runs the growing suite in
`regression-suite-*.md` against the live server and files issues for anything
that fails or has slowed down — same consumer-only isolation as the tester,
but it never blocks on or hands off to anyone; it just checks and posts.

## How a cycle goes

```
┌─────────────┐   GitHub Issues     ┌─────────────┐
│ implementer │ ──────────────────▶ │   tester    │
│             │ ◀────────────────── │             │
│ source repo │                     │ MCP only    │
│ ssh lem     │                     │ qa-* spaces │
└──────┬──────┘                     └──────┬──────┘
       │ deploy                            │ tools/skills
       ▼                                   ▼
   ┌──────────────── dw MCP server on lem ────────────────┐
```

1. **Implementer** lists issues it owns (`owner:implementer`), works each one:
   triage (duplicate? already shipped? previously rejected?), reproduce on
   the box, fix on a branch, merge to `develop`, deploy to `lem`, restart,
   confirm healthy, then hand each issue back with a comment on what changed.
2. **Tester** lists issues it owns (`owner:tester`), re-runs every repro
   handed to it — plus a couple of adjacent cases — through the MCP, and
   closes each `verified` or bounces it back to the implementer with what's
   still wrong. Then it advances a throwaway series in `qa-` workspaces,
   filing new issues for anything it hits.
3. The driver prints a status board (queried live from GitHub) and goes
   again. It sleeps only when a cycle left that board unchanged.

Each agent is a fresh `claude -p` session, so nothing survives between cycles
except what's written down. That's deliberate: state lives in the GitHub
Issues and the tester's `qa-bible.md` (a bounded snapshot — cast, assets,
episode ledger, current house rules, next step — not a journal), not in a
context window that will eventually compact.

## The ticket protocol

Tickets are **GitHub Issues** on `dkackman/diffusers-workflow` (a separate
repo from this one), filed with the "MCP agent-loop ticket" template. Both
agents act on them entirely through the `gh` CLI — `gh issue list` / `view` /
`edit` / `comment` / `close`. The rules that make it work:

- **`owner` is a label, and a baton.** Exactly one of `owner:implementer`,
  `owner:tester`, `owner:don` at a time — whoever's turn it is to act next.
  An agent only touches issues carrying its own owner label and never edits
  another agent's issue beyond the label/comment that hands it off.
- **`status:verified` belongs to the tester alone**, and only from a real MCP
  call made this cycle — only the tester may close an issue as `completed`.
  The implementer never self-verifies.
- **`wontfix`** (GitHub's built-in label) belongs to the implementer, reason
  in a comment, issue closed as `not planned`. The tester may reopen once
  with materially new evidence; a second `wontfix` is final. "Can't
  reproduce" goes through `status:needs-info` first.
- **`duplicate`** (GitHub's built-in label) closes an issue as `not planned`
  in favour of another, named in a comment (`duplicate of #NN`). Closed
  issues stay canonical for duplicate detection — the implementer checks
  `--state all`, not just open issues.
- **`status:needs-approval` + `owner:don`** parks an issue with the human.
  The implementer must use it for engine or syntax changes, new
  consumer-facing concepts, and breaking changes beyond a rename — it writes
  a proposal (`docs/proposals/` in the source repo), then stops. Neither
  agent touches a parked issue.
- **`breaking-change`** flags an interface change in a comment so the tester
  adjusts its calls instead of filing the change as a new bug.
- Nobody polls or sleeps inside a session. "Nothing to do" means exit.

Status flow:

```
open ──▶ status:fixed-pending-verify ──▶ status:verified (closed completed)
 ▲                    │
 └────────────────────┘  (tester bounces it back to owner:implementer)
open ──▶ status:needs-info ──▶ open
open ──▶ wontfix (closed not planned) ──▶ (tester accepts, or reopens once)
open ──▶ duplicate (closed not planned)
open ──▶ status:needs-approval + owner:don ──▶ open | wontfix   (human decides)
```

Tickets filed before the 2026-09-12 migration to Issues lived in
`mcp-feedback.md` / `mcp-feedback-archive.md` in this repo. The ones still
active then were carried forward as fresh Issues, cited in their body as
"migrated from T0xx" so old cross-references still resolve; those files
have since been removed, since GitHub is now the sole ticket history.

## The regression suite

A third agent, independent of the implementer/tester alternation, runs a
standing suite of checks against the live server and files/comments on
GitHub Issues for anything that fails or has slowed down. It never hands
work to or waits on the other two agents — it just checks and posts.

The suite is split one file per level, each with its own workspace so a
level never shares fixtures with or skews the timings of another:

| level | file | workspace | what belongs there |
|---|---|---|---|
| `smoke` | `regression-suite-smoke.md` | `regression-smoke` | fast, fundamental, general-purpose — runs every time, the default |
| `complete` | `regression-suite-complete.md` | `regression-complete` | general-purpose but slower or more edge-case-y; runs on top of `smoke` |
| `model-specific` | `regression-suite-model-specific.md` | `regression-model-specific` | tied to one named model/pipeline/checkpoint; opt-in only |
| `security` | `regression-suite-security.md` | `regression-security` | hostile-input probes against the server's default security posture — arbitrary-code gates on introspection-based instantiation, path containment, URL scheme/host policy, secret disclosure, destructive scope; opt-in only. Issues from this suite also carry the `security` label. Its header defines "refused too late" as a failure, and lists what a consumer-only agent can't cover — that belongs in the dw repo's pytest suite instead. |

Case IDs are prefixed per level (`S-`/`C-`/`M-`/`SE-`) so the same number in
two files never collides. Each case is intent + expected result, not a pinned
tool/param name — the agent confirms the exact call shape against the live
tool schema every run, since the server evolves.

```sh
./run-regression.sh                    # smoke only (the default)
./run-regression.sh complete           # smoke, then complete
./run-regression.sh model-specific     # model-specific only
./run-regression.sh security           # security only
./run-regression.sh all                # all four levels, once each
```

`./run-regression.sh [level] [suite-file]` also takes an optional second
argument overriding just that level's suite file — its workspace is then
derived from the override's filename, never the canonical one, so a one-off
suite can't delete another suite's fixtures.

The suite isn't only grown by the regression agent — the implementer and
tester grow it too, whenever a fix or a verification touches something
fundamental enough to be worth a permanent check (see each role's own "Adding
a case" step, and each suite file's own "Adding a case" section for which
file a new case belongs in). The implementer can only *propose* a case, in
its issue hand-off comment — it doesn't have this repo checked out, and a
case shouldn't be recorded as confirmed behavior before the tester verifies
it over MCP. `run-regression.sh` commits any pending suite changes, from
whatever source, before and after every level it runs.

A level normally runs as one session. `CASES_PER_SESSION=N` splits it into
sessions of N consecutive cases plus a final sweep-only session, logged as
`[regression:smoke.1]`, `[regression:smoke.2]`, …, `[regression:smoke.sweep]`.
It defaults to 3 when the provider declares a context window under 120k
tokens (`OLLAMA_CONTEXT_TOKENS` / `GW_CONTEXT_TOKENS`) and 0 otherwise: a
40-50 KB suite read whole plus twenty cases of tool output is what put 64k
Ollama models into auto-compact thrashing. The role prompt's "Chunked runs"
section says how a slice honours `cleanup:` lines that cross its boundary.

Invoke it by hand, from cron, or via the `loop` skill — like the other two
agents, it never loops or sleeps internally.

## Running it

```sh
./run-loop.sh                                   # forever
MAX_CYCLES=1 ./run-loop.sh                      # one round, then look
IMPLEMENTER_MODEL=haiku SLEEP_SECS=60 ./run-loop.sh   # per-role models; defaults sonnet / opus
tail -f logs/loop.log                           # watch from another terminal
```

Environment:

| var | default | what |
|---|---|---|
| `SOURCE_DIR` | `~/src/dkackman/diffusers-workflow` | implementer's cwd; also where the `dw` plugin is loaded from |
| `TICKET_REPO` | `dkackman/diffusers-workflow` | the repo whose Issues are the ticket system |
| `PROVIDER` | `anthropic` | where the models live: `anthropic`, `ollama`, `gateway` |
| `IMPLEMENTER_MODEL` / `TESTER_MODEL` | `sonnet` / `opus` | per-role models |
| `IMPLEMENTER_PROVIDER` / `TESTER_PROVIDER` | `$PROVIDER` | per-role provider overrides |
| `REGRESSION_MODEL` / `REGRESSION_PROVIDER` | `opus` / `$PROVIDER` | same, for `run-regression.sh` |
| `RESEARCH_MODEL` / `RESEARCH_PROVIDER` | `sonnet` / `$PROVIDER` | same, for `run-research.sh` |
| `IMPLEMENTER_BUDGET_USD` / `TESTER_BUDGET_USD` / `TRIAGE_BUDGET_USD` | `8` / `5` / `3` | `--max-budget-usd` per session; `0` = uncapped |
| `AUTOCOMPACT_TOKENS` | `120000` | `--autocompact` for every session |
| `TESTER_TASK_EVERY` | `2` | run the tester's standing-task session every Nth cycle |
| `CASES_PER_SESSION` | 3 if the declared context window is under 120k, else 0 | `run-regression.sh` only: cases per session, 0 = whole level in one session |
| `FALLBACK_MODEL` | unset | passed as `--fallback-model` when set; must be a model the role's provider can serve (a Claude name for `anthropic`, a non-Claude tag for `ollama`) |
| `CO_AUTHOR` / `CO_AUTHOR_EMAIL` | derived | commit trailer on suite edits (see below) |
| `DW_URL` | `http://192.168.1.194:8765/mcp` | the MCP endpoint handed to the tester |
| `DW_TOKEN` | `xyz` | dev token, LAN only |
| `SLEEP_SECS` | `120` | pause after an idle cycle |
| `MAX_CYCLES` | `0` | 0 = run forever |

Preconditions: `claude` and `gh` on `PATH`, `gh` already authenticated,
passwordless `ssh don@lem`, the source checkout on `develop`.

### Models and providers

Each role has its own model knob and its own default — implementer `sonnet`,
tester `opus`, regression `opus`, researcher `sonnet`. Which role may run a
weak model is a design decision (a weak
tester rubber-stamps silently; a weak implementer's mistakes show up in
verification), so it is set per role, never for the loop as a whole.
`PROVIDER` says where the models live and is shared, with a `*_PROVIDER`
override per role:

```sh
TESTER_MODEL=opus IMPLEMENTER_MODEL=haiku ./run-loop.sh    # per-role, native
PROVIDER=ollama IMPLEMENTER_MODEL=gemma4:31b-it-q4_K_M TESTER_MODEL=gemma4:31b-it-q4_K_M ./run-loop.sh
                                                           # non-Anthropic: name every role that runs
REGRESSION_MODEL=sonnet ./run-regression.sh                # regression agent
```

`providers.sh` is the one table mapping a provider to the environment its
`claude` process needs — adding a provider is a case there, not an edit in both
drivers:

| provider | what it is |
|---|---|
| `anthropic` | native Claude Code models — an alias (`opus`, `sonnet`, `haiku`, `fable`, `opus[1m]`) or a full id. The default; sets nothing, but scrubs an ambient `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_DEFAULT_*_MODEL` (e.g. left behind by `ollama launch claude`) from the agent's environment so `anthropic/opus` is really served by Anthropic. Rejects a non-Claude model name. |
| `ollama` | a model served by Ollama, local or an Ollama-cloud tag. Rejects a Claude alias/id; requires `OLLAMA_CONTEXT_TOKENS`. |
| `gateway` | anything else speaking the Anthropic Messages API — LiteLLM, claude-code-router, a proxy. Requires `GW_BASE_URL` (never falls back to an ambient `ANTHROPIC_BASE_URL`). |

**Ollama needs no proxy.** Ollama serves the Anthropic Messages API itself at
`/v1/messages`, tool calls and streaming included (verified against Ollama
0.34). `providers.sh` sets what `ollama launch claude` sets —
`ANTHROPIC_BASE_URL`, all three `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL`
tiers pointed at the same tag, `CLAUDE_CODE_SUBAGENT_MODEL`,
`CLAUDE_CODE_ATTRIBUTION_HEADER=0` — plus two that matter specifically here:

- `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, because Ollama has no
  `/v1/messages/count_tokens` and Claude Code would otherwise assume 200k and
  auto-compact against a window the model doesn't have. There is no default:
  you must set `OLLAMA_CONTEXT_TOKENS`, and the Ollama server's own window
  (`OLLAMA_CONTEXT_LENGTH`, or the model's `num_ctx`) must be at least that
  value or the server silently truncates. Ollama's own Claude Code guidance
  uses 64k (`65536`), which is a reasonable value for the tester's working set
- `ENABLE_TOOL_SEARCH=true`, because a non-first-party base URL turns MCP tool
  search off by default and this harness is almost entirely MCP calls

It deliberately does *not* shell out to `ollama launch`: that writes a single
global profile to `~/.ollama/config.json`, which per-role models would rewrite
between agents and which is shared with your interactive `claude`. Setting the
variables directly is the same effect without the global state.

| var | default | what |
|---|---|---|
| `OLLAMA_BASE_URL` | `http://127.0.0.1:11434` | the Ollama endpoint |
| `OLLAMA_TOKEN` | `ollama` | dummy bearer token, so no ambient real key rides along to it |
| `OLLAMA_CONTEXT_TOKENS` | — | required by `ollama`; the context window Claude Code plans against, which must not exceed the server-side `OLLAMA_CONTEXT_LENGTH` / `num_ctx` (64k per Ollama's Claude Code guidance) |
| `OLLAMA_STRICT_SUPPRESS` | unset | also suppress thinking / prompt caching / experimental betas — for a model that errors on those fields instead of ignoring them |
| `GW_BASE_URL` | — | required by `gateway` |
| `GW_TOKEN` | unset | without it the gateway receives the ambient `ANTHROPIC_API_KEY` |
| `GW_CONTEXT_TOKENS` | unset | declare the window for `gateway` |

**Which roles to vary, and which not to.** The design rests on a tester that is
genuinely independent — consumer-only, no code, no box. That is only worth
anything if the tester is a capable adversary; a weak local tester degrades the
apparatus *silently*, by rubber-stamping a fix it can't really judge. Vary the
implementer and the throwaway `TESTER_TASK.agent.md` exercise freely — an
implementer's mistakes show up in its patches. Keep the tester and the
regression agent on a strong model: a verifier's mistakes are invisible, and
its verdict is the thing everything else is gated on. The two roles are also
not equally dangerous to experiment on — the implementer holds SSH to `lem`
and its shell surface can't be enumerated up front, so pointing it at an
unvetted model is a different risk class (see "Permissions" below). The
tester has neither, so its blast radius is small — but its judgment is the
load-bearing part of the whole design, which is exactly why it is the worst
place to put a weak model.

Two smaller consequences of mixing models:

- **Provenance.** Each agent is a fresh session, so its model is otherwise
  unrecorded. Both drivers now state the model and provider in the agent's
  prompt, and each role prompt tells the agent to name them in the comments it
  writes — so a verification or a filed issue can be traced back to the model
  that produced it. Suite edits are attributed via the commit trailer, which
  is `Claude (<model>) <noreply@anthropic.com>` for a Claude model (the alias
  or id as given — no alias-to-version table to go stale) and
  `<model> (via <provider>) <noreply@localhost>` for anything else, so a
  non-Anthropic model is never credited to Anthropic. `CO_AUTHOR` overrides
  only the name, `CO_AUTHOR_EMAIL` only the address.
- **`model-specific` in the regression suite means the *video* model**, not the
  LLM. Don't reuse it for a per-LLM axis.

### Why the tester needs special flags

The tester runs from this directory, which has no MCP configuration, so the
driver hands it the `dw` server explicitly with `--mcp-config` and
`--strict-mcp-config` (it sees *only* `dw` — no other servers, no noise). It
also gets `--plugin-dir $SOURCE_DIR/plugins/dw`, which loads the `dw` plugin
live from the implementer's working tree rather than the frozen copy Claude
Code keeps in `~/.claude/plugins/cache`. Without that, skill fixes would be
invisible to the tester until someone reinstalled the plugin.

That gives two deploy paths, and the implementer says which one a fix used:

- **server code** → restart on `lem`; tool schemas refresh on the tester's
  next connection automatically
- **plugin / skills** → commit and leave the checkout on that branch; no
  restart

## Permissions

No agent runs with `--dangerously-skip-permissions`. A headless `claude -p`
session never prompts, so a call that would have prompted is simply denied —
the choice is what gets auto-approved vs. auto-denied, and that choice
differs sharply by role:

- **Tester and regression agent** run under `--permission-mode dontAsk` plus
  an explicit `--allowedTools` allowlist (`CONSUMER_PERMISSION_FLAGS` in
  `providers.sh`): `mcp__dw__*`, the dw skills, `gh`, file tools for the
  suite files and `qa-bible.md`, and a handful of read-only shell helpers
  (`date`, `file`, read-only `git`). No `ssh`, `curl`, `python`, or `git`
  writes — the drivers commit suite edits themselves. This is what makes the
  consumer-only isolation *enforced* rather than honor-system; the remaining
  gap is that `Read`/`Edit`/`Write` aren't scoped by path, which the role
  prompts cover. If a cycle logs a denial in `logs/tester.log` for something
  the role legitimately needs, the fix is to widen that list deliberately,
  not to reach for the bypass flag.
- **Implementer** runs under `--permission-mode auto`. Its shell surface
  (`git`, `gh`, `ssh lem`, `pytest`, `uv`, …) can't be enumerated without
  breaking a cycle the first time it needs something new, so the classifier
  approves routine work and denies destructive or exfiltrating actions.

## Watching

The terminal you launch from shows everything, prefixed `[implementer]` or
`[tester]` (or `[regression:<level>]` for a regression run — `<level>.<n>` /
`<level>.sweep` when chunked). The same stream
lands in `logs/loop.log`, with per-agent copies in `logs/implementer.log`,
`logs/tester.log`, and `logs/regression.log`. After each loop cycle the
driver prints a ticket board queried live from GitHub — one line per open
issue: number, status label, owner label, title.

Note that `claude -p` emits only the agent's final message, so the log stays
silent while an agent works and then lands its summary all at once. A
37-minute implementer pass produces nothing until minute 37.

## Layout

```
run-loop.sh                         driver for the implementer/tester alternation
run-regression.sh                   standalone driver for the regression agent
providers.sh                        model/provider → environment table, shared by both
agents/
  IMPLEMENTER.agent.md              implementer role: loop, guardrails, deploy steps
  TESTER.agent.md                   tester role: what it may and may not do
  TESTER_TASK.agent.md              the tester's standing exercise between verifications
  REGRESSION.agent.md               regression agent role: run mechanics, workspace rules
regression-suite-smoke.md           fast/fundamental checks, runs every time
regression-suite-complete.md        broader/slower general checks
regression-suite-model-specific.md  niche, tied to one model/pipeline
regression-suite-security.md        hostile-input probes, opt-in only
qa-bible.md                         tester's memory across cycles: ~12 KB snapshot (gitignored)
logs/                               per-cycle output (gitignored)
CLAUDE.md                           notes for Claude Code sessions working on this repo
```

## What the first round looked like

Thirteen tickets went in, back when tickets were still `## T###` blocks in
`mcp-feedback.md` rather than GitHub Issues. The implementer triaged all of
them in 37 minutes: ten shipped on one branch and deployed, one folded into
another as a duplicate, one declined with a stated what-would-change-my-mind,
one found to be a stale deploy rather than a bug, one held for a design
proposal.

The tester verified eight in six minutes with measured evidence — envelope
bins summing back to the track mean, a sample rate surviving a three-step
chain — and bounced one: a variable rename that missed the template's final
step, which validation didn't catch because `previous_result:` references
aren't checked and resolve lazily. Rather than burn the 42-minute run to
prove it, the tester built a two-step probe that failed the same way in
seconds. It then filed two new tickets about why the failure would have been
expensive to diagnose.

That bounce is the whole reason the tester can't read the code.
