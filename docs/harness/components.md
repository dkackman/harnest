# Harness components

Moved from `CLAUDE.md`. Sections named "below" in this text now live in sibling files: Running → `running.md`, Tests → `tests.md`, Permissions → `permissions.md`, Ticket protocol → `ticket-protocol.md`, the component list → `components.md`.

- `run-loop.sh` — the driver. Runs the implementer's sessions, then the tester's, then prints a
  ticket status board; repeats. Sessions are **per issue, not per role**: the implementer gets a
  short triage session when 2+ issues wait (dispositions each with a `triage:` comment, which
  is also where related issues get batched into one fix; it also runs for any stranded issue,
  relabelling it when its own record settles where it belongs, else parking it `owner:don`,
  each with an `unstrand:` comment), then one fresh `claude -p` per
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
  paragraph), and `commit_suite_changes` (commits only `regression-suite-*.md`,
  `regression-perf/` and `regression-results/`). It also holds what every session leaves *out*: `ISOLATION_FLAGS`
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
  Model choice is one knob per role: `IMPLEMENTER_MODEL` (default `claude-sonnet-5-5`), `TESTER_MODEL`
  (`claude-opus-5-5` — the exact id, not the `opus` alias, since an alias moves on the next
  release and a verification is only worth the model behind it), `REGRESSION_MODEL` (`claude-sonnet-5-5`),
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
  Kinds: implementer `fix`/`triage`; tester `verify`/`handoff`/`answer`/`closures`/`task`/`spec`
  (`task` also loads `standing-task.md`, `verify`/`handoff`/`task`/`spec` load `cases.md`, and
  `verify`/`spec`/`task`, the kinds that call the dw tools, load `mcp-rules.md`, the MCP house rules);
  regression `whole`/`chunk`/`sweep`, where `whole` is `core` + `run-cases` + `sweep` and
  `chunk` is `core` + `run-cases` + `chunk` (there is no `whole.md`); reviewer `docs`/`arch`;
  lead `design`/`decompose`/`build`/`closeout`; curator `audit`/`review`; release
  `review`/`notes`. `role_prompt`'s `case` in `providers.sh` is the map. State each rule once, in the core if more than one
  kind needs it, and have fragments point at it by section name, never by step number
  across files. A rule enforced by `guard.py` stays in the core as a one-line pointer.
- `agents/implementer/` — role prompt for the agent with source access and SSH to the
  `lem` box where the MCP server runs. It executes with cwd = the source checkout (`SOURCE_DIR`,
  default `~/src/dkackman/dw-agent`: a clone kept for the agents, with its own `venv` from
  `install.sh` — not Don's working checkout, which it used to share and switch branches under).
- `agents/reviewer/` — the reviewer: verifies a `docs-review` fix (text neither the
  server nor the plugin serves) by reading the merged tree, since the tester can't see it
  and must not read source. See "Ticket protocol". Its `arch` kind reviews a hand-off that
  changed `dw/`/`dw_mcp/` against dw's `docs/ARCHITECTURE.md` before the tester (`arch-review`).
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
  `regression-results/` is the drivers' own ledger beside it: one JSONL per case, a line per
  session handed it (outcome, issue, seconds where the fleet timed it), written by
  `harness/results.py` after every session and never by an agent (format in its `README.md`).
  A chunk session is handed its cases' text in the prompt (`scripts/case-text.sh`: the
  Fixtures section and each case's block) rather than reading the suite for it.
- `agents/lead/` / `run-features.sh` — the feature lead (roadmap R11). It owns `feature`
  issues from design to delivery, and `idea` issues: a design session decides whether an
  idea is a feature, a single fix it hands to `owner:implementer`, or not worth doing
  (R12 folded the old researcher role in here).
  - **Design and decompose** run in `run-features.sh`, which `run-loop.sh`'s
    `features_pass` starts in any cycle where one waits, first in the cycle so a
    single fix design hands to `owner:implementer` is fixed that cycle
    (`LEAD_DESIGN_IN_LOOP=0` to leave them to a hand run). They are lock-free and read-only
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
  `origin/develop` commit (`<!-- harnest:release-gate <gate> <sha> <result> <ts> <mac> -->`),
  signed with an HMAC under `RELEASE_KEY_FILE` (`lib/release_mac.py`, harnest#140): every agent
  posts as Don's login, so an unsigned marker is ignored and no role may read the key. `cut`
  refuses unless every gate passed, was accepted, or was carried on the commit it merges.
  Review, security and regression carry across the notes, and review and security
  across a verified release-blocker's fix (`release_carry_ok`). `accept check --waive`
  records `harnest:release-waive` markers that later checks honour. The review
  and notes sessions are read-only and file nothing (`RELEASE_PERMISSION_FLAGS`). The
  driver files their findings: public ones as issues, `release-blocker` for blockers, and
  security ones only as private draft advisories (`scripts/file-advisory.sh`; if filing
  fails, the findings stay in `logs/release-<v>/security-unfiled.json`). `guard.py` refuses both markers, and
  both release labels, from every agent. The `gates` stage needs the driver lock free, so
  stop the loop first. README "Releasing" has the stage list and knobs.
- `lib/classify.jq` (R12) — the ticket protocol's state machine, in one place. It maps
  every open issue (labels, parent, blockers, sub-issue counts, the lead's phase markers)
  to the queue that runs it next, or to `don`, `wait`, `external` or `stranded`. Every
  driver queue (`queue_issues`/`still_ready` in `providers.sh`), the digest and the
  post-session audit read it. "Stranded" means no queue will ever pick the issue up: the
  audit warns on it, the digest lists it, and the implementer's triage unstrands it
  (`stranded_here` in `run-loop.sh`). Change who acts on what here, not in a
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
    a per-chunk cost table parsed from `loop.log`. Weekly, `curator_pass` files coupling that moved
    in dw's `arch_report.py` as `consolidation` + `owner:don` issues (`lib/consolidation.py`).
  - **Retro:** files up to three `harness` + `status:needs-approval` issues on **this**
    repo (`dkackman/harnest`), from an evidence digest the driver computes. The window
    since the last retro is byte offsets in `logs/retro-seen.json`.
  - **Digest:** a tool-less summary of the `owner:don` queue.
- `harness/` (R8) is the Python port, stdlib only. `harness.drivers.regression` is
  `run-regression.sh` at parity (`tests/test-regression-py.sh` diffs the two). The
  **regression fleet** runs a level across every server's lanes at once:
  `python3 -m harness.drivers.fleet [--plan] <level|all>`. It's dispatched by each case's
  needs in `regression-requirements.json`, from `python3 -m harness.drivers.requirements`.
  Servers' policy is in `targets/dw/profile.toml`, and their facts come from the server at
  startup. Live progress is on the dashboard's `/regression` page. Spec:
  `docs/superpowers/specs/2026-10-18-regression-fleet.md`.
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
