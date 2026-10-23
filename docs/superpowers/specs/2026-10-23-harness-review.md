# Harnest quality review, 2026-10-23

Read-only review of the checkout at `1779f90` while the lem loop was running. `tests/run.sh`
passed (16 files, every assertion green). Five parallel reviewers covered the bash drivers,
the guard and classify layer, the Python port, the role prompts, and tests/docs/suite data.
Every finding marked **verified** was re-read in the source by the coordinating session.

## Numbers that frame the review

| Measure | Value |
|---|---|
| Sessions logged in `loop.log` | 2,817, $3,086 total |
| Cost by role | tester $990 (926 sessions), regression $829 (477), implementer $581 (533), lead $517 (401) |
| Regression sessions ≥ 80 turns | 157 of 477 (implementer 40 of 533, tester 36 of 926) |
| Last `complete` fleet run (2026-10-18) | 460 cases, 116 sessions, $95.96, 1.9 h to kill, 72 still queued |
| `complete` level, single server, by run | $21–54, 100–213 min |
| `smoke` level, by run | $7–9, 18–27 min (steady) |
| Regression-filed dw issues, last 45 days | 178: 62 closed verified (11 security), 55 duplicate, 22 wontfix, 28 closed unlabeled |
| Suite size | complete 980 KB / 492 cases (73 KB on 09-15); smoke 171 KB / 82; model-specific 352 KB / 135; security 100 KB / 52 |
| `[audit] WARNING` lines | 111, 93 of them "removed lines from a suite" |
| Open boards | dw: 2 open issues; harnest: 2 suite requests |
| Last retro / digest / bench run | 2026-09-23 / 2026-09-24 / 2026-09-23 |

## A. Regression cost and duration (your focus)

### Where a chunk session's turns go (last complete run, lem lanes)

| Tool | Calls |
|---|---|
| `run_workflow` | 385 |
| `delete_output` | 318 |
| `validate_workflow` | 304 |
| `Read` (642 of them on the suite file itself) | 292 |
| `get_gallery_metadata` | 219 |
| `Grep` | 144 |
| `ToolSearch` | 104 |

About one turn in five is navigation: the chunk prompt says "read the header, then only
those cases' sections" of a 1 MB file, so the agent greps for `^### C-F…` and pages by
offset. The driver already knows the case IDs; it can extract the header plus the N case
blocks (mean block 1,956 B, header 17.6 KB) and put them in the user prompt. That removes
roughly 250 turns per complete run, plus the context those reads occupy on every later turn.

### What is missing to do a value-vs-cost cull

1. **No per-case pass/fail history before 2026-10-18.** Older runs do not emit
   `REGRESSION-RESULT` lines; only the fleet writes `logs/fleet/runs/*.json`. Two runs exist.
2. **Per-case timing has never run live.** Both fleet run files predate PR #135 (merged 2026-10-19), so the lane
   weighting has nothing to weigh with yet (Python review, finding 2: when it does run, `secs`
   spans retries and rate-limit sleeps).
3. **The perf comparison is a prompt instruction, not code.** No module computes the
   50%-over-median rule; 639 cases declare `metrics:` but 43 have a perf file; no reading
   carries a baseline.
4. **The curator's evidence is per-chunk cost from `loop.log`,** not per case, so its
   culling proposals cannot rank cases by (cost × runs) / (failures found).

### Recommendations, in order of payoff

1. **Inline the case text into the chunk prompt** (driver change in `run-regression.sh` and
   `harness/drivers/regression.py`). Cheapest, measurable: compare turns per case before
   and after on one smoke run.
2. **Record `REGRESSION-RESULT` and duration per case into a durable per-case ledger** (one
   JSONL per case next to `regression-perf/`, or one file per run). Then the curator and a
   new `--rank` report can list: runs, fails, median duration, last fail date.
3. **Tier `complete` by evidence, not by hand.** Once (2) has four or five runs, move cases
   with ≥ N runs, zero failures, and median duration over X minutes to a `weekly` tier or to
   `model-specific`. Keep anything that has failed in the last 60 days in the regular run.
4. **Graduate mechanical cases to `contract/`.** Only 2 of 761 cases run by script
   (roadmap R6). Cases whose expected result is a schema error, a validation refusal, or a
   field equality cost $0 as a script and about $0.20 as an agent turn set. A triage pass
   over the complete suite for "runnable without a GPU" would likely move 100+ cases.
5. **Cut the per-chunk fixed cost.** The complete suite header is 17.6 KB (≈4.4k tokens)
   on every chunk; most of it is "Adding a case"/"Removing a case" prose the chunk never
   uses. Load the Fixtures section only. `target.md` adds 6 KB on the Mac lanes.
6. **Stop paying for the failure-noise tail.** 105 of 178 regression issues were
   duplicate/wontfix/unlabeled. The regression agent's dedupe search runs against a fake
   that matches everything in tests, so its real precision is unmeasured. A driver-side
   dedupe (title similarity against open+closed issues in the last 60 days) before
   `gh issue create` is cheap and testable.
7. **Make the parallel run finish.** Fleet findings 1, 3 and 4 below explain why a run
   ends "done, exit 0" with cases unreported or lost.

## B. Enforcement layer (guard.py, permissions, classify)

All four of the top items are **verified**.

1. **Unbalanced-quote fallback drops quoting** (`guard.py:163`). `gh issue edit 5
   --add-label "status:verified" # it's done` is split on whitespace with the quotes kept, so
   no label rule matches. Every label rule, for every role, is reachable this way. Fix: on
   `ValueError`, deny any command mentioning `gh`, or strip quotes in the fallback.
2. **`status:plan-approved`, `release`, `release-blocker` are checked on `edit` only**
   (`guard.py:792-801`). `gh issue create --label status:plan-approved …` passes for every
   role, and a pre-approved feature classifies straight to decompose. Fix: apply the checks
   to the merged `added` set that `arch-approved` already uses.
3. **The tester and regression agent can lift an `owner:don` park** (`guard.py:829-842`):
   the removal rule sits inside `if role in ("implementer","lead","reviewer")`. CLAUDE.md
   states the rule without a role limit. Fix: hoist it, exempting only the curator path.
4. **No top-level try/except in `guard.py main()`.** An uncaught exception exits 1, which
   Claude Code treats as non-blocking. `handoff_gate` has several unguarded calls (missing
   venv python, `git worktree add`, `os.symlink`). Fix: wrap `main()` and exit 2.
5. Command position is literal: `for n in …; do gh issue close $n; done`, `FOO=1 gh …`,
   `bash -c`, `eval`, `xargs gh` are invisible to the hook for the implementer.
6. `gh api` with a write method is unguarded except the PR merge base; `gh pr merge` into
   master is allowed.
7. `Read`/`Grep`/`Write` are unscoped for consumers; the tester's cwd is this repo, so it can
   write `guard.py` or the live drivers, and `gh issue comment --body-file` publishes any
   readable file. Consumer `git log/show/diff` allow `--git-dir`/`--no-index`.
8. `freeze.py` fails open on an unreadable `origin/develop` (returns "not frozen"), contrary
   to the fail-closed claim; the hand-off path is rescued by `arch_ratchet.active()`.
9. Label comparisons are case-sensitive; GitHub's are not.
10. `classify.jq`: a `target:` claim never expires (a down Mac loop holds its issues at
    `wait` forever, unflagged); a zero-stage plan waits forever; `def has($l)` shadows the
    jq builtin.
11. Unknown `HARNEST_ROLE` applies only the universal rules (fails open on a typo).

Overall: a good guard against slips, a poor guard against deliberate routing-around. Items
1-4 are small diffs and close most of the gap.

## C. Drivers (bash)

1. **Plan and arch-review markers are read from any commenter** (`providers.sh:1320`,
   `run-loop.sh:868`). **Verified.** `issue_context` withholds non-owner comments, but
   `plan_text` and the arch range do not filter by author. A third party on the public repo
   can comment `<!-- harnest:plan v9 -->` and that text becomes the build session's "approved
   plan", run under auto mode with push and ssh. The arch range also goes unvalidated into
   `git log`. Fix: `select(.author.login==$me)` in both; regex-validate the range.
2. **SIGTERM ignored mid-session**: the only trap is `rm -rf lock` on EXIT; the session is a
   foreground pipeline; nothing tears down `claude -p`. Fix: run the pipeline in the
   background with `wait`, trap TERM/INT/HUP to kill the process group, and refuse stale-lock
   takeover while a `claude` child of the old owner is alive. (This also explains the memory
   note "stopping loops needs KILL".)
3. **`release_freeze` fails open** (`providers.sh:1371`). **Verified.** A `gh` blip during a
   freeze reads as "no freeze", and the standing task, curator and nightly regression then
   run. Queues fail safe; these three callers do not. Fix: print `UNKNOWN` on failure and
   skip the pass.
4. Rate-limited or budget-cut sessions count as handled: curate stamps the level for 7 days,
   retro advances its window, a rejected regression chunk is not re-run, bench appends a
   `fail` row. A missing `resetsAt` yields `resets_epoch=0` and no sleep.
5. ~75 `gh` calls per idle cycle: `classify_issues` rebuilds the 4-call snapshot about 16
   times a cycle. Snapshot once per pass.
6. Bearer token in argv via `--mcp-config` JSON (three drivers) and `contract/run.py --token`.
7. Lock stale-check is `kill -0` on a pid; after a reboot the pid can be live and unrelated.
   Takeover has a narrow two-holder race.
8. `unpark_pass` stamps itself done even when a `gh` edit failed, so a parked issue stays
   parked. mini-ai's startup deploy runs before the lock. A release-review blocker that
   matches an existing issue never gets `release-blocker`.
9. `run-features.sh` state files lack `$TARGET_SUFFIX`; `resolved_model` reads lem's jsonl on
   the Mac loop, so Mac suite commits can carry the wrong trailer.
10. Structure: `providers.sh` (1,598 lines) is five libraries; `run-loop.sh` repeats the
    queue → still_ready → run_agent shape eight times; MCP config JSON is built three times.

## D. Python port (harness/, contract/)

1. **A crashed lane is reported as a clean run** (`fleet.py:896`, `main` returns 0).
   **Verified.** `_guard` swallows the exception, cases stay `queued`/`running`, and
   `finish("done")` runs. `main` also returns 0 when cases fail or are unreported.
2. Per-case `secs` spans retries and rate-limit sleeps; the live run recorded 0 s anyway.
3. Cases a finished session never answered are marked `unreported` and never requeued;
   only a died session is retried. A budget cut-off on an 8-case chunk loses the rest.
4. Stolen or requeued cases can run in an unseeded workspace.
5. `contract/run.py`: an unknown assertion key is a pass; a case whose filename stem differs
   from its inner `id` is dropped from both agent and script; no `__main__` guard; no timeout.
6. Dashboard `StreamIndex.refresh` races under the threading server (double-counted costs).
7. `arch_ratchet.check` reads the stamp non-atomically; a truncated stamp refuses every
   hand-off with a traceback until deleted (`check_ui` already has the fix).
8. The parity test covers the happy path only; Python already diverges (watchdog, killpg,
   token via env, minid target).
9. The REGRESSION-* protocol is parsed by four separate regex sets.

Verdict: the planning and parsing layers are well tested; the runtime orchestration is where
the first live run found bugs and where none of the unit tests reach. Finish the port, but
fix 1-4 and add fault-injection variants to `test-fleet.sh` first.

## E. Role prompts

1. **Triage re-dispositions the same issues every cycle** (`run-loop.sh:536`,
   `issue_context … brief` passes zero comments). **Verified:** 12 of 65 triaged issues carry
   2-4 `triage:` comments. Fix: exclude issues that already have one, or include the last
   comment in brief mode.
2. **Verify sessions never see the house rules.** They live in `qa-bible.md`, loaded only by
   the task kind. A verify of #978 pulled a 32 KB `list_models {}` result. Verifies are the
   tester's expensive sessions (feature-stage verifies at 83-99 turns, $1.8-3.1). Fix: a
   small prompt-owned `mcp-rules.md` loaded by verify/spec/task.
3. **The lead's design session posts nothing until step 6**; its 1,000 s, $3-4 sessions have
   no resumable trail. Post a draft plan comment after the sweep and PATCH it in place.
4. Hand-off comments carry diff summaries and "the exact call to make", and `verify.md` tells
   the tester to run that call. Verification becomes replay. Describe what a consumer
   observes; have the tester design its own repro first.
5. "Second wontfix is final" is uncountable across a restated issue; three documents give
   three answers on who reopens a regressed verified issue; the curator core cites a guard
   rule that does not apply to it.
6. `qa-bible.md` is 15.1 KB against its 12 KB cap, and nothing enforces the cap.
7. Spec sessions cut off mid-way can write duplicate `pending:` cases.
8. Missing guidance: `gh` failing mid-session, a job that never finishes, `breaking-change`
   during the standing task, labels changed under a session.
9. Boilerplate repeated across seven cores (~1.5 KB per consumer session).

Per-kind assembled prompt sizes run 3-17 KB (0.8-4.3k tokens); turn-1 context is 36-56k, so
prompt bytes are not the lever. Turns × context in tester verifies is.

## F. Tests, docs, suite data

1. Perf regression rule not implemented (see A).
2. The add-only suite rule is breached in the normal path: 88 "removed lines" warnings,
   many on ordinary `tester added case` commits, repaired by nothing.
3. `fake-gh.py` ignores `--limit` and most of `--search`, so window-overflow and dedupe bugs
   pass silently; every fake comment is by `dkackman`, so the withholding of other logins'
   comments is never exercised in a driver run.
4. Untested live-cost paths: rate-limit sleep, bounce escalation to `TESTER_MODEL`,
   `IMPLEMENTER_PARK_AFTER`, lem's `check_target_on_develop`, closures cadence, every
   positive `audit_issue` warning, `run-digest.sh`, `run-bench.sh`, script-case dispatch,
   the `CASES_PER_SESSION` default.
5. `HARNESS-ROADMAP.md` is three weeks stale: R4, R6, R8, R13 are built but listed as
   todo/planned; the baseline says "0 audit warnings". CLAUDE.md's Tests section names 5 of
   16 test files; `agents/regression/whole.md` does not exist (whole = core+run-cases+sweep).
6. `regression-requirements.json` is 42 cases behind the suites; the fleet cannot dispatch
   those cases.
7. The bench has not run since the day it was built (2026-09-23); two implementer changes
   since were not benched. With 17 cases a 1-case swing is 6 points.
8. Suites are structurally clean: no duplicate IDs, every case has `cleanup:`, all required
   sections present. `S-F036.json` exists in `contract/` but the case lacks `runner: script`.

## G. Operational observations

- Retro and digest (R7, R9) have not run since late September. The self-improvement loop is
  built but idle; the "Needs you" dashboard card is the only live digest.
- The dw board is nearly empty (2 open). Throughput is not the bottleneck now; the cost of
  the regression floor and the lead's feature sessions is.
- 93 of 111 audit warnings are the curator's own approved deletions. The signal is buried.
  Either suppress the warning for commits on a curator ruling, or key it to the session.

## Suggested order

1. Guard: quote fallback, create-label checks, consumer park lift, top-level exit 2.
2. Drivers: author filter on plan/arch markers; `release_freeze` UNKNOWN; signal teardown.
3. Fleet: non-zero exit on unreported/queued; requeue unanswered cases; seed lazily.
4. Regression cost: inline case text; per-case result ledger; then evidence-based tiering
   and script graduation.
5. Prompts: triage dedupe; house rules into verify; lead draft-plan comment.
6. Hygiene: roadmap status table, requirements regen, bench rerun, retro/digest on cron.
