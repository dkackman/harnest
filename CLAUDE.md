# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Not an application — an orchestration harness for Claude Code agents (implementer, tester,
regression, lead, reviewer, curator, release, retro) that iterate on the `diffusers-workflow`
MCP server, communicating through GitHub Issues on `dkackman/diffusers-workflow` and, for
regression coverage, the `regression-suite-*.md` files. There is no build step.

**`tests/run.sh` is the test suite: run it before committing any change to a driver,
`providers.sh`, `lib/classify.jq` or the guard.** It is offline (fake `gh` over a JSON board,
stub `ssh`/`claude`), takes about a minute, and runs the real drivers end to end.

## Where things are

| Topic | File |
|---|---|
| Every driver, `providers.sh`, role-prompt assembly, regression suites, lead, release, bench, curator/retro/digest, `harness/`, `contract/`, logs | [docs/harness/components.md](docs/harness/components.md) |
| Running the loop, the second server (`mini-ai`), driver lock, audit, MCP/plugin wiring | [docs/harness/running.md](docs/harness/running.md) |
| What each `tests/test-*.sh` covers | [docs/harness/tests.md](docs/harness/tests.md) |
| Per-role permissions, `guard.py`, the hand-off gate, deploy paths, bounce escalation | [docs/harness/permissions.md](docs/harness/permissions.md) |
| Ticket protocol: owner/status labels, freezes, security advisories, regressions | [docs/harness/ticket-protocol.md](docs/harness/ticket-protocol.md) |
| Planned evolution of the harness | `HARNESS-ROADMAP.md` — read it before a structural change to the drivers or role prompts |
| Knobs and Don's moves | `README.md` |

Read the matching file before changing that area.

## Rules that apply to most changes

- **Keep the asymmetry.** Any change that gives the tester code or box access, or lets the
  implementer self-verify, defeats the purpose of the setup. The tester talks to `dw` only
  over MCP and never reads source.
- **`lib/classify.jq` is the state machine.** Change who acts on what there, not in a driver.
  Add a board to `tests/classify-cases.json` when you add or change a state.
- **Keep the `owner:*` / `status:*` label prefixes.** The status board and `classify.jq`
  depend on them. An open issue has exactly one `owner:*` label.
- **No state survives between sessions** except GitHub Issues and the suite files. Agents never
  poll or sleep inside a session.
- **Suite cases are add-only.** No agent deletes or rewrites a case to make it go away; the
  only route is a `suite` + `status:needs-approval` issue on `dkackman/harnest` for the curator.
  Suite files hold the durable test, never a log of results.
- **No `--dangerously-skip-permissions`.** If a role legitimately needs something its allowlist
  denies, widen the list in `providers.sh` deliberately.
- **Role prompts:** `agents/<role>/core.md` + one fragment per session kind (`role_prompt` in
  `providers.sh` is the map). State each rule once — in the core if more than one kind needs
  it — and point at it by section name, never by step number across files. A rule enforced by
  `guard.py` stays in the core as a one-line pointer.
- **Every knob read** (`${KNOB:-}` in shell, `environ.get("KNOB")` in Python) must be named in
  the README; `test-lint.sh` enforces it.
- **Bash 3.2** (`/bin/bash` on macOS): no `source <(…)`, and no apostrophe in a comment inside
  `<( )`.

## Running

Which roles may run a weak model is a design decision, not a config detail: the tester's
independence is the whole point, and a weak tester degrades that silently by rubber-stamping.
Vary the implementer (its mistakes show up in its patches) and keep the tester on a strong
model, by exact id (`claude-opus-5-5`), not an alias. The regression agent is the measured
exception and defaults to Sonnet. Commands and multi-server details: [docs/harness/running.md](docs/harness/running.md).
