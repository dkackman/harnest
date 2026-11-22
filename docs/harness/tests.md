# Tests

Moved from `CLAUDE.md`. Sections named "below" in this text now live in sibling files: Running → `running.md`, Tests → `tests.md`, Permissions → `permissions.md`, Ticket protocol → `ticket-protocol.md`, the component list → `components.md`.

`tests/run.sh [name]` runs every `tests/test-*.sh` (plain bash on `tests/lib.sh`, no bats).
Seventeen files:
- `test-approve-batch.sh`: `scripts/approve-batch.sh` on a fake-gh board. It approves only
  issues still in the batch lane, skips the rest untouched, asks once, and logs each
  approval.
- `test-classify.sh`: `lib/classify.jq` over fixture boards in `tests/classify-cases.json`,
  one per protocol state. Add a board when you add or change a state; a board's
  `expect_reason` checks reasons too, for a state a driver reads by reason.
- `test-consolidation.sh`: the curator's weekly consolidation (`lib/consolidation.py`) on a
  fixture tree with a canned `arch_report.py`.
- `test-drivers.sh`: the real `run-loop.sh`, `run-features.sh`, `run-regression.sh`,
  `run-release.sh`, `run-curate.sh` and `run-retro.sh` against `tests/fake-gh.py` (a JSON
  board that edits change; it lists newest first within `--limit`, honours the `--search`
  qualifiers the drivers use, and stamps comments with `FAKE_GH_AUTHOR` and the time) and a
  throwaway git origin. It covers a GitHub outage, the ledger parking an issue,
  fix-then-verify in one cycle, an outside filing, the closures window, withheld comments, the dry-round rule, the day budget (a
  session not started, a drain exiting), the retro's applied proposals to check,
  the curator's audited removals, the spec race, `DRAIN=1` with the idle backoff (and waiting out a claimed feature's stage at another loop), and item mode (`lib/run-item.sh`: one session for one issue, no lock, no deploy, no suite commit, the suite tree as the tester's cwd, the task and closures split, `park`, the queue as part of the item: a feature parent's spec item runs no stage verify).
- `test-fleet.sh`: a whole regression fleet run (`harness/drivers/fleet.py`) against three
  `tests/fake-mcp.py` servers.
- `test-guard.sh`: `guard.py` as a table (role, session kind, command, allowed or refused).
- `test-lint.sh`: `bash -n` under `/bin/bash` 3.2, `shellcheck -S error`, Python parses,
  `ruff check` and `ruff format --check` clean under `ruff.toml` (a missing ruff fails; fix with
  `ruff check --fix . && ruff format .`), and every knob read (`${KNOB:-}` in the drivers and
  `scripts/*.sh`, `environ.get("KNOB")` in `lib/`, `scripts/` and `harness/` Python) is named
  in the README.
- `test-providers.sh`: the shared helpers. Session outcomes on canned logs, the stream
  renderer against `tests/fixtures/stream.expected`, model/effort validation, the
  no-progress ledger, `handoff_count`, `park_external_issues`, the driver lock, suite commits,
  the board snapshot cache, and the spend record with `day_budget_reached`.
- `test-python.sh`: the `harness/` unit tests in `tests/py/` (stdlib `unittest`: contract,
  dashboard, fleet, parity, perf check, rank, results, suite; R17: scheduler, board,
  loop, loop state, deploy policy, lock, gpu-busy; spend, with the day budget and the dry-round
  rule in the loop driver).
- `test-loop-py.sh`: the R17 loop driver (`harness/drivers/loop.py`) end to end, each
  scenario in its own world in parallel: `lib/board.sh`; a design beside a verify; one gpu
  slot; deploys batched, after the running gpu session, retried then parked, the gpu slot held
  through a failed deploy until the server answers again; SIGTERM mid-deploy; a verify beside a
  spec gets a fresh plugin tree; plugin-only and
  deployed fixes with no deploy; a GitHub outage; a stale lock; stop-after-cycle for one
  server; SIGTERM; a rate-limit pause; the standing task's gate; suite trees landing, a
  suite conflict kept on a branch; the curator; the nightly regression; `DRAIN=1`; `--only`.
- `test-ratchet.sh`: the architecture ratchet (`lib/arch_ratchet.py`, the guard's
  `arch_gate`) on fixture repos with a stand-in `arch_metrics.py`.
- `test-regression-py.sh`: the Python regression driver against `run-regression.sh`, same
  scenarios, outputs diffed (parity).
- `test-release.sh`: `lib/release.sh`'s gate markers, board check, findings validation and
  notes insertion.
- `test-requirements-py.sh`: the requirements generator (`harness/drivers/requirements.py`)
  end to end.
- `test-setup.sh`: `scripts/setup-mac-loop.sh` (twice, the second a no-op) and
  `scripts/install-schedules.sh` (retro, digest, suite audit) under a throwaway `HOME`.
- `test-sync.sh`: `scripts/sync-fixtures.sh` with fake curl, rsync and ssh.
- `test-testbed.sh`: `scripts/testbed.sh` with fake ssh and curl.
- `test-ui-check.sh`: `tools/ui-check/ui-check.mjs` against a fixture page on 127.0.0.1:
  steps, mocks built from the real answer (and a status), stubs (POST on write routes only, GET
  anywhere on the origin), abort, the rerun route allowed and restart-batch blocked, inspect's
  attributes, dup_ids, window_flag, request recording, the origin lock, fetch (JSON, HEAD,
  the 256 KB cap on a sized and an endless chunked body, an endless drip returned at the step
  timer, JSON too deep to print, redirects not followed, `/api/...` and `/openapi.json` only
  with dot-segment escapes refused, path and method refusals, never in `recorded`, the token
  scrubbed from an echo, from Location and content type, and where the cap cuts through it),
  bearer-token injection from an MCP config (and its scrubbing) against an auth-requiring server, a
  backtracking regex ended by the step cap, SIGTERM leaving no Chromium, locator and spec-path refusals.
  Skipped when `tools/ui-check/node_modules` is missing.
- `test-ui-ratchet.sh`: the UI's architecture ratchet (`check_ui`) on fixture repos.

Two bash 3.2 traps the suite has already caught: an apostrophe in a comment inside `<( )`
("bad substitution"), and `source <(…)`, which 3.2 doesn't support.
