# Loop Scheduler (R17, phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `run-loop.sh`'s serial cycle with a Python scheduler that runs server-free sessions alongside GPU sessions, owns every deploy, and writes a `state.json` the dashboard shows. Phase 1 has one GPU slot per server.

**Architecture:**
- A pure scheduler core (`harness/scheduler.py`: resources, work items, priority, deploy gate) is driven by an event loop (`harness/drivers/loop.py`).
- The loop snapshots the board through the existing bash `classify_issues`. It runs each work item as a child process: `lib/run-item.sh <pass> <issue>`, which sources `run-loop.sh` in a new item mode and calls the existing pass function with `ONLY_ISSUES=<n>`.
- So the per-pass logic (prompts, claims, audit, suite commit) is reused unchanged. Porting it to Python is a later plan (see "Deviation from the spec").
- Deploys, locks, health polling and `state.json` are Python.

**Tech Stack:**
- Python 3 stdlib only (`harness/`, unittest under `tests/py`);
- bash 3.2 (`/bin/bash` on macOS);
- jq, `gh`, `claude -p`;
- offline tests via `tests/fake-gh.py` and stub `ssh`/`claude`/`curl`.

**Spec:** `docs/superpowers/specs/2026-11-18-loop-scheduler-design.md`

## Deviation from the spec (Don to confirm)

The spec's "What gets ported" lists the `run-loop.sh` passes and `providers.sh` helpers to
port to Python. This plan does **phase 1a** instead:
- The Python scheduler calls the existing bash passes one item at a time (`lib/run-item.sh`).
- The GPU win, the deploy move, the dashboard and the measurement all land without
  re-implementing about 3k lines of tested pass logic first.
- Porting each pass to Python (**phase 1b**) is a follow-up plan. It swaps `run-item.sh`
  calls for Python one pass at a time, behind the same `Runner` interface (Task 6).

Everything else in the spec is in this plan except phase 2 (two GPU slots, regression
backfill), which is a separate plan.

## Global Constraints

- `lib/classify.jq` stays the state machine. The scheduler decides when and where, never who.
- Keep the `owner:*` / `status:*` / `target:*` label prefixes. An open issue has exactly one `owner:*`.
- No state survives between sessions except GitHub Issues and the suite files. `state.json` is rebuilt on restart.
- Suite cases are add-only. The removed-lines audit (`commit_suite_changes`) runs on every suite commit.
- No `--dangerously-skip-permissions`.
- Every knob read (`${KNOB:-}`, `environ.get("KNOB")`) is named in `README.md` (`tests/test-lint.sh`).
- Bash 3.2: no `source <(…)`, no apostrophe in a comment inside `<( )`.
- The tester stays on `claude-opus-5-5` by exact id. The tester never reads source.
- Run `tests/run.sh` before every commit that touches a driver, `providers.sh`, `lib/classify.jq` or the guard.
- Python stays stdlib only.
- Never edit `run-loop.sh` or `providers.sh` while a bash loop is live (`pgrep -fl run-loop`). Stop it first, with `kill -TERM`.
- New knobs (README): `LOOP_FREE_SLOTS` (3), `LOOP_POLL_SECS` (60), `LOOP_HEALTH_SECS` (30), `DEPLOY_RETRY_SECS` (300), `TESTER_TASK_GAP_SECS` (from the baseline), `MAX_SESSIONS` (0 = unlimited). Profile field `loop_gpu_slots` (default 1). `TESTER_TASK_EVERY` and `MAX_CYCLES` are retired for the new driver.
- Priority, highest first: `reviewer:arch`, `tester:verify`, `tester:answer`, `implementer:fix`, `lead:build`, `lead:closeout`, `tester:spec`, `lead:decompose`, `lead:design`, `reviewer:docs`, `tester:handoff`, `curator`, `tester:closures`, `tester:task`.
- One `free` slot is reserved for `reviewer:arch`, `implementer:fix`, `lead:build`.

## Review Focus

1. **A board read fails mid-run** (`gh` outage). Expect: nothing new dispatches, running sessions finish, `state.json` says `board: unreadable`, nothing gets marked closed. Test in Task 7 (`loop: gh outage`).
2. **A session crashes or is killed** (non-zero exit, or no `usage:` line). Expect: its slot frees, the item is re-offered at the next snapshot, and it isn't retried hot in a loop (it waits for the next board change or poll). Test in Task 1 (`test_failed_item_waits_for_next_snapshot`).
3. **The loop is restarted while sessions were running** (SIGKILL, reboot). Expect: stale `.driver.lock*` taken over as today, `state.json` rewritten with the new pid, the dashboard shows "stalled", not "running", in between. Tests in Task 8 (stale fixture) and Task 7 (`loop: stale lock`).
4. **Develop moves while a verify waits on a deploy that's draining.** Expect: one deploy of the newest develop, not two. Test in Task 2 (`test_deploy_takes_newest_develop_once`).
5. **Both servers offer the same unclaimed item.** Expect: it is dispatched once, on the first server with a free resource, and the claim label goes on before the session. Test in Task 1 (`test_item_dispatched_once_across_servers`).

---

### Task 0: Baseline measurement (before anything changes)

**Files:**
- Create: `scripts/gpu-busy.py`
- Test: `tests/py/test_gpu_busy.py`, fixture `tests/fixtures/gpu-busy/loop.log`

**Interfaces:**
- Produces: `scripts/gpu-busy.py [--days 14] [--log logs/loop.log] [--repo dkackman/diffusers-workflow] [--json]`. It prints per day:
  - `gpu_slot_busy_pct`, tester plus regression session seconds over wall seconds;
  - `standing_task_interval_secs`, the mean gap between `tester:task` headers;
  - `closes`, dw issues closed `completed` that day (`gh issue list --state closed --search "closed:>=YYYY-MM-DD" --json number,closedAt,stateReason`);
  - `cost`, the sum of `usage:` cost.
  It also prints the window totals, including `cost_per_close`.
- Uses `dashboard/serve.py`'s `_clock_epoch` day-rollover rule, copied as a 6-line helper. The log has HH:MM:SS only: a time earlier than the previous line's means the next day. The anchor is the log file's mtime as the last line's date.

- [ ] **Step 1: Write the failing tests.**
  - `test_rollover_assigns_days`: a fixture with headers at 23:50 and 00:10 gives two days.
  - `test_slot_busy_counts_tester_and_regression_only`: tester 600 s + regression 300 s + lead 900 s in a 3600 s day gives 25.0.
  - `test_standing_task_interval`: three `=== HH:MM:SS tester:task (` headers 3600 s apart give 3600.
  - `test_cost_per_close`: cost 30.0 and 6 closes give 5.0; 0 closes give `None`.
- [ ] **Step 2: Run** `python3 -m unittest tests.py.test_gpu_busy -v`. Expect: FAIL (module missing).
- [ ] **Step 3: Implement.** Load the script via `importlib` in the test (scripts aren't a package). `gh` is called only when `--repo` is given, so tests pass `closes` in directly.
- [ ] **Step 4: Run the tests.** Expect: PASS. Then run it for real: `python3 scripts/gpu-busy.py --days 14 --json > docs/superpowers/specs/2026-11-18-loop-scheduler-baseline.json`.
- [ ] **Step 5:** Add `scripts/gpu-busy.py` to `docs/harness/components.md`. Run `tests/run.sh python lint`. Commit:
  ```bash
  git add scripts/gpu-busy.py tests/py/test_gpu_busy.py tests/fixtures/gpu-busy docs/superpowers/specs/2026-11-18-loop-scheduler-baseline.json docs/harness/components.md
  git commit -m "R17: gpu-busy baseline (slot busy %, standing-task cadence, cost per close)"
  ```

### Task 1: Scheduler core (pure, no I/O)

**Files:**
- Create: `harness/scheduler.py`
- Test: `tests/py/test_scheduler.py`

**Interfaces:**
- Produces:
  ```python
  PRIORITY: tuple[str, ...]          # the Global Constraints order, queue names
  GPU_FEEDERS = frozenset({"reviewer:arch", "implementer:fix", "lead:build"})

  @dataclass(frozen=True)
  class Item:
      queue: str          # classify queue name, or "curator", "tester:task", "tester:closures", "regression", "deploy"
      issue: int | None
      server: str | None  # None = shared (design, reviews, curator, spec, handoff)
      candidates: tuple[str, ...] = ()   # servers that may take a shared-or-unclaimed item
      @property
      def key(self) -> tuple: ...        # (queue, issue): identity across servers

  def needs(item: Item, server: str) -> frozenset[str]   # resource names, e.g. {"gpu:lem"}, {"src:lem","free"}, {"leadtree:lem","free"}, {"free"}
  class Pool:
      def __init__(self, servers: dict[str, int], free_slots: int): ...   # servers: name -> gpu slots
      def can_take(self, item: Item, server: str) -> bool
      def take(self, item: Item, server: str) -> None
      def release(self, item: Item, server: str) -> None
      def busy(self) -> dict[str, list[Item]]           # resource -> holders
  class Scheduler:
      def __init__(self, pool: Pool, clock=time.monotonic): ...
      def offer(self, items: list[Item]) -> None         # replaces the ready set (one board snapshot)
      def next_dispatches(self) -> list[tuple[Item, str]] # items to start now, each with its server; takes their resources
      def finished(self, item: Item, server: str, ok: bool) -> None
      def hold(self, server: str, reason: str) -> None    # stop handing out gpu:<server> (deploy, regression, stop flag)
      def unhold(self, server: str) -> None
      def gpu_idle(self, server: str) -> bool             # no session holds gpu:<server>
      def pause_until(self, t: float) -> None             # rate limit: dispatch nothing before t
  ```
- The resource map is spec "Work items and resources". Standing task and closures need `gpu:<server>`, nothing else. Suite writers need no `suite` here; the suite token is taken only by the commit step (Task 4).
- `free` holds `LOOP_FREE_SLOTS` units. An item outside `GPU_FEEDERS` may take a `free` unit only while at least 2 are free, which keeps the reserve.
- An item already running (same `key`) is never dispatched again, on any server.
- A failed item is not re-dispatched until the next `offer()`.

- [ ] **Step 1: Write the failing tests** (fake clock):
  - `test_code_item_runs_while_gpu_busy`: verify on `gpu:lem` running, fix offered, so fix dispatches.
  - `test_priority_order`: `lead:design` and `reviewer:arch` offered with 1 free unit, so arch first.
  - `test_reserved_free_slot`: 3 free units, 3 designs offered, so 2 dispatch; then a fix is offered and dispatches.
  - `test_src_serializes_fix_and_build`: fix and build on lem, so one at a time.
  - `test_leadtree_serializes_design_and_decompose`.
  - `test_hold_blocks_gpu_only`: `hold("lem")` stops verify dispatch but not fix; `unhold` resumes.
  - `test_pause_until`: nothing dispatches before t, and things dispatch after it.
  - `test_item_dispatched_once_across_servers`: an item with `candidates=("lem","mini-ai")` offered while both are free dispatches exactly once.
  - `test_failed_item_waits_for_next_snapshot`: `finished(ok=False)` means it doesn't dispatch again until `offer()`.
  - `test_standing_task_last`: task and verify offered with one GPU slot, so verify first.
- [ ] **Step 2: Run** `python3 -m unittest tests.py.test_scheduler -v`. Expect: FAIL.
- [ ] **Step 3: Implement `harness/scheduler.py`.** In `next_dispatches`, walk the ready items sorted by `(PRIORITY.index(queue), issue)`. For each, try `item.server` or else each of `candidates` in order, and `take` the first server that `can_take`.
- [ ] **Step 4: Run the tests.** Expect: PASS.
- [ ] **Step 5: Commit.**
  ```bash
  git add harness/scheduler.py tests/py/test_scheduler.py
  git commit -m "R17: scheduler core - resources, priority, reserved free slot, gpu hold"
  ```

### Task 2: Deploy policy

**Files:**
- Create: `harness/deploy_policy.py`
- Modify: `harness/deploy.py` (add `run_deploy(server, say) -> tuple[bool, str]`, which wraps `deploy_cmd` over ssh and returns `(ok, deployed_head)`)
- Test: `tests/py/test_deploy_policy.py`

**Interfaces:**
- Consumes: `harness/deploy.py` `deployed_head(server)`, `deploy_cmd(server)`, `preflight(server, url, token)`; `harness/gitops.git`.
- Produces:
  ```python
  def fix_commit(source_dir: str, issue: int) -> str | None
      # newest commit on origin/develop whose message matches r"#<issue>\b" (git log --grep, -E), or None
  def runnable_now(source_dir: str, issue: int, deployed: str) -> bool
      # fix_commit is an ancestor of deployed (git merge-base --is-ancestor); False if fix_commit is None
  def server_paths_changed(source_dir: str, deployed: str, develop: str) -> bool
      # git diff --name-only deployed..develop has a path outside PLUGIN_ONLY
  PLUGIN_ONLY = ("plugins/",)   # the plugin tree refresh_plugin_tree serves; extend only from permissions.md's two deploy paths
  class DeployGate:
      def __init__(self, retry_secs: int, clock=time.monotonic): ...
      def wanted(self, ready_gpu_issues: list[int], runnable: dict[int, bool], changed: bool) -> bool
          # ready GPU work exists, none of it runnable, server paths changed, not in a failed-retry wait
      def failed(self) -> str   # "retry" the first time (wait retry_secs), "park" the second
      def succeeded(self) -> None
  ```
- `state` for `state.json`: one of `idle|waiting|draining|deploying|failed`.

- [ ] **Step 1: Write the failing tests** (temp git repo with an origin, as in `tests/test-regression-py.sh` fixtures, built in `setUp`):
  - `test_fix_commit_newest_match`: two commits mentioning `#12` give the newest; `#120` doesn't match `#12`.
  - `test_runnable_now_ancestor`: fix in deployed gives True; fix after deployed gives False; no fix commit gives False.
  - `test_plugin_only_change_needs_no_deploy`.
  - `test_wanted_only_when_nothing_runnable`: issues 1 and 2 ready, 1 runnable, so not wanted. Once 1 is gone, wanted.
  - `test_failed_retry_then_park`: the first `failed()` gives "retry" and `wanted` stays False for `retry_secs`; the second gives "park".
  - `test_deploy_takes_newest_develop_once`: the gate wants a deploy, develop moves during the drain, the deploy runs once, and its head is the newest develop. This is asserted through `run_deploy` called once with branch `develop`.
- [ ] **Step 2: Run** `python3 -m unittest tests.py.test_deploy_policy -v`. Expect: FAIL.
- [ ] **Step 3: Implement.** Before trusting `#N` matching, check it against real history: `git -C ~/src/dkackman/dw-agent log origin/develop --oneline -40`. Fix and merge commits name `#N` there (seen 2026-11-18: `fix(chain): #1444 - …`, `Merge … (#1397)`).
- [ ] **Step 4: Run the tests.** Expect: PASS.
- [ ] **Step 5: Commit.**
  ```bash
  git add harness/deploy_policy.py harness/deploy.py tests/py/test_deploy_policy.py
  git commit -m "R17: deploy policy - batch deploys, runnable-now verifies first, retry then park"
  ```

### Task 3: Deploys leave the agents (prompts and guard)

**Files:**
- Modify: `agents/implementer/fix.md` ("Deploy" section), `agents/implementer/core.md` ("Already addressed?"), `agents/implementer/triage.md` (the "needs deploy" lines)
- Modify: the lead's build fragment (`grep -ln "deploy" agents/lead/*.md`: the stage-build kind) and `agents/implementer/target.md` (its "Deploy" section becomes a pointer to `fix.md`'s, now that the rule is the same everywhere)
- Modify: `agent-settings/hooks/guard.py` (the `deploy.sh` refusal around line 2717, now for implementer and lead on every `HARNEST_TARGET`, lem included)
- Modify: `docs/harness/permissions.md` (the two deploy paths: the driver deploys server code)
- Test: `tests/test-guard.sh`

**Interfaces:**
- Produces: the hand-off comment still names the deploy path: `deploy: server` or `deploy: plugin`. This is the existing wording in `fix.md`; keep its exact form, and Task 2 doesn't parse it.

- [ ] **Step 1: Write the failing guard tests** in `tests/test-guard.sh`, following that file's existing deploy cases (`grep -n deploy.sh tests/test-guard.sh`):
  - `HARNEST_TARGET=lem HARNEST_ROLE=implementer ssh lem '~/diffusers-workflow/scripts/deploy.sh develop'` is denied.
  - The same for `HARNEST_ROLE=lead`.
  - `HARNEST_ROLE=tester` stays denied as before.
- [ ] **Step 2: Run** `tests/run.sh guard`. Expect: the 2 new cases FAIL.
- [ ] **Step 3: Implement** the guard change. State the rule once in `agents/implementer/core.md`: "You never deploy: merge to `develop`, push, hand off naming the deploy path; the driver deploys." `fix.md`, `triage.md`, `target.md` and the lead fragment point at it by section name. Remove the `ssh lem … deploy.sh` instructions.
- [ ] **Step 4: Run** `tests/run.sh guard lint providers`. Expect: PASS.
- [ ] **Step 5: Commit.**
  ```bash
  git add agents agent-settings/hooks/guard.py tests/test-guard.sh docs/harness/permissions.md
  git commit -m "R17: the driver owns every deploy - guard refuses deploy.sh for implementer and lead on all targets"
  ```

### Task 4: Per-session suite worktrees

**Files:**
- Create: `harness/suite_tree.py`
- Modify: `agent-settings/hooks/guard.py` (the add-only suite rule and `HARNEST_ROOT` handling, around its lines 122–155, must treat the session's worktree as the harness root)
- Test: `tests/py/test_suite_tree.py`, `tests/test-guard.sh`

**Interfaces:**
- Consumes: `harness/suite.py` `commit_changes(repo, logs, paths, msg, name, email, say)` (removed-lines audit included).
- Produces:
  ```python
  def make(harnest: str, session_id: str) -> str
      # git worktree add --detach <harnest>/.worktrees/<session_id> main; returns its path
  def land(harnest: str, tree: str, msg: str, name: str, email: str, say, suite_lock) -> str
      # under suite_lock: commit suite changes in tree (commit_changes), rebase onto main, ff main;
      # returns "landed" | "clean" | "conflict" (commit left on branch suite-conflict/<session_id>, [audit] WARNING said)
  def remove(harnest: str, tree: str) -> None
  ```
- Today the tester and curator run with cwd `$REPO` (`run-loop.sh` `run_agent tester … "$REPO"`). In item mode, `lib/run-item.sh` (Task 5) sets `REPO`'s session cwd to the worktree path via `HARNEST_SESSION_TREE`. Check every place `run_agent tester|curator` passes `$REPO` and route it through `${HARNEST_SESSION_TREE:-$REPO}`.
- `.worktrees/` is added to `.gitignore`.

- [ ] **Step 1: Write the failing tests:**
  - `test_land_clean`: append a case line in the tree and land it; main has the line and the trailer.
  - `test_land_concurrent_appends`: two trees append different cases at different places; both land, and main has both.
  - `test_land_conflict_keeps_branch`: two trees edit the same line; the second gives "conflict", branch `suite-conflict/<id>` exists, main is unchanged by it.
  - `test_land_refuses_removal`: removing a line hits the existing removed-lines warning from `commit_changes`.
  - Guard: an Edit to `<worktree>/regression-suite-complete.md` that appends is allowed for the tester; one that drops a line is denied.
- [ ] **Step 2: Run** `python3 -m unittest tests.py.test_suite_tree -v` and `tests/run.sh guard`. Expect: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them again.** Expect: PASS.
- [ ] **Step 5: Commit.**
  ```bash
  git add harness/suite_tree.py tests/py/test_suite_tree.py agent-settings/hooks/guard.py tests/test-guard.sh .gitignore
  git commit -m "R17: per-session harnest worktrees for suite edits, landed under one suite token"
  ```

### Task 5: Item mode for the bash passes

**Files:**
- Modify: `run-loop.sh`. Under `HARNEST_ITEM=1`, skip `acquire_driver_lock` (line 238), the startup deploy and the `main` call. `LAST_SESSION` becomes `${HARNEST_LAST_SESSION:-$LOGS/.last-session.loop$TARGET_SUFFIX}`.
- Create: `lib/run-item.sh`
- Modify: `implementer_pass` and `lead_pass`. They no longer deploy, and `check_target_on_develop` doesn't run in item mode.
- Test: `tests/test-drivers.sh` (unchanged scenarios still pass), new section `# --- 19. item mode`

**Interfaces:**
- Produces: `lib/run-item.sh <pass> [<issue>]`, where `<pass>` is one of `implementer triage lead features tester reviewer-arch reviewer-docs curator tester-task tester-closures`. The environment the Python loop sets:
  - `DW_TARGET`
  - `HARNEST_ITEM=1`
  - `ONLY_ISSUES=<issue>`
  - `HARNEST_LAST_SESSION=logs/.last-session.item.<slot>`
  - `HARNEST_SESSION_TREE` (suite writers only)
  - `DEPLOYED_HEAD`
  - every role knob, passed through
- Exit codes: 0 means a session ran or nothing was ready, 1 means a driver error. The board is the outcome.
- `features` calls `run-features.sh` with `ONLY_ISSUES`, unchanged.
- `tester-task` runs only the standing task, and `tester-closures` only the closures session (split `tester_pass`'s two branches behind a `TESTER_PART=task|closures|issues` variable; default `issues`).

- [ ] **Step 1: Write the failing tests** in `tests/test-drivers.sh` section 19, using the existing fixtures:
  - `item: verify runs one session for #N only`: a board with 2 hand-offs and `lib/run-item.sh tester 2` gives one `claude` call, whose prompt names #2.
  - `item: takes no lock`: `.driver.lock` is held by another pid and the item still runs.
  - `item: implementer never deploys`: the ssh stub log has no `deploy.sh` after `run-item.sh implementer N`.
  - `item: last-session file is the one given`.
- [ ] **Step 2: Run** `tests/run.sh drivers`. Expect: the new cases FAIL and the old ones PASS.
- [ ] **Step 3: Implement.** Keep `main "$@"; exit` as the last line and wrap it: `[ "${HARNEST_ITEM:-}" = 1 ] || { main "$@"; exit; }`. `run-item.sh` sources `run-loop.sh` with `HARNEST_ITEM=1`, then calls the pass function.
- [ ] **Step 4: Run** `tests/run.sh`. Expect: all pass.
- [ ] **Step 5: Commit.**
  ```bash
  git add run-loop.sh lib/run-item.sh tests/test-drivers.sh
  git commit -m "R17: item mode - one pass for one issue, no lock, no deploy"
  ```

### Task 6: Loop state file and GPU metrics

**Files:**
- Create: `harness/loop_state.py`
- Test: `tests/py/test_loop_state.py`

**Interfaces:**
- Consumes: `Scheduler.busy()`, `DeployGate.state`, `harness/deploy.health(url, token)`.
- Produces:
  ```python
  class LoopState:
      def __init__(self, path: str, servers: list[str], clock=time.time): ...
      def session_started(self, item, server, label, model, log): ...
      def session_ended(self, item, server, cost: float | None): ...
      def deploy(self, server, state, waiting: list[int], last: dict | None = None): ...
      def heads(self, server, deployed, develop): ...
      def queues(self, server, queues: dict[str, list[int]]): ...
      def board(self, rows: list, readable: bool): ...          # appends a history point only when rows changed
      def gpu_sample(self, server, slot_busy: bool, worker_busy: bool | None): ...  # integrates busy seconds since last sample
      def status(self, s: str): ...                             # running|draining|stopping|paused-rate-limit
      def closed(self, n: int): ...
      def write(self): ...                                      # tmp + os.replace; also called by a heartbeat every LOOP_POLL_SECS
  ```
- The schema is spec "State file and dashboard". Add `"heartbeat": <epoch>` and `"board_readable": bool`.
- `worker_busy` comes from `/api/health`'s workers. Find the field by reading `harness/deploy.health`'s current parse and dw's health payload (`gh api repos/dkackman/diffusers-workflow/contents/...` per the repo facts). Use `None` when it can't tell, and the dashboard then shows slot busy only.

- [ ] **Step 1: Write the failing tests:**
  - `test_write_is_atomic`: no partial file is ever visible. Write in a loop while a reader thread parses; it never gets a `JSONDecodeError`.
  - `test_board_history_only_on_change`.
  - `test_gpu_integration`: samples at t=0 busy, t=30 busy, t=60 idle give slot_busy 60 and wall 60.
  - `test_cost_per_close`: two sessions at $3, then closed(2), give totals cost 6, closed 2.
  - `test_unreadable_board_keeps_rows`.
- [ ] **Step 2: Run** `python3 -m unittest tests.py.test_loop_state -v`. Expect: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests.** Expect: PASS.
- [ ] **Step 5: Commit.**
  ```bash
  git add harness/loop_state.py tests/py/test_loop_state.py
  git commit -m "R17: loop state.json - slots, deploy line, queues, board history, gpu busy"
  ```

### Task 7: The loop driver

**Files:**
- Create: `harness/drivers/loop.py`, `harness/board.py`, `lib/board.sh`
- Modify: `targets/dw/profile.toml` (add `loop_gpu_slots = 1` to lem and mini-ai), `harness/profile.py` (read it, default 1)
- Test: `tests/test-loop-py.sh` (new, in the style of `tests/test-regression-py.sh`)

**Interfaces:**
- Consumes: Tasks 1, 2, 4, 5 and 6; `harness/lock.acquire`; `harness/session.kill_all`; `harness/outcome.rejected_until` (rate limit); `harness/gitops.refresh_plugin_tree`.
- Produces:
  - `lib/board.sh <target>` sources `providers.sh` and prints `classify_issues` TSV (`number queue parent reason`). It exits 1 when the board is unreadable.
  - `harness/board.py`:
    - `snapshot(target) -> list[Row] | None`, where `Row(number:int, queue:str, parent:int|None, reason:str)`;
    - `items(rows_by_target: dict[str, list[Row]]) -> list[Item]`. An issue claimed here has `server`. Unclaimed items offered by several targets get `candidates`. Design, decompose, reviews, spec and handoff are shared.
  - `python3 -m harness.drivers.loop [--servers lem,mini-ai] [--only QUEUE[,QUEUE]] [--once]`.
  - `class Runner` with `start(item, server, slot) -> Popen`, which wraps `lib/run-item.sh`. This is the seam phase 1b replaces pass by pass.
- Behaviour, all from the spec:
  - Take `.driver.lock<sfx>` per server with `lock.acquire`.
  - Wake on child exit, on deploy end, or every `LOOP_POLL_SECS`.
  - Run the housekeeping at most once per `LOOP_POLL_SECS`: run `park_external_issues`, `unpark_pass` and `consolidation_pass` via `run-item.sh`, check `dw_frozen` and `release_freeze` via `lib/board.sh`, and offer `tester:closures` items when `pending_closures` says so.
  - Deploy: `DeployGate.wanted`, then `hold`, wait for `gpu_idle`, `run_deploy`, `preflight`, then `unhold`. The second failure parks the waiting verifies via `run-item.sh implementer-park <n>`. If no such pass exists, add a 10-line `park_issue` call in item mode in Task 5's style, with the `environment` reason.
  - Nightly regression: after `REGRESSION_NIGHTLY_AT`, once per day: `hold`, then drain, then run `run-regression.sh` as a child holding every `gpu:S`, then `unhold`. Run it with `HARNEST_PARENT_HOLDS_LOCK=1`, so it doesn't wait on our own lock. Check how `nightly_regression_pass` does this today and copy it.
  - Standing task: only when `gpu_idle("lem")`, no lem item is queued, and `TESTER_TASK_GAP_SECS` has passed.
  - Before each tester item: `refresh_plugin_tree`, and set `DEPLOYED_HEAD`.
  - Suite writers: `suite_tree.make`, then the session, then `land`, then `remove`.
  - After a session exits: re-snapshot. The audit already ran inside the item.
  - Rate limit: on a child's last-session file showing a rejection, `pause_until(rejected_until)`.
  - `logs/stop-after-cycle<sfx>`: `hold` that server, wait for its children, release its lock, consume the flag. Exit when no server is left.
  - `DRAIN=1`: exit when nothing is running and `drain_left` (via `lib/board.sh drain <target>`) says done.
  - `MAX_SESSIONS`: stop dispatching after that many sessions, then drain.
  - SIGTERM: `hold` all, `kill_all`, kill children within `SESSION_KILL_SECS` / `CHILD_DRIVER_KILL_SECS`, then exit.
  - Write `LoopState` on every event, plus a heartbeat.

- [ ] **Step 1: Write the failing end-to-end tests** in `tests/test-loop-py.sh`. Use the `test-drivers.sh` fixtures: fake `gh` board, stub `ssh` that records `deploy.sh` calls and reads `$T/lem-head`, stub `claude` with `FAKE_CLAUDE_DO`, and stub `curl` health. Every run uses `--once` or `MAX_SESSIONS`.
  - `loop: a design and a verify run at the same time`: the stub claude sleeps 2 s and logs start/end. The two sessions' intervals overlap.
  - `loop: verify of an undeployed fix deploys first, once`: two hand-offs whose `#N` commits are newer than `lem-head` give exactly one `deploy.sh` call, before either tester session.
  - `loop: a deployed fix verifies with no deploy`.
  - `loop: plugin-only change, no deploy`.
  - `loop: deploy waits for the running verify`: the `deploy.sh` timestamp is after the running tester session's end.
  - `loop: failed deploy retries then parks`: the ssh stub fails `deploy.sh` twice, so the issue gets `owner:don` and an environment reason.
  - `loop: gh outage`: the fake board is unreadable, so no sessions start and `state.json` has `board_readable: false`.
  - `loop: stale lock`: a lock owned by a dead pid is taken over.
  - `loop: stop-after-cycle stops one server`: with `--servers lem,mini-ai` and the flag `stop-after-cycle.mini-ai`, the mini-ai lock is released and the process keeps running lem.
  - `loop: SIGTERM kills sessions`: no `claude` children are left within the kill bounds.
  - `loop: rate limit pauses all`.
  - `loop: standing task only when lem is idle and the gap passed`.
  - `loop: state.json shows both slots busy`: sampled mid-run.
  - `loop: one GPU slot`: two verifies run serially.
- [ ] **Step 2: Run** `tests/run.sh loop-py`. Expect: FAIL.
- [ ] **Step 3: Implement.** Use one thread per child to wait and push to a `queue.Queue`. The main loop blocks on that queue with `timeout=LOOP_POLL_SECS`.
- [ ] **Step 4: Run** `tests/run.sh`. Expect: all pass. Check the time: the new file should take under 20 s, so use sleep 0–2 in the stubs.
- [ ] **Step 5: Commit.**
  ```bash
  git add harness/drivers/loop.py harness/board.py lib/board.sh harness/profile.py targets/dw/profile.toml tests/test-loop-py.sh
  git commit -m "R17: the loop driver - concurrent lanes, driver-owned deploys, per-server stop, state.json"
  ```

### Task 8: Dashboard reads state.json

**Files:**
- Modify: `dashboard/serve.py` (`state()`, `processes()` already match `harness.drivers.loop`), `dashboard/index.html`
- Test: `tests/py/test_dashboard.py`, fixtures `tests/fixtures/loop-state/{idle,running,deploying,failed,stalled,rate-limited}.json`

**Interfaces:**
- Consumes: `logs/loop/state.json` (Task 6).
- Produces: `/api/state` gains `"loop": {...state.json..., "live": bool, "stalled": bool}`.
  - `live` means the pid is alive and the heartbeat is no older than `2 × LOOP_POLL_SECS`. Read that value from `state.json`'s own `poll_secs` field; add that field in Task 6.
  - `stalled` means the pid is alive and the heartbeat is old, or the pid is dead and the status isn't `stopped`.
  - The old per-stream `loop_run` / `looping` stay for reading old logs.
- The page has a card per server, as in the spec's ASCII sketch:
  - slots with label, elapsed time and cost so far;
  - the deploy line (state, deployed vs develop, waiting issue links);
  - queue depths;
  - GPU busy slot % and card % with a sparkline from `gpu.<s>.series`;
  - a shared row, and the totals with cost per close.
  - Stalled shows in the warning colour, with "stalled since HH:MM".

- [ ] **Step 1: Write the failing tests:**
  - `test_loop_live`: a fresh heartbeat with our pid gives live True.
  - `test_loop_stalled_old_heartbeat`.
  - `test_loop_stalled_dead_pid`.
  - `test_loop_failed_deploy_passthrough`: `servers.lem.deploy.state == "failed"` comes through.
  - `test_no_state_file`: `loop` is None and nothing else breaks.
- [ ] **Step 2: Run** `python3 -m unittest tests.py.test_dashboard -v`. Expect: the new tests FAIL.
- [ ] **Step 3: Implement** the server part, then the page. Check the page in a browser against each fixture: `python3 dashboard/serve.py` with `logs/loop/state.json` symlinked to each fixture in turn. Look at idle, running, deploying, failed, stalled and rate-limited, at desktop width and at 390 px.
- [ ] **Step 4: Run** `tests/run.sh python`. Expect: PASS.
- [ ] **Step 5: Commit.**
  ```bash
  git add dashboard tests/py/test_dashboard.py tests/fixtures/loop-state
  git commit -m "R17: dashboard loop card from state.json - lanes, deploy line, gpu busy, stalled"
  ```

### Task 9: Knobs, docs, roadmap

**Files:**
- Modify: `README.md` (the knobs in Global Constraints; how to start the new loop; `TESTER_TASK_EVERY` and `MAX_CYCLES` marked "run-loop.sh only")
- Modify: `docs/harness/running.md` (commands, one process for both servers, per-server stop flag), `docs/harness/components.md` (new modules), `docs/harness/tests.md` (`test-loop-py.sh`)
- Modify: `CLAUDE.md` (the "Where things are" row now names `harness/drivers/loop.py`)
- Modify: `HARNESS-ROADMAP.md` (add an R17 row to the status table with the baseline numbers from Task 0; mark the "`lem` runs one job at a time" principle as amended by R17; add the phase 1b and phase 2 items)
- Modify: `TESTER_TASK_GAP_SECS`'s default in `harness/drivers/loop.py`: the baseline's `standing_task_interval_secs`, rounded to the hour

- [ ] **Step 1: Run** `tests/run.sh lint`. Expect: FAIL, listing the new knobs.
- [ ] **Step 2: Write the docs.** The README line for each knob gives its default and one sentence.
- [ ] **Step 3: Run** `tests/run.sh`. Expect: all pass.
- [ ] **Step 4: Commit.**
  ```bash
  git add README.md CLAUDE.md HARNESS-ROADMAP.md docs/harness harness/drivers/loop.py
  git commit -m "R17: knobs, running docs and roadmap row for the loop scheduler"
  ```

### Task 10: Cutover on lem (operational, with Don)

- [ ] **Step 1:** Re-run the baseline: `python3 scripts/gpu-busy.py --days 14 --json`. Commit it if it changed.
- [ ] **Step 2:** Stop the bash loops:
  ```bash
  pgrep -fl run-loop
  kill -TERM <pid>
  ```
  Confirm `logs/.driver.lock` is gone, then do the same for mini-ai.
- [ ] **Step 3:** Start the new loop: `nohup python3 -m harness.drivers.loop --servers lem > logs/loop-py.nohup.out 2>&1 &`.
- [ ] **Step 4:** Watch the first deploy and the first parallel pair on the dashboard. `grep '\[audit\]' logs/loop.log` should show nothing new that the bash loop wouldn't have raised.
- [ ] **Step 5:** Add mini-ai once it has work: restart with `--servers lem,mini-ai`.
- [ ] **Step 6:** At day 14, record the before and after figures in the R17 roadmap row (GPU slot %, card %, closes/day, cost per close). Under "Fail forward", tune rather than roll back. Delete `run-loop.sh`'s cycle `main` only in the phase 1b plan, once no item still sources it.
