# iterate

Two Claude Code agents improving an MCP server by arguing through a ticket file.

One agent — the **implementer** — has the source, SSH to the box where the
server runs, and the authority to change things. The other — the **tester** —
has none of that. It only ever talks to the server as an MCP consumer, the way
a real user would, and reports what it finds. A shell script runs them in
strict alternation. The only channel between them is `mcp-feedback.md`.

The point of the asymmetry is that the tester can't be fooled by the code. It
can only be convinced by the interface. Fixes that read correctly but don't
behave correctly get bounced.

## How a cycle goes

```
┌─────────────┐   mcp-feedback.md   ┌─────────────┐
│ implementer │ ──────────────────▶ │   tester    │
│             │ ◀────────────────── │             │
│ source repo │                     │ MCP only    │
│ ssh lem     │                     │ qa-* spaces │
└──────┬──────┘                     └──────┬──────┘
       │ deploy                            │ tools/skills
       ▼                                   ▼
   ┌──────────────── dw MCP server on lem ────────────────┐
```

1. **Implementer** reads the ticket file, works every ticket it owns:
   triage (duplicate? already shipped? previously rejected?), reproduce on
   the box, fix on a branch, merge to `develop`, deploy to `lem`, restart,
   confirm healthy, then hand each ticket back with notes on what changed.
2. **Tester** reads the ticket file, re-runs every repro handed to it — plus
   a couple of adjacent cases — through the MCP, and marks each `verified` or
   bounces it back `open` with what's still wrong. Then it advances a
   throwaway series in `qa-` workspaces, filing tickets for anything it hits.
3. The driver prints a status board and goes again. It sleeps only when a
   cycle left the ticket file untouched.

Each agent is a fresh `claude -p` session, so nothing survives between cycles
except what's written down. That's deliberate: state lives in the ticket file
and the tester's `qa-bible.md`, not in a context window that will eventually
compact.

## The ticket protocol

Every ticket is a `## T###` block copied from the `T000` template in
`mcp-feedback.md`. The rules that make it work:

- **`owner` is a baton.** It names whose turn it is: `implementer`,
  `tester`, or `don`. An agent only touches
  tickets it owns and never rewrites the other agent's entries.
- **`verified` belongs to the tester alone**, and only from a real MCP call
  made this cycle. The implementer never self-verifies.
- **`wontfix` belongs to the implementer**, with the reason in `notes:`. The
  tester may reopen once with materially new evidence; a second `wontfix` is
  final. "Can't reproduce" goes through `needs-info` first.
- **`duplicate`** closes a ticket in favour of another, named in `notes:`.
- **`needs-approval`** with `owner: don` parks a ticket with the human. The
  implementer must use it for engine or syntax changes, new consumer-facing
  concepts, and breaking changes beyond a rename — it writes a proposal, then
  stops. You can also set it on anything to mean "not yet." Neither agent
  touches a parked ticket.
- Breaking interface changes are called out in `notes:` so the tester adjusts
  its calls instead of filing the change as a bug.
- Nobody polls or sleeps inside a session. "Nothing to do" means exit.

Status flow:

```
open ──▶ fixed-pending-verify ──▶ verified
 ▲               │
 └───────────────┘  (tester bounces it)
open ──▶ needs-info ──▶ open
open ──▶ wontfix    ──▶ (tester accepts, or reopens once)
open ──▶ duplicate
open ──▶ needs-approval ──▶ open | wontfix   (human decides)
```

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
| `MODEL` | `opus` | passed to both agents as `--model` |
| `DW_URL` | `http://192.168.1.194:8765/mcp` | the MCP endpoint handed to the tester |
| `DW_TOKEN` | `xyz` | dev token, LAN only |
| `SLEEP_SECS` | `120` | pause after an idle cycle |
| `MAX_CYCLES` | `0` | 0 = run forever |

Preconditions: `claude` on `PATH`, passwordless `ssh don@lem`, the source
checkout on `develop`.

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
`[tester]`. The same stream lands in `logs/loop.log`, with per-agent copies
in `logs/implementer.log` and `logs/tester.log`. After each cycle the driver
prints the ticket board — one line per ticket: id, status, owner, title.

Note that `claude -p` emits only the agent's final message, so the log stays
silent while an agent works and then lands its summary all at once. A
37-minute implementer pass produces nothing until minute 37.

## Layout

```
run-loop.sh              driver
mcp-feedback.md          the shared ticket file — the whole conversation
agents/
  IMPLEMENTER_AGENT.md   implementer role: loop, guardrails, deploy steps
  TESTER_AGENT.md        tester role: what it may and may not do
  TESTER_TASK.md         the tester's standing exercise between verifications
qa-bible.md              tester's memory across cycles (gitignored)
logs/                    per-cycle output (gitignored)
CLAUDE.md                notes for Claude Code sessions working on this repo
```

## What the first round looked like

Thirteen tickets went in. The implementer triaged all of them in 37 minutes:
ten shipped on one branch and deployed, one folded into another as a
duplicate, one declined with a stated what-would-change-my-mind, one found
to be a stale deploy rather than a bug, one held for a design proposal.

The tester verified eight in six minutes with measured evidence — envelope
bins summing back to the track mean, a sample rate surviving a three-step
chain — and bounced one: a variable rename that missed the template's final
step, which validation didn't catch because `previous_result:` references
aren't checked and resolve lazily. Rather than burn the 42-minute run to
prove it, the tester built a two-step probe that failed the same way in
seconds. It then filed two new tickets about why the failure would have been
expensive to diagnose.

That bounce is the whole reason the tester can't read the code.
