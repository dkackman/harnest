# Harness roadmap

Where this harness goes next, now that it is the main way `diffusers-workflow` changes. It was
written 2026-09-22 from a review of the loop as it stood at `e35d69d`. Pick up any item
independently: each one says why it exists, what to build, what is still undecided, and how to
know it's done. Update the status table as items move; record decisions inline under the item
rather than in a separate log.

## Status

| ID  | Item                                              | Status  | Depends on |
|-----|---------------------------------------------------|---------|------------|
| R1  | Replay benchmark (measure the loop itself)        | todo    | —          |
| R2  | Pre-hand-off reviewer subagent                    | todo    | —          |
| R3  | Invariant hooks for the implementer               | todo    | —          |
| R4  | Tester-authored acceptance specs for features     | todo    | —          |
| R5  | Scheduled suite curation                          | todo    | —          |
| R6  | Graduate mechanical cases to an executable client | todo    | R5 helps   |
| R7  | Retro agent (the self-improvement loop)           | todo    | R1         |
| R8  | Port the drivers to the Claude Agent SDK          | todo    | opportunistic |
| R9  | Approval digest for `owner:don`                   | todo    | —          |
| R10 | Split role prompts into on-demand skills          | todo    | R1 to measure |

Suggested order: R1 → R2 + R3 → R4 → R5 + R6 → R7, with R8 done the next time the drivers need
major changes, and R9 and R10 whenever there's room.

## Principles every item must keep

- **The asymmetry is the product.** The implementer never verifies its own work. The tester
  and regression agent never see source code or `lem`. Any item that blurs this (R6 comes
  close) must say how it doesn't.
- **Agents propose changes to the harness; a human approves them.** Changes to prompts,
  drivers, suites and hooks go through `owner:don` + `status:needs-approval`, the same gate
  as engine changes. Nothing here lets the loop edit its own instructions unattended.
- **Measure before and after.** Every item that claims to save cost or improve quality names
  the number that shows it: `usage:` lines, bounce counts, R1 scores, `measure-base-ctx.sh`.
- **`lem` runs one job at a time and all work goes through it.** Parallelism is only worth
  adding where it doesn't queue up behind a deploy or a GPU job.

## Baseline (2026-09-22)

The numbers later work gets compared against:

- Issues on `dkackman/diffusers-workflow`: 280 total, 31 open. 179 carry `status:verified`,
  18 `wontfix`, 55 `regression`. 40 carry `owner:don` and 27 `status:needs-approval`. These
  are labels issues carry now, open or closed, not their history. Bounce rate (hand-offs per
  verified issue) hasn't been measured yet; getting that number is R2's first step.
- 555 sessions have logged a `usage:` line, with 0 `[audit] WARNING`s since audits landed.
  A typical tester verify runs 8–29 turns at $0.32–$0.71 with a 38–65k context peak. The
  worst recorded implementer session ran 269 turns, $37 and a 352k context peak.
- Regression suites: smoke has 90 cases (240 KB), complete 34 (112 KB), model-specific 19
  (81 KB), security 30 (52 KB). `regression-perf/` tracks 19 cases.
- Driver code: `run-loop.sh` is 37 KB and `providers.sh` 37 KB (bash). The role prompts run
  4–17 KB each, and every one is loaded as the system prompt on every turn.

---

## R1 — Replay benchmark

**Why.** Prompt edits, model swaps and alias moves (`opus` becoming a new model) are judged
today by feel. The 179 verified issues are a corpus where the right answer is already known.
No other item can prove it helped without this one.

**Build.**
- `bench/`: a curated set of ~15–25 closed-and-verified issues across kinds (MCP schema bug,
  engine bug, skill-text fix, perf, security, one of each that bounced at least twice). Each
  entry records the issue, the `develop` commit just before the fix, and the verifying
  comment.
- `run-bench.sh` (or R8's SDK driver): for each entry it resets a scratch worktree of the
  dw checkout to the pre-fix commit and runs one implementer session with the issue body
  as it was filed. Then it scores the result:
  - **automatic:** the repo's `pytest` passes, the diff touches the same files as the real
    fix, and the session ran within its budget;
  - **judged:** a fresh Opus session compares the diff to the real fix and the tester's
    verify comment, then records pass, partial or fail with a reason;
  - cost, turns and peak context, taken from the `usage:` line.
- Output: one JSONL line per (entry, model, prompt commit) under `bench/results/`, plus a
  short summary table.

**Open decisions.**
- Implementer only, or the tester too? Tester replay needs `lem` on the pre-fix commit and
  real GPU time, so start with the implementer and score it offline.
- Where it runs: locally against a worktree, which is cheap and never touches `lem`.
- Keep the set small enough to run for under ~$40 total.

**Done when.** One command compares two configurations (such as `IMPLEMENTER_MODEL=sonnet`
vs `opus`, or two commits of `IMPLEMENTER.agent.md`) and prints pass rate, cost and turns
for each.

**First step.** Pick the issues. Query closed `status:verified` issues and bin them by label
and bounce count (`handoff_count` logic already exists in `run-loop.sh`).

## R2 — Pre-hand-off reviewer

**Why.** A bounce costs a full cycle: a tester session, another implementer session, and
possibly a redeploy. Many bounces are things a diff review would catch, such as a missed
edge case or a partial fix. **First step:** measure the current bounce rate by running
`handoff_count` over closed issues, and read a sample of bounce comments to confirm that a
diff review would have caught them.

**Build.** A step in `IMPLEMENTER.agent.md` before the hand-off comment: dispatch a subagent
with a fresh context (the implementer already has `Agent` in `IMPLEMENTER_TOOLS`), giving it
the issue and `git diff develop...HEAD`. It answers one question: *does this diff fix what
the issue describes, and what input would still break it?* The implementer either addresses
the findings or explains in the hand-off comment why it didn't. The reviewer never touches
labels, and it doesn't replace the tester, since it sees code and the tester must not.

**Open decisions.** Which model reviews: the tester's model is a safe default, and a
different family from the implementer's gives more independent eyes. It's still undecided
whether the review runs in the driver (a separate short `claude -p`, easier to budget and
log) or as a subagent inside the session (simpler, but shares the implementer's budget).

**Done when.** The bounce rate (tester send-backs per hand-off, from `handoff_count`) drops
over the ~30 issues after it lands, and R1 shows no pass-rate loss for the added cost.

## R3 — Invariant hooks

**Why.** Invariants that are cheap to check deterministically currently live in prompt text
and get audited only after the fact (`audit_issue` warns and repairs nothing). A red test
suite handed to the tester wastes a whole cycle.

**Build.** Hooks in `agent-settings/implementer.json`, which is already passed via
`--settings`:
- `PreToolUse` on Bash that blocks `gh issue close ... --reason completed`, any push to
  `master`, `--force` pushes, and `gh issue edit` that removes `owner:don` or
  `status:needs-approval`.
- A hand-off gate that refuses the label swap to `status:fixed-pending-verify` unless
  `pytest` (and `ruff`, if CI uses it) passed on the current HEAD. This is either a
  `PreToolUse` hook that matches the `gh issue edit ... --add-label
  status:fixed-pending-verify` command, or a `Stop` hook that checks the test result against
  the label state.
- The tester and regression agent get the mirror image: they must not add
  `status:verified` in a session with no `mcp__dw__*` call in it. That makes "only from a
  real MCP call" enforced, not just requested.

**Open decisions.** Put the hook scripts under `agent-settings/hooks/`, so they're
versioned with the harness. How to cache the test result so the gate doesn't rerun the
suite every time (a stamp file keyed on HEAD).

**Done when.** Each invariant in CLAUDE.md's "Ticket protocol" section is either enforced by
a hook or explicitly marked as prompt-only, with a reason.

## R4 — Tester-authored acceptance specs for features

**Why.** The loop is built for bugs: issue → fix → narrow repro → verify. Features and new
engine surface are escalated to `owner:don` because a narrow verify passes while the edge
cases underneath it fail. That's correct, but it makes Don the throughput limit. For the
loop to carry features, the tester has to define what "done" means before any code exists.

**Build.**
- **Parent and child issues.** A feature gets a parent issue carrying `feature`. Its
  approved proposal splits the work into child issues, each small enough for one
  implementer session. The status board and `audit_issue` learn to read the link.
- **A spec step.** Once Don approves a feature proposal, the parent goes to `owner:tester`
  with `status:needs-spec`. The tester writes acceptance cases (expected MCP behavior,
  negative cases, and edge cases the proposal implies) as suite cases marked `pending: #NN`
  in the right `regression-suite-*.md`. Then it hands the parent to `owner:implementer`.
- **Verification is the spec.** A child issue is verified against its own repro plus every
  `pending: #parent` case. When the parent closes, `pending:` is removed from those cases
  and they become ordinary regression cases. That's the only edit the no-rewrite rule
  needs to allow.

**Open decisions.** The label name (`status:needs-spec`). Whether the researcher drafts the
child breakdown or the implementer's triage does. How the regression agent treats `pending:`
cases (skip them, or run them and report the result without filing).

**Done when.** One real feature goes from `idea` to closed through this path with no
engine-surface escalation after the proposal is approved.

**First step.** Pick a feature waiting in `owner:don` and run it through this path by hand
before writing any driver code.

## R5 — Scheduled suite curation

**Why.** Suites only grow, which is right, because agents must not delete cases. But
`smoke` is 240 KB and 90 cases, which is no longer "fast and fundamental". The only way a
suite shrinks today is Don running an ad-hoc audit (the 7-agent pass on 2026-09-22 found
overlaps, contradictions and dangling references).

**Build.** A `curate` mode for `run-regression.sh`, or a small standalone driver, run on a
schedule of about once a week. It reads one suite file at a time with its
`regression-perf/` history and files a single `owner:don` + `status:needs-approval` issue
listing proposed merges, level moves (smoke → complete), retirements with reasons,
contradictions and stale references. It never edits a suite itself. Approved edits are
applied the way #329/#330/#337 were.

**Also set a budget per level.** For example, smoke should finish in under N minutes and
under $X on the default model. A curation run that finds the budget exceeded must propose
moving cases out.

**Done when.** Smoke is back under its budget and stays there without any hand-run audit.

## R6 — Move mechanical cases to an executable MCP client

**Why.** Many cases are just "call X with Y, expect field Z". Having an LLM run those is the
most expensive and least reliable way to do it: #310–#312 included a wrong literal an agent
had committed. A script runs them for $0 in seconds, and does it identically every time.

**Build.**
- `contract/`, in this repo so it stays on the consumer side of the fence: a small Python
  MCP client and a list of cases in YAML/JSON (tool, arguments, assertions on the result
  shape), keyed by the same case IDs.
- A case can declare `runner: script`. The regression agent then runs the script, reads its
  report, and handles only filing and triage for failures. Cases that need judgment (did the
  image look right, is this error message useful) stay with the LLM.
- The tester adds `runner: script` cases the same way it adds prose cases today. It needs no
  code execution, because the case is data.

**Keeping the asymmetry.** The implementer never writes or edits `contract/` cases. The
runner is a pure MCP consumer with no access to source or `lem`. If R4 lands, `pending:`
cases can be script cases too.

**Open decisions.** Which MCP client library to use. Whether the runner is invoked by the
driver before the LLM session (a cleaner cost split) or by the agent through one allowlisted
Bash command.

**Done when.** At least a third of smoke is `runner: script`, and smoke's LLM cost has
dropped by about that share.

## R7 — Retro agent (the self-improvement loop)

**Why.** The loop produces rich data about itself: `usage:` lines, bounce counts, audit
warnings, permission denials in `logs/*.log`, and wontfix reopens. Nothing reads that data
except Don in an interactive session. Every harness improvement so far started that way.

**Build.** A standalone `run-retro.sh`, read-only, run after every N cycles or weekly. It
reads the logs and issue timelines since the last retro (tracked in `logs/retro-seen`) and
files issues **against this repo** (`dkackman/iterate`), each labeled `harness` + `status:needs-approval`.
Each issue is one concrete, evidenced proposal, for example:

- "tester sessions on #3xx re-fetched the issue with `gh issue view` 4× despite
  `issue_context`"
- "implementer on sonnet bounced 3 of 4 engine issues, but 0 of 9 skill-text issues"
- "`gh api` was denied 11 times this week; widen or explain"

Where a proposal is a prompt or driver diff, it includes the diff but doesn't apply it.

**Relies on R1.** A retro proposal that changes prompts or models cites R1 results, or asks
for an R1 run, before Don approves it.

**Open decisions.** Whether this repo's issues are the right home, or whether a
`harness`-labeled issue on the dw repo is simpler, since the tooling is already there.
Whether to cap it at three proposals per run to keep signal high.

**Done when.** A retro-proposed change is approved, applied, and shown by R1 or the `usage:`
data to have helped.

## R8 — Port the drivers to the Claude Agent SDK

**Why.** About 75 KB of bash now carries the status board, escalation, bounce counting,
rate-limit sleeps, stream-json rendering and locking. Bash makes each of those harder to
change safely (see the "don't edit a live driver" memory). The Agent SDK turns each session
into a function call with structured results, hooks as callbacks, and per-call model and
budget.

**Build.** A Python package (such as `harness/`) that keeps the same CLI surface and
environment variables as `run-loop.sh`, so the knobs documented in CLAUDE.md and the README
still work. Port one driver at a time, starting with `run-research.sh` (the smallest), then
`run-regression.sh`, then `run-loop.sh`. Run the old and new drivers side by side for a few
cycles each.

**When.** Opportunistically: the next time a driver needs major changes (R3's hand-off gate,
R4's parent/child flow and R7 are all candidates), rather than as a project of its own.

**Done when.** The bash drivers are deleted, and `providers.sh`'s provider table lives in one
Python module.

## R9 — Approval digest for `owner:don`

**Why.** As the loop takes on more (R4 especially), Don's approval queue is the ceiling.
Parked issues now arrive with a proposal but no one-line summary of the recommended
decision.

**Build.** A scheduled job, daily or on each loop exit, that summarizes every `owner:don`
issue in one line: what's being asked, the agent's recommended disposition, and the command
or comment that carries it out. It's posted somewhere Don already looks: an issue comment on
a pinned tracking issue, a page, or a notification.

**Done when.** The median time an issue stays parked with Don goes down.

## R10 — Split role prompts into on-demand skills

**Why.** `IMPLEMENTER.agent.md` (16 KB), `TESTER.agent.md` (14 KB) and `REGRESSION.agent.md`
(17 KB) are loaded on every turn. Much of that text is a procedure used in a minority of
sessions: deploying, adding a suite case, closure responses, triage.

**Build.** Keep each role's identity, fences and core loop in the system prompt. Move the
occasional procedures into project skills that the role loads when the step comes up.
Measure turn-1 context before and after with `measure-base-ctx.sh`.

**Guard.** A fence must never move into a skill, because a skill might not be loaded. R1
must show no pass-rate loss after the change.

**Done when.** Turn-1 context drops measurably, and R1 or the bounce rate shows no
regression.

---

## Considered and deferred

- **Parallel implementers in worktrees.** The code could be done in parallel, but deploys to
  `lem` and GPU verification can't be, so parallel sessions would queue behind the deploy.
  Revisit if there's ever a second box or a GPU-free test tier.
- **Multi-agent workflows inside the unattended loop.** Fan-out adds cost without solving a
  problem the loop has. Workflows are useful for one-off audits Don runs interactively (like
  the 2026-09-22 suite audit), which R5 makes routine.
- **Letting the retro agent apply its own proposals.** Rejected on principle; see
  "Principles every item must keep".
