# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Not an application — an orchestration harness for two Claude Code agents that iterate on the
`diffusers-workflow` MCP server in strictly alternating cycles, communicating through GitHub
Issues (see "Ticket protocol" below) and, for regression coverage, the `regression-suite-*.md`
files described below. There is no build step. **`tests/run.sh` is the test suite: run it
before committing any change to a driver, `providers.sh`, `lib/classify.jq` or the guard.**
It is offline (a fake `gh` over a JSON board, and stub `ssh`/`claude`), takes about a minute,
and runs the real drivers end to end. See "Tests" below.

- `run-loop.sh` — the driver. Runs the implementer's sessions, then the tester's, then prints a
  ticket status board; repeats. Sessions are **per issue, not per role**: the implementer gets a
  short triage session when 2+ issues wait (dispositions each with a `triage:` comment, which
  is also where related issues get batched into one fix), then one fresh `claude -p` per
  remaining issue; the tester gets one per `status:fixed-pending-verify` issue, plus a "task"
  session (closure responses + one step of the standing task, `agents/tester/standing-task.md`) every `TESTER_TASK_EVERY` cycles
  (default 4 — it is the most expensive session in a cycle and is discovery, not verification;
  on the cycles in between, a pending `wontfix`/`duplicate` closure gets a short "closures"
  session of its own, tracked in `logs/closures-seen`, so the reopen window doesn't stretch
  with the knob). A session that starts while the account's rate limit is rejected returns in
  under a second at $0; `sleep_if_rate_limited` (`providers.sh`) then sleeps every driver
  until the reset the event named instead of relaunching (37 such sessions spun on
  2026-09-21). The driver re-checks an issue's labels right before its session so one already
  handed off by a batch is skipped. Every session runs with `--max-budget-usd`
  (`IMPLEMENTER_BUDGET_USD`/`TESTER_BUDGET_USD`/`TRIAGE_BUDGET_USD`, defaults 8/5/3, 0 = none;
  `REGRESSION_BUDGET_USD` 6 per chunk session in `run-regression.sh`) and `--autocompact $AUTOCOMPACT_TOKENS` (default 120k). The reason is measured, not
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
  `LEAD_DESIGN_TOOLS`/`IMPLEMENTER_TOOLS` — only the built-in tools a role has ever used; the
  ~20k tokens of Artifact/Workflow/Agent/... schemas a role is denied anyway no longer ride
  on every turn), and `effort_flags` with the `EFFORT` default (`medium`, what sessions ran
  at while it was inherited from user settings; per-role `*_EFFORT` knobs in each driver).
  `measure-base-ctx.sh` is how a flag set's turn-1 context is measured before and after a
  change like this.
  Model choice is one knob per role: `IMPLEMENTER_MODEL` (default `sonnet`), `TESTER_MODEL`
  (`claude-opus-5-5` — the exact id, not the `opus` alias, since an alias moves on the next
  release and a verification is only worth the model behind it), `REGRESSION_MODEL` (`sonnet`),
  `LEAD_MODEL` (the tester's), each with a `*_PROVIDER`
  that defaults to `PROVIDER` (`anthropic`). The implementer's triage session is the one
  exception: `TRIAGE_MODEL`/`TRIAGE_PROVIDER` default to the *tester's*, not the
  implementer's, because a wrong `wontfix`/`duplicate`/park call never bounces back — it
  just disappears — and the session is short and capped, so the strong model costs almost
  nothing there. Which role may run a weak model is a design decision (see "Running"), so
  the defaults are per role. Under a non-anthropic `PROVIDER`
  every role that runs must be named explicitly, since a Claude alias can't be served there
  and `resolve_model_env` rejects it at startup.
- Role prompts for the loop's three MCP roles are built per session kind (roadmap R10):
  `agents/<role>/core.md` holds the role's identity, fences, label scheme, trust rule and
  guardrails, and one fragment per session kind holds only that kind's steps.
  `role_prompt <role> <kind> <file>` (`providers.sh`) concatenates them, and `run_agent`,
  `run_session` and `run-bench.sh` pass the result as `--append-system-prompt-file`.
  Kinds: implementer `fix`/`triage`; tester `verify`/`handoff`/`answer`/`closures`/`task`
  (`task` also loads `standing-task.md`, and `verify`/`handoff`/`task` load `cases.md`);
  regression `whole`/`chunk`/`sweep`; reviewer `docs`. State each rule once, in the core if more than one
  kind needs it, and have fragments point at it by section name, never by step number
  across files. A rule enforced by `guard.py` stays in the core as a one-line pointer.
- `agents/implementer/` — role prompt for the agent with source access and SSH to the
  `lem` box where the MCP server runs. It executes with cwd = the source checkout (`SOURCE_DIR`,
  default `~/src/dkackman/dw-agent`: a clone kept for the agents, with its own `venv` from
  `install.sh` — not Don's working checkout, which it used to share and switch branches under).
- `agents/reviewer/` — the docs reviewer: verifies a `docs-review` fix (text neither the
  server nor the plugin serves) by reading the merged tree, since the tester can't see it
  and must not read source. See "Ticket protocol".
- `agents/tester/` — role prompt for the agent that talks to the MCP server *only* as a
  protocol consumer. It executes with cwd = this repo, which contains no code. That cwd split
  plus an enforced tool allowlist (`CONSUMER_PERMISSION_FLAGS` in `providers.sh`, see
  "Permissions" below) is the basis of the tester's isolation.
- `agents/tester/standing-task.md` — the tester's standing exercise: a throwaway series built in
  `qa-`-prefixed workspaces so it finds bugs in use, not just by re-verifying fixes. Not a
  deliverable; never touches the default workspace.
- `agents/regression/` / `run-regression.sh` — a third, standalone agent (not part of
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
  low-value it looks from a single run; the only route to changing or removing one is an issue
  proposing it, filed on this repo (`dkackman/harnest`) labeled `suite` +
  `status:needs-approval`. A curator review session (`run-loop.sh`'s `curator_pass`,
  `agents/curator/review.md`, on the tester's model) rules on it:
  - it applies what the record settles: a stale reference, or an expectation a verified or
    `breaking-change` issue changed on purpose;
  - it denies an edit that would make a failing case pass with no such record;
  - it escalates judgment calls to Don with `owner:don`: moves, merges, audit retirements,
    the security suite beyond a stale reference, and anything touching more than 3 cases.

  `run-digest.sh` lists its rulings, and Don reverses one by reopening it.
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
- `agents/lead/` / `run-features.sh` — the feature lead (roadmap R11). It owns `feature`
  issues from design to delivery, and `idea` issues: a design session decides whether an
  idea is a feature, a single fix it hands to `owner:implementer`, or not worth doing
  (R12 folded the old researcher role in here).
  - **Design and decompose** run in `run-features.sh`, which `run-loop.sh`'s
    `features_pass` starts in any cycle where one waits (`LEAD_DESIGN_IN_LOOP=0` to
    leave them to a hand run). They are lock-free and read-only
    against a detached worktree at `origin/develop` (`LEAD_TREE`), behind
    `LEAD_DESIGN_PERMISSION_FLAGS`: read-only source, `gh issue`, `WebFetch`, plus `Write`
    to /tmp, a `gh api` PATCH to edit the plan comment in place, the `Agent` tool for the
    one read-only code sweep, and read-only `dw` calls for measuring demand.
  - **Builds and close-outs** run in `run-loop.sh`'s `lead_pass`, between the implementer
    and tester passes. They use the implementer's flags, R3 gate included.
  - **The tester's `spec` kind** (`status:needs-spec`) writes `pending: #<stage>` cases
    from the approved plan before any code exists. Its verify kind judges a stage by
    those cases and bounces it to `owner:lead`.
  - **Order.** Stages are GitHub sub-issues ordered by "blocked by" links. A stage builds
    only when it has no open blocker and its parent is `owner:lead` +
    `status:plan-approved` with `decomposed vN` and `specced vN` markers for the current
    plan version N (`lib/classify.jq`). A re-plan bumps N, so decompose and spec run again
    by themselves.
  - **Approval** (`status:plan-approved`) is Don's alone: `guard.py` refuses it from
    every role.
- `run-release.sh` / `lib/release.sh` / `agents/release/` (R14) — cuts a release in stages
  Don runs: `freeze`, `check`, `review`, `notes`, `gates`, `accept`, `status`, `cut`. It
  records each gate as a marker comment on the release issue, keyed to the full
  `origin/develop` commit (`<!-- harnest:release-gate <gate> <sha> <result> -->`). `cut`
  refuses unless every gate passed, or was accepted, on the commit it merges. The review
  and notes sessions are read-only and file nothing (`RELEASE_PERMISSION_FLAGS`). The
  driver files their findings: public ones as issues, `release-blocker` for blockers, and
  security ones only to `logs/release-<v>/security.md`. `guard.py` refuses the marker, and
  both release labels, from every agent. The `gates` stage needs the driver lock free, so
  stop the loop first. README "Releasing" has the stage list and knobs.
- `lib/classify.jq` (R12) — the ticket protocol's state machine, in one place. It maps
  every open issue (labels, parent, blockers, sub-issue counts, the lead's phase markers)
  to the queue that runs it next, or to `don`, `wait`, `external` or `stranded`. Every
  driver queue (`queue_issues`/`still_ready` in `providers.sh`), the digest and the
  post-session audit read it. "Stranded" means no queue will ever pick the issue up: the
  audit warns on it, and the digest lists it. Change who acts on what here, not in a
  driver.
- `run-bench.sh` / `bench/` — the replay benchmark (roadmap R1). It re-runs the
  implementer, with its real role prompt plus `bench/replay-note.md`, on curated
  already-verified issues. Each run starts from a clone holding only history up to the
  commit before the real fix, with no remote. `gh`/`ssh`/push/web are denied and there's
  no MCP, because the real fix is on GitHub. `PYTHONPATH` points at the clone, because the
  shared venv's editable install otherwise imports `SOURCE_DIR`. Scoring covers new pytest
  failures against that commit's own failures, the real fix's tests on the candidate, file
  overlap, and an Opus judge verdict. Results are one JSONL row per case in
  `bench/results/results.jsonl` (checked in, append-only); `--summary` groups them by
  `BENCH_LABEL`. Offline, so no driver lock. Use it before and after any change to
  `agents/implementer/` or the implementer's model.
- `run-curate.sh` / `agents/curator/` (R5; `audit` kind here, `review` kind in `run-loop.sh`), `run-retro.sh` / `agents/RETRO.agent.md`
  (R7) and `run-digest.sh` (R9) are standalone drivers that only propose changes. None of
  them edits a suite, prompt or driver, and none takes the driver lock (no MCP).
  - **Curator:** files one issue per level on **this** repo, labeled `suite` +
    `status:needs-approval`, and searches the ticket repo for case history. Its evidence is
    a per-chunk cost table parsed from `loop.log`.
  - **Retro:** files up to three `harness` + `status:needs-approval` issues on **this**
    repo (`dkackman/harnest`), from an evidence digest the driver computes. The window
    since the last retro is byte offsets in `logs/retro-seen.json`.
  - **Digest:** a tool-less summary of the `owner:don` queue.
- `contract/` (R6) holds script-run regression cases: a standard-library MCP client
  (`mcp_client.py`), a runner (`run.py`) and JSON cases keyed by suite case IDs.
  `run-regression.sh` runs a case by script only when its suite block carries
  `runner: script` and the JSON exists. It then drops that case from the agent's chunks
  and gives the report to the level's last session, which files failures only. Marking a
  case edits it, so it needs approval like any other change to a case. The implementer
  never touches `contract/`.
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
  capped at ~12 KB by `agents/tester/standing-task.md`, not a journal; per-cycle narrative belongs on the issues.

Planned evolution of the harness itself (replay benchmark, hooks, feature specs, suite
curation, retro loop, SDK port) is tracked in `HARNESS-ROADMAP.md`. Read it before a
structural change to the drivers or role prompts.

## Running

```sh
./run-loop.sh                          # forever; SOURCE_DIR defaults to ~/src/dkackman/dw-agent
MAX_CYCLES=3 SLEEP_SECS=60 ./run-loop.sh                # three cycles, then stop
TESTER_MODEL=opus IMPLEMENTER_MODEL=haiku ./run-loop.sh # per-role models (defaults claude-opus-5-5 / sonnet)
PROVIDER=ollama IMPLEMENTER_MODEL=qwen2.5:32b TESTER_MODEL=qwen2.5:32b ./run-loop.sh   # non-Anthropic: name every role
IMPLEMENTER_BUDGET_USD=0 TESTER_TASK_EVERY=1 ./run-loop.sh   # no implementer cap; standing task every cycle
tail -f logs/loop.log                  # combined stream, prefixed [implementer:#145] / [tester:task] etc.
grep usage: logs/loop.log              # one line per session: turns, duration, cost, peak context
TESTER_EFFORT=high REGRESSION_EFFORT=high ./run-loop.sh   # per-role --effort (default medium)
./measure-base-ctx.sh lean --setting-sources project,local --tools "Bash,Read,Edit,Write,Glob,Grep,ToolSearch,Skill,TodoWrite"   # turn-1 context of a flag set
```

Which roles may run a weak model is a design decision, not a config detail: the tester's
independence is the whole point, and a weak tester degrades that silently by rubber-stamping, so
vary the implementer (its mistakes show up in its patches) and keep the tester on a strong model.
The regression agent is the measured exception: its work is executing written cases, not judging,
and a same-day smoke run on each (2026-09-21) cost $32.64 on Opus vs $17.85 on Sonnet with no loss
in what was filed (#310–#312, one of them a wrong literal the Opus run had committed an hour
earlier) — so it defaults to `sonnet`. Each agent's prompt now states the model and provider it is running as,
and each role prompt requires the agent to name them in the comments it writes — a fresh session
is otherwise unidentifiable afterwards, and a verification is only worth what the model behind it
was. An alias (`opus`) moves when a new model ships, so the runtime note tells the agent to use
the exact id its system prompt states, `render_stream` logs a `model:` line per session from
the init event, and suite-commit trailers use that resolved id (`resolved_model`). Suite-edit
commits are attributed by trailer, honestly: a non-Anthropic model gets
`<model> (via <provider>)`, not a Claude name and an anthropic.com address.

The loop sleeps only when a cycle left the ticket board unchanged; if either agent's issue
activity changed it, the next cycle starts immediately. (Whether an agent also appended a
regression case in the same cycle isn't part of that check.)

`run-loop.sh` and `run-regression.sh` never run at once: both take `logs/.driver.lock`
(`acquire_driver_lock`, a `mkdir` lock; a stale one is taken over) and wait for the other,
because an implementer deploy restarts the server under a regression run. The lock is per
server target (harnest#15; `resolve_target` and friends in `providers.sh`). With
`DW_TARGET=local`, `run-loop.sh`, `run-features.sh` and `run-regression.sh` run against a
dw server on this machine (the Mac, MPS) under `.driver.lock.local`, alongside the loop
on lem. That server runs from the serving clone `DW_LOCAL_DIR` (`dw-mps-serve`), which
`deploy_target` redeploys with its own `scripts/deploy.sh`, never over ssh.
- **Per-target state.** Logs and state files carry a `.local` suffix (`loop.local.log`,
  `progress.local.tsv`, …), and the clones a `-mps` one (`dw-agent-mps`,
  `dw-agent-plugin-mps`, `dw-agent-lead-mps`), so two loops never share a tree.
- **Which loop works which issue:** two label families, read by `lib/classify.jq` with
  the snapshot's `target`.
  - `backend:shared|cuda|mps` says what the bug is about.
  - `target:lem|local` is the claim `claim_issue` adds before triage. A loop never
    claims over another's, and one that reads back both labels removes its own.
  - The legacy rule: an unclaimed issue past the implementer is lem's.
  - A session hands an issue to lem by swapping `target:local` for `target:lem`.
- **What stays on lem.** Feature specs, lead builds and close-outs, and the tester's
  standing task. The server-free passes (features, reviewer, curator) run on the Mac
  only while lem's loop isn't running (`lem_loop_running`, `SHARED_PASSES`).
- **Prompts.** The Mac implementer, tester and regression agent each get
  `agents/<role>/target.md` appended to the system prompt (`target_note`).
- **Guard** (`HARNEST_TARGET`, `HARNEST_ROLE`):
  - no ssh, scp or rsync for the Mac implementer;
  - no suite edit from a Mac regression run, though the Mac tester may add a case for a
    shared fix;
  - no write to lem's perf history;
  - a new Mac issue carries exactly one `backend:mps|shared` and no `target:`;
  - no comment on a `target:lem` issue;
  - a Mac verification adds `verified-on:mps`.
- **Regression runs.** A Mac run commits only `regression-perf/local/`.
- **Preflight.** `target_preflight` refuses a server whose `/api/health` hostname isn't
  this machine, so a tunnel to lem can't pass as local.
- **Setup and fixtures.** `scripts/setup-mac-loop.sh` makes the clones.
  `scripts/sync-fixtures.sh` copies lem's `qa-cast` fixture media when Don runs it.

`run-release.sh` refuses any target but lem, and its regression gate counts every
regression filed during it, `backend:mps` included. `run-features.sh`
and `run-curate.sh` make only read-only MCP calls (or none) and take no lock. Each driver keeps its own
`logs/.last-session.<driver>` for the rate-limit and died-session checks.

After every per-issue session (and on each triaged issue after triage) `audit_issue` checks
the invariants the prompts state — an open issue has exactly one `owner:*` label; only the
tester (or the docs reviewer) closes as `completed` — and `commit_suite_changes` flags a suite commit that removed
lines (cases and `regression-perf/` readings are add-only unless a human approved it). Both log
`[audit] WARNING` to `loop.log` and repair nothing: `grep '\[audit\]' logs/loop.log` after a
model change is how drift from the prompts shows up.

The tester's directory has no MCP config, so `run-loop.sh` hands it the `dw` server via
`--mcp-config` + `--strict-mcp-config` (it sees *only* `dw`) and loads the `dw` plugin via
`--plugin-dir` from `PLUGIN_TREE` (default `~/src/dkackman/dw-agent-plugin`): a detached
worktree of `SOURCE_DIR` that `refresh_plugin_tree` resets to `origin/develop` — the commit lem
deploys — at startup and before every tester pass. Without `--plugin-dir` it would use the
frozen copy in `~/.claude/plugins/cache` and never see skill fixes; loading from `SOURCE_DIR`'s
own working tree (the old way) meant loading whatever branch was checked out there, which on
2026-09-22 was Don's in-progress feature branch. `run-regression.sh` uses the same tree. The implementer gets the same
`--mcp-config` + `--strict-mcp-config` pair (not `--plugin-dir`; it works from the source tree).
Its checkout already has `dw` at local scope in `~/.claude.json`, so the flags change nothing
about `dw` — they exist to drop the account-level claude.ai connectors (Gmail, Drive, Calendar)
that every unrestricted session inherits, which an unattended agent must not hold. The same
paragraph of flags now also drops user-level settings entirely (`ISOLATION_FLAGS`) — the
implementer's own `--append-system-prompt-file` role prompt and `--settings` file are what
it runs on. Both roles see MCP tools as deferred names (schemas load on first use), so the
`dw` surface costs each session well under 2k tokens at connect; per-call result size is the
real budget (see issue #101).

## Tests

`tests/run.sh [name]` runs every `tests/test-*.sh` (plain bash on `tests/lib.sh`, no bats):
- `test-classify.sh`: `lib/classify.jq` over fixture boards in `tests/classify-cases.json`,
  one per protocol state. Add a board when you add or change a state.
- `test-guard.sh`: `guard.py` as a table (role, session kind, command, allowed or refused).
- `test-providers.sh`: the shared helpers. Session outcomes on canned logs, the stream
  renderer against `tests/fixtures/stream.expected`, model/effort validation, the
  no-progress ledger, `handoff_count`, `park_external_issues` and the driver lock.
- `test-drivers.sh`: the real `run-loop.sh`, `run-features.sh`, `run-regression.sh`,
  `run-curate.sh` and `run-retro.sh` against `tests/fake-gh.py` (a JSON board that edits
  change) and a throwaway git origin. It covers a GitHub outage, the ledger parking an issue,
  fix-then-verify in one cycle, an outside filing, and the spec race.
- `test-lint.sh`: `bash -n` under `/bin/bash` 3.2, `shellcheck -S error`, Python parses, and
  every `${KNOB:-}` a driver reads is named in the README.

Two bash 3.2 traps the suite has already caught: an apostrophe in a comment inside `<( )`
("bad substitution"), and `source <(…)`, which 3.2 doesn't support.

## Permissions

No agent runs with `--dangerously-skip-permissions`. A headless `claude -p` session never
prompts — a call that would have prompted is denied and the denial comes back to the agent as a
tool result — so the choice is what gets auto-approved vs. auto-denied, per role:

- Tester and regression agent: `--permission-mode dontAsk` + an explicit `--allowedTools` list
  (`CONSUMER_PERMISSION_FLAGS` in `providers.sh`): `mcp__dw__*`, the dw skills, `gh issue`, file
  tools for the suite files and `qa-bible.md`, and a few read-only shell helpers. No `ssh`, `curl`,
  `python`, or `git` writes (the drivers commit suite edits themselves), and no other `gh`
  subcommand — a bare `gh *` let a consumer read the source through `gh api .../contents` or
  `gh repo clone`. `--disallowedTools` denies `delete_model` and `update_diffusers` outright
  (server-wide, used by no case); the other destructive dw tools are exercised by suite cases
  and stay on the prompts. This is what makes
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
- Feature lead, design and decompose: `--permission-mode dontAsk` +
  `LEAD_DESIGN_PERMISSION_FLAGS` (`providers.sh`) — read-only against the source
  (`Read`/`Grep`/`Glob`, read-only `git`), read-only `dw` calls, `gh issue`, `WebFetch`,
  `Write` for staging text in /tmp, and one `gh api` PATCH form for the plan comment. A
  third isolation shape: it sees source, like the implementer, but can never change it.
  Its build and close-out sessions run with the implementer's flags.
- Docs reviewer: `--permission-mode dontAsk` + `REVIEWER_PERMISSION_FLAGS` — the lead-design
  shape minus every write: `Read`/`Grep`/`Glob`, read-only `git`, read-only `dw` discovery,
  `gh issue`. Its cwd is the plugin tree, and it runs with `--setting-sources local`, not
  `project,local`: the dw repo's checked-in `.claude/settings.json` allows `pip install`,
  `pytest` and `curl`, which a project source would add to its allowlist.

Guard hooks (roadmap R3): `agent-settings/hooks/guard.py` is a `PreToolUse` hook on `Bash`.
The implementer loads it via `agent-settings/implementer.json`; tester and regression load it
via `guard_settings consumer` (`providers.sh`, which generates the `--settings` JSON for the
consumer, lead, curator and reviewer roles), inside `CONSUMER_PERMISSION_FLAGS`. It refuses at
call time what `audit_issue` otherwise only finds afterwards:
- `completed` closes and `status:verified` from the implementer;
- lifting a `owner:don`/`needs-approval` park;
- pushes to `master`, and force pushes;
- stacking `owner:*` labels;
- a consumer verifying in a session with no `mcp__dw__*` call. A tester handoff session may
  close as `completed` without one, since it applies a harness-side edit with nothing to verify
  (`HARNEST_SESSION_KIND`, set by `run_agent`). It still can't add `status:verified`;
- `status:verified` from the docs reviewer, which closes as `completed` without an MCP call
  and marks it `status:reviewed` instead.

It also gates the implementer's hand-off. The tree must be clean, `ruff` must pass on the
changed files, the UI's `npm run check`/`lint`/`test` must pass when `ui/` changed (about
15 s; absolute, since CI now holds `develop` to them), and no test may fail that passed on `HARNEST_BASE_COMMIT` (origin/develop
when the session began, exported by `implementer_pass`). The gate is relative because
`develop` isn't always green. The result is stamped per tree in the checkout's `.git`.
`HARNEST_HOOKS` (exported by `providers.sh`) is how the settings files find the script.
The role prompts' cores carry each guard rule as one line under "Enforced by the harness".

Two deploy paths, and the implementer must say which one a fix used: server code →
`ssh lem '~/diffusers-workflow/scripts/deploy.sh <branch>'` (in the dw repo: fetch, ff-only pull,
reinstall if `pyproject.toml` changed, wait for a running job, restart via the `dw-serve`
systemd user unit if installed else its `screen` session, poll health — the one call that
replaced ~40 hand-rolled ssh turns per issue and eleven `kill -9`s of the server), tool schemas
refresh automatically; plugin/skill changes → merge to `develop` and push, no restart (the
tester's plugin tree follows `origin/develop`). `run-loop.sh` also records what lem is running at the start of every cycle
(`deployed_head`, one ssh) and puts it, plus the issue's title/labels/body/latest comments
(`issue_context`, capped), into every per-issue session prompt so neither role spends its first
turns on `gh issue view`. `issue_context` withholds comments by any login other than
`TICKET_OWNER` (a one-line stub instead): the repo is public, `park_external_issues` only vets
who *filed* an issue, and the implementer that reads the prompt runs in auto mode with push
and ssh; every agent posts as `TICKET_OWNER`, so nothing the loop wrote is lost. The role
prompts say the same of comments met via `gh`. `DEPLOYED_HEAD` is refreshed between the implementer and tester
passes (the tester must be told what it is actually verifying against), and
`check_target_on_develop` logs a warning and redeploys `develop` itself (`deploy_target`; `DEPLOY_ON_MISMATCH=0`
to only warn) if the server isn't on `origin/develop` at that point —
the implementer merges every fix into `develop` and deploys `develop` (the "Fix" and "Deploy" sections of `agents/implementer/fix.md`)
because lem can only be on one commit and a cycle hands off several fixes; on 2026-09-21
three branch-only deploys were wiped by a fourth session's `develop` deploy and had to be
merged by hand before the tester ran. Both are driver-side (one `ls-remote`, the same ssh) —
the tester still reaches lem only over MCP.

Bounce escalation: `handoff_count` (labeled events for `status:fixed-pending-verify` on the
issue's timeline since its last `reopened` event, so hand-offs that passed before a
regression reopened it don't count) is how many fixes the tester has sent back. At `IMPLEMENTER_ESCALATE_AFTER`
(default 2) the issue's next implementer session runs on `TESTER_MODEL`/`TESTER_PROVIDER`
with a prompt note that the bounce comments are now the spec; at `IMPLEMENTER_PARK_AFTER`
(default 4) the driver parks it `owner:don` + `status:needs-approval` with a comment instead
of launching another session. Two, not one, because a first bounce is usually a spec gap
the bounce comment closes (#265's second round on sonnet cost $0.71 against $4.65 for the
first, and verified); 0 disables either.

## Ticket protocol (the core of the design)

Tickets are **GitHub Issues on `dkackman/diffusers-workflow`**, not entries in a file in this
repo. Both agents act on them with the `gh` CLI (`gh issue create` / `edit` / `comment` /
`close` / `list`). The invariants both role prompts and the status-board query depend on:

- **Which server's loop** (harnest#15): `backend:shared|cuda|mps` says what a bug is about
  and `target:lem|local` is the claim of the loop working it; `lib/classify.jq` holds
  another loop's issues at `wait` (README "Another server").
- `owner` is a label, exactly one of `owner:implementer` / `owner:tester` /
  `owner:don` / `owner:lead` at a time — whoever's turn it is to act
  next. Swap it with `gh issue edit <n> --remove-label owner:X --add-label
  owner:Y`. An agent only touches issues carrying its own owner label and
  never edits another agent's issue beyond the label/comment that hands it
  off. An `idea`-labeled issue goes to `owner:lead`, whose design session
  makes it a feature, hands it to `owner:implementer` as one fix, or closes
  it. `lib/classify.jq` is the authoritative map from labels to the session
  that runs next.
- **A release freeze** (R14): while an open issue labeled `release` exists (owner:don, titled
  with the version), `lib/classify.jq` holds every agent queue at `wait` except issues
  labeled `release-blocker`, and `run-loop.sh` holds the tester's standing task
  (`release_freeze` in `providers.sh`). Closing the release issue lifts it.
  `touch logs/stop-after-cycle` is the other freeze: the loop exits at the next cycle
  boundary.
- **Security holes are private** (R14 item 3). A finding where a boundary didn't hold
  goes to a draft GitHub security advisory via `scripts/file-advisory.sh`, never a public
  issue. That covers a gate, a path, a URL, a disclosure, or a destructive call without
  acknowledgement. Only Don and the repo's admins can see a draft. The script dedupes
  by summary, appending "seen again" rather than filing twice. The tester and regression
  agent may run it (`CONSUMER_PERMISSION_FLAGS`), and so may the implementer
  (`$HARNEST_ROOT`), and `run-release.sh review` files its security findings the same
  way. `guard.py` refuses the `security` label on any issue from every agent. A
  security-level case that fails while its boundary held is an ordinary issue. The
  board line and the digest count open drafts. Nothing in the loop works them: Don hands
  each one out.
- **The owner label is the only signal.** A status addressed to Don (`needs-approval`,
  `plan-review`, or `needs-info` on an implementer's or lead's issue) is stale once he
  swaps the owner back. It never decides a queue, and the agent that receives the issue
  clears it. README "Your moves" lists Don's actions.
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
  The one exception is a fix that changed only text neither the server nor the plugin serves
  (README, non-guide `docs/`): the implementer labels it `docs-review` at hand-off (or the
  tester does on meeting one it can't observe), `lib/classify.jq` routes it to
  `reviewer:docs`, and `run-loop.sh`'s `reviewer_pass` (`agents/reviewer/`, on the tester's
  model, read-only against the plugin tree at `origin/develop`) closes it as `completed` with
  `status:reviewed` — never `status:verified`, which `guard.py` refuses it — or bounces it.
  The tester stays source-blind: that is why this is a separate role, not a wider fence.
  That rule is about the ticket repo: on this repo the curator closes the suite requests it
  applies as `completed`.
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
