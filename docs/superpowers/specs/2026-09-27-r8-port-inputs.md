# R8 port inputs: the target profile, the prompt split, and what the Agent SDK changes

Status: approved by Don, 2026-09-28. He accepted all five recommendations under "Decisions".
Nothing here is built yet; the plan is `docs/superpowers/plans/2026-09-27-r8-port.md`.

## Goal

R8 ports the bash drivers to Python. R13 says to draw the line between framework and target
first and port along it, so the Python package reads a target profile from its first module
instead of hardcoding dw and being split apart later. This document is that line, plus the
facts about the Claude Agent SDK that decide how the port runs a session.

R8's trigger has been met. R12 finished on 2026-09-24, and dw#378 ran end to end and closed
verified.

Since the trigger was written on 09-23, the bash has grown from about 3,080 lines to about
4,600 (drivers, `providers.sh`, `lib/`). Most of the growth is harnest#15's second server.

The full inventories this summarizes are in `2026-09-27-r8-inputs/`:
- `code.md`: every env knob, every `claude` flag, the log contract, all 364 dw-specific code
  lines tagged, a map from each function to a proposed module, and the test seams.
- `prompts.md`: every prompt section classed core, pack, mixed or per-server; the assembly
  table; hard-coded values; cross-file references.
- `sdk.md`: `claude-agent-sdk` 0.2.160 read from source, with each flag mapped and the four
  deciding questions answered.

Their `file:line` references are as of `be9a72e`. The suite files have been edited since then (harnest#34–36), so check any suite line before citing it.

## Vocabulary: "target" means two things today

harnest#15 uses "target" for **one dw server**: lem or the Mac. Examples are `DW_TARGET`,
`TARGET_SUFFIX`, `agents/<role>/target.md`, the `target:lem`/`target:local` labels and
`HARNEST_TARGET`. R13 uses "target" for **a product under test**: dw, and later a second
MCP server.

Porting with both meanings produces names like `targets/dw/agents/tester/target.md`,
where "target" means a server note, not a target pack.

Proposal: in the Python package and in file names, harnest#15's concept becomes a
**server**, and "target" keeps R13's meaning. `DW_TARGET` stays as an accepted env var
(the knob contract), and the `target:` GitHub labels stay as they are. The label prefix
becomes a profile value (`claim_label_prefix`), so a label migration can happen later,
separately, or never.

This document uses the new words: **target** = the product (dw), **server** = one
deployment of it (lem, local).

## The target profile

The profile is one file per target, `targets/dw/profile.toml`, read by `harness/profile.py`
(`tomllib`, stdlib since Python 3.11; the Mac has 3.13). Every value below is a constant or
default in bash today. `code.md` §4d gives each one's current sources.

### Fields that are values

| field | dw value |
|---|---|
| `ticket_repo`, `harness_repo`, `ticket_owner` | `dkackman/diffusers-workflow`, `dkackman/harnest`, `dkackman` |
| `human` | `Don`, named about 150 times across the prompts. This belongs to the framework install, not the target, but it lives in the profile for now. |
| `product`, `advisory_package` | `diffusers-workflow` |
| `integration_branch`, `release_branch` | `develop`, `master` |
| `mcp.name` | `dw`. It derives the `mcp__dw__*` allowlists, the `mcpServers` key, `plugins/dw` and the guard's MCP-call check. |
| `mcp.deny_tools` | `delete_model`, `update_diffusers` |
| `mcp.readonly_tools` | the per-role lists for lead design, reviewer and curator review (`providers.sh:371-376, 399-401, 442-443`) |
| `mcp.auth` | a Bearer header from `DW_TOKEN` |
| `clones` | `source`, `plugin`, `lead` and `release` paths under `~/src/dkackman/dw-agent*`. Clone URL, install command (`bash ./install.sh`), plugin subdir `plugins/dw`. |
| `labels.backend` | `backend:shared`, `backend:cuda`, `backend:mps`, plus the triage guidance on which applies |
| `labels.claim_prefix`, `labels.verified_on` | `target:`, `verified-on:` |
| `suite.levels` | smoke / complete / model-specific / security. Each has a file, workspace, ID prefix, whether it's in `all`, whether it implies another level, the curator's minutes and USD, and whether the curator always escalates it (security). |
| `suite.case_id_regex`, `suite.contract_runner` | `[A-Z]+-[A-Z][0-9]+`; `contract/run.py` with `contract/cases/<ID>.json` |
| `docs` | `design_docs` (`docs/proposals/…`), `release_notes_file` (`docs/RELEASING.md`), `issue_template` (`mcp-ticket.md`) |
| `prompt_values` | the placeholders the prompt cores need (`prompts.md` §2): `commit_example`, `caller_warning_channel`, `served_text_rule`, `mcp_efficiency_tips`, `orphan_cleanup`, `tester_memory_file`, and about 20 more |

### The servers table

This is the largest field. Today it is implicit, spread across `resolve_target`,
`deploy_cmd`, `deployed_head`, `target_health`, `claim_issue`, `serves()` in
`lib/classify.jq`, and scattered `if lem` branches. `code.md` §4c has every row.

| per-server field | lem | local |
|---|---|---|
| state suffix, clone suffix | `""`, `""` | `.local`, `-mps` |
| MCP URL | `http://lem:8765/mcp` | `http://localhost:8765/mcp`, which must be loopback or this host |
| backends served | `cuda`, `shared` | `mps`, `shared` |
| primary (wins claim ties, gets unclaimed legacy hand-offs) | yes | no |
| deploy | `ssh … lem '~/diffusers-workflow/scripts/deploy.sh develop'` | `scripts/deploy-local.sh` with `DW_DIR`, `DW_WORKSPACE`, host, port and record |
| deployed head | an ssh one-liner printing `<branch> @ <sha>` | `head -1 logs/.deployed.local` |
| preflight | none | `GET /api/health`; the hostname must be this machine |
| verification label | none | `verified-on:mps`, required with `status:verified` |
| queues it may not run | none | `tester:spec`, `lead:build`, `lead:closeout` |
| standing task, release | yes, yes | no, refused |
| shared passes (features, reviewer, curator) | always | only while the primary's loop is down |
| suite commit paths, perf dir | suites + `regression-perf/` | `regression-perf/local/` (suites only with `SUITE_EDITS`, and only while lem's loop is down) |
| regression `all`, skipped cases | four levels, none | three levels, `TARGET_SKIP_CASES` |
| implementer settings, tester budget default | `implementer.json`, 5 | `implementer.local.json`, 8 |
| guard rules | none | no ssh/scp/rsync/deploy for the implementer; consumer filing rules; no comment on the primary's issues |

### Fields that are logic, not values

These are dw code in files that are otherwise generic. Each becomes a command or callable
the profile names.

- **The hand-off gate** (`guard.py:240-319`). It hard-codes `ruff` on `dw/ dw_mcp/ tests/`,
  `npm run check/lint/test` in `ui/`, and `venv/bin/python -m pytest`, compared against a
  base worktree.
  - It becomes `handoff_gate`: a list of `{name, when_changed: [globs], run: cmd}` plus a
    `relative_test: cmd` entry.
  - The guard keeps the mechanism: a clean tree, stamps, and a relative comparison against
    `HARNEST_BASE_COMMIT`.
- **Bench scoring** (`run-bench.sh:139-154, 240-284`). This is the pytest command, the venv
  symlink and the `tests/` hidden-test prefix.
- **Release** (`run-release.sh`). It runs `scripts/preflight.sh`, checks `ci.yml`/`codeql.yml`,
  frees port 8971, updates `docs/RELEASING.md` and runs `scripts/release.sh`. The whole
  driver is dw's release process. It becomes a target plug-in; only `lib/release.sh`'s pure
  functions are framework.
- **Fixture sync** (`scripts/sync-fixtures.sh`). dw only; it moves to `targets/dw/scripts/`.
- **The implementer's auto-mode environment** (`agent-settings/implementer*.json`
  `autoMode.environment`). This is prose about lem, the repo, pip/uv and Hugging Face. It is
  pack content, generated into the settings file per server.

## The prompt split

`prompts.md` §3 has all 128 sections. By role, after moving the dw parts of the mixed
sections:

| role | generic | pack after split | verdict |
|---|---:|---:|---|
| curator | 95% | ~650 B | profile values only; rewrite one worked example neutrally |
| reviewer | 94% | ~300 B | profile values only |
| lead | 92% | ~2.4 KB | profile values, plus one optional fragment: design step 3 "Measure demand" |
| implementer | 84% | ~2.7 KB | small but high-stakes: deploy, the served-text rule, the warning channel, gate commands |
| regression | 80% | ~3.4 KB | levels, workspace rules, orphan cleanup, perf timing source |
| tester | 75% | ~6.8 KB | the standing task (~4 KB), efficiency tips, levels, the memory file |
| release | 73% | ~1.6 KB | `review.md` "Areas" is wholly pack |
| retro | 100% | 0 | none |

This answers R13's open question: **neither the lead nor the curator needs a pack file.**

**Layout.**
- **Framework.** `agents/<role>/<kind>.md` stays with the framework and holds
  `{placeholder}` values from the profile.
- **Target pack.** `targets/dw/agents/<role>/<name>.md` holds only the pack fragments:
  `standing-task.md`, `release/areas.md` and the optional `lead/demand.md`.
- **Per-server notes.** They become `targets/dw/servers/<server>/<role>.md`, the renamed
  `target.md` files. The backend and claim text that sits in three cores today
  (implementer "Backend and target labels", `tester/core.md:57-62`,
  `regression/core.md:47-50, 61-62`) moves there too.
- **Suite contract.** It is framework text, and the pack's suite files must meet it. Three
  paragraphs appear word for word in all four suite files (about 10.9 KB): "Maintained by",
  "Removing a case", "No case may depend on chance". Every pack's suite files must also have
  the headings the cores point at: "Where a case belongs", "Adding a case", "Fixtures".

**Existing breakage to fix first.** These cross-file references already break R10's rule,
independent of the port:
- `tester/core.md:90` points at "Verifying a feature", which is in `verify.md` and not loaded
  for the other five tester kinds.
- `lead/decompose.md:14` and `lead/closeout.md:78` point at `build.md`'s "Stop and re-plan",
  which isn't loaded in those sessions.
- `regression-suite-security.md:45` points at `agents/regression/core.md` by path.
- `regression/core.md:183` says the suite header "ends with the Fixtures section", which is
  false for the security suite.

## The log format is a contract

The port must reproduce these lines byte for byte (`code.md` §3):
- `=== HH:MM:SS … ===`, `--- … ---`, `[tag] …`, `model: `, `· ctx=`, `> Tool {…}`,
  `< [ERROR ]N chars`, `rate-limit: … resets_epoch=`, `usage: turns=… ctx_peak=…`, `result: `;
- the per-model lines;
- the driver lines (`[audit] WARNING`, `[lock]`, and the others).

Their readers:
- the dashboard's regexes, including the rule that `cycle N: role:tag` headers count as run
  banners;
- the curator's chunk cost table, which depends on the `regression:<level>.<n>` label shape;
- the retro's evidence regexes;
- `resolved_model`, which greps compact JSON, so the raw `.jsonl` must stay the CLI's own
  bytes or `separators=(",",":")`;
- the bench's scorers;
- `session_died`/`ran`/`ok`, `sleep_if_rate_limited`;
- the regression agent's `REGRESSION-ABORT/SKIP/DIFFERS` lines;
- about 40 strings asserted in `tests/test-drivers.sh`.

`tests/fixtures/stream.jsonl` → `stream.expected` is the golden test for the renderer.

## What the Agent SDK changes

Read from `claude-agent-sdk` 0.2.160 source, which bundles CLI 2.1.283. The drivers run
`~/.local/bin/claude` 2.1.283. Full map in `sdk.md`.

**What maps cleanly.** These are all native `ClaudeAgentOptions` fields: model,
fallback model, effort, `max_budget_usd`, `tools` (the built-in whitelist), `allowed_tools`,
`disallowed_tools`, `permission_mode` (`dontAsk` and `auto` are both in its `Literal`),
`mcp_servers` + `strict_mcp_config`, `plugins`, `settings`, `setting_sources`, cwd and env.
Typed `RateLimitEvent`, `ResultMessage.total_cost_usd`, `usage` and `model_usage` cover what
the jq renderer reads.

**What needs care:**

| issue | consequence | handling |
|---|---|---|
| The SDK prefers its **bundled** CLI over the `claude` on PATH | Without `cli_path`, `tests/run.sh` would bypass the stub and start the real, billed CLI, with `DW_URL` defaulting to lem. Production would also run a different binary from the auto-updated one. | Always pass `cli_path`, and add a test asserting the stub is what ran |
| **Handshake**: no `-p`; the prompt goes over stdin after an `initialize` control request | The current stub never answers, so every stubbed session hangs 60 s and fails; every `grep 'claude -p'` assertion breaks | A stub that answers `initialize`, reads the user frame and prints complete `init`/`result` frames (about 30 lines). A custom Transport would skip the options-to-argv step, losing the flag assertions. |
| `system_prompt=None` sends `--system-prompt ""` | Claude Code's own system prompt is wiped, including the model id `runtime_note` tells agents to cite | preset `claude_code` + `extra_args={"append-system-prompt-file": path}` |
| `setting_sources=None`, or any `skills=`, loads **user** settings | `ISOLATION_FLAGS` is undone: user plugins, hooks and memory reach the agent | Always set `setting_sources`; never use `skills=` |
| `env=` can't unset | The `anthropic` provider's `env -u ANTHROPIC_BASE_URL …` scrub can't be expressed | A `cli_path` wrapper that runs `env -u … claude "$@"` |
| `--autocompact`, `--append-system-prompt-file` | no fields | `extra_args` |
| An error result raises `ResultError`; a malformed frame raises `MessageParseError`; unknown frame types are dropped | Budget cut-offs and rejected rate limits arrive as exceptions. The renderer's "keep going past a bad line" is lost, and the raw `.jsonl` can't be rebuilt from parsed messages. | Catch and classify; subclass the transport to tee raw lines |
| One JSON line may be at most 1 MB by default | A large MCP result could kill the session | `max_buffer_size` |
| Dependencies | `mcp`, pydantic, starlette, uvicorn and more, plus a 225 MB platform wheel; a venv becomes mandatory | Only if the SDK is adopted |
| `guard.py` as a `--settings` command hook | Should still load, since `settings=` is passed through verbatim; not yet run live | One live run before relying on it |

**What the SDK would add** that bash can't easily do:
- typed results instead of greps on rendered text;
- `interrupt()` to stop a runaway session on a driver-side condition;
- `get_mcp_status()` to check that `dw` connected before spending a turn;
- in-process hook callbacks that could carry driver state instead of env vars and stamp files;
- `resume` by session id;
- `output_format` JSON schemas for the digest and the judge;
- cleanup of orphaned child processes.

None of these is needed for parity.

**Reading the table.** Most of the SDK's value is structured results, and a Python driver
reading `claude -p --output-format stream-json` already gets those with `json.loads`. Most
of its cost falls on the offline tests and the isolation flags. That is the basis for the
recommendation in decision 1.

## Pre-port fixes

These are independent of the port and worth doing in bash now. They're small, and each
removes something the port would otherwise copy.

1. **`HARNEST_HARNESS_REPO` is never exported.** `guard.py:357,429` always falls back to the
   literal `dkackman/harnest`.
2. **The retro never sees the Mac loop.** It reads only `loop.log` (`run-retro.sh:61`), so
   Mac sessions' costs, audit warnings and guard refusals are missing from it. A test's
   stated intent says they should be there.
3. **`run-features.sh` writes shared files with no server suffix.** `.last-session.features`
   and `.prompt.lead.<kind>.md` have none (`:78,93`). Only the `SHARED_PASSES` convention
   keeps a lem and a Mac features run from clobbering each other.
4. **Some variables leak into every later session.** `HARNEST_BASE_COMMIT`, `SUITE_EDITS` and
   `HARNEST_HELD_LOCK` are exported process-wide. It's harmless today, but it should be
   per-session.
5. **`run-digest.sh` bypasses the session path.** It has no stream-json, `usage:` line,
   rate-limit sleep or retry, so its cost is invisible to the retro and the dashboard.
6. **The dashboard reads `logs/release-*/gates.out`, and nothing writes it.**
7. **`providers.sh`'s header is stale.** Its note on which drivers accept `local` contradicts
   the code, its function list is missing about ten functions, and `target_default` has no
   caller.
8. **The four prompt cross-references** listed under "The prompt split".

## Decisions (accepted by Don, 2026-09-28)

1. **How sessions run in the port.**
   - **Accepted: Python first, SDK later.** The Python drivers keep running
     `claude -p --output-format stream-json` as a subprocess, with the same argv, so the stub,
     the flag assertions and `--append-system-prompt-file` all keep working. The package is
     stdlib-only, so no venv is needed. The SDK becomes a second implementation behind
     `harness/session.py`, adopted when a feature needs it (`interrupt`, hook callbacks,
     `get_mcp_status`).
   - This changes R8's scope. R8 is titled "port to the Agent SDK", and this makes the SDK
     an optional later phase. R8's title and "Done when" in `HARNESS-ROADMAP.md` were changed
     to match.
   - **Not taken: straight to the SDK.** This means building the protocol-speaking stub,
     the env wrapper, the raw-line transport and the venv up front.
2. **The vocabulary.** Rename harnest#15's "target" to "server" in code and file names, and
   keep `DW_TARGET` and the `target:` labels as they are, as proposed above.
3. **Packaging.** Put `targets/dw/` in this repo, and split it out when a second target
   exists. This is R13's own suggestion.
4. **The guard.** It stays a `--settings` command hook through R8, with its dw logic moved
   to profile values (`mcp.name`, backend labels, harness repo, the `handoff_gate` commands).
   Porting it to SDK callbacks is a separate change, after parity.
5. **Release.** `run-release.sh` becomes a dw target plug-in, not framework, and is ported
   last.
