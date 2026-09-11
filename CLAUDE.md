# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Not an application — an orchestration harness for two Claude Code agents that iterate on the
`diffusers-workflow` MCP server in strictly alternating cycles, communicating only through a
shared Markdown ticket file. There is no build, lint, or test step.

- `run-loop.sh` — the driver. Runs implementer, then tester, then prints a ticket status board;
  repeats. Each agent is a fresh `claude -p` session, so no state survives between cycles except
  what's written to the ticket file.
- `agents/IMPLEMENTER_AGENT.md` — role prompt for the agent with source access and SSH to the
  `lem` box where the MCP server runs. It executes with cwd = the source checkout (`SOURCE_DIR`).
- `agents/TESTER_AGENT.md` — role prompt for the agent that talks to the MCP server *only* as a
  protocol consumer. It executes with cwd = this repo, which contains no code. That cwd split is
  the whole basis of the tester's isolation (honor-system beyond that — it runs with
  `--dangerously-skip-permissions`).
- `agents/TESTER_TASK.md` — the tester's standing exercise: a throwaway series built in
  `qa-`-prefixed workspaces so it finds bugs in use, not just by re-verifying fixes. Not a
  deliverable; never touches the default workspace.
- `mcp-feedback.md` — the shared ticket log. `logs/` — per-agent and combined output, gitignored.
  The tester also keeps `qa-bible.md` here (gitignored) as its memory across cycles.

## Running

```sh
./run-loop.sh                          # forever; SOURCE_DIR defaults to ~/src/dkackman/diffusers-workflow
MAX_CYCLES=3 SLEEP_SECS=60 MODEL=sonnet ./run-loop.sh   # MODEL defaults to opus
tail -f logs/loop.log                  # combined [implementer]/[tester]-prefixed stream
```

The loop sleeps only when a cycle left the ticket file untouched; if either agent wrote to it,
the next cycle starts immediately.

The tester's directory has no MCP config, so `run-loop.sh` hands it the `dw` server via
`--mcp-config` + `--strict-mcp-config` (it sees *only* `dw`) and loads the `dw` plugin live from
`$SOURCE_DIR/plugins/dw` via `--plugin-dir`. Without the latter it would use the frozen copy in
`~/.claude/plugins/cache` and never see skill fixes. The implementer needs neither flag: the
source checkout already has `dw` configured at local scope in `~/.claude.json`.

Two deploy paths, and the implementer must say which one a fix used: server code → restart on
`lem`, tool schemas refresh automatically; plugin/skill changes → commit and leave the checkout
on that branch, no restart.

## Ticket protocol (the core of the design)

Tickets in `mcp-feedback.md` are `## T###` blocks copied from the `T000` template. The
invariants both role prompts and the status-board parser depend on:

- `owner` is a baton: `implementer`, `tester`, or `don` (the human) — whoever's turn it is to act next. An agent
  only touches tickets it owns and never edits the other agent's entries beyond the fields it
  is handing off.
- Status flow: `open` → (implementer fixes + deploys to `lem`) → `fixed-pending-verify` →
  (tester re-runs repro over MCP) → `verified`, or back to `open`. `needs-info` is a
  question bounce. `wontfix` is the implementer's call (reason in `notes:`); the tester may
  reopen it once with new evidence, and a second `wontfix` is final. `duplicate` points at a
  canonical ticket. `needs-approval` / `owner: don` parks a ticket with the human — the
  implementer must use it for engine/syntax changes and anything breaking beyond a rename,
  after writing a proposal; neither agent touches a parked ticket. The implementer triages every ticket for duplicates and fixes already on
  `develop`/`lem` before reproducing. Only the tester may set `verified`, and only from a real
  MCP call.
- Implementer commits reference the ticket ID (`fix(mcp): T003 - ...`), works on branches
  merged to `develop`, never `master`.
- Breaking MCP interface changes must be called out in `notes:` so the tester adjusts its calls
  rather than filing the change as a new bug.
- Agents never poll or sleep inside a session; "nothing to do" means exit and let the driver
  re-run them. Because cycles are serialized, server restarts can't collide with tester calls.

When editing either role prompt, keep the asymmetry intact: any change that gives the tester
code or box access, or lets the implementer self-verify, defeats the purpose of the setup.
The status board in `run-loop.sh` parses the `- **status:**` / `- **owner:**` / `- **title:**`
lines, so keep that field format if you change the template.
