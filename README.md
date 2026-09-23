# Harnest

Claude Code agents that improve [an MCP server](https://github.com/dkackman/diffusers-workflow)
by arguing through [its GitHub Issues](https://github.com/dkackman/diffusers-workflow/issues).

Two agents alternate:

- **Implementer:** has the source, SSH to `lem` (the box the server runs on), and the
  authority to change things.
- **Tester:** has none of that. It talks to the server only as an MCP consumer, the way a
  real user would, and reports what it finds.

The only channel between them is GitHub Issues. Because the tester can't read the code, a
fix can only convince it through the interface. A fix that reads correctly but doesn't
behave correctly gets sent back.

Two standalone agents sit outside the alternation:

- **Regression agent:** runs the growing `regression-suite-*.md` checks against the live
  server and files issues for failures and slowdowns.
- **Researcher:** turns `idea` issues into a plan, a rejection, or a question for Don.

This repo holds no application code, only the drivers, role prompts and regression suites.
[`HARNESS-ROADMAP.md`](HARNESS-ROADMAP.md) is the plan for where the harness goes next.

## How a cycle goes

```
┌─────────────┐   GitHub Issues     ┌─────────────┐
│ implementer │ ──────────────────▶ │   tester    │
│             │ ◀────────────────── │             │
│ source repo │                     │ MCP only    │
│ ssh lem     │                     │ qa-* spaces │
└──────┬──────┘                     └──────┬──────┘
       │ deploy                            │ tools/skills
       ▼                                   ▼
   ┌──────────────── dw MCP server on lem ────────────────┐
```

`run-loop.sh` repeats the following. Every session is a fresh `claude -p`, one per issue,
never one per role.

1. **Park outside filings.** An issue filed by any login other than `TICKET_OWNER` is
   parked for Don (`owner:don` + `status:needs-approval`). The repo is public, and nothing
   a stranger files is worked unattended.
2. **Implementer triage.** This runs when two or more issues are waiting. For each one it
   asks: is it a duplicate, already fixed on `develop`, or a restated `wontfix`? Should it
   be batched with a related issue? Would the fix add new engine or validation surface
   that a narrow verify can't cover? In that last case it escalates the issue to Don.
   Every outcome is recorded as a `triage:` comment.
3. **One implementer session per remaining issue.** The session reproduces the bug,
   fixes it on a branch, and merges to `develop`. It then deploys `develop` (never the
   branch) with one call: `ssh lem '~/diffusers-workflow/scripts/deploy.sh develop'`.
   `lem` can only be on one commit, and a cycle hands off several fixes, which is why only
   `develop` is deployed. The session ends by handing the issue to the tester with a
   comment saying what changed.
4. **One tester session per handed-off issue.** It reruns the repro and one or two nearby
   cases over MCP. It then either closes the issue as `verified` or sends it back with
   what's still wrong.
   - Every `TESTER_TASK_EVERY` cycles, a *task* session also moves forward a throwaway
     series in `qa-` workspaces ([`TESTER_TASK.agent.md`](agents/TESTER_TASK.agent.md))
     and files anything it hits.
   - On the cycles in between, a pending `wontfix`/`duplicate` closure gets its own
     short session, so the tester can accept it or reopen it once.
5. **Print a status board** queried live from GitHub, then start the next cycle. The
   driver sleeps only when a cycle left the board unchanged.

A few things the driver does so the sessions don't have to:

- **Prompt contents.** It puts the issue's title, labels, body and latest comments in each
  prompt, along with the commit `lem` is running. Comments by any login other than
  `TICKET_OWNER` are withheld.
- **Label check.** It checks an issue's labels just before starting its session, so an
  issue already handed off as part of a batch is skipped.
- **Keeping `lem` on `develop`.** It redeploys `develop` if `lem` is on anything else
  before the tester runs (`DEPLOY_ON_MISMATCH=0` only warns).
- **Bounce escalation.** After `IMPLEMENTER_ESCALATE_AFTER` bounces (default 2), an
  issue's next implementer session runs on the tester's model. After
  `IMPLEMENTER_PARK_AFTER` bounces (default 4), the driver parks the issue with Don
  instead, because the two roles aren't agreeing on what "fixed" means.

Nothing survives between sessions except what's written down: the issues, the suite files,
and the tester's `qa-bible.md`. `qa-bible.md` is a snapshot capped at about 12 KB (cast,
assets, episode ledger, house rules, next step), not a journal. The role prompts tell each
agent to leave a trail another session can resume from: a pushed branch plus a progress
comment. A session cut off by its spend cap is then picked up where it stopped.

## The ticket protocol

Tickets are GitHub Issues on `dkackman/diffusers-workflow`, filed with its "MCP agent-loop
ticket" template. Agents work on them only through `gh issue`.

- **`owner:*` is a baton.** An open issue has exactly one of `owner:implementer`,
  `owner:tester`, `owner:researcher` or `owner:don`, naming whoever acts next. An agent
  touches only issues with its own owner label, and only to act on them or hand them off.
- **Only the tester closes an issue as `completed`** (with `status:verified`), and only
  after a real MCP call in that session. The implementer never verifies its own fixes.
- **`wontfix`** is the implementer's call. It gives a reason and closes the issue as
  `not planned`. The tester may reopen once with new evidence, and a second `wontfix` is
  final. "Can't reproduce" goes through `status:needs-info` first.
- **`duplicate`** closes an issue as `not planned`, with `duplicate of #NN` in a comment.
  Closed issues still count when checking for duplicates. A reproducing `verified` issue is
  a regression to reopen, not a duplicate.
- **`status:needs-approval` + `owner:don`** parks an issue with the human. The
  implementer must use it for engine or syntax changes, new concepts consumers would have
  to learn, and breaking changes bigger than a rename, after writing a proposal in the
  source repo's `docs/proposals/`. Triage can escalate earlier, without a proposal. No
  agent touches a parked issue.
- **`breaking-change`** tells the tester to adjust its calls rather than file the change
  as a bug.
- **Commits** reference the issue (`fix(mcp): #42 - ...`), go on branches merged to
  `develop`, and never go to `master`.
- **No session polls or sleeps.** "Nothing to do" means the session exits.

```
open ──▶ status:fixed-pending-verify ──▶ status:verified (closed completed)
 ▲                    │
 └────────────────────┘  (tester bounces it back to owner:implementer)
open ──▶ status:needs-info ──▶ open
open ──▶ wontfix (closed not planned) ──▶ (tester accepts, or reopens once)
open ──▶ duplicate (closed not planned)
open ──▶ status:needs-approval + owner:don ──▶ open | wontfix   (human decides)
idea ──▶ owner:researcher ──▶ owner:implementer | owner:don | wontfix
```

GitHub is the only ticket history. Issues from before the 2026-09-12 migration that were
still active then were carried forward and cite "migrated from T0xx" in their body.

## The regression suite

`run-regression.sh` runs the regression agent. It uses the same consumer-only fence as the
tester, but it never hands work to anyone: it runs cases and reports failures on GitHub.
Each level has its own file and its own workspace, so levels never share fixtures or
affect each other's timings:

| level | file | workspace | what belongs there |
|---|---|---|---|
| `smoke` | `regression-suite-smoke.md` | `regression-smoke` | fast, fundamental, general-purpose; the default |
| `complete` | `regression-suite-complete.md` | `regression-complete` | general-purpose but slower or more edge-case; runs after `smoke` |
| `model-specific` | `regression-suite-model-specific.md` | `regression-model-specific` | tied to one video/image model or pipeline; opt-in |
| `security` | `regression-suite-security.md` | `regression-security` | hostile-input probes against the default security posture; opt-in, and its issues carry `security` |

```sh
./run-regression.sh                    # smoke (default)
./run-regression.sh complete           # smoke, then complete
./run-regression.sh security           # one opt-in level
./run-regression.sh all                # all four, once each
./run-regression.sh smoke my-suite.md  # override one level's file; workspace comes from the filename
```

- **Case IDs** carry a per-level prefix (`S-`/`C-`/`M-`/`SE-`). A case states its intent
  and expected result, and the agent checks the exact call shape against the live tool
  schema on every run.
- **Chunking:** a level runs as sessions of `CASES_PER_SESSION` consecutive cases, plus a
  final sweep that removes leftover artifacts. The default is 3 cases on a provider that
  declares a context window under 120k tokens, and 8 otherwise. Set it to `0` to run each
  level in one session.
- **Cleanup:** each case deletes what it generated once it and anything depending on it
  are done. What stays is the durable fixtures listed in the suite's "Fixtures" section
  and artifacts an open issue needs for a repro.
- **Performance:** `regression-perf/` holds one append-only JSONL file per case, recording
  each timing or declared metric, pass or fail. When no human has set a `baseline:`, a
  reading more than about 50% over the recent or all-time median is flagged. The format is
  in [`regression-perf/README.md`](regression-perf/README.md).
- **Who adds cases:** all three consumer-side paths grow the suites. The regression agent
  adds cases next to ones it already covers. The tester adds a case after verifying it
  over MCP. The implementer only *proposes* a case in its hand-off comment, because it
  doesn't have this repo and a case isn't confirmed until the tester runs it.
- **What's in a suite file:** only the durable test. A pass leaves no trace in the file,
  and a failure becomes an issue.
- **Removing a case:** no agent deletes or weakens one. The only route is a proposal filed
  on this repo, labeled `suite` + `status:needs-approval`.
- **Commits:** the driver commits suite and `regression-perf/` changes before and after
  every level. It flags any commit that removed lines.

Run it by hand, from cron, or with the `loop` skill. `run-loop.sh` and `run-regression.sh`
share a lock (`logs/.driver.lock`) and wait for each other, because an implementer deploy
would restart the server partway through a regression run.

## The researcher

`run-research.sh` gives each open `idea` issue (`owner:researcher`) its own session, on
`sonnet` by default. The session ends with one of three outcomes:

- a concrete plan, handed to `owner:implementer`;
- a rejection (`wontfix`);
- a question for Don (`owner:don` + `status:needs-approval`).

The researcher can read the source checkout but not write to it. It can also make read-only
`dw` discovery calls, use `gh issue`, and use `WebFetch` for links cited in the idea. It
has no SSH and no write access to git. It takes no driver lock, because it never changes
anything on the server.

## The replay benchmark

`run-bench.sh` measures the implementer against issues whose right answer is already known.
It re-runs the implementer on an issue from `bench/cases/`, starting at the `develop` commit
just before the real fix. The clone holds no later history and has no remote, and GitHub,
`lem`, MCP and the web are all denied. The script then scores the result four ways:
- new pytest failures;
- the real fix's tests run against the candidate;
- overlap with the files the real fix touched;
- a verdict (`pass`/`partial`/`fail`) from a separate Opus judge.

```sh
./run-bench.sh                              # all cases: sonnet, the working-tree prompt
IMPLEMENTER_MODEL=opus ./run-bench.sh       # a different model
BENCH_PROMPT_REV=<commit> ./run-bench.sh    # the implementer prompt as of a commit
./run-bench.sh --summary                    # pass rate, cost and turns per configuration
```

It never touches `lem`, so it takes no driver lock. See [`bench/README.md`](bench/README.md).

## Curation, retro, digest and contract cases

These are standalone, read-only drivers. Each one proposes changes and never applies them;
a human approves.

- **`run-curate.sh [level]`** runs one Opus session per regression level. It reads the
  suite, its perf history and what recent runs cost per chunk, then files one issue on this
  repo (`suite` + `status:needs-approval`) of proposed moves, merges, contradictions, stale references and retirements
  against a per-level budget. A level is skipped for 7 days after a run, or while its last
  curation issue is still open.
- **`run-retro.sh`** reads the logs since the last retro and files up to three evidenced
  proposals on this repo, labeled `harness` + `status:needs-approval`. The logs cover
  cost per role, denials, guard refusals, audit warnings, bounces and bench results.
  `RETRO_EVIDENCE_ONLY=1` prints the evidence without running a session.
- **`run-digest.sh`** writes one line per `owner:don` issue: the ask, a recommendation and
  the command that carries it out, plus the median days parked. It writes
  `logs/digest.md`; `DIGEST_ISSUE=N` also posts it on issue N.
- **`contract/run.py`** runs mechanical cases as a plain MCP client, with no LLM.
  `run-regression.sh` uses it for any suite case marked `runner: script`. See
  [`contract/README.md`](contract/README.md).

## Running it

```sh
./run-loop.sh                                   # forever
MAX_CYCLES=1 ./run-loop.sh                      # one cycle, then stop
ONLY_ISSUES=227 ./run-loop.sh                   # work only #227 (comma-separate for more)
IMPLEMENTER_MODEL=haiku SLEEP_SECS=60 ./run-loop.sh
tail -f logs/loop.log                           # watch from another terminal
```

**Preconditions:**
- `claude` and `gh` on `PATH`, with `gh` authenticated as `TICKET_OWNER`.
- Passwordless `ssh don@lem`.
- The agents' own clone at `SOURCE_DIR`: run `git clone -b develop
  https://github.com/dkackman/diffusers-workflow.git ~/src/dkackman/dw-agent`, then
  `bash ./install.sh` inside it. This is not your working checkout.
- On `lem`: the dw repo's `scripts/deploy.sh`, with the server running under the
  `dw-serve` systemd user unit. The script falls back to a `screen` session if the unit
  isn't installed.

| var | default | what |
|---|---|---|
| `SOURCE_DIR` | `~/src/dkackman/dw-agent` | agents' clone of the dw repo, with its own `venv`; the implementer's and researcher's cwd |
| `PLUGIN_TREE` | `~/src/dkackman/dw-agent-plugin` | detached worktree reset to `origin/develop`; where the tester and regression agent load the `dw` plugin from |
| `TICKET_REPO` / `TICKET_OWNER` | `dkackman/diffusers-workflow` / `dkackman` | where the tickets live; the only login whose issues and comments are trusted |
| `DW_URL` / `DW_TOKEN` | `http://lem:8765/mcp` / `xyz` | the MCP endpoint (dev token, LAN only) |
| `PROVIDER` | `anthropic` | `anthropic`, `ollama` or `gateway`; see below |
| `IMPLEMENTER_MODEL` / `TESTER_MODEL` | `sonnet` / `claude-opus-5-5` | per-role models (tester pinned to the exact id, not the `opus` alias); each has a `*_PROVIDER` defaulting to `$PROVIDER` |
| `TRIAGE_MODEL` / `TRIAGE_PROVIDER` | the tester's | triage is strong by default: a wrong `wontfix`/`duplicate` never bounces back |
| `REGRESSION_MODEL` / `RESEARCH_MODEL` | `sonnet` / `sonnet` | standalone drivers; same `*_PROVIDER` pattern |
| `EFFORT` | `medium` | `--effort` for every role; override per role with `IMPLEMENTER_`/`TESTER_`/`TRIAGE_`/`REGRESSION_`/`RESEARCH_EFFORT` (triage follows the tester's) |
| `IMPLEMENTER_BUDGET_USD` / `TESTER_BUDGET_USD` / `TRIAGE_BUDGET_USD` | `8` / `5` / `3` | `--max-budget-usd` per session; `0` = uncapped |
| `REGRESSION_BUDGET_USD` / `RESEARCH_BUDGET_USD` | `6` / `3` | per regression chunk / per research session |
| `AUTOCOMPACT_TOKENS` | `120000` | `--autocompact` for every session |
| `TESTER_TASK_EVERY` | `4` | run the tester's standing-task session every Nth cycle |
| `IMPLEMENTER_ESCALATE_AFTER` / `IMPLEMENTER_PARK_AFTER` | `2` / `4` | bounces before escalating to the tester's model / parking with Don; `0` = never |
| `DEPLOY_ON_MISMATCH` | `1` | redeploy `develop` if `lem` is on anything else before the tester pass; `0` = warn only |
| `ONLY_ISSUES` | unset | restrict a cycle to these issue numbers |
| `CASES_PER_SESSION` | 3 or 8 | `run-regression.sh` only; see above |
| `FALLBACK_MODEL` | unset | `--fallback-model`; must be servable by the role's provider |
| `SESSION_RETRY_PAUSE_SECS` | `30` | a session that ends without a result is retried once; a rejected rate limit instead sleeps the driver until the reset |
| `CO_AUTHOR` / `CO_AUTHOR_EMAIL` | derived | override the commit trailer on suite edits |
| `SLEEP_SECS` / `MAX_CYCLES` | `120` / `0` | pause after an idle cycle; `0` = run forever |

### Models and providers

Each role has its own model setting, because which roles may run a weak model is a design
decision:

- **Keep the tester on a strong model.** Its verdict gates everything else, and a weak
  verifier fails silently by approving fixes it can't really judge.
- **The implementer is safe to vary.** Its mistakes show up in its patches and get
  bounced. It does hold SSH and auto-mode shell access, so an unvetted model there is a
  different kind of risk.
- **The regression agent is the measured exception.** It executes written cases rather
  than judging fixes. On 2026-09-21, the same smoke run cost $17.85 on Sonnet against
  $32.64 on Opus, with no loss in what was filed.

`providers.sh` is the one table that maps a provider to the environment its `claude`
process needs:

| provider | what it is |
|---|---|
| `anthropic` | Native Claude models, as an alias (`opus`, `sonnet`, `haiku`, `fable`, `opus[1m]`) or a full id. Clears any ambient `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_DEFAULT_*_MODEL`, so the label is true. Rejects non-Claude names. |
| `ollama` | A local or Ollama-cloud tag. Ollama serves the Anthropic Messages API at `/v1/messages`, so no proxy is needed. Requires `OLLAMA_CONTEXT_TOKENS`. Rejects Claude names. |
| `gateway` | Anything else speaking the Messages API (LiteLLM, claude-code-router, …). Requires `GW_BASE_URL`, and never falls back to an ambient one. |

Under a provider other than `anthropic`, name every role that runs, because a Claude alias
can't be served there:

```sh
PROVIDER=ollama OLLAMA_CONTEXT_TOKENS=65536 \
  IMPLEMENTER_MODEL=gemma4:31b-it-q4_K_M TESTER_MODEL=gemma4:31b-it-q4_K_M ./run-loop.sh
```

**Ollama settings.** For `ollama`, `providers.sh` sets what `ollama launch claude` would
set, without writing that command's global `~/.ollama/config.json`. On top of that it sets
two more:

- `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, from `OLLAMA_CONTEXT_TOKENS`. Without it, Claude Code
  assumes a 200k window. The server's `OLLAMA_CONTEXT_LENGTH` (or `num_ctx`) must be at
  least this value, or the server silently truncates. 64k is Ollama's own recommendation.
- `ENABLE_TOOL_SEARCH=true`, because MCP tool search is off by default for base URLs that
  aren't Anthropic's, and this harness is almost entirely MCP calls.

The other provider settings are `OLLAMA_BASE_URL` (default `http://127.0.0.1:11434`),
`OLLAMA_TOKEN` (a dummy token, so no real key is sent), and `OLLAMA_STRICT_SUPPRESS` (for
models that reject thinking, caching or beta fields). For `gateway` they are `GW_TOKEN`
(without it, the ambient `ANTHROPIC_API_KEY` is sent) and `GW_CONTEXT_TOKENS`.

**Provenance.** Each prompt states the model and provider the session runs as. Agents
must name the exact model id in every comment they write, because a verification is only
worth what the model behind it was. Suite-edit commits carry a trailer with the resolved
id:
- `Claude (<id>) <noreply@anthropic.com>` for a Claude model;
- `<model> (via <provider>) <noreply@localhost>` for anything else.

"Model-specific" in the regression suite means the *video* model, not the LLM.

## Isolation and permissions

No agent runs with `--dangerously-skip-permissions`. A headless session never prompts: a
call that would have prompted is denied, and the denial comes back to the agent. What
differs by role is what gets approved automatically.

- **Tester and regression agent:** `--permission-mode dontAsk` plus an explicit allowlist
  (`CONSUMER_PERMISSION_FLAGS`). It allows:
  - `mcp__dw__*`, except `delete_model` and `update_diffusers`, which are denied outright;
  - the `dw` skills;
  - `gh issue` and nothing else from `gh`, since `gh api` or `gh repo clone` would expose
    the source;
  - file tools for the suite files and `qa-bible.md`;
  - a few read-only shell helpers.

  There's no `ssh`, `curl`, `python`, or `git` write; the drivers commit suite edits
  themselves. The one gap is that `Read`/`Edit`/`Write` can't be limited by path, so the
  prompts cover it. If a legitimate need is denied, widen the list on purpose.
- **Implementer:** `--permission-mode auto`. Its shell use (`git`, `gh`, `ssh lem`,
  `pytest`, `uv`, …) can't be listed up front, so the classifier approves routine work and
  denies destructive or exfiltrating actions. The classifier's description of the
  environment is [`agent-settings/implementer.json`](agent-settings/implementer.json),
  passed with `--settings`.
- **Researcher:** `dontAsk` plus `RESEARCHER_PERMISSION_FLAGS`: read-only source,
  read-only git, read-only `dw` discovery, `gh issue` and `WebFetch`.

**Guard hooks.** A `PreToolUse` hook,
[`agent-settings/hooks/guard.py`](agent-settings/hooks/guard.py), refuses the protocol
violations that are cheap to spot on a command line, at the moment of the call. The agent
gets the reason back and can correct itself, rather than the audit finding it later.
- The implementer can't close an issue as `completed`, add `status:verified`, lift an
  `owner:don`/`status:needs-approval` park, push to `master`, or force-push.
- The implementer can't hand off (`status:fixed-pending-verify`) with uncommitted changes,
  with `ruff` failing on files it changed, or with a test failing that passed on `develop`
  when the session began. The driver exports that commit as `HARNEST_BASE_COMMIT`.
- The tester and regression agent can't close as `completed` or add `status:verified` in a
  session that has made no `mcp__dw__*` call.
- No role can add an `owner:*` label without removing one in the same command.

The hook is wired through `agent-settings/implementer.json` and
`agent-settings/consumer.json`. It matches command text, so it catches mistakes, not a
determined workaround; the audit is still the backstop.

**What sessions don't get.** Every session runs with `--setting-sources project,local` and
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, so no user-level plugins, hooks, memory or MCP servers
reach an unattended agent. `--tools` limits each role to the built-in tools it uses.
`--mcp-config` together with `--strict-mcp-config` gives each role only the `dw` server,
with no account-level connectors. The tester and regression agent load the `dw` plugin
with `--plugin-dir` from `PLUGIN_TREE`, which the driver resets to `origin/develop` (the
commit `lem` runs) before every tester pass. A skill fix is therefore testable in the cycle
it merges.

That leaves two deploy paths, and the implementer says which one a fix used:
- **Server code:** merge to `develop`, then deploy `develop` on `lem`.
- **Plugin or skill changes:** merge to `develop` and push, with no restart needed.

## Watching

Everything streams to the terminal and to `logs/loop.log`, prefixed by session:
`[implementer:triage]`, `[implementer:#145]`, `[tester:#145]`, `[tester:task]`,
`[tester:closures]`, `[regression:smoke.2]`, `[regression:smoke.sweep]`,
`[researcher:#N]`. Each role also has its own `.log` and a `.jsonl` of the raw events.

- `grep usage: logs/loop.log`: one line per session, with turns, duration, cost, peak
  context and token totals. Each session also logs a `model:` line with the resolved id.
- `grep '\[audit\]' logs/loop.log`: drift from the protocol, checked after each session.
  It flags an open issue without exactly one `owner:*` label, a `completed` close by
  anyone but the tester, and a suite commit that removed lines. The audit only logs; it
  repairs nothing.
- After every cycle, the driver prints a status board with one line per open issue:
  number, status, owner and title.

## Layout

```
run-loop.sh                         implementer/tester driver
run-regression.sh                   regression driver
run-research.sh                     researcher driver
run-bench.sh                        replay benchmark of the implementer (offline)
run-curate.sh                       suite curation: one owner:don proposal issue per level
run-retro.sh                        retro: evidenced harness proposals, filed on this repo
run-digest.sh                       one-line-per-issue digest of the owner:don queue
contract/                           script-run regression cases and their MCP client
bench/                              benchmark cases, replay note, results (see bench/README.md)
providers.sh                        provider table and shared helpers (isolation, permissions, logging, audits)
measure-base-ctx.sh                 measures turn-1 context for a flag set
agent-settings/implementer.json     auto-mode classifier's picture of the implementer's environment, plus its guard hook
agent-settings/consumer.json        tester/regression guard hook
agent-settings/hooks/guard.py       the guard (protocol invariants and the hand-off gate)
agents/
  IMPLEMENTER.agent.md              implementer role, including triage
  TESTER.agent.md                   tester role
  TESTER_TASK.agent.md              the tester's standing exercise
  REGRESSION.agent.md               regression agent role
  RESEARCHER.agent.md               researcher role
  CURATOR.agent.md                  suite curator role
  RETRO.agent.md                    retro role
regression-suite-{smoke,complete,model-specific,security}.md
regression-perf/                    append-only per-case metric history (JSONL)
HARNESS-ROADMAP.md                  planned evolution of the harness
CLAUDE.md                           notes for Claude Code sessions working on this repo
qa-bible.md                         tester's memory across cycles (gitignored)
logs/                               session output (gitignored)
```
