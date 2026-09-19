# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Not an application — an orchestration harness for two Claude Code agents that iterate on the
`diffusers-workflow` MCP server in strictly alternating cycles, communicating through GitHub
Issues (see "Ticket protocol" below) and, for regression coverage, the `regression-suite-*.md`
files described below. There is no build, lint, or test step.

- `run-loop.sh` — the driver. Runs the implementer's sessions, then the tester's, then prints a
  ticket status board; repeats. Sessions are **per issue, not per role**: the implementer gets a
  short triage session when 2+ issues wait (dispositions each with a `triage:` comment, which
  is also where related issues get batched into one fix), then one fresh `claude -p` per
  remaining issue; the tester gets one per `status:fixed-pending-verify` issue, plus a "task"
  session (closure responses + one `TESTER_TASK.agent.md` step) every `TESTER_TASK_EVERY` cycles
  (default 2). The driver re-checks an issue's labels right before its session so one already
  handed off by a batch is skipped. Every session runs with `--max-budget-usd`
  (`IMPLEMENTER_BUDGET_USD`/`TESTER_BUDGET_USD`/`TRIAGE_BUDGET_USD`, defaults 8/5/3, 0 = none)
  and `--autocompact $AUTOCOMPACT_TOKENS` (default 120k). The reason is measured, not
  theoretical: one six-issue implementer session ran 269 turns to a 352k-token peak and 60M
  cached-input tokens, $37, because issue six re-read issues one to five on every turn. No
  state survives between sessions except what's written to GitHub Issues (or, per each role
  prompt's "Adding a case" step, a `regression-suite-*.md` file) — the role prompts tell each
  agent to leave a resumable trail (branch pushed, progress comment) so a budget cut-off is
  picked up by the next session rather than lost.
- `providers.sh` — sourced by both drivers. The one table mapping a (provider, model) pair to the
  environment its `claude` process needs: `anthropic` (native — the default; sets nothing but
  scrubs ambient `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_DEFAULT_*_MODEL` via
  `env -u` so the label can't lie), `ollama` (local or Ollama-cloud tags; no proxy needed,
  since Ollama serves the Anthropic Messages API itself at `/v1/messages`; requires
  `OLLAMA_CONTEXT_TOKENS`), and `gateway` (anything else speaking that API; requires
  `GW_BASE_URL`). Each branch rejects a model name that doesn't fit the provider (a
  non-Claude name under `anthropic`, a Claude name under `ollama`) at startup. It also holds
  the helpers both drivers share: `validate_fallback_model`/`fallback_model_flags`,
  `co_author_for` (commit-trailer identity), `runtime_note` (the per-role "Runtime:" prompt
  paragraph), and `commit_suite_changes` (commits only `regression-suite-*.md` and
  `regression-perf/`). It also holds what every session leaves *out*: `ISOLATION_FLAGS`
  (`--setting-sources project,local` — no user-level plugins, hooks, memory or MCP servers
  reach an unattended agent; measured 2026-09-19, those were ~12 KB of SessionStart hook
  text per session, and the `remember` plugin was capturing agent sessions into Don's own
  memory and re-injecting them), `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` exported alongside it
  (auto-memory isn't a settings source; the implementer had been reading *and writing* Don's
  project memory under the source checkout), the per-role `--tools` lists (`CONSUMER_TOOLS`/
  `RESEARCHER_TOOLS`/`IMPLEMENTER_TOOLS` — only the built-in tools a role has ever used; the
  ~20k tokens of Artifact/Workflow/Agent/... schemas a role is denied anyway no longer ride
  on every turn), and `effort_flags` with the `EFFORT` default (`medium`, what sessions ran
  at while it was inherited from user settings; per-role `*_EFFORT` knobs in each driver).
  `measure-base-ctx.sh` is how a flag set's turn-1 context is measured before and after a
  change like this.
  Model choice is one knob per role: `IMPLEMENTER_MODEL` (default `sonnet`), `TESTER_MODEL`
  (`opus`), `REGRESSION_MODEL` (`opus`), `RESEARCH_MODEL` (`sonnet`), each with a `*_PROVIDER`
  that defaults to `PROVIDER` (`anthropic`). The implementer's triage session is the one
  exception: `TRIAGE_MODEL`/`TRIAGE_PROVIDER` default to the *tester's*, not the
  implementer's, because a wrong `wontfix`/`duplicate`/park call never bounces back — it
  just disappears — and the session is short and capped, so the strong model costs almost
  nothing there. Which role may run a weak model is a design decision (see "Running"), so
  the defaults are per role. Under a non-anthropic `PROVIDER`
  every role that runs must be named explicitly, since a Claude alias can't be served there
  and `resolve_model_env` rejects it at startup.
- `agents/IMPLEMENTER.agent.md` — role prompt for the agent with source access and SSH to the
  `lem` box where the MCP server runs. It executes with cwd = the source checkout (`SOURCE_DIR`).
- `agents/TESTER.agent.md` — role prompt for the agent that talks to the MCP server *only* as a
  protocol consumer. It executes with cwd = this repo, which contains no code. That cwd split
  plus an enforced tool allowlist (`CONSUMER_PERMISSION_FLAGS` in `providers.sh`, see
  "Permissions" below) is the basis of the tester's isolation.
- `agents/TESTER_TASK.agent.md` — the tester's standing exercise: a throwaway series built in
  `qa-`-prefixed workspaces so it finds bugs in use, not just by re-verifying fixes. Not a
  deliverable; never touches the default workspace.
- `agents/REGRESSION.agent.md` / `run-regression.sh` — a third, standalone agent (not part of
  the implementer/tester alternation) that runs the growing suite against the live MCP server
  and files/comments on GitHub Issues for failures and performance regressions. Same
  consumer-only isolation as the tester; ends by posting to GitHub, no back-and-forth with the
  implementer. The suite is split one file per level, each with its own workspace so levels
  never share fixtures or skew each other's timings: `regression-suite-smoke.md` (workspace
  `regression-smoke`, fast/fundamental/general-purpose, the default), `regression-suite-complete.md`
  (workspace `regression-complete`, general-purpose but broader/slower, runs on top of `smoke`),
  `regression-suite-model-specific.md` (workspace `regression-model-specific`, niche, tied
  to one model/pipeline, opt-in only), and `regression-suite-security.md` (workspace
  `regression-security`, opt-in only: hostile-input probes run on the server's default
  security posture — arbitrary-code gates on introspection-based instantiation, path
  containment, URL scheme/host policy, secret disclosure, destructive scope. Its issues also
  carry the `security` label. Its header defines "refused too late" as a failure, and lists
  what a consumer-only agent can't cover, which belongs in the dw repo's pytest suite).
  `./run-regression.sh [level] [suite-file]` picks the level (default `smoke`; `complete`
  also runs `smoke` first; `all` runs all four, once each) and
  optionally overrides just that level's suite file (its workspace is then derived from the
  override's filename, never the canonical one, so a one-off suite can't delete another suite's
  fixtures). Case IDs are prefixed per level (`S-`/`C-`/`M-`/`SE-`) so the same number in two files
  never collides in the regression agent's duplicate-issue search. A level runs as a series of
  sessions of `CASES_PER_SESSION` consecutive cases plus a final sweep-only session (the role
  prompt's "Chunked runs" section says how a slice honours `cleanup:` lines that cross its
  boundary). It defaults to 3 when the provider declares a context window under 120k tokens
  (`MODEL_CONTEXT_TOKENS` from `providers.sh`), 8 otherwise (including under Anthropic, which
  declares no window here) — a 40-50 KB suite read whole plus twenty cases of tool output is
  what put 64k Ollama models into auto-compact thrashing, and a full suite's tool output alone
  can clear the 120k autocompact threshold before the last case even on a 200k-window model.
  Set `CASES_PER_SESSION=0` explicitly to force one session per level. Each run deletes what its
  cases generate as soon as a case (and any dependent case) is done, keeping only durable
  fixtures listed in that suite file's "Fixtures" section (workflows/assets reused across runs)
  and artifacts an open issue needs for a repro; a final sweep removes anything else. All three
  suite files are checked in (not gitignored) — they're the deliverable. `run-regression.sh`
  commits any pending changes to them before and after every level it runs, so edits made
  outside a regression run (see below) aren't lost or misattributed. The regression agent grows
  the suites over time as it finds adjacent functionality worth covering; the implementer and
  tester grow them too, but not the same way — the implementer only *proposes* a case in its
  issue hand-off comment (it doesn't have this repo checked out, and a case shouldn't be recorded
  as confirmed behavior before the tester verifies it over MCP); the tester adds the case for
  real once it verifies. Either role picks whichever suite file fits (same format, plus a
  `source:` line) — see each suite file's own "Adding a case" section for the line between
  levels. Invoke the regression agent by hand, from cron, or via the `loop` skill; it never loops
  or sleeps internally. Suite files hold only the durable test — intent, expected result,
  cleanup — never a running log of results: a case is expected to keep passing, so a pass leaves
  no trace in the file, and a failure is a GitHub Issue, not a note appended to the case. None of
  the three agents may delete or rewrite a case to make it go away, however expensive or
  low-value it looks from a single run; the only route to removing one is a comment/issue
  proposing it, labeled `owner:don` + `status:needs-approval`, left for a human to act on.
  Measurements are the complement of that rule, not an exception to it: `regression-perf/`
  holds one append-only JSONL per case (`S-P001.jsonl`, …; format in its `README.md`) where
  the regression agent records every `-P` case's timing and any metric a functional case
  declares with a `metrics:` line (a payload size, a count), pass or fail. That is what makes
  "regression" a comparison rather than a feeling: with `baseline:` left `TBD` — the norm,
  since no human ever set one — the agent flags a reading more than ~50% over the median of
  the last 5 entries *or* of the full history for the same metric+condition (the second
  catches slow creep); a human-set `baseline:` is a hard ceiling on top. Per-case files so an
  agent reads only the history it needs, never the whole log. Checked in and committed by
  the drivers alongside the suite files (#135 is where the old "record it in `last run:`"
  instruction met the no-edit-on-pass rule and this replaced both).
- `agents/RESEARCHER.agent.md` / `run-research.sh` — a fourth, standalone
  agent (not part of the implementer/tester alternation, and not the
  regression agent) that turns an `idea`-labeled GitHub Issue into a
  disposition: reject it (`wontfix`), propose a concrete plan to the
  implementer (`owner:implementer`, ready to work), or park it for Don's
  input (`owner:don` + `status:needs-approval`). It is read-only against the
  `diffusers-workflow` source checkout (no write, no SSH to `lem`) plus
  read-only `dw` MCP discovery calls and `gh` for issue management — a third
  isolation shape distinct from both the implementer's full access and the
  tester/regression agent's MCP-consumer-only fence. `./run-research.sh`
  gives each open idea issue its own fresh session (never one long session
  across issues, to keep context from accumulating across a batch), by
  default on `sonnet` — deep feasibility judgment is
  expected to land with the implementer pass and, where parked, Don.
- Tickets live as **GitHub Issues** on `dkackman/diffusers-workflow` (not in this repo) — both
  agents act on them with the `gh` CLI, already authenticated on this machine. Filed with the
  "MCP agent-loop ticket" template (`.github/ISSUE_TEMPLATE/mcp-ticket.md` in that repo). Tickets
  filed before the 2026-09-12 migration to Issues were carried forward there too (see "Ticket
  protocol" below); GitHub is the only ticket history now. `logs/` — per-agent and combined
  output, gitignored. Every driver runs `claude -p` in stream-json mode through
  `render_stream` (`providers.sh`), so `<role>.log`/`loop.log` show each tool call, each tool
  result's size, a `· ctx=Nk` line per model turn, and a final `usage:` line (turns, duration,
  cost, peak context, token totals) per session — `grep usage: logs/loop.log` is how to see
  which role and cycle spent the budget; the raw events are kept in `<role>.jsonl`. The tester
  also keeps `qa-bible.md` here (gitignored) as its memory across
  cycles — a snapshot (cast, assets, workspaces, episode ledger, current house rules, next step)
  capped at ~12 KB by `TESTER_TASK.agent.md`, not a journal; per-cycle narrative belongs on the issues.

## Running

```sh
./run-loop.sh                          # forever; SOURCE_DIR defaults to ~/src/dkackman/diffusers-workflow
MAX_CYCLES=3 SLEEP_SECS=60 ./run-loop.sh                # three cycles, then stop
TESTER_MODEL=opus IMPLEMENTER_MODEL=haiku ./run-loop.sh # per-role models (defaults opus / sonnet)
PROVIDER=ollama IMPLEMENTER_MODEL=qwen2.5:32b TESTER_MODEL=qwen2.5:32b ./run-loop.sh   # non-Anthropic: name every role
IMPLEMENTER_BUDGET_USD=0 TESTER_TASK_EVERY=1 ./run-loop.sh   # no implementer cap; standing task every cycle
tail -f logs/loop.log                  # combined stream, prefixed [implementer:#145] / [tester:task] etc.
grep usage: logs/loop.log              # one line per session: turns, duration, cost, peak context
TESTER_EFFORT=high REGRESSION_EFFORT=high ./run-loop.sh   # per-role --effort (default medium)
./measure-base-ctx.sh lean --setting-sources project,local --tools "Bash,Read,Edit,Write,Glob,Grep,ToolSearch,Skill,TodoWrite"   # turn-1 context of a flag set
```

Which roles may run a weak model is a design decision, not a config detail: the tester's
independence is the whole point, and a weak tester degrades that silently by rubber-stamping, so
vary the implementer (its mistakes show up in its patches) and keep the tester and the regression
agent on a strong model. Each agent's prompt now states the model and provider it is running as,
and each role prompt requires the agent to name them in the comments it writes — a fresh session
is otherwise unidentifiable afterwards, and a verification is only worth what the model behind it
was. Suite-edit commits are attributed by trailer, honestly: a non-Anthropic model gets
`<model> (via <provider>)`, not a Claude name and an anthropic.com address.

The loop sleeps only when a cycle left the ticket board unchanged; if either agent's issue
activity changed it, the next cycle starts immediately. (Whether an agent also appended a
regression case in the same cycle isn't part of that check.)

The tester's directory has no MCP config, so `run-loop.sh` hands it the `dw` server via
`--mcp-config` + `--strict-mcp-config` (it sees *only* `dw`) and loads the `dw` plugin live from
`$SOURCE_DIR/plugins/dw` via `--plugin-dir`. Without the latter it would use the frozen copy in
`~/.claude/plugins/cache` and never see skill fixes. The implementer gets the same
`--mcp-config` + `--strict-mcp-config` pair (not `--plugin-dir`; it works from the source tree).
Its checkout already has `dw` at local scope in `~/.claude.json`, so the flags change nothing
about `dw` — they exist to drop the account-level claude.ai connectors (Gmail, Drive, Calendar)
that every unrestricted session inherits, which an unattended agent must not hold. The same
paragraph of flags now also drops user-level settings entirely (`ISOLATION_FLAGS`) — the
implementer's own `--append-system-prompt-file` role prompt and `--settings` file are what
it runs on. Both roles see MCP tools as deferred names (schemas load on first use), so the
`dw` surface costs each session well under 2k tokens at connect; per-call result size is the
real budget (see issue #101).

## Permissions

No agent runs with `--dangerously-skip-permissions`. A headless `claude -p` session never
prompts — a call that would have prompted is denied and the denial comes back to the agent as a
tool result — so the choice is what gets auto-approved vs. auto-denied, per role:

- Tester and regression agent: `--permission-mode dontAsk` + an explicit `--allowedTools` list
  (`CONSUMER_PERMISSION_FLAGS` in `providers.sh`): `mcp__dw__*`, the dw skills, `gh`, file tools
  for the suite files and `qa-bible.md`, and a few read-only shell helpers. No `ssh`, `curl`,
  `python`, or `git` writes (the drivers commit suite edits themselves). This is what makes
  consumer-only isolation enforced rather than honor-system; the remaining gap is that
  `Read`/`Edit`/`Write` aren't path-scoped, which the role prompts cover. If a cycle shows a
  denial in `logs/tester.log` for something the role legitimately needs, widen the list there,
  deliberately, rather than reaching for the bypass flag.
- Implementer: `--permission-mode auto`. Its shell surface (`git`, `gh`, `ssh lem`, `pytest`,
  `uv`, …) can't be enumerated without breaking a cycle the first time it needs something new,
  so the auto-mode classifier approves routine work and denies destructive or exfiltrating
  actions. The classifier's picture of the environment (trusted repo, `lem`, what "routine"
  means here) is `agent-settings/implementer.json`, passed via `--settings`; it used to be
  inherited from user settings and described a different checkout.
- Researcher: `--permission-mode dontAsk` + `RESEARCHER_PERMISSION_FLAGS`
  (`providers.sh`) — read-only against the `diffusers-workflow` source
  checkout (`Read`/`Grep`/`Glob`, read-only `git`) plus read-only `dw` MCP
  discovery calls, `gh`, and `WebFetch` (to follow links cited in idea
  issues). No `Edit`/`Write` on source, no write `git` subcommands, no
  `ssh`, no `curl`. A third isolation shape: unlike the tester/regression
  agent it does see source, and unlike the implementer it can never change
  it.

Two deploy paths, and the implementer must say which one a fix used: server code → restart on
`lem`, tool schemas refresh automatically; plugin/skill changes → commit and leave the checkout
on that branch, no restart.

## Ticket protocol (the core of the design)

Tickets are **GitHub Issues on `dkackman/diffusers-workflow`**, not entries in a file in this
repo. Both agents act on them with the `gh` CLI (`gh issue create` / `edit` / `comment` /
`close` / `list`). The invariants both role prompts and the status-board query depend on:

- `owner` is a label, exactly one of `owner:implementer` / `owner:tester` /
  `owner:don` / `owner:researcher` at a time — whoever's turn it is to act
  next. Swap it with `gh issue edit <n> --remove-label owner:X --add-label
  owner:Y`. An agent only touches issues carrying its own owner label and
  never edits another agent's issue beyond the label/comment that hands it
  off. An `idea`-labeled issue starts as `owner:researcher`; the researcher
  agent (see above) moves it to `owner:implementer` (proposal ready to
  work) or `owner:don` + `status:needs-approval` (parked for input), or
  closes it `wontfix`, same conventions the implementer/tester already use.
- Status flow: no status label ("open", ready for the implementer) → (implementer fixes +
  deploys to `lem`) → `status:fixed-pending-verify` → (tester re-runs repro over MCP) → close the
  issue as `completed` with `status:verified` added, or back to no status label / owner back to
  `owner:implementer`. `status:needs-info` is a question bounce. `wontfix` (GitHub's built-in
  label) is the implementer's call, reason in a comment, issue closed as `not planned`; the
  tester may reopen it once with new evidence, and a second `wontfix` is final. `duplicate`
  (GitHub's built-in label) closes an issue as `not planned` in favour of another, named in a
  comment (`duplicate of #NN`). `status:needs-approval` + `owner:don` parks an issue with the
  human — the implementer must use it for engine/syntax changes and anything breaking beyond a
  rename, after writing a proposal; neither agent touches a parked issue. The triage session
  (see below) applies the same label earlier and more cheaply, before any fix is built: when an
  issue's own text suggests the fix would add new engine or validation surface (a new
  task/command, a new `validate_workflow` rule, widening an existing task's argument matrix)
  where a narrow repro-only verify is likely to pass while untested edge cases underneath it
  don't, triage escalates it straight to `owner:don` + `status:needs-approval` with a `triage:
  escalate` comment, no proposal required at that point — for Don to assess and either approve,
  ask for a proposal, or route out of band. It is also where any
  issue filed by a GitHub login other than `TICKET_OWNER` (default `dkackman`) lands: both agents
  run as that login, so their own filings pass, but a third party filing on the public repo must
  not be picked up unattended. `run-loop.sh` (`park_external_issues`) relabels such issues
  `owner:don` + `status:needs-approval` with an explanatory comment before every cycle, and the
  implementer's triage repeats the check; only a human hands one back in. The implementer
  triages every issue for duplicates and fixes already on `develop`/`lem` before reproducing,
  checking both open and closed issues (`gh issue list --state all`) — a closed issue is still
  canonical for duplicate detection. But a closed issue carrying `status:verified` is a prior fix,
  not a standing "already handled" — if the repro still reproduces against current `develop`/`lem`,
  that's a regression, not a duplicate: reopen the old issue (or link a new one to it) and fix it,
  never close the new report as `duplicate`/`wontfix` on the strength of the old verification alone.
  Only the tester may close an issue as `completed` (`verified`), and only from a real MCP call.
- Implementer commits reference the issue number (`fix(mcp): #42 - ...`), works on branches
  merged to `develop`, never `master`.
- Breaking MCP interface changes get the `breaking-change` label plus a comment, so the tester
  adjusts its calls rather than filing the change as a new bug.
- Agents never poll or sleep inside a session; "nothing to do" means exit and let the driver
  re-run them. Because cycles are serialized, server restarts can't collide with tester calls.
- Tickets filed before 2026-09-12 lived in `mcp-feedback.md` / `mcp-feedback-archive.md` in this
  repo; the ones still active then were carried forward as fresh Issues (#69–#79), cited in
  their body as "migrated from T0xx" so old cross-references still resolve. Those files have
  since been removed — GitHub is the sole ticket history, including everything that predates
  the migration.

When editing either role prompt, keep the asymmetry intact: any change that gives the tester
code or box access, or lets the implementer self-verify, defeats the purpose of the setup.
The status board in `run-loop.sh` queries `gh issue list --json number,title,labels`, so keep
the `owner:*` / `status:*` label prefixes if you change the label scheme.
