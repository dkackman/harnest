# Loop scheduler: keep the GPUs busy (R17)

Status: design, 2026-11-18. Not built. Replaces `run-loop.sh` and folds in `run-features.sh`.

## Why

A loop cycle runs its passes one after another: features (design, decompose) → implementer
→ lead builds → arch review → tester → docs review → curator (`run-loop.sh` `main`). Only
the tester (and the regression agent, in its own driver) puts work on a GPU. Everything
else is a Claude session on this Mac (minid) that reads code, writes code, or writes
comments. While it runs, lem's two RTX 3090s and mini-ai's MPS sit idle.

The logged session time shows the scale (`grep usage: logs/loop.log`, all history):
lead 136 h (design, decompose and builds mixed), implementer 79 h, tester 128 h,
regression 57 h. Most of the loop's wall time is spent on work that needs no GPU.

They are serial for one reason. A deploy restarts dw. An implementer or lead deploy in
the middle of a tester session drops its MCP connection, or changes the code it is
verifying without telling it. A single serial cycle avoided that by construction.

Don's goal: issues move faster because the GPU hosts are kept as busy as possible, while
analysis and coding run on minid at the same time. The dashboard must show the new
arrangement accurately: what each lane is doing, what's waiting on a deploy, and how busy
the GPUs are.

## Goals

- GPU work (tester verify, answer, standing task) starts as soon as it is ready. It never
  waits behind a design, decompose, build, fix or review session.
- Server-free work runs at the same time as GPU work, on minid.
- Exactly one thing deploys to a server: the scheduler, between GPU sessions. No session
  ever has the server restarted under it.
- One process drives every loop server (lem and mini-ai).
- The dashboard reads the scheduler's own state file, not heuristics over the log.
- Measure it: GPU busy %, before and after.

## Non-goals

- No change to the ticket protocol, `owner:*` / `status:*` labels or `lib/classify.jq`'s
  queues. The scheduler consumes its output. A new state, if one turns up, goes in
  `classify.jq` and `tests/classify-cases.json` as usual.
- No change to what any role may see or do, apart from the deploy move below.
- No Agent SDK. Sessions stay `claude -p` children through `harness/session.py`.
- `run-release.sh`, `run-curate.sh`, `run-retro.sh` and `run-digest.sh` are not ported
  here.

## Anti-goals (a failure even if it runs)

- A tester session that loses its server mid-session, or verifies a head other than the
  one its prompt names.
- Any blurring of the asymmetry: the tester gets no source access, and the implementer
  gets no way to verify its own fix.
- A weaker tester to save money while things run in parallel. Tester stays on
  `claude-opus-5-5` by exact id.
- Faster spend with no faster closes. More concurrency spends the same per issue, sooner.
  If cost per closed issue rises, that is a regression of this work.
- A dashboard that shows "running" for a lane that is stuck, or "idle" for one that is
  busy.

## Constraints (from CLAUDE.md and the roadmap)

- `lib/classify.jq` stays the state machine. The scheduler decides when and where a
  ready item runs, never who acts on it.
- No state survives between sessions except GitHub Issues and the suite files. The
  scheduler's in-memory state and `state.json` are driver state. They are rebuilt from the
  board on restart.
- Suite cases are add-only. `commit_suite_changes`'s removed-lines audit is ported as is.
- No `--dangerously-skip-permissions`. Allowlists stay in `providers.sh` / `guard.py`.
- Every knob read is named in the README (`test-lint.sh`).
- `tests/run.sh` stays offline and runs the real driver end to end over the fake board.

## Approaches considered

| | What | Trade-off | Verdict |
|---|---|---|---|
| A | Two bash drivers per server: a code lane, and a GPU lane that owns deploys | Smallest change. Two processes per server to watch. The dashboard has to merge two log streams. Thrown away at the R8 port. | not chosen |
| B | One bash driver that backgrounds the code passes, with a deploy lease | Sessions that want to deploy would have to wait inside a session (forbidden) or fail and bounce | dropped |
| **C** | **Port the loop to Python as one scheduler with resource slots per server; the scheduler owns deploys** | **The biggest build. Gives the dashboard real state, two GPU slots on lem, and regression in idle GPU time. R8 says to port the loop at its next major change, and this is that change.** | **chosen (Don, 2026-11-18)** |

Don is fine with stopping the current loops for the build. There is no side-by-side
period.

## Design

### Work items and resources

Each tick, the scheduler snapshots the board (`issue_snapshot` + `classify.jq`, once per
target, as `queue_issues` does today). It turns every ready queue entry into a **work
item** and dispatches it when the resources it needs are free.

Resources, per server `S` (lem, mini-ai) unless marked global:

| Resource | Count | Held by |
|---|---|---|
| `gpu:S` | profile `loop_gpu_slots` (phase 1: 1; phase 2: lem 2) | sessions that may run jobs on S |
| `deploy:S` | exclusive, and excludes every `gpu:S` | the scheduler's deploy |
| `src:S` | 1 | sessions that commit in `SOURCE_DIR` for S (branch, merge to develop) |
| `leadtree:S` | 1 | sessions that read `LEAD_TREE` for S (it is reset before each run) |
| `suite` (global) | 1 | the commit step only: rebasing a session's suite commit onto `main` (see "Suite edits") |
| `free` (global) | `LOOP_FREE_SLOTS`, default 3, one of them kept for GPU-feeding work | cap on server-free sessions running at once |

Queue → resources:

| Queue / pass | Resources | Notes |
|---|---|---|
| `tester:verify`, `tester:answer` | `gpu:S` | the tester may add a case |
| tester standing task, tester closures | `gpu:S` | see "Standing task" |
| `tester:spec`, `tester:handoff` | `free` | no jobs, writes cases |
| `implementer:fix` (triage + fix sessions) | `src:S`, `free` | may run reproduction jobs over MCP; holds no `gpu` slot (dw queues one job per card) |
| `lead:build`, `lead:closeout` | `src:S`, `free` | no longer deploys (below) |
| `lead:design`, `lead:decompose` | `leadtree:S`, `free` | `claim_session` per issue, as today |
| `reviewer:arch`, `reviewer:docs` | `free` (+ the tree it reads, if shared) | |
| curator | `free` | |
| nightly regression | every `gpu:S` | runs `harness.drivers.regression` as a child; a reservation, not a backfill (below) |

**Reserved free slot.** One `free` slot is only for work that feeds the GPU queue:
`reviewer:arch`, `implementer:fix` and `lead:build`. Design, decompose, docs review,
spec, handoff and curator can use only the other `LOOP_FREE_SLOTS - 1`, so three long
designs can't hold up an arch review that gates a verify.

### Suite edits

Every session that may edit a suite file (tester of any kind, curator) runs with its
`regression-suite-*.md` reads and writes pointed at its own harnest worktree. That worktree
is a detached checkout of `main`, made at session start. After the session the scheduler
does three things:
1. takes `suite`;
2. commits the worktree's suite changes, with the session's trailer and the removed-lines
   audit;
3. rebases that commit onto `main` and fast-forwards, then releases.

A rebase conflict leaves the commit on a branch `suite-conflict/<session>`, logs
`[audit] WARNING` and raises a `stranded_board` line for Don. Nothing is dropped. So no
GPU session ever waits on a server-free session for the suite, and two GPU slots (phase 2)
need nothing new here.

The builder checks how each role reaches the suite files today (cwd, absolute path in
the prompt, guard allowlist) and points that at the worktree. `guard.py`'s path rules must
accept the worktree path for those roles and no other.

Priority when several items compete: first, work that feeds the GPU queue soonest;
second, work that uses it. In order: `reviewer:arch` (it gates a verify) →
`tester:verify` / `tester:answer` → `implementer:fix` → `lead:build` → `tester:spec` →
`lead:decompose` → `lead:design` → `reviewer:docs` → `tester:handoff` → curator →
standing task → regression. Within a queue, order is the one `classify.jq` gives.

What already holds today still holds:
- `LEAD_STAGES_PER_CYCLE` becomes "at most one feature in build per server".
- `IMPLEMENTER_CLAIM_MAX`, the escalation and park thresholds, budgets and models are read
  as today.

### Deploys move to the scheduler

On every target, the implementer and the lead merge to `develop`, push, and hand off.
They never deploy. That is mini-ai's rule today (`agents/implementer/target.md` "Deploy"),
extended to lem. Changes:

- `agents/implementer/fix.md` "Deploy", `core.md` "Already addressed?" and `triage.md`'s
  "needs deploy" line: "the driver deploys". The hand-off still names the deploy path
  (server code or plugin only).
- The lead's build prompt: "deploys once with the path the plan named" becomes "merges and
  names the path".
- `guard.py`: refuse `deploy.sh` (and the testbed deploy) for implementer and lead on
  every target, not only `HARNEST_TARGET=mini-ai`. Add `tests/test-guard.sh` cases.

The deploy rule batches. A `tester:verify` item is **runnable now** when the commit its
hand-off names (the merge into develop; the builder finds where the hand-off records it,
and falls back to "not runnable" when it can't tell) is an ancestor of S's deployed head.
Runnable verifies run first. The scheduler deploys only when a verify (or `answer`) is
ready and none of them is runnable now, and `git diff deployed..develop` touches anything
outside the plugin tree. So a burst of merges costs one deploy, not one each. The tester's
prompt still names the deployed head it runs against, as today. The steps:
1. stop handing out `gpu:S`;
2. wait for the running `gpu:S` sessions to end (a regression child counts);
3. take `deploy:S`, run `deploy_target` (`harness/deploy.py`), then preflight;
4. release.

Plugin-only differences need no restart. `refresh_plugin_tree` runs before each tester
session instead. A failed deploy is logged. S's GPU items then wait, flagged
`deploy failed` in `state.json`, and after `DEPLOY_RETRY_SECS` the deploy is retried
once. A second failure parks the waiting verifies with Don (`environment` reason), as an
implementer deploy failure does today.

Code sessions keep running during a deploy. An implementer that happens to be reproducing
over MCP at that moment loses its connection. That's accepted: it is rare, and it is a
reproduction, not a verification. It is logged so we can count it.

### Nightly regression

Kept guaranteed, as today. Once `REGRESSION_NIGHTLY_AT` passes, the scheduler drains
`gpu:S` the way it does for a deploy: no new GPU work, running sessions finish. Then it
runs the regression child holding every `gpu:S`. Verifies wait for that run, as they do
today. The deploy rule doesn't fire while regression holds S. A deploy that comes due
then waits for the run to end. Phase 2's backfill is extra regression on top, not a
replacement for this.

### Standing task

The tester's standing task is discovery: $1.5–3.7 a session, measured 2026-09-21. Don
values it, but it slows item progression, so it runs **at today's cadence or less**
(Don, 2026-11-18). It never fills idle time on its own account. It runs only when all of
these hold:
- a `gpu:lem` slot is free;
- nothing is queued for lem in any queue (verify, answer, fix, build, arch review, design,
  decompose);
- at least `TESTER_TASK_GAP_SECS` have passed since the last one.

The default for `TESTER_TASK_GAP_SECS` is the mean interval between standing tasks in
the 14-day baseline, which `scripts/gpu-busy.py` reports. It is set to that before
cutover, with `TESTER_TASK_EVERY` retired. It runs on lem only, as today ("What stays on
lem").

Closure responses (`pending_closures`) keep their own cheap session. It takes a `gpu`
slot only because it is a tester session with MCP; it runs no jobs.

### No cycles: an event loop

The scheduler wakes when a session ends, when a deploy finishes, or every
`LOOP_POLL_SECS` (default 60). On each wake it does three things:
1. Re-snapshots the board only if a session ended, or the poll interval has passed. The
   snapshot cache in `providers.sh` is the model.
2. Runs the housekeeping that used to run once per cycle, rate-limited to once per
   `LOOP_POLL_SECS`: `park_external_issues`, the freeze check (`dw_frozen`) and
   `unpark_pass`, `pending_closures`, `consolidation_pass`, `release_freeze`.
3. Dispatches every item whose resources are free, in priority order.

The idle backoff (`drain_left`, `SLEEP_SECS` → `SLEEP_MAX_SECS`) applies to the poll
interval when nothing is dispatchable and only Don's decisions are left.
- `DRAIN=1` exits when nothing is running and `drain_left` says done.
- `logs/stop-after-cycle<sfx>` stops **that server**: no new work on it, wait for its
  sessions, release its `.driver.lock<sfx>`, consume the flag. The process keeps driving
  the others and exits when it drives none. Shared passes move to a remaining server.
  `run-release.sh` (which flags lem and then needs lem's lock) and a hand run of
  `run-regression.sh` on one target work unchanged.
- `MAX_CYCLES` becomes `MAX_SESSIONS`. This is a knob rename; the README changes with it.

After every per-issue session the scheduler does what the cycle did:
- `audit_issue`;
- `commit_suite_changes` for sessions that held `suite`, under that token, with the
  session's model in the trailer;
- re-read `DEPLOYED_HEAD` before the next tester prompt is built.

Rate limits: a session that hits a rate limit (`sleep_if_rate_limited`'s check) pauses
dispatch globally until the reset time, because every session shares the account.

SIGTERM: stop dispatching, then kill every session process group (`session.kill_all`) and
any child driver, then exit. This keeps the existing `SESSION_KILL_SECS` /
`CHILD_DRIVER_KILL_SECS` bounds.

### One process, two servers

`python3 -m harness.drivers.loop` drives every profile server with `loop = true`. For each
one it takes that server's `.driver.lock<sfx>` (so `run-regression.sh` and the fleet still
exclude it) and keeps its own `src`, `leadtree` and `gpu` resources, and its own clones
(`dw-agent-mini-ai` …). `--servers lem` limits it to one server.

Claims stay labels (`claim_issue`, `target:*`), because the guard and the protocol read
them:
- An unclaimed item that both servers' classify passes offer goes to the first server
  whose resources are free. For a GPU item that means the server whose GPU would idle
  first.
- Shared passes (design, reviews, curator) run once, not once per server.
  `SHARED_PASSES` / `lem_loop_running` / `claimed_here` / `shared_here` reduce to
  in-process checks. `claim_session` keeps its lock file, so a hand-run of
  `run-features.sh` can't collide.

### Sessions and logs

Sessions start through `harness/session.py`, with role prompts assembled as
`role_prompt` does today. `harness/prompts.py` exists. The role → kind map is ported from
`providers.sh`, not duplicated: one copy, and the bash side calls the Python one or the
reverse. That is the builder's call, with one rule: one copy.

Every session writes to `logs/loop.log` as today, with its `=== label (provider/model) ===`
header, `[role:#N]` prefixed lines and closing `usage:` line. Concurrent sessions
interleave by line, and the prefix tells them apart. Each server's lines go to that
server's stream (`loop.log`, `loop.mini-ai.log`), so `tail -f` and `grep usage:` keep
working.

### State file and dashboard

The scheduler rewrites `logs/loop/state.json` on every change. It writes a temp file and
renames it, as the fleet's `State` does. Shape:

```json
{
  "pid": 1234, "started": 1763520000, "status": "running|draining|stopping|paused-rate-limit",
  "servers": {
    "lem": {
      "deployed": "a1b2c3d", "develop": "e4f5a6b",
      "deploy": {"state": "idle|waiting|draining|deploying|failed", "waiting": [1450, 1452],
                 "last": {"at": 0, "head": "a1b2c3d", "ok": true, "secs": 95}},
      "slots": [{"resource": "gpu:lem", "session": {"label": "tester:#1450", "kind": "verify",
                 "issue": 1450, "model": "claude-opus-5-5", "started": 0, "log": "loop.log"}},
                {"resource": "src:lem", "session": null}],
      "workers": [{"device": "cuda:0", "busy": true, "job": "..."}],
      "queues": {"tester:verify": [1450], "implementer:fix": [1449, 1451]}
    }
  },
  "shared": {"slots": [{"resource": "free", "session": {"label": "lead:#1448 decompose"}}]},
  "board": {"rows": [[1450, "status:fixed-pending-verify", "owner:tester", "title"]],
            "history": [{"time": 0, "closed": 3, "agents": 7, "don": 2, "parked": 1, "arrived": 4}]},
  "totals": {"sessions": 31, "cost": 58.4, "closed": 6},
  "gpu": {"lem": {"wall": 21600, "slot_busy": 15400, "worker_busy": 11200,
                  "series": [{"t": 0, "slot": 1, "worker": 1}]}}
}
```

`board.history` holds a point per distinct board, as the dashboard keeps one today, so
closed and arrived counts survive a page reload. On restart it is rebuilt from the first
snapshot: no history carries across runs, the same as today.

**Two GPU-busy numbers, because they differ:**
- `slot_busy` is time a GPU slot holds a session.
- `worker_busy` is time dw reports a worker running a job. The scheduler reads
  `/api/health` every `LOOP_HEALTH_SECS` (default 30). The dashboard never calls a server
  itself.

A tester that is reading output between jobs holds a slot but leaves the card idle. The
gap between the two numbers is that thinking time.

Dashboard changes (`dashboard/serve.py`, `index.html`):
- **The loop card reads `state.json`.** It shows per server: each slot with its session,
  elapsed time and cost so far, the deploy line (deployed vs develop, waiting hand-offs,
  state), queue depths, and GPU busy % (slot and worker) with a sparkline. The shared
  slots get their own row. The `{status}` line shows rate-limit pauses and draining.
- **"Running" means `state.json`'s pid is alive and the file is fresh.** The file is
  touched at least every `LOOP_POLL_SECS`. A stale file shows as "stalled", not
  "running".
- The session list and log tail keep reading the per-server log streams. Cycle-banner
  logic stays only for reading old logs.
- `processes()` learns the `harness.drivers.loop` command line (`PY_DRIVER_RE` already
  matches `harness.drivers.<name>`).
- The board-history chart reads `board.history`.
- Totals show cost per closed issue next to cost, the anti-goal metric.

ASCII sketch of a server card:

```
lem ───────────────────────────────────────────────────────
  gpu  ● tester:#1450 verify        12m  $1.10
  src  ● implementer:#1449 fix       6m  $0.80
  deploy  running a1b2c3d · develop e4f5a6b · waiting: #1452 (draining)
  queues  verify 1 · fix 2 · build 0 · design 1
  GPU busy  slot 71% · card 52%  ▁▃▆█▇█▆▇   (this run, 6h)
shared ────────────────────────────────────────────────────
  free ● lead:#1448 decompose  4m   ● reviewer:#1447 arch  1m
```

### Measurement

Before cutover, write `scripts/gpu-busy.py`. It computes slot occupancy for the old loop
from `loop.log`: tester and regression session seconds over wall time, per day, for the
last 14 days. Session headers carry only HH:MM:SS, so days come from the rollover
heuristic `_clock_epoch` already uses. That number is the baseline.

After cutover, `state.json`'s `gpu` block gives the same number plus worker busy. Record
both in the roadmap's R17 row, with cost per closed issue before and after.

**Cost per closed issue.** "Closed" means closed as `completed` on dw (the tester's or the
docs reviewer's close), both servers combined. Cost is every logged `usage:` cost in the
same window, across all roles. The baseline is the 14 days before cutover, from the logs
and `gh issue list --state closed --search closed:>=…`. `gpu-busy.py` computes this too.
The after figure is the first 14 days on the new driver. Closes per day is reported next
to it, because the goal is more of them.

**Fail forward (Don, 2026-11-18).** This is the better design, so a shortfall is tuned,
not rolled back: slots, priority, the reserved slot, the deploy batching. A rollback to
`run-loop.sh` is only for significant degradation that tuning hasn't fixed within the 14
days:
- closes/day well below the baseline, or
- cost per closed issue well above it (on the order of +50%).

`run-loop.sh` stays in the tree, unused, for those 14 days, then is deleted.

### What gets ported

From `run-loop.sh`:
- the passes: `implementer_pass`, `lead_pass`, `features_pass`, `tester_pass`,
  `reviewer_pass`, `curator_pass`, `consolidation_pass`, `unpark_pass`,
  `nightly_regression_pass`;
- the checks and helpers: `check_target_on_develop`, `arch_review_after`,
  `pending_closures`, `status_board`, `stranded_board`, `drain_left`, `idle_wait`.

From `providers.sh`, every function those passes call that `harness/` lacks:
- claims: `claim_issue`, `claim_winner`, `claim_session`;
- invariants: `audit_issue`;
- suite commits: `commit_suite_changes*`, `suite_commit_paths`;
- context: `issue_context`, `triaged_issue`, `plan_text`, `handoff_count`,
  `issue_fingerprint`, `note_progress`;
- prompts and models: `role_prompt`, `target_note`, `co_author_for`, `resolved_model`;
- freezes: `release_freeze`, `dw_frozen`, `freeze_hold_line`;
- review tools: `ensure_arch_tools`, `ensure_ui_tools`, `ratchet_deps_current`;
- issues: `park_external_issues`, `still_ready`.

`render_stream`, session flags and deploy/health already have Python equivalents.

`run-features.sh` becomes a thin wrapper:
`python3 -m harness.drivers.loop --only lead:design,lead:decompose [ONLY_ISSUES]`. It
stays for running one issue by hand. `run-loop.sh` stays in the tree, unused, for the
14-day measurement window ("Fail forward"), then is deleted.

`providers.sh` keeps whatever the drivers not ported here still use (`run-regression.sh`,
`run-release.sh`, `run-curate.sh`, …).

### Tests

- `tests/test-loop-py.sh`: the real driver end to end over the fake `gh` board with stub
  `ssh`/`claude`, as `test-regression-py.sh` does. Port every `run-loop.sh` and
  `run-features.sh` scenario in `tests/test-drivers.sh`, then retire those scenarios with
  the bash driver.
- Scheduler unit tests, with no sessions:
  - a deploy waits for the running GPU sessions and blocks new ones;
  - a code session runs while a GPU session runs;
  - priority order;
  - `suite` serializes the curator and the tester;
  - `leadtree` serializes design and decompose;
  - `src` serializes fix and build;
  - a rate limit pauses everything;
  - stop-after-cycle drains;
  - SIGTERM kills all session groups;
  - `state.json` reflects each of these.
- `tests/test-guard.sh`: deploy refused for implementer and lead on lem.
- Dashboard: a fixture `state.json` per state (idle, running, deploying, failed deploy,
  stalled, rate-limited), with assertions on `/api/state`.
- `tests/run.sh` runs all of it and stays about a minute. Scheduler tests use a fake clock.

### Phases

**Phase 1: the scheduler, one GPU slot per server.**
- Everything above, except two GPU slots and regression in idle slots.
- Cut over lem first: it has the work, and mini-ai's board is empty (Don, 2026-11-18), so
  a mini-ai run would prove nothing. Stop lem's bash loop and run the new driver with
  `--servers lem`. Add mini-ai (drop `--servers`) once lem has run cleanly and mini-ai
  has work, or straight away if a two-server bug needs flushing out. Loops are stopped with `kill -TERM` (verified 2026-10-25).
- Don't edit `run-loop.sh` or `providers.sh` while a bash loop is live.

**Phase 2: more GPU.**
- `loop_gpu_slots = 2` on lem. Suite edits already use per-session worktrees (phase 1),
  so nothing new is needed for them.
- The plugin tree: one per GPU slot (`dw-agent-plugin`, `dw-agent-plugin-2`), each
  refreshed only when its slot is free.
- Regression in idle GPU slots: regression cases run as lowest-priority `gpu:S` items, in
  the fleet's batch sizes. The cases come from the fleet's planner (`plan_level`) for
  whatever level is due. A ready verify preempts at the next batch boundary, never mid
  batch. The nightly pass becomes "a level is due".

## Left to the builder

- Module layout under `harness/` (e.g. `scheduler.py`, `board.py`, `passes/`,
  `drivers/loop.py`).
- Which side owns the single copy of `role_prompt` and the queue → kind map.
- The exact path list that counts as "plugin only" for the deploy check. Start from
  `refresh_plugin_tree`'s tree and `permissions.md`'s two deploy paths.
- Threads or `selectors`/subprocess polling for concurrency. It stays stdlib only.
- Whether `reviewer:*` shares `LEAD_TREE` (then it takes `leadtree:S`) or has its own
  tree.
- Exact `state.json` field names, as long as the dashboard and its tests agree.

## Calls I made (Don to check)

- Implementer reproduction jobs hold no GPU slot, and a deploy doesn't wait for code
  sessions.
- The priority order above, which puts arch review and verifies ahead of new fixes and
  designs.
- `LOOP_FREE_SLOTS` defaults to 3.
- `MAX_CYCLES` → `MAX_SESSIONS`.
- Two GPU numbers (slot and card) rather than one.
- Per-session harnest worktrees for suite edits move into phase 1, so no verify waits on
  the curator or a spec session.
- One `free` slot is kept for arch review, fix and build.
- Deploys are batched: runnable verifies go first, and a deploy happens only when no ready
  verify can run as things stand.
- `stop-after-cycle<sfx>` stops one server, not the process.
- Nightly regression stays guaranteed, with a drain like a deploy.
- Cost per closed issue: `completed` closes on dw, all roles' cost, 14-day windows.
