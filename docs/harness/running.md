# Running

Moved from `CLAUDE.md`. Sections named "below" in this text now live in sibling files: Running → `running.md`, Tests → `tests.md`, Permissions → `permissions.md`, Ticket protocol → `ticket-protocol.md`, the component list → `components.md`.

```sh
./run-loop.sh                          # forever; SOURCE_DIR defaults to ~/src/dkackman/dw-agent
MAX_CYCLES=3 SLEEP_SECS=60 ./run-loop.sh                # three cycles, then stop
TESTER_MODEL=opus IMPLEMENTER_MODEL=haiku ./run-loop.sh # per-role models (defaults claude-opus-5-5 / claude-sonnet-5-5)
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
earlier) — so it defaults to Sonnet (`claude-sonnet-5-5` since 2026-09-28). Each agent's prompt now states the model and provider it is running as,
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
server target (harnest#15; `target_row`, `resolve_target` and friends in `providers.sh`).
Every target is an ssh host running dw from `~/diffusers-workflow`, deployed with dw's own
`scripts/deploy.sh`; `scripts/testbed.sh <target> status|update|start|stop|logs` runs one by
hand. With `DW_TARGET=mini-ai`, `run-loop.sh`, `run-features.sh` and `run-regression.sh` run
against the MPS test bed on host `mini-ai` under `.driver.lock.mini-ai`, alongside the loop on lem.
- **Per-target state.** Logs and state files carry a `.mini-ai` suffix (`loop.mini-ai.log`,
  `progress.mini-ai.tsv`, …), and the clones here a `-mini-ai` one (`dw-agent-mini-ai`,
  `dw-agent-plugin-mini-ai`, `dw-agent-lead-mini-ai`), so two loops never share a tree.
- **Which loop works which issue:** two label families, read by `lib/classify.jq` with
  the snapshot's `target`.
  - `backend:shared|cuda|mps` says what the bug is about.
  - `target:lem|mini-ai` is the claim `claim_issue` adds before triage. A loop never
    claims over another's, and one that reads back both labels removes its own.
  - The legacy rule: an unclaimed issue past the implementer is lem's.
  - A session hands an issue to lem by swapping `target:mini-ai` for `target:lem`.
- **Features are claimed whole.** The spec session's `claim_issue` puts `target:<loop>` on
  the feature parent; a build claims parent and stage; a stage reads its parent's claim as
  well as its own (`lib/classify.jq`). Unclaimed spec/build/close-out is claimable by any
  loop whose server the backend allows. `LEAD_STAGES_PER_CYCLE` is per loop, so each loop
  can have one feature in build.
- **What stays on lem.** The tester's standing task. The server-free passes (features, reviewer, curator) run on the Mac
  only while lem's loop isn't running (`lem_loop_running`, `SHARED_PASSES`), except the
  design, decompose or docs/architecture review of an issue a loop has claimed: that runs in
  the claiming loop (`claimed_here`), so the Mac's hand-offs don't sit behind a long lem lead
  session, and Don sends a design to the Mac by labeling the issue `target:mini-ai`.
- **Prompts.** The Mac implementer, tester and regression agent each get
  `agents/<role>/target.md` appended to the system prompt (`target_note`).
- **Guard** (`HARNEST_TARGET`, `HARNEST_ROLE`):
  - for the Mac implementer, ssh only to its own test bed (`HARNEST_TARGET_HOST`), no
    scp/rsync, and no `deploy.sh` (the driver deploys between sessions: the session's own
    MCP connection holds the old server open);
  - no suite edit from a Mac regression run, though the Mac tester may add a case for a
    shared fix;
  - no write to lem's perf history;
  - a new Mac issue carries exactly one `backend:mps|shared` and no `target:`;
  - no comment on a `target:lem` issue;
  - a Mac verification adds `verified-on:mps`.
- **Regression runs.** A Mac run commits only `regression-perf/mini-ai/` and `regression-results/mini-ai/`
  (`regression-perf/local/` is the earlier local server's history, other hardware).
- **Preflight.** `target_preflight` refuses a server whose `/api/health` hostname isn't
  the target's host, so a tunnel to lem can't pass as the test bed.
- **Setup and fixtures.** README "Another server" sets up a box; `scripts/setup-mac-loop.sh`
  makes the clones here. `scripts/sync-fixtures.sh` copies lem's `qa-cast` media, via a stage here.

`run-release.sh` refuses any target but lem, and its regression gate counts every
regression filed during it, `backend:mps` included. `run-features.sh`
and `run-curate.sh` make only read-only MCP calls (or none) and take no lock. Each driver keeps its own
`logs/.last-session.<driver>` for the rate-limit and died-session checks.

After every per-issue session (and on each triaged issue after triage) `audit_issue` checks
the invariants the prompts state — an open issue has exactly one `owner:*` label; only the
tester (or the docs reviewer) closes as `completed` — and `commit_suite_changes` flags a suite commit that removed
lines (cases and `regression-perf/` readings are add-only unless a human approved it; a
curator review whose request closed as `completed` commits as `curator: applied`, which is
logged, not warned; any other ruling that changed a suite still warns). Both log
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
