# iterate

Two Claude Code agents improving an MCP server by arguing through GitHub Issues,
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
Issues and the tester's `qa-bible.md`, not in a context window that will
eventually compact.

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

Tickets filed before 2026-09-12 live in `mcp-feedback.md` /
`mcp-feedback-archive.md` in this repo — frozen history from before the
migration to Issues, never edited again. The ones still active then were
carried forward as fresh Issues, cited in their body as "migrated from T0xx"
so old cross-references still resolve.

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

Case IDs are prefixed per level (`S-`/`C-`/`M-`) so the same number in two
files never collides. Each case is intent + expected result, not a pinned
tool/param name — the agent confirms the exact call shape against the live
tool schema every run, since the server evolves.

```sh
./run-regression.sh                    # smoke only (the default)
./run-regression.sh complete           # smoke, then complete
./run-regression.sh model-specific     # model-specific only
./run-regression.sh all                # all three levels
```

The suite isn't only grown by the regression agent — the implementer and
tester grow it too, whenever a fix or a verification touches something
fundamental enough to be worth a permanent check (see each role's own "Adding
a case" step, and each suite file's own "Adding a case" section for which
file a new case belongs in). The implementer can only *propose* a case, in
its issue hand-off comment — it doesn't have this repo checked out, and a
case shouldn't be recorded as confirmed behavior before the tester verifies
it over MCP. `run-regression.sh` commits any pending suite changes, from
whatever source, before and after every level it runs.

Invoke it by hand, from cron, or via the `loop` skill — like the other two
agents, it never loops or sleeps internally.

## Running it

```sh
./run-loop.sh                                   # forever
MAX_CYCLES=1 ./run-loop.sh                      # one round, then look
MODEL=sonnet SLEEP_SECS=60 ./run-loop.sh        # MODEL defaults to opus
tail -f logs/loop.log                           # watch from another terminal
```

Environment:

| var | default | what |
|---|---|---|
| `SOURCE_DIR` | `~/src/dkackman/diffusers-workflow` | implementer's cwd; also where the `dw` plugin is loaded from |
| `TICKET_REPO` | `dkackman/diffusers-workflow` | the repo whose Issues are the ticket system |
| `MODEL` | `opus` | passed to both agents as `--model` |
| `DW_URL` | `http://192.168.1.194:8765/mcp` | the MCP endpoint handed to the tester |
| `DW_TOKEN` | `xyz` | dev token, LAN only |
| `SLEEP_SECS` | `120` | pause after an idle cycle |
| `MAX_CYCLES` | `0` | 0 = run forever |

Preconditions: `claude` and `gh` on `PATH`, `gh` already authenticated,
passwordless `ssh don@lem`, the source checkout on `develop`.

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

## Watching

The terminal you launch from shows everything, prefixed `[implementer]` or
`[tester]` (or `[regression:<level>]` for a regression run). The same stream
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
agents/
  IMPLEMENTER_AGENT.md              implementer role: loop, guardrails, deploy steps
  TESTER_AGENT.md                   tester role: what it may and may not do
  TESTER_TASK.md                    the tester's standing exercise between verifications
  REGRESSION_AGENT.md               regression agent role: run mechanics, workspace rules
regression-suite-smoke.md           fast/fundamental checks, runs every time
regression-suite-complete.md        broader/slower general checks
regression-suite-model-specific.md  niche, tied to one model/pipeline
qa-bible.md                         tester's memory across cycles (gitignored)
mcp-feedback.md                     frozen ticket history from before the Issues migration
mcp-feedback-archive.md             older frozen ticket history
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
