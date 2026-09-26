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
- **Feature lead:** designs features and ideas with Don in issue comments, then builds
  approved ones in stages (see below).

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
     series in `qa-` workspaces ([`agents/tester/standing-task.md`](agents/tester/standing-task.md))
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
  `owner:tester`, `owner:lead` or `owner:don`, naming whoever acts next. An agent
  touches only issues with its own owner label, and only to act on them or hand them off.
- **Only the tester closes an issue as `completed`** (with `status:verified`), and only
  after a real MCP call in that session. The implementer never verifies its own fixes.
  One exception: a fix that changed only text neither the server nor the plugin serves
  (the README, a `docs/` page that isn't a guide) is labeled `docs-review`, and a
  read-only docs reviewer closes it with `status:reviewed`. The tester can't see those
  files, and must not read source to try.
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
- **`field-report`** marks an issue filed from Don's own dw sessions (real use) rather
  than by the harness. The loop works it like any other issue. The feature lead (roadmap
  R11) reads it as evidence of demand.
- **`breaking-change`** tells the tester to adjust its calls rather than file the change
  as a bug.
- **Commits** reference the issue (`fix(mcp): #42 - ...`), go on branches merged to
  `develop`, and never go to `master`.
- **No session polls or sleeps.** "Nothing to do" means the session exits.

```
open ──▶ status:fixed-pending-verify ──▶ status:verified (closed completed)
 ▲                    │
 └────────────────────┘  (tester bounces it back to owner:implementer)
open ──▶ status:fixed-pending-verify + docs-review ──▶ status:reviewed (closed completed)
                                                       or back to owner:implementer
open ──▶ status:needs-info ──▶ open
open ──▶ wontfix (closed not planned) ──▶ (tester accepts, or reopens once)
open ──▶ duplicate (closed not planned)
open ──▶ status:needs-approval + owner:don ──▶ open | wontfix   (human decides)
idea ──▶ owner:lead ──▶ feature plan | owner:implementer (one fix) | closed
```

[`lib/classify.jq`](lib/classify.jq) is the protocol as code: it maps every open issue to
the session that runs next, or to where it waits. Every driver queue, the digest and the
post-session audit read it. An issue no queue will ever pick up is "stranded": the audit
warns on it, and the digest lists it.

## Your moves

**Only an owner change moves an issue.** Status labels are context for whoever holds it.
A status addressed to you (`status:needs-approval`, `status:plan-review`, or
`status:needs-info` on an issue you were asked about) goes stale once you hand the issue
back, and the agent that receives it clears it. So you never need to tidy statuses: the
owner swap is the whole move. `lib/classify.jq` encodes this, and
`tests/classify-cases.json` holds a fixture for each hand-back below.

| To | Do this |
|---|---|
| Hand back an issue you were asked about (a park, a question, a failed deploy) | Comment your answer, then swap `owner:don` for `owner:implementer` (a bug) or `owner:lead` (a feature, idea or stage). |
| Start a feature or an idea | Swap `owner:don` for `owner:lead`. A comment on scope or priority is optional. |
| Approve a plan | Add `status:plan-approved` and swap to `owner:lead`. Only you can add that label. |
| Ask for changes to a plan | Comment what you want, then swap to `owner:lead`. |
| Decline a feature or idea | Comment "don't build", then swap to `owner:lead`. The lead records it, and a close-out closes it. |
| Defer one | Comment, and keep `owner:don`. |
| Verify a stage the plan gave you (no MCP surface) | Check it, then `gh issue close <n> --reason completed`. |
| Reject a bug | Add `wontfix`, then close it `not planned`. |
| Answer a curator escalation (harnest) | Comment approve, deny or your amendment, then remove `owner:don`. |
| Reverse a curator ruling (harnest) | Reopen it with a comment saying what you want instead. |
| Let an outside filer's issue into the loop | Hand it back as in the first row. It is never re-parked after that. |
| Handle a private security finding | `./scripts/file-advisory.sh --list` (also on the board line and in the digest). Fix it out of band, or hand it to the implementer yourself without the details going public; publish the advisory once the fix ships, or close it. |
| Freeze for a release | Open an issue titled with the version (`Release 0.5.0`), labeled `release` + `owner:don`. Until you close it, only issues labeled `release-blocker` move, and the tester's standing task is held. Add `release-blocker` to what must land first. |
| Send a Mac issue to lem (or fix a wrong claim) | `gh issue edit <n> --remove-label target:local --add-label target:lem`. lem's loop deploys `develop`, which has any Mac fix. |
| Correct an issue's backend | Swap its `backend:` label. `cuda` keeps it off the Mac loop, `mps` off lem's. |
| Check a Mac-only verification on CUDA | Issues with `verified-on:mps` were verified on the Mac only. Reopen one as `owner:tester` + `status:fixed-pending-verify` + `target:lem` and lem's tester re-verifies it. |

**What doesn't move anything:**
- A comment on its own, while you hold the issue. Agents read your comments when you
  hand the issue back, not before.
- Adding or removing a status without the owner swap.
- `priority:*`, `field-report`, or other plain labels.
- Any change to an issue an agent holds. It's mid-flight, so a change can race the
  session working on it. To step in, swap its owner to `owner:don` first.

`run-digest.sh` prints the exact command for each parked issue's approve and reject, from
its state.

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

### Another server: `DW_TARGET=local`

A second `dw` server on this machine (the Mac: Apple silicon, MPS) runs the loop and the
regression suites while lem is busy, and covers MPS. Everything for it is keyed by
`DW_TARGET=local`, and nothing it does reaches lem. The design is in
[`docs/superpowers/specs/2026-09-26-mac-loop-design.md`](docs/superpowers/specs/2026-09-26-mac-loop-design.md).

**One-time setup.**

```sh
scripts/setup-mac-loop.sh --dry-run    # what it would make
scripts/setup-mac-loop.sh              # dw-agent-mps (implementer clone), dw-mps-serve (serving clone), venvs, ~/dw-mps-workspace
```

Then stop any `dw` server you started by hand. When the loop starts and nothing answers,
it deploys the serving clone (`scripts/deploy-local.sh`, which runs
`DW_LOCAL_DIR/scripts/deploy.sh develop` and records what it deployed in
`logs/.deployed.local`; that record, not the clone's checkout, is what the prompts call
"running"). The server binds to
127.0.0.1 in a `screen` session named `dw-serve` (`screen -r dw-serve`) and logs to
`~/dw-serve.log`. The deploy needs the dw `deploy.sh` that finds the server by its port
(branch `fix/deploy-find-server-by-port`).

**Running it.**

```sh
DW_TARGET=local SHARED_PASSES=1 ./run-loop.sh    # SHARED_PASSES=1 while lem's loop is off
DW_TARGET=local ./run-regression.sh smoke
tail -f logs/loop.local.log
scripts/sync-fixtures.sh                          # lem's qa-cast media, when lem isn't busy (below)
```

**Which loop works which issue.** Two label families decide it:

| label | question | set by |
|---|---|---|
| `backend:shared` / `backend:cuda` / `backend:mps` | what is the bug about? | the filer, or triage when it's missing |
| `target:lem` / `target:local` | which server's loop holds it? | the driver, when a loop takes it; kept until it closes |

| issue | lem loop | Mac loop |
|---|---|---|
| claimed `target:lem` / `target:local` | its own claims only | its own claims only |
| unclaimed `backend:cuda` | yes | no |
| unclaimed `backend:mps` | no | yes |
| unclaimed `backend:shared`, or no backend | yes | yes (triage labels it) |
| unclaimed, past the implementer (handed off before claims existed) | yes | no: it was deployed to lem |

- **Claiming.** A loop claims every fix in its queue before triage, and never over another
  loop's claim. When both claim the same issue in the same moment, the one that reads
  back both labels removes its own. If both do, neither holds it, and it is claimed next
  cycle.
- **Handing over to lem.** A session that finds an issue belongs on lem hands the claim
  over with `--remove-label target:local --add-label target:lem`. That's the Mac
  implementer for a cuda bug, and the Mac tester for a repro it can't run here: a lem-only
  fixture, CUDA, or a model too big for 64 GB. Both loops deploy `develop`, so lem's
  tester gets the fix.
- **A contradiction.** A `backend:cuda` issue claimed `target:local` is `stranded`, and
  the audit flags it.

**What the Mac loop does differently.**
- **Its own state:**
  - its lock is `logs/.driver.lock.local`. A Mac regression run uses the same lock, so
    the two take turns; neither ever waits on lem's lock.
  - logs: `loop.local.log` and `<role>.local.log`;
  - state files: `progress.local.tsv`, `closures-seen.local`, `stop-after-cycle.local`;
  - clones: `dw-agent-mps`, `dw-agent-plugin-mps`, `dw-agent-lead-mps`, `dw-mps-serve`.
- **Deploy.** Only the driver deploys, between sessions: `deploy_cmd` (`providers.sh`)
  runs the serving clone's `deploy.sh` through `scripts/deploy-local.sh`. The Mac
  implementer merges, pushes and hands off, and the guard refuses it the deploy scripts.
  A session's own MCP connection keeps the old server from exiting on the `screen`
  restart path (#446, 2026-09-26). Its target section
  ([`agents/implementer/target.md`](agents/implementer/target.md)) and
  `agent-settings/implementer.local.json` say so.
- **Verify.** The tester follows its target section
  ([`agents/tester/target.md`](agents/tester/target.md)). A verification here adds
  `verified-on:mps`, meaning CUDA hasn't re-verified the fix.
- **Suite cases.** The Mac tester adds a case only for a verified `backend:shared` fix,
  since every suite runs on lem too. For a `backend:mps` fix it proposes the case in its
  verify comment, until the MPS level exists (harnest#16).
- **Not on the Mac:** the tester's standing task (its `qa-bible.md` and series media are
  lem's), feature specs, lead builds and close-outs. Those issues wait for lem.
- **Server-free passes.** Feature design, docs review and curator review run in one loop
  only: lem's while it's running, the Mac's otherwise. `SHARED_PASSES=1` or `0`
  overrides that.
- **Budget.** `TESTER_BUDGET_USD` defaults to 8 here and 5 on lem, because MPS jobs run
  2-3x slower.
- **Guard** (via `HARNEST_TARGET` and `HARNEST_ROLE`):
  - the Mac implementer can't run `ssh`, `scp`, `rsync` or a deploy script;
  - a Mac regression run can't edit a suite file (the Mac tester may);
  - nothing on the Mac writes to lem's perf history;
  - a new issue carries one `backend:mps` or `backend:shared` label, one owner, and no
    `target:` label;
  - no comment on a `target:lem` issue;
  - a Mac verification must add `verified-on:mps`;
  - the only `target:` label an agent may add is the hand-over to lem, and only a Mac
    tester may add `verified-on:`.
- **Release gate.** Every regression filed during the gate blocks it, `backend:mps`
  included.

**A regression run here can't touch lem either.**
- **Identity.** `DW_URL` must name this machine, so a leftover lem URL is refused. Then
  `/api/health` must answer with this machine's hostname, so an ssh tunnel to lem is
  refused too. The Mac loop runs the same check before it starts.
- **Plugin and commits.** It loads the plugin from `DW_LOCAL_DIR/plugins/dw`, so lem's
  `PLUGIN_TREE` is never reset. It commits only `regression-perf/local/`, never the suite
  files or lem's readings, and makes no startup commit.

The agent follows
[`agents/regression/target.md`](agents/regression/target.md), which is added to its
system prompt:
- **Issues:** an open issue for the same case counts as already filed unless it is
  `backend:cuda` or claimed `target:lem`. A failure never becomes a comment on a
  `target:lem` issue. A new one is `owner:implementer` + `backend:mps` (`backend:shared`
  when the case also fails on lem), so the Mac loop can work it.
- **Timing:** figures in case text were measured on lem's CUDA GPU. A reading is judged
  only against `regression-perf/local/` history, and one that includes a first-time
  download is marked as such.
- **Skipped:** a case whose fixture is missing here, whose expectation is about CUDA
  hardware, or that would load H3 or full-size LTX is listed as
  `REGRESSION-SKIP: <case> <reason> <what>`, not filed.
- **Differs:** an expectation about lem's history or hardware (a quote's `basis`,
  `measured_on`) is listed as `REGRESSION-DIFFERS:`. The driver logs both counts per
  level.
- **Security probes:** Linux-only paths get macOS stand-ins for reads, and leak checks
  also catch `/Users/` and `/private/`.

The driver never hands out the cases in `TARGET_SKIP_CASES` on a local target. The
default is S-F079, C-F005, C-F007, C-F023 and C-F047, each of which can run a 64 GB
machine out of memory. It logs them as skipped. `all` on a local target is smoke, complete
and security. `model-specific` runs only when you
name it, since H3 and LTX at full size are a memory risk on 64 GB of unified memory.

**Fixtures.** Most cases that need fixtures use media the tester made on lem
(`asset:qa-cast/...`), and those cases are skipped until the media is here. To copy it,
run this when lem isn't busy:

```sh
scripts/sync-fixtures.sh --dry-run   # what would come across
scripts/sync-fixtures.sh             # copy lem's qa-cast/, uploads/qa-cast/, cast/, reference_sheet.jpg
```

It reads lem at idle priority with a bandwidth cap. It writes into the local server's
`common/assets`, never overwriting a file already there. Knobs: `FIXTURE_SOURCE`,
`DW_LOCAL_WORKSPACE`, `FIXTURE_BWLIMIT_KBPS`.

`run-release.sh` refuses any target but `lem`.

## The feature lead

Work bigger than one fix goes through the feature lead (roadmap R11). A feature is one
issue labeled `feature`, and you start one by swapping its `owner:don` for `owner:lead`.
An `idea` goes the same way: its first design session decides whether it is a feature, a
single fix (handed to `owner:implementer`), a duplicate, or not worth doing.

1. **Design** (`run-features.sh`, which `run-loop.sh` runs each cycle when a design or
   decompose waits). The lead first checks the proposal against the code
   with one read-only sweep, and measures demand (`field-report` issues, real use in your
   own workspaces). It then posts a plan that opens with a verdict: **build**, **build
   smaller**, **defer** or **don't build**. After the verdict come the design, the stages,
   and questions marked with defaults. The issue goes to `owner:don` +
   `status:plan-review`. You answer in comments and swap the owner back. The plan is one
   comment, edited in place.
2. **Approve.** You add `status:plan-approved`. No agent can: the guard refuses it.
3. **Decompose** (`run-features.sh`). Each stage becomes a sub-issue, ordered by "blocked
   by" links. A stage that needs another feature is blocked by that issue.
4. **Spec** (`run-loop.sh`, tester). The tester writes each stage's acceptance cases from
   the plan, before any code, as `pending: #<stage>` suite cases. The regression agent
   skips them.
5. **Build** (`run-loop.sh`, lead pass). One stage per cycle, once it has no open blocker.
   The lead fans code-only work out to `sonnet` subagents, then integrates, merges to
   `develop`, deploys once, and hands off.
6. **Verify** (`run-loop.sh`, tester). The tester checks the stage's repro plus its
   pending cases. A pass removes the `pending:` lines; a bounce goes back to the lead.
7. **Close out.** Once every stage is closed, the lead writes the design record, and the
   tester closes the parent after running every case the feature added.

The lead can also stop mid-build and re-plan. That removes `status:plan-approved` and
halts the feature until you approve again. If you decline a feature, a close-out moves
its doc to `docs/proposals/declined/` and closes any open stages.

Each phase ends with a marker comment carrying the plan version it belongs to
(`<!-- harnest:decomposed v2 -->`, `specced v2`, `spec-questions v2`). A stage builds only
when its parent's current plan has both `decomposed` and `specced`. A new plan version
makes the old markers stop counting, so after a re-plan decompose reconciles the stages
and the tester specs what changed, without anyone arranging it. If the tester finds the
plan too vague to test, it posts `spec-questions` instead, and the lead answers with a
new plan version for you to approve.

```sh
./run-features.sh                      # design/decompose whatever is the lead's turn, now (the loop also does)
ONLY_ISSUES=378 ./run-features.sh
```

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

These are standalone, read-only drivers. Each one proposes changes and never applies
them. Harness proposals go to a human. Suite proposals get a ruling from the curator's
review session in `run-loop.sh` (below), which escalates judgment calls to a human.

- **`run-curate.sh [level]`** runs one Opus session per regression level. It reads the
  suite, its perf history and what recent runs cost per chunk, then files one issue on this
  repo (`suite` + `status:needs-approval`) of proposed moves, merges, contradictions, stale references and retirements
  against a per-level budget. A level is skipped for 7 days after a run, or while its last
  curation issue is still open.
  The first run (harnest#2, applied 2026-09-23) moved 40 cases from smoke to complete,
  leaving smoke at 56 cases against a 30 min / $13 budget. The first measured run after
  it (61 cases, 2026-09-23) took 61 min and $14.53, so smoke's budget is now 65 min / $16.
- **Curator review** (`curator_pass` in `run-loop.sh`, on the tester's model). One session
  per open `suite` request on this repo, from any agent or from an audit.
  - It applies what the record settles: a stale reference, or an expectation that a
    verified or `breaking-change` issue changed on purpose.
  - It denies an edit that would make a failing case pass with no such record.
  - It escalates judgment calls to you with `owner:don`: moves, merges, audit retirements,
    the security suite beyond a stale reference, and anything touching more than 3 cases.

  Its rulings appear in `run-digest.sh`'s output; reverse one by reopening it with a
  comment.
- **`run-retro.sh`** reads the logs since the last retro and files up to three evidenced
  proposals on this repo, labeled `harness` + `status:needs-approval`. The logs cover
  cost per role, denials, guard refusals, audit warnings, bounces and bench results.
  `RETRO_EVIDENCE_ONLY=1` prints the evidence without running a session.
  The first (harnest#3, applied) added a "Your shell" section to the tester and regression
  prompts, naming the tool to use for each pattern the fence denies.
- **`run-digest.sh`** writes one line per `owner:don` issue: the ask, a recommendation and
  the command that carries it out, plus the median days parked. It writes
  `logs/digest.md`; `DIGEST_ISSUE=N` also posts it on issue N.
- **`contract/run.py`** runs mechanical cases as a plain MCP client, with no LLM.
  `run-regression.sh` uses it for any suite case marked `runner: script`. See
  [`contract/README.md`](contract/README.md).

## Releasing

`run-release.sh <version> <stage>` cuts a diffusers-workflow release (roadmap R14). You
run each stage. The script records each result on the release issue as a marker keyed to
the exact `origin/develop` commit, so a stage can be rerun or resumed. `cut` refuses until
every gate has passed on the commit it merges.

```sh
./run-release.sh 0.5.0 freeze      # opens "Release 0.5.0": the loop now moves only release-blockers
./run-release.sh 0.5.0 check       # nothing in flight, lem on develop, master merges cleanly
./run-release.sh 0.5.0 review      # four read-only area reviews; blockers become release-blocker issues
./run-release.sh 0.5.0 notes       # drafts the notes onto release/0.5.0-notes for you to edit and merge
touch logs/stop-after-cycle         # then, once the loop has exited:
./run-release.sh 0.5.0 gates       # CI + CodeQL, preflight in a worktree, regression (security complete)
./run-release.sh 0.5.0 status      # what passed on which commit
./run-release.sh 0.5.0 accept regression "filed #470-#472, all suite drift"
./run-release.sh 0.5.0 cut --next 0.6.0-alpha.1   # PR, CI, merge, tag, notes, reopen develop, close the freeze
```

- **Gates are per commit.** A fix after the gates moves `develop`, and `cut` then wants
  every gate again on the new commit. `accept <gate> <why>` records that you took an
  earlier run as good enough. Nothing is inferred from what a commit touched.
- **Security findings stay off the public tracker.** The review files each one as a
  private draft security advisory, and the release issue gets only their count. `cut`
  refuses while one is a blocker, unless you `accept security`.
- **Tested offline:** `freeze`, `check`, `accept`, `status` and `cut`'s refusal, plus the
  marker, findings and notes logic.
- **Not yet run against real GitHub:** the CI waits, the agent sessions and `cut`'s PR,
  merge, tag and release steps. Watch the first real release.

| Variable | Default | Controls |
|---|---|---|
| `RELEASE_TREE` | `~/src/dkackman/dw-agent-release` | the detached worktree the review and preflight run in |
| `RELEASE_MODEL` / `RELEASE_PROVIDER` | the tester's | the review and notes sessions |
| `RELEASE_EFFORT` | `EFFORT` | their `--effort` |
| `RELEASE_REVIEW_BUDGET_USD` | `8` | per review area (four areas) |
| `RELEASE_NOTES_BUDGET_USD` | `3` | the notes session |
| `RELEASE_REGRESSION_LEVELS` | `security complete` | the levels the regression gate runs (`complete` runs smoke first) |
| `RELEASE_FORCE` | `0` | `1` reruns a gate or review area that already passed on this commit |

## Running it

```sh
./run-loop.sh                                   # forever
MAX_CYCLES=1 ./run-loop.sh                      # one cycle, then stop
ONLY_ISSUES=227 ./run-loop.sh                   # work only #227 (comma-separate for more)
IMPLEMENTER_MODEL=haiku SLEEP_SECS=60 ./run-loop.sh
touch logs/stop-after-cycle          # finish the current cycle, then exit (a release freeze)
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
| `SOURCE_DIR` | `~/src/dkackman/dw-agent` (`-mps` on `DW_TARGET=local`) | agents' clone of the dw repo, with its own `venv`; the implementer's and the lead's builds' cwd |
| `PLUGIN_TREE` | `~/src/dkackman/dw-agent-plugin` (`-mps` on local) | detached worktree reset to `origin/develop`; where the tester and regression agent load the `dw` plugin from |
| `TICKET_REPO` / `TICKET_OWNER` | `dkackman/diffusers-workflow` / `dkackman` | where the tickets live; the only login whose issues and comments are trusted |
| `DW_URL` / `DW_TOKEN` | the target's (`http://lem:8765/mcp`) / `xyz` | the MCP endpoint (dev token, LAN only) |
| `DW_TARGET` / `DW_LOCAL_DIR` | `lem` / `~/src/dkackman/dw-mps-serve` | which server `run-loop.sh`, `run-features.sh` and `run-regression.sh` run against: `lem`, or `local`, a server this machine runs from the serving clone `DW_LOCAL_DIR` (see "Another server") |
| `SHARED_PASSES` | unset | `1`/`0` forces whether this loop runs the server-free passes (feature design, docs review, curator review). Unset: lem's loop always does, and another target's loop only while lem's isn't running |
| `DW_LOCAL_WORKSPACE` / `DW_ORIGIN_URL` | `~/dw-mps-workspace` / the dw repo on GitHub | the local server's `--workspace`, and what `scripts/setup-mac-loop.sh` clones |
| `PROVIDER` | `anthropic` | `anthropic`, `ollama` or `gateway`; see below |
| `IMPLEMENTER_MODEL` / `TESTER_MODEL` | `sonnet` / `claude-opus-5-5` | per-role models (tester pinned to the exact id, not the `opus` alias); each has a `*_PROVIDER` defaulting to `$PROVIDER` |
| `TRIAGE_MODEL` / `TRIAGE_PROVIDER` | the tester's | triage is strong by default: a wrong `wontfix`/`duplicate` never bounces back |
| `REGRESSION_MODEL` | `sonnet` | `run-regression.sh`; same `*_PROVIDER` pattern |
| `LEAD_MODEL` / `LEAD_PROVIDER` | the tester's | the feature lead, in both drivers; `LEAD_WORKER_MODEL` (`sonnet`) runs its code subagents |
| `LEAD_STAGE_BUDGET_USD` / `LEAD_CLOSEOUT_BUDGET_USD` / `TESTER_SPEC_BUDGET_USD` | `15` / `3` / `8` | per-session caps in `run-loop.sh`; `run-features.sh` has `LEAD_DESIGN_BUDGET_USD` (6) and `LEAD_DECOMPOSE_BUDGET_USD` (2) |
| `EFFORT` | `medium` | `--effort` for every role; override per role with `IMPLEMENTER_`/`TESTER_`/`TRIAGE_`/`REGRESSION_`/`LEAD_`/`CURATOR_EFFORT` and `REVIEWER_EFFORT` (triage and the docs reviewer follow the tester's) |
| `IMPLEMENTER_BUDGET_USD` / `TESTER_BUDGET_USD` / `TRIAGE_BUDGET_USD` | `8` / `5` (`8` on local) / `3` | `--max-budget-usd` per session; `0` = uncapped |
| `REGRESSION_BUDGET_USD` | `6` | per regression chunk |
| `NO_PROGRESS_PARK_AFTER` | `2` | sessions in a row that leave an issue's labels unchanged before the driver parks it with Don; `0` = never |
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
| `IMPLEMENTER_PROVIDER` / `TESTER_PROVIDER` / `REGRESSION_PROVIDER` | `$PROVIDER` | where each role's model is served |
| `IMPLEMENTER_EFFORT` / `TESTER_EFFORT` / `TRIAGE_EFFORT` / `REGRESSION_EFFORT` / `LEAD_EFFORT` | `$EFFORT` | per-role `--effort`; triage follows the tester's |
| `HARNESS_REPO` | `dkackman/harnest` | this repo: where suite requests and harness proposals are filed |
| `CURATOR_MODEL` / `CURATOR_PROVIDER` | the tester's | the curator's review sessions in `run-loop.sh` |
| `CURATOR_REVIEW_BUDGET_USD` | `3` | per curator review session |
| `REVIEWER_MODEL` / `REVIEWER_PROVIDER` | the tester's | the docs reviewer: verifies `docs-review` fixes (README, non-guide docs) the tester can't observe |
| `REVIEWER_BUDGET_USD` | `2` | per docs review session |
| `LEAD_STAGES_PER_CYCLE` | `1` | stage builds per cycle; one feature in build at a time |
| `LEAD_DESIGN_IN_LOOP` | `1` | `run-loop.sh`: run `run-features.sh` in a cycle when a design or decompose waits; `0` leaves them to a hand run |
| `LEAD_TREE` | `~/src/dkackman/dw-agent-lead` (`-mps` on local) | `run-features.sh`: the lead's detached worktree at `origin/develop` |
| `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` | `1800000` | how long a headless session waits for a background subagent before it is killed (Claude Code's default is 600 s) |

The standalone drivers have their own knobs:

| var | default | what |
|---|---|---|
| `CURATE_MODEL` / `CURATE_PROVIDER` / `CURATE_EFFORT` | `claude-opus-5-5` / `$PROVIDER` / `$EFFORT` | `run-curate.sh` audit sessions |
| `CURATE_BUDGET_USD` | `6` | per audit session |
| `CURATE_EVERY_DAYS` / `CURATE_FORCE` | `7` / `0` | how often a level is due; `1` audits even if it was curated recently |
| `CURATE_RUNS` | `3` | recent runs of a level in the audit's cost table |
| `CURATE_BUDGET_SMOKE` / `_COMPLETE` / `_MODEL_SPECIFIC` / `_SECURITY` | `65 16` / `60 20` / `60 12` / `15 6` | a level's target for one full run: minutes, then USD |
| `RETRO_MODEL` / `RETRO_PROVIDER` / `RETRO_EFFORT` / `RETRO_BUDGET_USD` | `claude-opus-5-5` / `$PROVIDER` / `$EFFORT` / `5` | `run-retro.sh` |
| `DIGEST_MODEL` / `DIGEST_PROVIDER` / `DIGEST_BUDGET_USD` | `sonnet` / `$PROVIDER` / `1` | `run-digest.sh` |
| `DIGEST_CURATOR_DAYS` | `7` | how far back the digest lists the curator's rulings |
| `BENCH_BUDGET_USD` / `BENCH_JOBS` | `4` / `1` | `run-bench.sh`: per replayed session, and cases run in parallel |
| `BENCH_LABEL` | `<provider>/<model>@<prompt commit>` | the label a run's results are grouped under in `--summary` |
| `BENCH_WORK` / `BENCH_RESCORE` | `$TMPDIR/harnest-bench` / `0` | where replays run; `1` re-scores a kept session without a new one, `judge` re-judges only |
| `JUDGE_MODEL` / `JUDGE_PROVIDER` / `JUDGE_EFFORT` / `JUDGE_BUDGET_USD` | `claude-opus-5-5` / `anthropic` / `high` / `1` | the bench's judge |
| `JUDGE_TIMEOUT_SECS` / `JUDGE_TRIES` | `150` / `3` | bound on each judge try, and how many tries |

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
- **Feature lead, design and decompose:** `dontAsk` plus `LEAD_DESIGN_PERMISSION_FLAGS`:
  read-only source, read-only git, read-only `dw`, `gh issue`, `WebFetch`, and writes only
  to /tmp and to its own plan comment. Its builds and close-outs use the implementer's
  flags.

**Guard hooks.** A `PreToolUse` hook,
[`agent-settings/hooks/guard.py`](agent-settings/hooks/guard.py), refuses the protocol
violations that are cheap to spot on a command line, at the moment of the call. The agent
gets the reason back and can correct itself, rather than the audit finding it later.
- The implementer can't close an issue as `completed`, add `status:verified`, lift an
  `owner:don`/`status:needs-approval` park, push to `master`, or force-push.
- The implementer can't hand off (`status:fixed-pending-verify`) with uncommitted changes,
  with `ruff` failing on files it changed, with the UI's `check`/`lint`/`test` failing when
  it changed `ui/`, or with a test failing that passed on `develop`
  when the session began. The driver exports that commit as `HARNEST_BASE_COMMIT`.
- The tester and regression agent can't close as `completed` or add `status:verified` in a
  session that has made no `mcp__dw__*` call.
- No role can add an `owner:*` label without removing one in the same command.

The hook is wired through `agent-settings/implementer.json` and
`guard_settings consumer` (`providers.sh`). It matches command text, so it catches mistakes, not a
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
`[lead:#N]`, `[curator:harnest#N]`. Each role also has its own `.log` and a `.jsonl` of the
raw events.

- `grep usage: logs/loop.log`: one line per session, with turns, duration, cost, peak
  context and token totals. Each session also logs a `model:` line with the resolved id.
- `grep '\[audit\]' logs/loop.log`: drift from the protocol, checked after each session.
  It flags an open issue without exactly one `owner:*` label, a `completed` close by
  anyone but the tester, an issue a session left stranded, and a suite commit that removed
  lines. The audit only logs; it repairs nothing.
- `logs/progress.tsv`: the no-progress ledger. An issue that sessions leave unchanged
  `NO_PROGRESS_PARK_AFTER` times in a row is parked with Don instead of re-run.
- After every cycle, the driver prints a status board with one line per open issue:
  number, status, owner and title.

## Layout

```
run-loop.sh                         the cycle: implementer, feature lead builds, tester, curator review
run-regression.sh                   regression driver
run-features.sh                     feature lead: design and decompose sessions (lock-free)
run-bench.sh                        replay benchmark of the implementer (offline)
run-curate.sh                       suite curation audit: one proposal issue per level
run-retro.sh                        retro: evidenced harness proposals, filed on this repo
run-digest.sh                       one-line-per-issue digest of the owner:don queue
contract/                           script-run regression cases and their MCP client
bench/                              benchmark cases, replay note, results (see bench/README.md)
providers.sh                        provider table and shared helpers (isolation, permissions, logging, audits, queues)
lib/classify.jq                     the ticket protocol's state machine: issue -> queue
measure-base-ctx.sh                 measures turn-1 context for a flag set
agent-settings/implementer.json     auto-mode classifier's picture of the implementer's environment, plus its guard hook
agent-settings/hooks/guard.py       the guard (protocol invariants and the hand-off gate)
agents/                           role prompts; the drivers build each session's from parts (role_prompt)
  implementer/                      core.md + fix.md or triage.md
  tester/                           core.md + verify/handoff/answer/closures/task/spec.md, cases.md, standing-task.md
  lead/                             core.md + design/decompose/build/closeout.md
  regression/                       core.md + run-cases.md + chunk.md or sweep.md
  curator/                          suite curator: audit (run-curate.sh), review (run-loop.sh)
  RETRO.agent.md                    retro role
regression-suite-{smoke,complete,model-specific,security}.md
regression-perf/                    append-only per-case metric history (JSONL)
HARNESS-ROADMAP.md                  planned evolution of the harness
CLAUDE.md                           notes for Claude Code sessions working on this repo
qa-bible.md                         tester's memory across cycles (gitignored)
logs/                               session output (gitignored)
```
