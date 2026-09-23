# Harness roadmap

Where this harness goes next, now that it is the main way `diffusers-workflow` changes. It was
written 2026-09-22 from a review of the loop as it stood at `e35d69d`. Pick up any item
independently: each one says why it exists, what to build, what is still undecided, and how to
know it's done. Update the status table as items move; record decisions inline under the item
rather than in a separate log.

## Status

| ID  | Item                                              | Status  | Depends on |
|-----|---------------------------------------------------|---------|------------|
| R1  | Replay benchmark (measure the loop itself)        | done; baseline + checklist run | —   |
| R2  | Pre-hand-off reviewer subagent                    | checklist applied; watch live bounces | — |
| R3  | Invariant hooks for the implementer               | done; watch live cycles | —   |
| R4  | Tester-authored acceptance specs for features     | todo    | —          |
| R5  | Scheduled suite curation                          | built; first proposal harnest#2 waiting | — |
| R6  | Graduate mechanical cases to an executable client | runner built; 3 cases; graduation needs approval | R5 helps |
| R7  | Retro agent (the self-improvement loop)           | built; first proposal harnest#3 | R1 |
| R8  | Port the drivers to the Claude Agent SDK          | todo    | opportunistic |
| R9  | Approval digest for `owner:don`                   | built (`run-digest.sh`) | — |
| R10 | Role prompts: dedupe, then assemble per session kind | todo | R1, R3     |
| R11 | Feature lead: proposals as issues, designed with Don, built in stages | proposals migrated (dw#374–#380, #244); design todo | R4 (absorbs it), R1 |

Suggested order: R1 → R2 + R3 → R4 → R5 + R6 → R7, with R8 done the next time the drivers need
major changes. R9 can go in whenever there's room; R10 goes after R3. R11 takes over R4: build
R4's spec step as R11's phase 3, not separately.

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
  are labels issues carry now, open or closed, not their history.
- Bounce rate, over the 195 `status:verified` issues: 210 hand-offs, 18 of them sent back
  (8.6%). 14 issues bounced at least once, 178 passed first time, and 3 predate hand-off
  labels.
- `develop` at `e5bfb9e` was red by CI's own standard: 2 real test failures
  (`test_the_tool_surface_fits_the_budget` at 14,224 against a 13,890-token budget, and the
  ltx-2.5 skill at 12,486 against a 12,288-byte cap). `ruff check` had 1 error and
  `ruff format` 11 files. Each hand-off added a little, and nothing stopped it; R3's gate
  now does. Two more `test_worker.py` failures are specific to this Mac (`/Volumes/NVME`),
  and `test_download_watch` is flaky.
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

**Built (2026-09-22).** `run-bench.sh` and `bench/`; `bench/README.md` has the details.
- 17 cases chosen from fixes of 1–2 commits and 20–600 changed lines: 4 that bounced
  twice, 1 security, 1 perf, 3 engine, 4 MCP, 3 validation, 1 skill-text, 1 template sweep.
  None of the issue bodies was edited after filing.
- Decisions on the open questions: implementer only, local, never touching `lem`. The real
  role prompt runs with a fixed replay note appended. The note routes the hand-off to
  `HANDOFF.md` and is enforced by deny rules. It cancels out of comparisons because every
  configuration gets it.
- Leak-proofing: each case is a fresh `git init` plus a fetch of the pre-fix sha, so no
  later object exists in the clone. There's no remote and no MCP, and `gh`/`ssh`/push/web
  are denied.
- Scoring: new pytest failures against that commit's own failures, the real fix's tests on
  the candidate tree, file recall, and an Opus judge (`JUDGE_MODEL`, no tools).
- Dry run on #238 (sonnet): pass, 49 turns, $1.47, 87k peak context, no new failures, the
  same file as the real fix.
- Live implementer sessions ran $1.29 median ($3.28 p90). A full 17-case run should be
  about $25–30, including roughly $0.10–0.30 of judge per case.

**First baseline (2026-09-23, `baseline-sonnet@5e4cfc7`, body-only snapshots).**
- Results: 9 pass, 5 partial, 3 fail (53% pass). No case introduced a new test failure.
  $15.62 total ($0.92/case), 30 turns and a 74k peak context per case.
- The real fix's tests passed on only 13% of candidates. That signal is weak, because the
  real tests pin names and message wording, so it stays an input to the judge rather than
  a verdict.
- The run exposed a flaw in the cases: three issues (#265, #272, #345) had been parked with
  Don before their fix. The replay saw only the body as filed, so #272 re-escalated instead
  of fixing. Most cases also had a `triage:` comment the real session saw.
- `snapshot.py` now freezes the body plus the owner's comments before the first hand-off,
  which is what `issue_context` gave the real session. The first baseline is kept, under
  its own label, as a record, not a reference point.
- On the bounced cases, the judge marks down what only the tester's bounce asked for (#75's
  `pipeline_released` event, #265's run-time backstop). The real implementer missed those
  too, so those cases measure whether a fix anticipates the tester, which is R2's target.
- The judge was somewhat lenient on error-message quality: #124 passed with a raw-regex
  message.

**Corrected baseline, and the R2 checklist (2026-09-23).** Both runs were judged by the
same judge. It was pinned to `claude-opus-5-5` at effort `high`, with a rubric that counts
error and warning message quality, and 3 tries of 150 s each.

| run | judged | pass | partial | fail | cost |
|---|---|---|---|---|---|
| `baseline2-sonnet@a84c53b` (corrected snapshots) | 16 of 17 | 10 | 5 | 1 | $18.74 |
| `checklist-sonnet@733e4db` (+ pre-merge checklist) | 17 of 17 | 11 | 6 | 0 | $19.53 |

Case by case, 14 of 17 cases got the same verdict. The differences:
- **#302, partial → pass.** The candidate swept all ~50 templates instead of two. That's
  exactly the checklist's "every item the issue names is covered".
- **#124, pass → partial.** The two sessions wrote different messages. The checklist run
  produced the raw-regex message the first run had also produced. That's sampling
  variance, correctly penalized by the new rubric.
- **#186, fail → partial.** Both runs have the same underlying flaw; this is judge variance
  on it.
- **#238** was never judged in baseline2: the Opus stall beat all three tries.

With 17 cases and one run each, the checklist is neutral on pass rate. It has one win
traceable to it, no loss attributable to it, and costs about 4% more.

Judge notes:
- Opus stalled mid-thinking on #238's baseline2 prompt in every try. A trivial Opus prompt
  answered in 2 s, and Sonnet answered that prompt every time. A case that exhausts its
  tries is counted as "unjudged" (`judged=` in `--summary`), not as a fail.
- A single run's noise is about ±1–2 cases. Before relying on a small difference, run the
  same config twice.

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

**Measured (2026-09-22).**
- The bounce rate is 8.6% (18 of 210 hand-offs). A subagent classified all 18 bounce
  comments:
  - 11 DIFF-VISIBLE: a reviewer with the issue, the diff and read access to the tree could
    have caught them;
  - 4 RUNTIME-ONLY: real GPU/model/hub behavior (#186, #153, and the borderline #217 and
    #198);
  - 2 SPEC-GAP: scope grew during verification (#197's third bounce, #75);
  - 1 OTHER: a dependency bump for #224 broke #223's verification.
- The diff-visible misses fall into four patterns:
  - **tests that mock the very thing the issue claims:** #223 twice, #197, #186;
  - **a user-facing warning sent to `logger.warning`**, which never reaches the job over
    MCP: #82, #108;
  - **an item the issue names with no change or no test:** #220 (the second docstring
    copy), #265 (the H3 half), #117 (the URL probe), #303;
  - **hand-off prose the diff contradicts:** #108, #303, #85.

**Decision: a checklist, not a reviewer, for now.** Eleven avoidable bounces at about $2
each (a tester verify plus an implementer rerun) is about $22 over 210 hand-offs. A
reviewer session on every hand-off would cost more than that. The four patterns are
specific enough to go into the implementer's step 3e as a self-check before the label
swap:
- does every item the issue names have a change and a test that exercises it, unmocked?
- is every run-time warning raised through `emit_warning`?
- does each claim in the hand-off comment match the diff?

That's a prompt change, so it goes through R1: a baseline run, the checklist, then a rerun.
The 4 bounced cases in `bench/` are the ones to watch. Revisit the reviewer if the checklist
doesn't move the bounce rate over the next ~30 hand-offs.

**Applied (2026-09-23), in step 3c of `IMPLEMENTER.agent.md`, before the merge.** It's in 3c
rather than 3e so that it runs before `develop` is pushed, where fixing a miss is cheaper,
and so that the benchmark's replay note (which skips 3e) exercises it. R1 result: neutral on
pass rate, one traceable win (#302), +4% cost; see R1. The measure that decides it is the
live bounce rate over the next ~30 hand-offs, against 8.6%. `run-retro.sh`'s digest reports
hand-offs and bounces for each window.

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

**Done (2026-09-22).** `agent-settings/hooks/guard.py` is one `PreToolUse` hook on `Bash`
for every role. The implementer loads it through `agent-settings/implementer.json`; tester
and regression load it through `agent-settings/consumer.json` inside
`CONSUMER_PERMISSION_FLAGS`. A 25-command table test covers it, and a headless `claude -p`
under the drivers' isolation flags confirmed it fires.
- **Hand-off gate, relative:** no test may fail that passed on `HARNEST_BASE_COMMIT`
  (origin/develop when the session began). It isn't absolute because `develop` was red
  (see Baseline) and an absolute gate would block every hand-off. The base's failures are
  cached per commit, and a passing tree+base is stamped, both in the checkout's `.git`.
  `ruff` runs only on changed files, for the same reason.
- **Tester's "real MCP call" check:** reads the session transcript for an `mcp__dw__*`
  tool use.

| Invariant (CLAUDE.md "Ticket protocol") | How it is held |
|---|---|
| Exactly one `owner:*` label | **hook**: adding one requires removing one in the same command; `audit_issue` still checks after |
| Only the tester closes as `completed` | **hook**: implementer `gh issue close` without `--reason "not planned"` is refused (gh's default is completed) |
| `status:verified` only from a real MCP call | **hook**: consumer close-completed/`status:verified` refused in a session with no `mcp__dw__*` call; implementer can't add it at all |
| Nobody touches a parked (`owner:don`) issue | **hook**, partly: removing `owner:don`/`status:needs-approval` is refused. Commenting on one stays prompt-only: parking an issue legitimately comments on it, and the hook can't tell the two apart without an API call per command |
| Never push `master`; no force pushes | **hook** |
| Hand-off only with tests passing | **hook** (the gate above) |
| Branches merged to `develop`, deploy `develop` | driver: `check_lem_on_develop` redeploys and warns |
| Third-party issues are parked | driver: `park_external_issues` before every cycle |
| Commits reference the issue number | prompt-only: cosmetic, and the benchmark reads it but nothing breaks without it |
| `breaking-change` label on interface changes | prompt-only: needs judgment about what counts as breaking |
| `wontfix` reopened at most once; second is final | prompt-only: needs the issue's history, which is a `gh api` call, and it has never been violated in the logs |
| Agents never poll or sleep in a session | prompt-only: `sleep` has legitimate short uses; per-session budget caps bound the damage |
| Suite cases are add-only | driver: `commit_suite_changes` warns on removed lines |
| Only issues with your own `owner:*` label | prompt-only: needs the issue's current labels, which is one `gh` call per command. The driver already chooses which issue a session works |

Watch the next few cycles for `Blocked by the harness guard` in `logs/*.log`. A denial
that recurs for a legitimate action is a bug in the guard, not in the agent.

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

**Folded into R11 (2026-09-23).** R11 builds this item's parent/child issues and its spec
step as its phases 2–3 and 5. It answers the open decisions: `status:needs-spec` is kept,
and the feature lead writes the child breakdown from the approved plan.

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

**Built (2026-09-22).** `run-curate.sh` and `agents/CURATOR.agent.md` run one Opus session per
level (`CURATE_MODEL`). The session reads the suite, its `regression-perf/` files and a
chunk table from `loop.log`: which cases ran in which session, and what that session cost,
because cost is only known per chunk. It files one issue with at most 12 proposals on **this repo**, labeled `suite` +
`status:needs-approval`. Suite proposals moved here from the ticket repo on 2026-09-22: they
edit files that live here, and on dw they sat in the loop's status board and Don's engine
queue. The "Removing a case" rule in every suite file, and the tester's and regression
agent's copies of it, now point here too.
- It has no Edit/Write and no MCP.
- A level is skipped for `CURATE_EVERY_DAYS` (7) after a run, and while its last curation
  issue is still open, so proposals don't pile up.
- Proposed budgets per full run: smoke 20 min / $8, complete 60 / $20, model-specific
  60 / $12, security 15 / $6 (`CURATE_BUDGET_<LEVEL>`). These are proposals, not
  measurements; smoke actually ran about 40 min / $17–18 on sonnet over its last three
  runs.
- First run: **harnest#2** (smoke; filed as dw#373 and transferred), $1.91, 12 proposals: 5 moves, 3 merges, 1 contradiction
  and stale references. Item 5 is flagged as only needed if $8 is firm. The session
  caught one bad citation (item 6) in its final message but didn't fix the issue, so the
  prompt now says to re-check citations before filing and to edit the issue if a mistake
  is found.

**Next.** Decide harnest#2, especially the smoke budget. Then schedule `run-curate.sh` weekly
(cron or the `loop` skill).

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

**Built (2026-09-22).** `contract/`; see `contract/README.md`.
- `mcp_client.py` is a standard-library MCP client over streamable HTTP. There's no
  dependency to choose, which settles the library question.
- `run.py` takes cases as JSON (`steps` of `{call, args, expect}`) and prints a JSON
  report, exiting 0/1/2.
- Three cases written: S-F002, S-F028 and S-F036. All pass on `lem` in 0.36 s total. A
  mutation check changed one expectation in each case, and every changed expectation
  failed with a readable message.
- Decision on the runner: the driver runs it, not the agent. `run-regression.sh` runs
  every case whose suite block has a `runner: script` line and a matching
  `contract/cases/<ID>.json`, before any session. It removes those cases from the agent's
  chunks and hands the report to the level's last session, which only files failures.
- The suite line is the switch. Graduating a case edits it, so it goes through
  `owner:don`. No case is marked yet, so the integration does nothing until one is.
- Writing S-F036 found a stale detail in its prose: `output:` references "need not exist"
  but must be well-formed names (`workflow/run/file`), which the server now checks. A
  script case makes that kind of literal explicit.

**Next.**
1. Approve marking S-F002/S-F028/S-F036 `runner: script`.
2. Pick the next batch. The free `validate_workflow` pre-flight cases (S-F010, S-F018,
   S-F026, S-F032–S-F035) are the obvious ones.
3. Teach the tester to add a JSON case beside a prose case it adds. That's a
   `TESTER.agent.md` change, and `commit_suite_changes` must also commit
   `contract/cases/`.

## R7 — Retro agent (the self-improvement loop)

**Why.** The loop produces rich data about itself: `usage:` lines, bounce counts, audit
warnings, permission denials in `logs/*.log`, and wontfix reopens. Nothing reads that data
except Don in an interactive session. Every harness improvement so far started that way.

**Build.** A standalone `run-retro.sh`, read-only, run after every N cycles or weekly. It
reads the logs and issue timelines since the last retro (tracked in `logs/retro-seen`) and
files issues **against this repo** (`dkackman/harnest`), each labeled `harness` + `status:needs-approval`.
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

**Built (2026-09-22).** `run-retro.sh` and `agents/RETRO.agent.md` (Opus, $5 cap).
- **Decisions:** proposals go to **`dkackman/harnest`**, labeled `harness` +
  `status:needs-approval`. That keeps them out of the dw loop's queue, status board and
  audit. At most **3** proposals per run.
- **Evidence:** the driver computes the evidence itself, so the agent starts from facts:
  - sessions and cost per role and kind, and the most expensive sessions;
  - `[audit]` warnings and guard refusals;
  - permission denials grouped by command;
  - bounces in the window;
  - the bench summary.
- **Window:** "since the last retro" is byte offsets into each log, in
  `logs/retro-seen.json`. They advance only after a session that finished.
  `RETRO_EVIDENCE_ONLY=1` prints the evidence without a session.
- **First evidence run (not yet a session):** 215 denials, 204 of them from the tester
  and regression agent.
  - The top pattern is shell-writing files: `cat >` a comment body to `/tmp` (74, from
    the tester) and `cat >>`/`printf` to `regression-perf/*.jsonl` (about 35, from
    regression).
  - Each is a wasted turn before the agent switches to Write/Edit. That's a legitimate
    need hitting the fence, the kind of thing the first retro should propose a fix for.
  - The most expensive session in the window was a `regression:complete` run: $37.62,
    311 turns, 345k peak context.

**First retro (2026-09-23): harnest#3**, $0.79. It judged the fence right, and proposed
that the tester and regression prompts name the allowed tool for each denied pattern: Write
plus `--body-file`, Edit for perf appends, `--jq` instead of pipelines and loops. The
measure it named is those denial counts in the next digest. It looked at the most expensive
sessions and the bounces and found nothing new to file. Its own fence denied it a `for`
loop and an `awk` pipeline once each.

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

**Built (2026-09-22).** `run-digest.sh` runs one tool-less sonnet session over every open
`owner:don` issue. Comments by other logins are withheld, as in `run-loop.sh`. For each
issue it produces a row: the ask, a recommendation, and the exact `gh` command that carries
it out. It prints the median days parked, which is this item's measure, and writes
`logs/digest.md`. `DIGEST_ISSUE=N` also posts it as a comment on issue N. Where to post by
default is still open.
- First run: 4 parked, median 3.5 days. #195, #218 and #244 each got a concrete
  "needs a proposal" ask; #300 got "read it yourself", since its thread has no
  recommendation.

## R10 — Role prompts: remove duplication, then build each prompt per session kind

**Origin.** The loop-monitoring session's harness review (2026-09-22, session `8b1f39d1`)
estimated the implementer and tester prompts "could each lose roughly a third": they carried
dated measurements and incident stories, and repeated the label scheme. Commit `0dfb73b`
trimmed the anecdotes lightly (the prompts now contain no dates or issue-number war
stories) and deliberately left the deeper cut for later, so the Opus 5.5 trial wasn't
testing two changes at once.

**Assessment (2026-09-22).** The one-third estimate is about right in bytes, but for a
different reason than the review gave, and cost is not the case for doing it:

- **Cost is negligible.** `IMPLEMENTER.agent.md` is about 4k tokens and `TESTER.agent.md`
  about 3.5k. Sessions peak at 40–65k context, and the system prompt is cached. Cutting a
  third saves roughly 1.3k cached tokens per turn, about $0.01–0.02 over a 25-turn verify,
  or around 1% of a session. Don't justify this item with cost.
- **The real problem is duplication and text for other session kinds.** A rule stated
  three times in slightly different words is where a model finds a contradiction.
  Examples from the current text:
  - The "filed by someone else → park" rule appears three times in the implementer prompt:
    step 3a, triage step 2 and Guardrails.
  - "Deploy failed → `needs-info` + `owner:don`" appears twice, in step 3d and Guardrails.
    That exact split was once a real contradiction: the older Guardrails text said to keep
    `owner:implementer`, which stranded the issue. The review caught it.
  - The duplicate-check procedure is written out in both step 3a and the triage section.
  - "Never close as completed" appears in step 4 and again under the tester's ownership.
  - "Don't poll or sleep" appears in implementer step 2 and tester step 5.
- **Some text no longer applies.**
  - "`notes`/`verify-notes` from the old markdown protocol" is in both prompts, but no
    agent has seen that protocol since the 2026-09-12 migration.
  - Tester step 1, "don't list and work every `owner:tester` issue", and step 5, "if none
    of your open issues are ready…", date from before per-issue sessions.
  - Implementer step 2, "if there's nothing to do, exit", mostly can't happen now that the
    driver names a ready issue.
- **Most of each prompt is for session kinds other than the current one.** A VERIFY session
  reads HANDOFF, ANSWER, closures and TASK text. A fix session reads the whole triage
  section, which is about 2.5 KB; a triage session reads the whole fix loop. The driver
  already knows the session kind when it builds the prompt (TRIAGE/fix,
  VERIFY/HANDOFF/ANSWER/TASK/closures), so it doesn't have to guess.

**Build.**
1. **Remove duplication and dead text.** Keep one authoritative statement of each rule,
   and where the rule is needed, point to it rather than restating it. Delete the
   old-protocol and pre-per-issue text. Keep a short *why* where it changes behavior, such
   as "because `lem` can only be on one commit". Rationale helps a model generalize, so
   this isn't a cut to bare rules; cut narrative, not reasons.
2. **Build the prompt per session kind in the driver.** Split each role prompt into a
   shared core (identity, fences, label scheme, trust rule, guardrails) plus one fragment
   per session kind. `run-loop.sh` concatenates core + fragment into the
   `--append-system-prompt-file` it already writes. Do this, not skills: the driver knows
   the kind for certain, while a skill might not load, and no fence may ever depend on
   something that might not load.
3. **Apply the same pass to `REGRESSION.agent.md`** (17 KB, the largest). It has chunked,
   sweep and full-run modes, and the driver knows which one it's starting.

**Guard.**
- Every fence and invariant stays in the shared core, word for word, or is enforced by R3
  hooks first. Removing duplication must never delete the only copy of a rule.
- Diff the rule list before and after: extract each "never / only / must" sentence and
  confirm each one still exists exactly once.
- This is a prompt change, so it follows the Principles: R1 before and after for the
  implementer; for the tester, compare bounce and verify-quality spot checks over the next
  ~20 verifies, since R1 doesn't cover the tester yet.

**Done when.** The prompts contain no duplicate rules or old-protocol text. Each session
loads only its kind's fragment, with the turn-1 context drop measured by
`measure-base-ctx.sh`. R1 and the verify spot checks show no regression.

**Sequencing.** Do this after R3. Once hooks enforce some of the invariants, their prose
copies can shrink to a one-line pointer, which makes the cut safer.

## R11 — Feature lead: proposals as issues, designed with Don, built in stages

**Why.** Work bigger than a fix doesn't go through the loop. It's written up in the dw repo's
`docs/proposals/` (10 open docs, 4 `complete/` design records, and `todo.md` ranking them). It
waits there until Don picks one. Then an interactive Claude Code session takes it from a
short Q&A to a plan, and executes the plan. That works, but it needs Don at the keyboard for
the whole build, and the proposals are invisible to the loop, the digest (R9) and the status
board. The Q&A is the only part that needs Don. It can happen as issue comments.

**Shape.** One issue per feature. A new role, the **feature lead**, owns it from design
through delivery. The lead designs with Don in the issue's comments. After Don approves the
plan, it builds the feature in stages and runs the code-side work as a swarm. Each stage is
verified by the existing tester, whose fence doesn't move.

```
feature issue ──(Don: "go")──► 1 design ◄──► Don (comments)
                                 │ plan approved (only Don can set it)
                                 ▼
                           2 decompose into stages (child issues)
                                 ▼
          3 tester writes acceptance cases per stage (R4, before any code)
                                 ▼
          4 lead builds a stage: swarm on a worktree → merge to develop → deploy
                                 ▼
          5 tester verifies the stage over MCP ── bounce ──► back to the lead
                                 ▼  (last stage verified)
          6 lead closes out: docs, plan → docs/proposals/complete/, parent closed by tester
```

**Issues and labels.**
- Label `feature` on the parent. "Proposal" stays a word in the plan, not a label. A
  client-agent request (such as a TESTER_TASK finding that is really a feature) gets the
  same label. The researcher (`idea`) can promote an idea to `feature` in place of its
  `owner:implementer` disposition when the idea is too big for one session.
- New owner **`owner:lead`**. `audit_issue`, the status board and `guard.py`'s
  one-owner rule learn it. New statuses: `status:plan-review` (a plan is posted and waiting
  for Don) and `status:plan-approved`. The guard refuses `status:plan-approved` from any
  agent, the way it refuses `status:verified` from the implementer. That makes approval
  Don's alone, by construction.
- The backlog is `feature` + `owner:don` + `status:needs-approval`, which is how the
  proposals sit today. Don starts one by swapping `owner:don` → `owner:lead`, with an
  optional comment for scope or priority. Don answers the lead's questions by commenting
  and swapping the owner back. Every agent posts as `TICKET_OWNER`, so a new comment can't
  signal a human turn. The label swap is that signal, as it is everywhere else.
- Stages are child issues (R4's parent/child) linked to the parent. Each carries `feature`,
  `stage`, `parent: #NN` in its body, and moves through the ordinary status flow. A child
  issue's implementer role is the lead: a bounce returns it to `owner:lead`, not to
  `owner:implementer`, because the lead holds the plan.

**Phase 1: design (a conversation over several sessions).** `run-features.sh` gives each
`owner:lead` parent in the design phase one fresh session. The session reads the issue, the
thread and the source, then does one of three things:
- asks Don questions, then `owner:don` + `status:needs-info`;
- posts or revises the plan, then `owner:don` + `status:plan-review`;
- or, when the design shows the feature isn't worth building, recommends that and parks it.

Design sessions are read-only against source and use read-only `dw` MCP discovery. That's
the researcher's fence (`RESEARCHER_PERMISSION_FLAGS`) plus `gh issue`, so they take no
driver lock and can run while the loop runs. The plan is **one comment, edited in place**
(`gh issue comment --edit-last`) and headed `<!-- harnest:plan vN -->`. Each revision adds
a short "changed since vN-1" comment, so Don reviews one current document and not a scroll.
The plan names:
- the problem and non-goals;
- the design and the engine, MCP and syntax surface it touches (everything
  `status:needs-approval` exists for is decided here, once);
- the stages, each independently landable on `develop` and small enough for a session;
- per stage, acceptance intent for the tester to turn into cases, the unit tests and docs
  it owes, and its deploy path (server or plugin);
- the risks, and a cost estimate per stage from R1 and `usage:` data.

The existing `docs/proposals/*.md` docs are the starting point. Migration is one issue per
open doc: the body is a summary plus a link to the file at its current commit. `todo.md`'s
tier becomes a `priority:1..3` label, and `audits/` stays as it is, since audits aren't
features.

**Phase 2: decompose.** After Don adds `status:plan-approved`, the lead files the child
issues from the plan (one session, no code) and hands the parent to `owner:tester` with
`status:needs-spec`.

**Phase 3: acceptance specs, which is R4.** The tester reads the approved plan (never the
source) and writes each stage's acceptance cases as `pending: #child` suite cases, plus
`contract/` JSON where they're mechanical (R6). Then it hands back. The tester writes these
cases before any code exists, so the lead's code can't shape them. That keeps a narrow
repro from passing while untested edge cases underneath it fail, which is why features
escalate today.

**Phase 4: build, and where the swarm lives.** One `run-features.sh` session per stage, under
the driver lock, with the implementer's permissions (`auto` mode, `implementer.json`, the R3
guard and hand-off gate). The lead runs on a stage branch and fans code-only work out to
subagents: the stage's code in one or more worktrees where it splits cleanly, unit tests,
docs and skill text, and a proposed regression case per behavior (proposed only; the tester
records it). Then it integrates, runs pytest and ruff, merges to `develop`, deploys once with
the path the plan named, and hands the child to the tester.
- **Code-side fan-out is fine, and verification-side fan-out isn't.** Subagents never deploy
  and never call MCP, so they don't queue on `lem`. One deploy per stage keeps `lem` serial.
  That's why this narrows "Considered and deferred" rather than contradicting it: the
  objection there was parallel sessions queuing behind a deploy, and here nothing parallel
  touches `lem`.
- **The tester is never a subagent of the lead.** A subagent's prompt is written by a parent
  that has read the code, so a lead-dispatched "tester" would verify what the lead told it
  to look for. Independence is about who writes the verifier's instructions, not only about
  its tool fence. Verification stays a driver-launched tester session that reads only the
  issue record and the `pending:` cases.
- **Stages land on `develop`, not a long-lived feature branch.** `lem` can only be on one
  commit, and `check_lem_on_develop` redeploys `develop` whenever it isn't. A feature-branch
  deploy would be wiped by the next cycle, as on 2026-09-21. The plan's "independently
  landable" rule exists for this. A stage that would expose half a feature goes in behind a
  flag or as an unreferenced tool or template until the last stage wires it in.

**Phase 5–6: verify and close.** The tester verifies each child against its repro plus every
`pending: #child` case. Verified means `pending:` comes off those cases (R4's one allowed
edit) and the child closes. A bounce goes back to `owner:lead`, with the existing
`handoff_count` escalation and park thresholds. After the last child closes, the lead runs
one close-out session: it moves the plan into `docs/proposals/complete/<slug>.md` (the format
the four existing `-complete.md` docs use) and updates user-facing docs and `todo.md`. Then
it hands the parent to the tester, which closes it after a smoke pass over the feature's
cases.

**Models: who plans and who builds.** The harness's own evidence points one way. Put the
strong model where a mistake doesn't bounce back, and the cheap model where a mistake is
caught by a check. That's why triage runs on the tester's model and regression runs on
sonnet.
- **Design and the lead itself: Opus 5.5 (`claude-opus-5-5`).** A wrong plan is the most
  expensive error in this whole flow and the least likely to be caught. The tester writes
  cases from the plan, so every stage can pass verification while delivering the wrong
  feature, and Don's approval is the only check. Design is also cheap in tokens: a few
  sessions of reading and one document out. At $4/$20 per MTok against sonnet's $2/$10,
  Opus doubles a line item that's small to begin with.
- **Code-side subagents: sonnet by default, measured before it's trusted.** Execution is
  most of the tokens, and every mistake it makes meets pytest, the R3 gate, the lead's
  integration review and the tester. A well-specified stage is the case sonnet is good at.
  A weak plan makes the executor re-plan, which is the argument *against* the opposite split
  (sonnet plans, Opus executes): the executor pays Opus rates to recover what the plan
  didn't say.
- **Haiku** only for read-only sweeps inside the swarm, such as finding every call site or
  every doc that mentions a tool. Never for code that lands.
- **What's a decision and what's a hypothesis.** "Opus designs" is a decision on the
  asymmetry argument above. "Sonnet builds stages" is a hypothesis. The alternative to
  measure is Opus 5.5 at `low`/`medium` effort for everything: one model, one cache
  namespace, and often as cheap per *completed* task as a cheaper model that takes more
  turns. R1 already has the lever. Run the planned `IMPLEMENTER_MODEL=claude-opus-5-5`
  comparison at `medium` and `low` against the sonnet baseline (53% pass, $0.92/case). If
  Opus-low matches its cost at a higher pass rate, the lead's subagents inherit the lead's
  model and the split goes away.
- Knobs follow the existing pattern: `LEAD_MODEL`/`LEAD_PROVIDER` (default the tester's),
  `LEAD_WORKER_MODEL` (default `sonnet`), `LEAD_EFFORT`, and `LEAD_DESIGN_BUDGET_USD`,
  `LEAD_STAGE_BUDGET_USD`, sized from the first runs.

**Keeping the asymmetry.** The lead is an implementer with a plan: it sees code, never
verifies, and can't approve its own plan. The tester gets one new input, the approved plan,
which is prose written *before* the code and already public on the issue. It still never
sees source. Nothing lets the lead write suite or `contract/` cases.

**Open decisions.**
- Label names: `owner:lead`, `status:plan-review`, `status:plan-approved`, `stage`.
- Whether a design session can run while its issue waits on Don. Probably no: one session
  per Don turn keeps the thread readable and the cost bounded.
- Whether trivial stages (docs only, a one-file skill fix) can skip phase 3 when the plan
  says so, as long as Don approved that line.
- How many features may be in build at once. Start with **one**, because stages from two
  features interleaving on `develop` makes a bounce hard to attribute.
- Whether stage-build sessions run inside `run-loop.sh`'s cycle (simpler locking, and the
  board sees them) or in `run-features.sh` under the shared lock. Design sessions stay
  outside either way.
- R8: this is a large enough driver change to be the one that goes straight to the SDK.

**Done when.** One proposal from `docs/proposals/` goes from issue to closed parent through
this path. Don's only input is issue comments and label swaps, with no engine-surface
escalation after plan approval. Also record, for that feature, the total cost, the bounces
per stage, and Don's comment count. Compare them against the last comparable interactive
proposal (`h3-video-mux-headroom-warning`'s fixes 1–4 shipped in one branch on 2026-09-20).

**First step.** Migrate the open proposal docs to issues (a script, run by hand). Then run
`workspace-folders.md` through phases 1–6 by hand, with an interactive session playing the
lead from the written prompt. `todo.md` rates it low-complexity, and it spans engine, MCP
and UI. Write `LEAD.agent.md` and `run-features.sh` from what that run shows, not before.

---

## Considered and deferred

- **Parallel implementers in worktrees.** The code could be done in parallel, but deploys to
  `lem` and GPU verification can't be, so parallel sessions would queue behind the deploy.
  Revisit if there's ever a second box or a GPU-free test tier.
- **Multi-agent workflows inside the unattended loop.** Fan-out adds cost without solving a
  problem the loop has. Workflows are useful for one-off audits Don runs interactively (like
  the 2026-09-22 suite audit), which R5 makes routine. R11 narrows this: a feature
  stage's code-only work (code, unit tests, docs) can fan out inside one session, because
  none of it touches `lem`. Deploys and verification stay serial.
- **Letting the retro agent apply its own proposals.** Rejected on principle; see
  "Principles every item must keep".
