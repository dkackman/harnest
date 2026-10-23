# Harness Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the enforcement, driver-safety and fleet-accounting defects the 2026-10-23 review found, and cut the regression suite's cost per run by removing navigation turns and giving the curator per-case evidence to tier cases by.

**Architecture:** Six phases, each an independent PR that leaves `tests/run.sh` green: guard hardening, driver safety, fleet correctness, regression cost, prompts, hygiene. Every behavioural change lands with a test in the existing table-driven suites (`tests/test-guard.sh` rows, `tests/test-drivers.sh` boards, `tests/py/test_fleet.py`). New state (per-case results) follows the `regression-perf/` pattern: one append-only JSONL per case, committed by the drivers.

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), jq, Python 3.11+ stdlib only, `ruff`, the existing `tests/lib.sh` assert library (`ok`/`fails`/`eq`/`has`), `tests/fake-gh.py`, `tests/fake-mcp.py`.

**Spec:** `docs/superpowers/specs/2026-10-23-harness-review.md` (sections A–G; task headers cite the section and item they close).

## Global Constraints

- A loop is usually running from this checkout. **Never edit `run-loop.sh`, `providers.sh`, `run-regression.sh` or `run-features.sh` in the checkout a loop was started from**: bash resumes at the old byte offset. Work in a git worktree (`superpowers:using-git-worktrees`) and merge to `main` only after `touch logs/stop-after-cycle` has stopped the loop.
- `tests/run.sh` must pass before every commit. `tests/run.sh lint` covers `bash -n` under bash 3.2, `shellcheck -S error`, `ruff check`, `ruff format --check`, and "every `${KNOB:-}` a driver reads is named in README".
- bash 3.2: no `declare -A`, `mapfile`, `${x,,}`, `source <()`, `|&`; empty arrays as `${a[@]+"${a[@]}"}`; no apostrophe in a comment inside `<( )`.
- Python: stdlib only, `ruff` clean under `ruff.toml`, no new third-party imports.
- `tests/test-regression-py.sh` diffs the bash and Python regression drivers byte for byte on prompts and logs: any change to a chunk prompt or a log line lands in **both** `run-regression.sh` and `harness/drivers/regression.py` in the same task.
- The tester stays source-blind and the implementer never self-verifies. No task widens a consumer allowlist.
- Commit messages: conventional prefix (`fix(guard): …`, `feat(regression): …`), Co-Authored-By trailer as the session's attribution reminder states.

## Review Focus

Inputs the spec implies but no single task's tests fully exercise; each has its test pinned to the owning task below.

1. A `gh` command whose label value is quoted inside a heredoc body (`--body "$(cat <<EOF … it's … EOF)"`): the guard must still deny a Don-only label. (Task 1)
2. A `release` issue whose `gh` lookup fails mid-cycle: the standing task, curator and nightly regression must not run. (Task 10)
3. A fleet lane whose session is cut by `--max-budget-usd` after answering 3 of 8 cases: the other 5 run again somewhere and the run exits non-zero if any case is still unreported. (Tasks 16, 17)
4. A chunk whose case block contains a fenced example with a `### X-F999` heading: the inlined text must not include a phantom case and the result ledger must not record one. (Tasks 21, 22)
5. A triaged issue whose only `triage:` comment was written by a login other than `TICKET_OWNER`: the driver must still treat it as untriaged. (Task 27)

---

## Phase 1 — Guard hardening (spec B.1–B.4, B.6, B.9, B.11, prompts #14)

All in `agent-settings/hooks/guard.py` with rows in `tests/test-guard.sh`. Row syntax: `row <expect> <role> <kind> <transcript> <command>`; `2` = refused, `0` = allowed.

### Task 1: Unbalanced quotes never bypass a label rule

**Files:**
- Modify: `agent-settings/hooks/guard.py:146-167` (`segments`)
- Test: `tests/test-guard.sh`

**Interfaces:**
- Produces: `segments(cmd) -> list[list[str]]` unchanged in signature; on `ValueError` it returns the plain split with every `'` and `"` character removed from each word, and sets module global `UNBALANCED = True`.
- `main()` denies when `UNBALANCED` and any segment's first word is `gh`, with message `unbalanced quote in a gh command: write it on one line with matched quotes.`

- [ ] **Step 1: Add failing rows**

```bash
# unbalanced quotes: the fallback keeps the rules (spec B.1)
row 2 consumer "" $none 'gh issue edit 5 --add-label "status:verified" # it'"'"'s done'
row 2 implementer "" $none 'gh issue edit 5 --remove-label owner:don # don'"'"'t'
row 2 lead "" $none 'gh issue comment 5 --body "$(cat <<EOF
<!-- harnest:release-gate ci abc pass --> it'"'"'s
EOF
)"'
row 0 consumer "" $none 'echo it'"'"'s fine'
```

- [ ] **Step 2: Run `tests/run.sh guard`** — expected: the three `2` rows FAIL (got 0).
- [ ] **Step 3: Implement** — in the `except ValueError` branch strip quote characters per word and set `UNBALANCED`; in `main()` after `segments(cmd)` add the deny.
- [ ] **Step 4: Run `tests/run.sh guard`** — expected: all rows pass.
- [ ] **Step 5: Commit** `fix(guard): deny gh commands with unbalanced quotes instead of dropping their quoting`

### Task 2: Don-only labels are refused on `create` as well as `edit`

**Files:**
- Modify: `agent-settings/hooks/guard.py:792-801` (move the `plan-approved`, `release`, `release-blocker` checks onto the merged `added` list built at `:802-808`); add `status:verified` and `status:fixed-pending-verify` to the create-time check for every role (no issue is ever filed already verified or already handed off).
- Test: `tests/test-guard.sh`

- [ ] **Step 1: Add rows** inside the existing `for r in implementer lead consumer curator reviewer` loop:

```bash
row 2 $r "" $none 'gh issue create --title x --label feature,owner:lead,status:plan-approved'
row 2 $r "" $none 'gh issue create --title x --label release'
row 2 $r "" $none 'gh issue create --title x -l bug,release-blocker'
row 2 $r "" $none 'gh issue create --title x --label status:verified'
row 2 $r "" $none 'gh issue create --title x --label status:fixed-pending-verify'
```

- [ ] **Step 2: Run** — expected FAIL (got 0) for every role.
- [ ] **Step 3: Implement** — compute `added` before the role branches; replace the three `is_gh_issue(words,"edit")`-scoped checks with checks on `added`.
- [ ] **Step 4: Run** — PASS. Existing edit rows still pass.
- [ ] **Step 5: Commit** `fix(guard): approval and release labels are refused on issue create too`

### Task 3: Consumers cannot lift a park; unknown roles fail closed

**Files:**
- Modify: `agent-settings/hooks/guard.py:829-842` (hoist the `owner:don` / `status:needs-approval` removal rules out of the `role in (...)` gate; keep the curator exemption for adding `owner:don`), `:696` (role validation)
- Test: `tests/test-guard.sh`

- [ ] **Step 1: Add rows**

```bash
row 2 consumer "" $none 'gh issue edit 7 --remove-label owner:don --add-label owner:tester'
row 2 consumer "" $none 'gh issue edit 7 --remove-label status:needs-approval'
row 2 curator "" $none 'gh issue edit 7 --remove-label status:needs-approval'
row 2 bogus "" $none 'gh issue list'
row 2 "" "" $none 'gh issue list'
```

- [ ] **Step 2: Run** — expected FAIL (got 0).
- [ ] **Step 3: Implement** — `ROLES = ("implementer","lead","consumer","curator","reviewer","release")`; `deny("unknown guard role %r" % role)` when not in it; move the two removal checks above the role gate.
- [ ] **Step 4: Run** — PASS. Check `grep -rn 'guard_settings\|guard.py' providers.sh agent-settings/*.json` to confirm every real role name is in `ROLES`.
- [ ] **Step 5: Commit** `fix(guard): no role lifts a park; an unknown role is refused`

### Task 4: The hook fails closed on its own errors

**Files:**
- Modify: `agent-settings/hooks/guard.py:885` (`main()` call site)
- Test: `tests/test-guard.sh`

**Interfaces:**
- Produces: `main()` wrapped so any exception other than `SystemExit` prints `Blocked by the harness guard (R3): guard error: <type>: <msg>` to stderr and exits 2.

- [ ] **Step 1: Add a row that feeds malformed JSON**

```bash
rc=0; printf 'not json' | HARNEST_SESSION_KIND= python3 "$guard" implementer >/dev/null 2>&1 || rc=$?
eq "guard: a crash refuses, never passes" 2 "$rc"
```

- [ ] **Step 2: Run** — expected FAIL (got 1).
- [ ] **Step 3: Implement** the wrapper at the bottom of the file.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `fix(guard): exit 2 on any internal error so a crash cannot pass a call`

### Task 5: Labels compare case-insensitively; `gh issue` subcommands are allowlisted for consumers

**Files:**
- Modify: `agent-settings/hooks/guard.py:171-180` (`flag_values` lowercases values), `:695+` (consumer subcommand check)
- Test: `tests/test-guard.sh`

**Interfaces:**
- `CONSUMER_ISSUE_SUBCOMMANDS = ("view","list","create","comment","edit","close","reopen","status")`; a consumer `gh issue <other>` is denied with `gh issue <sub> is not a consumer action (delete, transfer, lock, pin, develop are Don's).`

- [ ] **Step 1: Add rows**

```bash
row 2 consumer "" $none 'gh issue edit 5 --add-label Status:Verified'
row 2 implementer "" $none 'gh issue edit 5 --remove-label Owner:Don'
row 2 consumer "" $none 'gh issue delete 5 --yes'
row 2 consumer "" $none 'gh issue transfer 5 o/other'
row 2 consumer "" $none 'gh issue develop 5'
row 0 consumer "" $none 'gh issue view 5 --json labels'
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `fix(guard): case-insensitive labels; consumers get only the issue verbs they use`

### Task 6: Consumer `git` cannot read another tree; implementer `gh api` writes and wrapper shells are refused

**Files:**
- Modify: `agent-settings/hooks/guard.py` (new `consumer_git_rule(words)` and `implementer_api_rule(words)`; wrapper detection in `main()` for the implementer)
- Test: `tests/test-guard.sh`

**Interfaces:**
- `consumer_git_rule`: deny a consumer `git` with any of `--git-dir`, `--work-tree`, `-C`, `--no-index`.
- `implementer_api_rule`: for roles `implementer`/`lead`, deny `gh api` when the method (`-X`/`--method`) is not GET or any `-f`/`-F`/`--field`/`--raw-field`/`--input` is present, unless the path matches `^repos/[^/]+/[^/]+/issues/\d+/comments$` (the lead's plan PATCH, already in `LEAD_DESIGN_PERMISSION_FLAGS`).
- Wrappers: for the implementer, deny a segment whose command word (after env assignments and the shell keywords `do`, `then`, `else`, `{`, `!`, `time`, `command`, `env`) is `bash`/`sh`/`zsh` with `-c`, `eval`, or `xargs` **when the remaining words contain `gh` or `git push`**.

- [ ] **Step 1: Add rows**

```bash
row 2 consumer "" $none 'git --git-dir=/Users/don/src/dkackman/dw-agent/.git log -p'
row 2 consumer "" $none 'git diff --no-index a b'
row 0 consumer "" $none 'git log --oneline -5'
row 2 implementer "" $none 'gh api -X PATCH repos/o/r/issues/5 -f state=closed'
row 2 implementer "" $none 'gh api repos/o/r/issues/5/labels -f "labels[]=status:verified"'
row 0 implementer "" $none 'gh api repos/o/r/issues/5 --jq .state'
row 0 lead "" $none 'gh api -X PATCH repos/o/r/issues/comments/9 -f body=plan'
row 2 implementer "" $none 'for n in 5 6; do gh issue close $n; done'
row 2 implementer "" $none 'bash -c "gh issue close 5"'
row 2 implementer "" $none 'echo 5 | xargs gh issue close'
row 2 implementer "" $none 'FOO=1 gh issue edit 5 --add-label status:verified'
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS, and `tests/run.sh drivers` still green (the lead's plan PATCH form is used there).
- [ ] **Step 5: Commit** `fix(guard): close the git-dir, gh api and shell-wrapper routes around the label rules`

### Task 7: Update the "Enforced by the harness" lines in the role cores

**Files:**
- Modify: `agents/implementer/core.md`, `agents/tester/core.md`, `agents/regression/core.md`, `agents/lead/core.md`, `agents/curator/core.md:43` (correct: the hook refuses *removing* `owner:don`, not stacking owners, for the curator)
- Test: `tests/run.sh lint`

- [ ] **Step 1:** One line per new rule from Tasks 1–6 in each affected core, matching the existing one-line style. Replace the curator's wrong line.
- [ ] **Step 2:** `tests/run.sh` green. **Step 3: Commit** `docs(prompts): state the new guard rules in each role core`

---

## Phase 2 — Driver safety (spec C.1–C.4, C.6, C.8, C.9)

### Task 8: Plan and arch-review markers come only from `TICKET_OWNER`

**Files:**
- Modify: `providers.sh:1320-1323` (`plan_text`), `run-loop.sh:868-875` (arch range)
- Test: `tests/test-drivers.sh` (scenario §5 spec race already builds a feature board), `tests/fake-gh.py:122` (comment author must be settable)

**Interfaces:**
- `fake-gh.py`: `gh issue comment N --body X` honours env `FAKE_GH_AUTHOR` (default `dkackman`) for the comment's `author.login`.
- `plan_text <n>` jq: `[.comments[] | select(.author.login == $me and (.body | startswith("<!-- harnest:plan")))] | last | .body // empty`.
- Arch range: same author filter, then `[[ "$range" =~ ^[0-9a-f]{7,40}\ [0-9a-f]{7,40}$ ]] || range=""`.

- [ ] **Step 1: Test** in `test-drivers.sh` after §5: a feature parent with an approved plan comment by `dkackman` and a later `<!-- harnest:plan v9 -->` comment by `stranger` (write it with `FAKE_GH_AUTHOR=stranger gh issue comment …` against the board). Run one cycle with `FAKE_CLAUDE_DO` capturing the build prompt to `$T/build-prompt`. Assert:

```bash
has   "plan text: the owner's plan is what the build sees" "<!-- harnest:plan v1 -->" "$(cat "$T/build-prompt")"
fails "plan text: a stranger's marker never reaches a session" grep -q 'harnest:plan v9' "$T/build-prompt"
```

  And for the arch range: a comment `<!-- harnest:arch-review --output=/tmp/x abc -->` by `stranger` on an `arch-review` issue; assert the reviewer prompt says "There is no arch-review marker from the driver".

- [ ] **Step 2: Run `tests/run.sh drivers`** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `fix(drivers): read plan and arch-review markers only from the ticket owner`

### Task 9: One shared MCP-config writer, token out of argv

**Files:**
- Create: function `mcp_config_file <url> <token>` in `providers.sh` (prints the path of a `0600` file under `$LOGS/.mcp.<pid>.json` written with `jq -n --arg`).
- Modify: `run-loop.sh:284`, `run-regression.sh:232`, `run-features.sh:82` to call it; `run-regression.sh:313` passes the token to `contract/run.py` via `DW_TOKEN` in the environment (the Python runner already reads env, per `harness/drivers/regression.py`).
- Test: `tests/test-providers.sh`

- [ ] **Step 1: Test**

```bash
f="$(DW_URL='http://x/"q' DW_TOKEN='t"k' mcp_config_file "http://x/\"q" 't"k')"
eq  "mcp config: valid json with odd characters" 't"k' "$(jq -r '.mcpServers.dw.headers.Authorization' "$f" | sed 's/^Bearer //')"
eq  "mcp config: private" "600" "$(stat -f %Lp "$f")"
```

  In `test-drivers.sh`: `fails "mcp config: no token in argv" grep -q "$DW_TOKEN" "$FAKE_CLAUDE_LOG"`.

- [ ] **Step 2–4:** FAIL, implement, PASS (parity test must still match: the Python driver already passes a path; align the file name).
- [ ] **Step 5: Commit** `fix(drivers): build the MCP config once, in a private file, never in argv`

### Task 10: `release_freeze` reports UNKNOWN and its three callers hold

**Files:**
- Modify: `providers.sh:1371-1375`, `run-loop.sh:808`, `:901`, `:996`
- Test: `tests/test-drivers.sh` (extend §3d, the release-freeze scenario)

**Interfaces:**
- `release_freeze` prints `UNKNOWN` (and returns 0) when `classify_issues` fails; callers treat non-empty output, including `UNKNOWN`, as "held", and log `[<pass>] board unreadable; holding under a possible release freeze`.

- [ ] **Step 1: Test** — board with an open `release` issue; `FAKE_GH_FAIL_AFTER=<n>` (add to `fake-gh.py`: fail every call after the nth) set so the snapshot fails inside `tester_pass`; `TESTER_TASK_EVERY=1`. Assert no `claude -p` with `task` in `$FAKE_CLAUDE_LOG` and the hold line in `loop.out`.
- [ ] **Step 2–4.** **Step 5: Commit** `fix(loop): an unreadable board holds the freeze-gated passes instead of lifting them`

### Task 11: Sessions stop when the driver does

**Files:**
- Modify: `providers.sh:1216-1237` (`run_claude_session`): run the pipeline in the background, `wait "$!"`; new `kill_session_tree` (TERM the pipeline's process group via `set -m` in the subshell, or `pkill -TERM -P`), `trap 'kill_session_tree; exit 143' TERM INT HUP` installed by `acquire_driver_lock` next to the EXIT trap; `acquire_driver_lock:904-917` refuses takeover while `pgrep -f "claude -p" -P <old pid>` finds a child.
- Test: `tests/test-providers.sh`

- [ ] **Step 1: Test** — a fake `claude` that `sleep 30`s; start `run_claude_session` in a background bash with the lock acquired; `kill -TERM` the driver pid; within 5 s assert `pgrep -f 'sleep 30'` is empty and the lock directory is gone.
- [ ] **Step 2–4.** Run `tests/run.sh` whole: the drivers tests exercise the pipeline shape.
- [ ] **Step 5: Commit** `fix(session): TERM stops the driver and its claude child; no takeover over a live child`
- [ ] **Step 6:** Delete memory `stopping-loops-needs-kill.md` after this ships live and is confirmed (not part of the PR).

### Task 12: A rejected rate limit is re-run, and a missing reset never spins

**Files:**
- Modify: `providers.sh:1170-1185` (`sleep_if_rate_limited`: `epoch` 0 or empty → sleep `RATE_LIMIT_FALLBACK_SECS`, default 300; returns 1 when it slept), `:1216-1237` (`run_claude_session`: after a sleep, run the attempt once more), `run-curate.sh:142` and `run-retro.sh:154-158` use `session_ok` instead of `! session_died`; `run-bench.sh:197-204` skips scoring unless `session_ran`.
- README knob table: `RATE_LIMIT_FALLBACK_SECS`.
- Test: `tests/test-providers.sh` (extend the rate-limit test at `:21`)

- [ ] **Step 1: Tests**

```bash
printf 'rate-limit: status=rejected type=x overage=false resets=1970 resets_epoch=0\nusage: turns=1\n' > "$T/rl"
eq "rate limit: a missing reset sleeps the fallback" "sleeping 1s" "$(RATE_LIMIT_FALLBACK_SECS=1 sleep_if_rate_limited "$T/rl" | grep -o 'sleeping 1s')"
```

  And a fake `claude` that emits a rejected `rate_limit_event` on its first call and success on the second: `eq "rate limit: the rejected attempt is run again" 2 "$(grep -c 'claude -p' "$FAKE_CLAUDE_LOG")"` with `RATE_LIMIT_FALLBACK_SECS=0`.

- [ ] **Step 2–4.** **Step 5: Commit** `fix(session): re-run a rate-limited attempt; never treat a missing reset as no wait`

### Task 13: `unpark_pass` retries after a gh failure; mini-ai locks before it deploys

**Files:**
- Modify: `run-loop.sh:975-985` (stamp only when no `gh-failed` entry), `run-loop.sh:225-240` (move `acquire_driver_lock` above the preflight/deploy block)
- Test: `tests/test-drivers.sh` §6c (unpark) and §10 (mini-ai)

- [ ] **Step 1: Tests** — §6c variant with `FAKE_GH_FAIL_AFTER` hitting the unpark edit: after a second cycle with gh healthy, the issue is back to `owner:implementer` and the stamp exists. §10: with the mini-ai lock held by another pid and `curl` health failing, assert no `deploy.sh` call in the ssh log before the "waiting for the lock" line.
- [ ] **Step 2–4.** **Step 5: Commit** `fix(loop): unpark retries after a gh blip; the Mac loop takes its lock before a startup deploy`

### Task 14: One board snapshot per pass

**Files:**
- Modify: `providers.sh:1338-1352` (`issue_snapshot` caches to `$LOGS/.snapshot$TARGET_SUFFIX.json` for `SNAPSHOT_TTL_SECS`, default 20; `classify_issues` reads the cache; `audit_issue` and `claim_issue` call `snapshot_invalidate` after an edit)
- README knob table: `SNAPSHOT_TTL_SECS`.
- Test: `tests/test-drivers.sh`

- [ ] **Step 1: Test** — on the idle-board scenario (§1 with a healthy gh) assert `eq "snapshot: at most 12 list calls in an idle cycle" …` using `grep -c 'issue list' "$FAKE_GH_LOG"` (record the number before the change in the commit message; it is about 64).
- [ ] **Step 2–4.** **Step 5: Commit** `perf(loop): snapshot the board once per pass`

---

## Phase 3 — Fleet correctness (spec D.1–D.5, D.7)

Tests: `tests/py/test_fleet.py` (unit, `unittest`), `tests/test-fleet.sh` (end to end with `tests/fake-mcp.py` and a fake `claude`; the fake already supports a died session and a watchdog kill).

### Task 15: A run that lost cases finishes `failed` and exits 1

**Files:**
- Modify: `harness/drivers/fleet.py:896-902` (`_guard` marks the lane's batch and queue `not run`), `:912` (`finish`: status `failed` if any case outcome is in `("queued","running","next","unreported","not run")`), `:985-994` (`main` returns 1 when `finish` recorded `failed` or any case is `fail`; add `--allow-failures` to return 0 on case failures only).
- Test: `tests/py/test_fleet.py`, `tests/test-fleet.sh`

**Interfaces:**
- `Fleet.finish(status: str) -> str` returns the status it recorded.
- `main(argv) -> int`.

- [ ] **Step 1: Unit tests**

```python
def test_finish_downgrades_done_when_cases_are_unresolved(self):
    f = fleet_with_cases({"S-F001": "pass", "S-F002": "unreported"})
    self.assertEqual(f.finish("done"), "failed")


def test_guard_marks_the_batch_not_run_on_a_lane_crash(self):
    # lane_main raises RuntimeError: every case in its batch and queue ends "not run"
    f = fleet_with_lane_that_raises(RuntimeError("boom"))
    f._guard(f.lane_main, f.lanes[0])
    self.assertEqual({c["outcome"] for c in f.state.data["cases"].values()}, {"not run"})
```

  End to end: in `test-fleet.sh`, a fake `claude` variant that emits a `usage:` line after answering only `S-F001` of a 3-case batch; assert `eq "fleet: exit 1 when a case is left unreported" 1 "$rc"` and `has "fleet: state says failed" '"status": "failed"' "$(cat "$T/h/logs/fleet/state.json")"`.

- [ ] **Step 2–4.** **Step 5: Commit** `fix(fleet): a lane crash or an unanswered case fails the run`

### Task 16: Unanswered cases are re-queued once

**Files:**
- Modify: `harness/drivers/fleet.py:763-790` (`settle`: `o is None and not died and not it.retried` → `it.retried = True; requeue(it, lane, why="had no answer (budget or turns ran out)", same_server=True)`); abort path: after `REGRESSION-ABORT` requeue the batch's unanswered cases to another server too.
- Test: `tests/py/test_fleet.py`, `tests/test-fleet.sh`

- [ ] **Step 1: Tests** — `test_settle_requeues_an_unanswered_case_once`; e2e: the Task 15 fake now gets a second session for `S-F002 S-F003`, and the run exits 0 with all cases `pass`.
- [ ] **Step 2–4.** **Step 5: Commit** `fix(fleet): re-run the cases a finished session never answered`

### Task 17: Workspaces are seeded lazily, per lane and level

**Files:**
- Modify: `harness/drivers/fleet.py:485-496` (`seed` becomes `seed_for(lane, level)`, called from `run_batch` before the first batch of that level on that lane; `Lane.seeded: set[str]`)
- Test: `tests/py/test_fleet.py` (`test_a_stealing_lane_seeds_the_level_it_steals`), `tests/test-fleet.sh` (assert the fake MCP saw `create_workspace` for the second lane's workspace before its first `run_workflow`)

- [ ] **Step 1–5** as above. Commit `fix(fleet): seed a lane's workspace when it first runs a level, stolen cases included`

### Task 18: Per-case time covers one attempt only

**Files:**
- Modify: `harness/drivers/fleet.py:737-754`, `harness/session.py:289+` (`run` returns `attempts: list[tuple[float,float]]` start/end per attempt, or `on_line` sees the `usage:` line and the batch closes `live` there); drop `secs` for a batch whose session died or was retried.
- Test: `tests/py/test_fleet.py` (`test_case_seconds_exclude_retry_pause_and_rate_limit_sleep` with an injected clock)

- [ ] **Step 1–5.** Commit `fix(fleet): a case's seconds stop at its session's result, not after retries`

### Task 19: `contract/run.py` rejects malformed cases and never passes an empty assertion

**Files:**
- Modify: `contract/run.py:87-135` (`check`: unknown key → `MCPError("unknown assertion %r")`), `:141` (case `id` must equal the filename stem), `:198` (`if __name__ == "__main__": sys.exit(main())`), `contract/mcp_client.py:50-55` (wrap `ValueError`, `http.client.HTTPException`, `IncompleteRead` as `MCPError`; per-case timeout `--timeout`, default 600)
- Test: `tests/py/test_contract.py` (new; the fake MCP server from `tests/fake-mcp.py`)

- [ ] **Step 1: Tests** — `test_unknown_assertion_key_fails_the_case`, `test_id_must_match_filename`, `test_import_does_not_run_main`.
- [ ] **Step 2–4.** Add the file to `tests/test-python.sh`'s discovery if it enumerates. **Step 5: Commit** `fix(contract): a case asserts something or fails; ids match filenames`

### Task 20: Atomic ratchet stamps and a locked dashboard index

**Files:**
- Modify: `lib/arch_ratchet.py:204-215` (`check` uses `_read_stamp`/`_write_stamp` like `check_ui`), `dashboard/serve.py:262-279` (`threading.Lock` on `StreamIndex.refresh` and readers)
- Test: `tests/test-ratchet.sh` (a truncated stamp re-measures instead of refusing), `tests/py/test_dashboard.py` (two threads refreshing one index count each session once)

- [ ] **Step 1–5.** Commit `fix: tolerate a truncated ratchet stamp; serialize dashboard index refresh`

---

## Phase 4 — Regression cost (spec A, F.1, F.6)

### Task 21: The chunk prompt carries its cases' text

**Files:**
- Create: `harness/suite.py: case_text(suite_file, ids) -> str` (the Fixtures section only from the header — from `## Fixtures` to the next `## ` — followed by each case's block in the order given; blocks come from `requirements.case_blocks`, which is fence-aware).
- Create: `scripts/case-text.sh <suite-file> <id>...` — a 10-line wrapper `python3 -m harness.suite case-text "$@"` so bash and Python produce identical bytes.
- Modify: `run-regression.sh:361-362` and `harness/drivers/regression.py:87-95` (`chunk_instructions(chunk, text)`): prompt becomes `This is one chunk of a chunked run: this session exercises ONLY these cases, in this order: … The Fixtures section and these cases' full text follow; do not read the suite file for them (read it only if a case points elsewhere in it). Skip the final sweep …` followed by the text. The sweep prompt likewise carries the Fixtures section.
- Modify: `agents/regression/chunk.md` to match (it no longer says "read its header").
- Test: `tests/py/test_suite.py` (new or extend), `tests/test-regression-py.sh` (parity still byte-identical), `tests/test-drivers.sh` §7

- [ ] **Step 1: Tests**

```python
def test_case_text_skips_a_fenced_heading(self):
    text = suite.case_text(SUITE, ["S-F001"])
    self.assertIn("### S-F001", text)
    self.assertNotIn("### S-F999", text)  # S-F001's block holds a fenced example with that heading


def test_case_text_carries_fixtures_only_from_the_header(self):
    self.assertIn("## Fixtures", text)
    self.assertNotIn("## Adding a case", text)
```

  Driver: `has "chunk: the prompt carries the case text" "### S-F002" "$(grep 'S-F002' "$FAKE_CLAUDE_LOG" | head -1)"` (raise the fake's `cut -c1-200` to 4000 for this scenario via `FAKE_CLAUDE_WIDTH`).

- [ ] **Step 2–4.** **Step 5: Commit** `perf(regression): inline the cases' text into each chunk prompt`
- [ ] **Step 6 (measure, not code):** one smoke run before and after; record turns per case and `Read`/`Grep` counts in the PR description (`grep -c '> Read' logs/regression.log` over the run's span).

### Task 22: A per-case results ledger

**Files:**
- Create: `regression-results/README.md` (format below) and the directory (committed like `regression-perf/`; subdirectory per non-primary server).
- Create: `harness/results.py: record(results_dir, server, level, case, outcome, issue, secs, session_label, head, model) -> None` (append one JSON line to `<dir>/<case>.jsonl`; keys in this order: `ts, level, case, outcome, issue, secs, session, head, model, server`).
- Create: `scripts/record-results.sh <results-dir> <level> <session-label> <head> <model> < $LAST_SESSION` — parses `REGRESSION-RESULT:` and `REGRESSION-SKIP:` lines with the same regex as `fleet.RESULT_RE` (move that regex and `_SKIP_RE` into `harness/outcome.py` so there is one copy; `fleet.py`, `dashboard/serve.py` import it) and calls `harness.results.record`.
- Modify: `run-regression.sh` (after every `run_session` in `run_level`), `harness/drivers/regression.py` (same point), `harness/drivers/fleet.py:settle` (same call), `providers.sh:963` `commit_suite_changes` and `harness/suite.py:commit_paths` add `regression-results/` (and `regression-results/<server>/` off-primary); `guard.py` target rules allow writes there for a Mac run as for `regression-perf/<server>/`.
- Test: `tests/py/test_results.py`, `tests/test-drivers.sh` §7, `tests/test-fleet.sh`

- [ ] **Step 1: Tests** — `test_record_appends_in_key_order`; driver: after the two-case regression scenario `eq "results: one line per case" 2 "$(cat "$T/h/regression-results"/*.jsonl | wc -l | tr -d ' ')"` and the commit includes the directory.
- [ ] **Step 2–4.** **Step 5: Commit** `feat(regression): record every case's outcome and seconds in regression-results/`

### Task 23: A ranking report, and the curator reads it

**Files:**
- Create: `scripts/rank-cases.py [--level L] [--since DAYS] [--top N] [--json]` — one row per case: `case, runs, fails, last_fail, median_secs, est_cost` (`est_cost` = runs × `COST_PER_CASE_USD`, default 0.20, from the measured chunk median) with the ranking key `(fails == 0, -median_secs, -runs)`; a `--candidates` mode prints only cases with `runs >= MIN_RUNS` (default 4), `fails == 0`, `median_secs >= MIN_SECS` (default 300).
- Modify: `run-curate.sh:138` adds `$(python3 scripts/rank-cases.py --level "$level" --candidates)` under a "Per-case evidence" heading in the curator's prompt; `agents/curator/audit.md:20-36` says the rank table is the primary evidence and the chunk table is secondary; `README.md` knob table: `COST_PER_CASE_USD`, `MIN_RUNS`, `MIN_SECS`.
- Test: `tests/py/test_rank.py`, `tests/test-drivers.sh` §8 (the curator prompt contains the heading)

- [ ] **Step 1–5.** Commit `feat(curator): rank cases by runs, failures and time from the results ledger`

### Task 24: The perf comparison runs in code

**Files:**
- Create: `scripts/perf-check.py <case> <metric> <condition> <value> [--perf-dir regression-perf] [--baseline X]` — prints `ok`, `regression: <value> is N% over the median of the last 5 (<m5>)` or `… of all (<mall>)`, or `insufficient history (<n> prior)`; exit 0 for ok/insufficient, 3 for regression. Rule exactly as `agents/regression/run-cases.md:35-40`: more than 50% over either median; a `--baseline` is a hard ceiling; fewer than 3 prior entries records only.
- Modify: `agents/regression/run-cases.md` step 3: "run `python3 scripts/perf-check.py …` (it is on your allowlist) and treat its verdict as the comparison; append the reading as before"; `CONSUMER_PERMISSION_FLAGS` in `providers.sh` adds `Bash(python3 scripts/perf-check.py *)` only.
- Test: `tests/py/test_perf_check.py` (`test_fifty_percent_over_recent_median_is_a_regression`, `test_creep_is_caught_by_the_all_time_median`, `test_two_prior_entries_record_only`), `tests/test-guard.sh` row allowing the call for `consumer`.

- [ ] **Step 1–5.** Commit `feat(regression): compute the perf regression rule instead of asking the agent to`

### Task 25: Missing requirements entries are visible, not undispatchable

**Files:**
- Modify: `harness/drivers/fleet.py` (`plan`: cases absent from `regression-requirements.json` are listed in one `[fleet] N case(s) have no requirements entry: …; dispatched as heavy on the primary` line and placed in the primary's queue with `load: heavy`), `run-digest.sh` (one line: count of cases missing an entry, with the regen command `python3 -m harness.drivers.requirements`).
- Test: `tests/test-fleet.sh` (remove one case from the generated requirements; assert the line and that the case still runs)

- [ ] **Step 1–5.** Commit `fix(fleet): a case without a requirements entry still runs, on the primary`

---

## Phase 5 — Prompts (spec E.1–E.4, E.6, E.7)

### Task 26: Triage sees only untriaged issues, and brief context shows the last owner comment

**Files:**
- Modify: `run-loop.sh:535-536` (`triaged` excludes any issue whose comments contain a line starting `triage:` by `TICKET_OWNER`; use the snapshot's `comments` field already fetched by `issue_snapshot`, exposed as `triaged_issue <n>` in `providers.sh`), `providers.sh:1296` (`brief` mode: `comment_n=1`), `agents/implementer/triage.md:23` ("Your prompt lists only issues with no `triage:` comment; leave exactly one"), `agents/implementer/fix.md:6,15` ("the latest `triage:` comment governs").
- Test: `tests/test-drivers.sh` §3a

- [ ] **Step 1: Test** — board with #12 carrying a `triage: work` comment by `dkackman`, #13 with a `triage: work` comment by `stranger` (`FAKE_GH_AUTHOR`), #14 with none; assert the triage prompt names `#13` and `#14` and not `#12`.
- [ ] **Step 2–4.** **Step 5: Commit** `fix(loop): triage only what has no owner triage comment`

### Task 27: Verify sessions load the MCP house rules

**Files:**
- Create: `agents/tester/mcp-rules.md` — the durable rules moved out of `qa-bible.md` "House rules" (lines 91–146): `wait_seconds` per family, no cancel under 15 min silence, `workspace=` on every call, `list_models` summary form, `get_gallery_metadata` only on video, `get_output_image` refuses `asset:`. Target 2 KB.
- Modify: `providers.sh:role_prompt` (`tester:verify` → `core verify cases mcp-rules`, `tester:spec`, `tester:task` likewise), `agents/tester/standing-task.md:88` (the bible keeps episode state only; cap 12 KB), `run-loop.sh:tester_pass` (after a task session: `[audit] WARNING: qa-bible.md is N KB, over its 12 KB cap` when `wc -c` > 12288), `qa-bible.md` (delete the moved House rules; this is the one agent-owned file a human edits, say so in the commit).
- Test: `tests/test-drivers.sh` (the verify prompt file contains "wait_seconds"; the audit line appears when a 13 KB bible is planted)

- [ ] **Step 1–5.** Commit `feat(tester): house rules are a prompt fragment every MCP-using kind loads`

### Task 28: The lead's design session posts a draft plan after the sweep

**Files:**
- Modify: `agents/lead/design.md` (new step after the Explore sweep: post `<!-- harnest:plan v1 -->` with status `draft: sweep done`, then PATCH it in place as steps 3–5 complete; `core.md:118` points at it), `lib/classify.jq` (a plan comment whose first body line contains `draft:` does not count as a plan for `plan-review` routing — add a fixture board to `tests/classify-cases.json`)
- Test: `tests/test-classify.sh` fixture: `design-draft-plan` → still `lead:design`.

- [ ] **Step 1–5.** Commit `feat(lead): a design session leaves a draft plan comment it can resume from`

### Task 29: Hand-offs describe behaviour; verifies design their own repro first

**Files:**
- Modify: `agents/implementer/fix.md:97-117` ("Hand off": what a consumer observes — tool, input, old vs new response — and the commit hash; a proposed case states the behaviour to lock in, not the call; after deploy confirm health only, never re-run the repro over MCP — move the sentence from `agents/implementer/target.md:21-23`), `agents/tester/verify.md:9-11` (step 2: design the repro from the issue's `expected:` first; the hand-off's suggested call runs last, as one adjacent case).
- Test: `tests/run.sh lint`; bench the implementer change (`run-bench.sh`, label `handoff-wording@<sha>`, compare to the latest baseline in `bench/results/results.jsonl` with `--summary`).

- [ ] **Step 1–3.** Commit `docs(prompts): hand-offs describe observable behaviour; the tester verifies independently`

### Task 30: Settle the three contradictions

**Files:**
- Modify: `CLAUDE.md` Ticket protocol + `agents/implementer/core.md:120-123` + `agents/regression/core.md:63-64` + `agents/tester/core.md:54-56` → one rule: "a regression against a verified issue is a **new** issue labeled `regression` that references it; nobody reopens"; `agents/tester/closures.md:15` → count wontfixes per problem (an issue closed `wontfix` as "restates #NN" inherits #NN's count); `agents/implementer/core.md` Dispositions → `status:needs-info` goes to `owner:tester` for a repro question and to `owner:don` for a decision or an environment failure; `agents/tester/spec.md` step 1 → Grep `pending: #<stage>` before writing; one line in each core for `gh` failing twice (stop; the driver re-runs you) and for a job that never finishes (two `wait_for_job` caps with no new event → `cancel_job`, file with the events).
- Test: `tests/run.sh lint`.

- [ ] **Step 1–3.** Commit `docs(prompts): one reopen rule, countable wontfix, needs-info routing, cut-off safe spec`

---

## Phase 6 — Hygiene and measurement (spec F.3, F.5, F.7, G)

### Task 31: `fake-gh.py` honours `--limit`, `--search` dates and comment authors

**Files:**
- Modify: `tests/fake-gh.py:93-99` (`--limit N` truncates; `--search` understands `closed:>=DATE`, `created:>=DATE`, `in:title <word>`, `-author:`; comments carry `createdAt` = now and `author.login` from `FAKE_GH_AUTHOR`).
- Test: `tests/test-drivers.sh` — a 3-issue board with `--limit 2` in a driver path (`pending_closures` reads 200; plant 201 closed issues programmatically and assert the 201st is not seen, documenting the window); `issue_context` withholding: a `stranger` comment on a fix issue is a one-line stub in the fix prompt (`has "issue context: a stranger's comment is a stub" "comment by @stranger withheld" …`).

- [ ] **Step 1–5.** Commit `test(fake-gh): windows, search dates and comment authors behave like gh`

### Task 32: Audit warnings only where a human should look

**Files:**
- Modify: `providers.sh:commit_suite_changes` (when the commit message starts `curator:` or the session kind is `curator:review`, log `[audit] curator removed lines …` at info level, not `WARNING`), `run-loop.sh` (the tester's "added case" commit still warns on removal).
- Test: `tests/test-drivers.sh` §3f (a curator ruling that deletes lines produces no `[audit] WARNING`; a tester commit that deletes lines still does).

- [ ] **Step 1–5.** Commit `fix(audit): approved curator deletions are not warnings`

### Task 33: Retro and digest run on a schedule

**Files:**
- Create: `scripts/install-schedules.sh` — writes `~/Library/LaunchAgents/com.harnest.retro.plist` (weekly, Monday 06:00) and `com.harnest.digest.plist` (daily 07:00) that `cd` to this checkout and run `./run-retro.sh` / `./run-digest.sh`; `--uninstall` removes them; both skip when `logs/.driver.lock` is absent (no loop → nothing to retro).
- Modify: `README.md` "Running" (one paragraph), `run-retro.sh:154-158` already fixed in Task 12.
- Test: `tests/test-setup.sh` (the plists parse: `plutil -lint`; `--uninstall` leaves nothing).

- [ ] **Step 1–5.** Commit `feat(ops): launchd schedules for the retro and the digest`

### Task 34: Documentation matches the code

**Files:**
- Modify: `HARNESS-ROADMAP.md` status table (R4 built via the tester `spec` kind; R6 "2 cases script-run, `S-F036.json` orphaned"; R8 built: `harness/`, fleet, parity; R13 the fleet and `targets/dw/profile.toml`; baseline block dated and superseded by the spec's numbers), `CLAUDE.md` "Tests" (all 16 files, one line each), the role-prompt bullet (tester kinds include `spec`; regression `whole` = `core run-cases sweep`, no `whole.md`), `README.md:670` (`TESTER_BUDGET_USD` row: "8 on a non-lem target"), `tests/test-lint.sh:33-40` (also scan `scripts/*.sh`, `lib/*.py`, `harness/**/*.py` for `os.environ.get("…")`/`${…:-}` knobs: `HARNEST_PROFILE`, `HARNEST_ARCH_TOOLS`, `ADVISORY_PACKAGE`, `DW_PORT` get README rows).
- Test: `tests/run.sh lint`.

- [ ] **Step 1–3.** Commit `docs: roadmap status, test inventory and knob table match the tree`

### Task 35: Measure (no code)

- [ ] Re-run the bench at the current implementer prompt: `BENCH_LABEL=post-hardening@<sha> ./run-bench.sh` and `./run-bench.sh --summary`; paste the table into the PR for Phase 5.
- [ ] One `smoke` run before Task 21 and one after; record `turns/case`, `$ / case`, `Read+Grep` count in `regression-results/README.md` under "Why the prompt carries the text".
- [ ] After four `complete` runs with the ledger: `python3 scripts/rank-cases.py --level complete --candidates`, and file one `suite` + `status:needs-approval` issue on `dkackman/harnest` per tier move, as the curator would.

---

## Self-review notes

- **Spec coverage.** A (regression cost): Tasks 21–25, 35. B (guard): 1–7. C (drivers): 8–14. D (Python): 15–20. E (prompts): 26–30. F (tests/docs/suites): 31, 34, and the perf rule in 24, requirements in 25, bench in 35. G (operations): 32, 33. Not planned on purpose: `providers.sh` split into `lib/*.sh` (structural, no behaviour; do it when the Python port replaces those pieces), path-scoping `Read`/`Write` for consumers (needs a hook on non-Bash tools and a source-free tester tree; a separate design), driver-side issue dedupe (needs a similarity rule worth designing first; the results ledger will show whether the duplicate rate justifies it).
- **Interfaces used across tasks.** `outcome.RESULT_RE`/`SKIP_RE` (Task 22) are what Tasks 15–16's `settle` and Task 23's ranker read. `harness.suite.case_text` (Task 21) is what both drivers and the sweep prompt call. `FAKE_GH_AUTHOR` and `FAKE_GH_FAIL_AFTER` (Tasks 8, 10) are reused by Tasks 13, 26, 31.
- **Order.** Phases 1–3 are independent of each other; Phase 4 depends on nothing but should follow Phase 3 so the fleet records results through a `settle` that no longer loses cases; Phase 5 Task 29 should be benched after Task 35's baseline run; Phase 6 last.
