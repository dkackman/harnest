# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Not an application — an orchestration harness for two Claude Code agents that iterate on the
`diffusers-workflow` MCP server in strictly alternating cycles, communicating through GitHub
Issues (see "Ticket protocol" below) and, for regression coverage, the `regression-suite-*.md`
files described below. There is no build, lint, or test step.

- `run-loop.sh` — the driver. Runs implementer, then tester, then prints a ticket status board;
  repeats. Each agent is a fresh `claude -p` session, so no state survives between cycles except
  what's written to GitHub Issues (or, per each role prompt's "Adding a case" step, a
  `regression-suite-*.md` file).
- `agents/IMPLEMENTER_AGENT.md` — role prompt for the agent with source access and SSH to the
  `lem` box where the MCP server runs. It executes with cwd = the source checkout (`SOURCE_DIR`).
- `agents/TESTER_AGENT.md` — role prompt for the agent that talks to the MCP server *only* as a
  protocol consumer. It executes with cwd = this repo, which contains no code. That cwd split is
  the whole basis of the tester's isolation (honor-system beyond that — it runs with
  `--dangerously-skip-permissions`).
- `agents/TESTER_TASK.md` — the tester's standing exercise: a throwaway series built in
  `qa-`-prefixed workspaces so it finds bugs in use, not just by re-verifying fixes. Not a
  deliverable; never touches the default workspace.
- `agents/REGRESSION_AGENT.md` / `run-regression.sh` — a third, standalone agent (not part of
  the implementer/tester alternation) that runs the growing suite against the live MCP server
  and files/comments on GitHub Issues for failures and performance regressions. Same
  consumer-only isolation as the tester; ends by posting to GitHub, no back-and-forth with the
  implementer. The suite is split one file per level, each with its own workspace so levels
  never share fixtures or skew each other's timings: `regression-suite-smoke.md` (workspace
  `regression-smoke`, fast/fundamental/general-purpose, the default), `regression-suite-complete.md`
  (workspace `regression-complete`, general-purpose but broader/slower, runs on top of `smoke`),
  and `regression-suite-model-specific.md` (workspace `regression-model-specific`, niche, tied
  to one model/pipeline, opt-in only). `./run-regression.sh [level] [suite-file]` picks the level
  (default `smoke`; `complete` also runs `smoke` first; `all` runs all three, once each) and
  optionally overrides just that level's suite file (its workspace is then derived from the
  override's filename, never the canonical one, so a one-off suite can't delete another suite's
  fixtures). Case IDs are prefixed per level (`S-`/`C-`/`M-`) so the same number in two files
  never collides in the regression agent's duplicate-issue search. Each run deletes what its
  cases generate as soon as a case (and any dependent case) is done, keeping only durable
  fixtures listed in that suite file's "Fixtures" section (workflows/assets reused across runs)
  and artifacts an open issue needs for a repro; a final sweep removes anything else. All three
  suite files are checked in (not gitignored) — they're the deliverable. `run-regression.sh`
  commits any pending changes to them before and after every level it runs, so edits made
  outside a regression run (see below) aren't lost or misattributed. The regression agent grows
  the suites over time as it finds adjacent functionality worth covering; the implementer and
  tester grow them too, but not the same way — the implementer only *proposes* a case in its
  issue hand-off comment (it doesn't have this repo checked out, and a case shouldn't be recorded
  as confirmed behavior before the tester verifies it over MCP); the tester adds the case for
  real once it verifies. Either role picks whichever suite file fits (same format, plus a
  `source:` line) — see each suite file's own "Adding a case" section for the line between
  levels. Invoke the regression agent by hand, from cron, or via the `loop` skill; it never loops
  or sleeps internally.
- Tickets live as **GitHub Issues** on `dkackman/diffusers-workflow` (not in this repo) — both
  agents act on them with the `gh` CLI, already authenticated on this machine. Filed with the
  "MCP agent-loop ticket" template (`.github/ISSUE_TEMPLATE/mcp-ticket.md` in that repo).
  `mcp-feedback.md` and `mcp-feedback-archive.md` here are frozen: they hold every ticket filed
  before the 2026-09-12 migration to Issues, kept for history only, never edited again. `logs/` —
  per-agent and combined output, gitignored. The tester also keeps `qa-bible.md` here (gitignored)
  as its memory across cycles.

## Running

```sh
./run-loop.sh                          # forever; SOURCE_DIR defaults to ~/src/dkackman/diffusers-workflow
MAX_CYCLES=3 SLEEP_SECS=60 MODEL=sonnet ./run-loop.sh   # MODEL defaults to opus
tail -f logs/loop.log                  # combined [implementer]/[tester]-prefixed stream
```

The loop sleeps only when a cycle left the ticket board unchanged; if either agent's issue
activity changed it, the next cycle starts immediately. (Whether an agent also appended a
regression case in the same cycle isn't part of that check.)

The tester's directory has no MCP config, so `run-loop.sh` hands it the `dw` server via
`--mcp-config` + `--strict-mcp-config` (it sees *only* `dw`) and loads the `dw` plugin live from
`$SOURCE_DIR/plugins/dw` via `--plugin-dir`. Without the latter it would use the frozen copy in
`~/.claude/plugins/cache` and never see skill fixes. The implementer needs neither flag: the
source checkout already has `dw` configured at local scope in `~/.claude.json`.

Two deploy paths, and the implementer must say which one a fix used: server code → restart on
`lem`, tool schemas refresh automatically; plugin/skill changes → commit and leave the checkout
on that branch, no restart.

## Ticket protocol (the core of the design)

Tickets are **GitHub Issues on `dkackman/diffusers-workflow`**, not entries in a file in this
repo. Both agents act on them with the `gh` CLI (`gh issue create` / `edit` / `comment` /
`close` / `list`). The invariants both role prompts and the status-board query depend on:

- `owner` is a label, exactly one of `owner:implementer` / `owner:tester` / `owner:don` at a
  time — whoever's turn it is to act next. Swap it with `gh issue edit <n> --remove-label
  owner:X --add-label owner:Y`. An agent only touches issues carrying its own owner label and
  never edits another agent's issue beyond the label/comment that hands it off.
- Status flow: no status label ("open", ready for the implementer) → (implementer fixes +
  deploys to `lem`) → `status:fixed-pending-verify` → (tester re-runs repro over MCP) → close the
  issue as `completed` with `status:verified` added, or back to no status label / owner back to
  `owner:implementer`. `status:needs-info` is a question bounce. `wontfix` (GitHub's built-in
  label) is the implementer's call, reason in a comment, issue closed as `not planned`; the
  tester may reopen it once with new evidence, and a second `wontfix` is final. `duplicate`
  (GitHub's built-in label) closes an issue as `not planned` in favour of another, named in a
  comment (`duplicate of #NN`). `status:needs-approval` + `owner:don` parks an issue with the
  human — the implementer must use it for engine/syntax changes and anything breaking beyond a
  rename, after writing a proposal; neither agent touches a parked issue. The implementer
  triages every issue for duplicates and fixes already on `develop`/`lem` before reproducing,
  checking both open and closed issues (`gh issue list --state all`) — a closed issue is still
  canonical for duplicate detection. Only the tester may close an issue as `completed`
  (`verified`), and only from a real MCP call.
- Implementer commits reference the issue number (`fix(mcp): #42 - ...`), works on branches
  merged to `develop`, never `master`.
- Breaking MCP interface changes get the `breaking-change` label plus a comment, so the tester
  adjusts its calls rather than filing the change as a new bug.
- Agents never poll or sleep inside a session; "nothing to do" means exit and let the driver
  re-run them. Because cycles are serialized, server restarts can't collide with tester calls.
- Tickets filed before 2026-09-12 live in `mcp-feedback.md` / `mcp-feedback-archive.md` in this
  repo, frozen; the ones still active were carried forward as fresh Issues (#69–#79), cited in
  their body as "migrated from T0xx" so old cross-references still resolve.

When editing either role prompt, keep the asymmetry intact: any change that gives the tester
code or box access, or lets the implementer self-verify, defeats the purpose of the setup.
The status board in `run-loop.sh` queries `gh issue list --json number,title,labels`, so keep
the `owner:*` / `status:*` label prefixes if you change the label scheme.
