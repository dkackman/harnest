# Tests

Moved from `CLAUDE.md`. Sections named "below" in this text now live in sibling files: Running → `running.md`, Tests → `tests.md`, Permissions → `permissions.md`, Ticket protocol → `ticket-protocol.md`, the component list → `components.md`.

`tests/run.sh [name]` runs every `tests/test-*.sh` (plain bash on `tests/lib.sh`, no bats).
Sixteen files:
- `test-classify.sh`: `lib/classify.jq` over fixture boards in `tests/classify-cases.json`,
  one per protocol state. Add a board when you add or change a state.
- `test-consolidation.sh`: the curator's weekly consolidation (`lib/consolidation.py`) on a
  fixture tree with a canned `arch_report.py`.
- `test-drivers.sh`: the real `run-loop.sh`, `run-features.sh`, `run-regression.sh`,
  `run-release.sh`, `run-curate.sh` and `run-retro.sh` against `tests/fake-gh.py` (a JSON
  board that edits change; it lists newest first within `--limit`, honours the `--search`
  qualifiers the drivers use, and stamps comments with `FAKE_GH_AUTHOR` and the time) and a
  throwaway git origin. It covers a GitHub outage, the ledger parking an issue,
  fix-then-verify in one cycle, an outside filing, the closures window, withheld comments,
  the curator's audited removals, and the spec race.
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
  no-progress ledger, `handoff_count`, `park_external_issues`, the driver lock, suite commits
  and the board snapshot cache.
- `test-python.sh`: the `harness/` unit tests in `tests/py/` (stdlib `unittest`: contract,
  dashboard, fleet, parity, perf check, rank, results, suite).
- `test-ratchet.sh`: the architecture ratchet (`lib/arch_ratchet.py`, the guard's
  `arch_gate`) on fixture repos with a stand-in `arch_metrics.py`.
- `test-regression-py.sh`: the Python regression driver against `run-regression.sh`, same
  scenarios, outputs diffed (parity).
- `test-release.sh`: `lib/release.sh`'s gate markers, board check, findings validation and
  notes insertion.
- `test-requirements-py.sh`: the requirements generator (`harness/drivers/requirements.py`)
  end to end.
- `test-setup.sh`: `scripts/setup-mac-loop.sh` (twice, the second a no-op) and
  `scripts/install-schedules.sh` under a throwaway `HOME`.
- `test-sync.sh`: `scripts/sync-fixtures.sh` with fake curl, rsync and ssh.
- `test-testbed.sh`: `scripts/testbed.sh` with fake ssh and curl.
- `test-ui-ratchet.sh`: the UI's architecture ratchet (`check_ui`) on fixture repos.

Two bash 3.2 traps the suite has already caught: an apostrophe in a comment inside `<( )`
("bad substitution"), and `source <(…)`, which 3.2 doesn't support.
