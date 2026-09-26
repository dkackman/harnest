# The loop on another server: backend labels and target claims (harnest#15, part 2)

Status: draft for Don's review, 2026-09-26.

## Goal

Run `run-loop.sh` against the dw server on this Mac (M5 Pro, MPS) as well as against
lem, so fixes keep flowing while lem is busy and MPS bugs get fixed and verified on MPS.
The two loops must be able to run at the same time without working the same issue,
and nothing in the Mac loop may reach lem.

Part 1 (done: `DW_TARGET=local ./run-regression.sh`) gave the regression driver a target.
This part does the same for the loop. The flag stays `DW_TARGET=lem|local`.

This is a first, bash-only slice of R13's "target profile" (HARNESS-ROADMAP.md). The
per-target table below holds the deploy command, deployed-head check, source clone and
plugin tree. R13 says a bash profile is worth building only if R8 slips. This one is
kept to the minimum a second server needs, and R8 ports it along with everything else.

## Decisions already made

- Issues are split by **backend** (`shared`, `cuda`, `mps`), not by which server filed them.
- The Mac server runs from a **dedicated clone** that only the deploy touches, not Don's
  working checkout.
- Unlabeled backlog issues are labeled by **triage**, in whichever loop meets them first.
- The Mac loop runs every pass except the three that need lem-specific state (see "Passes").

## Labels

Two label families. They answer different questions.

| label | question | set by | lifetime |
|---|---|---|---|
| `backend:shared` / `backend:cuda` / `backend:mps` | what is the bug about? | the filer, or triage when missing | permanent, but can be corrected |
| `target:lem` / `target:local` | which server's loop is working it? | the driver, when a loop takes the issue | until the issue closes, or until a loop hands it over |

The meaning of `target:local` changes. Today it means "filed by a local regression run",
and the new meaning is "claimed by the Mac loop". #472 and #473 fit either meaning.

### Which loop may take an issue

The rule applies to every agent queue in `lib/classify.jq`: implementer, tester, reviewer
and lead. It is a post-filter, like the release freeze. A new input, `target`, names the
loop asking.

1. A claimed issue (`target:X`) belongs to loop X only.
2. An unclaimed issue is eligible for the loop only when its backend allows it:

   | backend | lem loop | Mac loop |
   |---|---|---|
   | `cuda` | yes | no |
   | `mps` | no | yes |
   | `shared` | yes | yes |
   | none | yes | yes (triage labels it first) |

3. **Legacy rule:** an unclaimed issue past the implementer (`owner:tester`, `owner:lead`,
   or `reviewer:docs`) is lem's. Everything handed off before this change was deployed to
   lem.

An issue ineligible for this loop goes to queue `wait`, with the reason
`claimed by target:lem` or `backend:cuda: not this server`. The digest and board show it
as waiting, not as stranded.

### The claim

- **Adding it.** At the start of the implementer pass, before triage, the driver claims
  every unclaimed issue in its queue: it adds `target:<this loop>` and then re-reads the
  labels.
  - **The race.** An issue that ends up with both `target:` labels is lem's, and the Mac
    loop removes its own label and drops the issue. Triage and fix sessions only ever see
    issues this loop holds, so two loops' triage never disposition the same issue.
  - **A later session.** `still_ready` re-reads the labels just before each session, as
    it does today.
- **Releasing it.** The only release is a hand-over. A session that finds the issue
  belongs on the other server swaps the claim itself: `target:local` → `target:lem`, with
  a comment. Two cases:
  - a Mac implementer finds the issue is really `cuda`;
  - a Mac tester can't meet a repro's precondition, such as a lem-only fixture.
- **Why a hand-over works.** Both loops deploy `develop`. A fix merged by the Mac
  implementer is on lem the next time lem's `check_lem_on_develop` runs, so the lem tester
  can verify it there.

### Filing

- **Regression run on the Mac.** Files `owner:implementer` (was `owner:don`), no claim, with
  a backend:
  - `backend:shared` when the same case also fails on lem (a lem twin exists);
  - `backend:mps` otherwise, and triage can correct it.

  The guard rule becomes "a `backend:` label is required, and the owner is not `don`-only".
  The `target:local` requirement goes away.
- **Tester in the Mac loop.** Files with `backend:` and the same `owner:implementer` as today.
- **lem-side filings.** No new rule for lem's prompts: an unlabeled issue is triaged. The
  prompts gain one line, "add a `backend:` label if you know it".

## Triage and fix

- **Triage** (`agents/implementer/triage.md`) gains one step: every issue it dispositions
  gets exactly one `backend:` label if it has none, judged from the issue text.
  - `cuda`: the bug is about CUDA hardware or a CUDA-only path.
  - `mps`: the same, for MPS.
  - `shared`: everything else, which is most bugs.
- **Fix** (`fix.md`) gains a first step for an unlabeled issue: label it. A Mac-loop fix
  session that concludes `cuda` swaps the claim to `target:lem`, comments why, and ends.
- **Triage batching** only batches issues the loop may take.

## The Mac loop's own things

| thing | lem loop | Mac loop |
|---|---|---|
| driver lock | `logs/.driver.lock` | `logs/.driver.lock.local` (shared with `DW_TARGET=local ./run-regression.sh`, so they serialize like lem's) |
| logs, session files, prompts | `loop.log`, `implementer.log`, … | same names with `.local` (`TARGET_SUFFIX`) |
| no-progress ledger, closures-seen, stop-after-cycle | `progress.tsv`, `closures-seen`, `stop-after-cycle` | `.local` suffixed |
| implementer clone (`SOURCE_DIR`) | `~/src/dkackman/dw-agent` | `~/src/dkackman/dw-agent-mps` (new; `install.sh` venv) |
| serving checkout | lem's `~/diffusers-workflow` | `~/src/dkackman/dw-mps-serve` (new; `DW_LOCAL_DIR` default changes to it) |
| deploy | `ssh lem '~/diffusers-workflow/scripts/deploy.sh develop'` | `deploy_cmd` in providers.sh: `DW_DIR=… DW_WORKSPACE=~/dw-mps-workspace DW_HOST=127.0.0.1 …/dw-mps-serve/scripts/deploy.sh develop` |
| deployed head | one ssh | `git -C $DW_LOCAL_DIR` (exists) |
| plugin tree (`PLUGIN_TREE`) | `~/src/dkackman/dw-agent-plugin`, a worktree of `dw-agent` | `~/src/dkackman/dw-agent-plugin-mps`, a worktree of `dw-agent-mps`. `refresh_plugin_tree` force-resets its tree before every tester pass, so one tree shared by two loops would be reset under the other loop's live session. |
| lead tree (`LEAD_TREE`) | `~/src/dkackman/dw-agent-lead` | `~/src/dkackman/dw-agent-lead-mps`, for the same reason |

- **The deploy.** On macOS there is no systemd, so `deploy.sh` restarts the server in a
  `screen` session named `dw-serve` (`/usr/bin/screen`), logging to `~/dw-serve.log`. It
  runs the server from the clone's `venv`, which is why the clone needs one.
- **`deploy.sh` needs one change first.** It finds the server with `pgrep -f 'python -m
  dw\.serve'`, and that finds nothing on this Mac: Homebrew's interpreter shows up in `ps`
  as `…/MacOS/Python`, capital P. Checked 2026-09-26, `pgrep` exit 1 while the server was
  running. The deploy would then decide nothing is running and start a second server on
  8765, which fails to bind.
  - **Broader matching doesn't fix it.** Matching `[Pp]ython` would SIGTERM every
    `dw.serve` on the machine, including one Don starts by hand from his working
    checkout. lem only ever runs one; the Mac doesn't.
  - **The fix.** Find the server by what listens on `DW_PORT`
    (`lsof -ti tcp:$DW_PORT -sTCP:LISTEN`), falling back to today's `pgrep` where `lsof`
    is missing. That behaves the same on lem.
  - **Who makes it.** This is a dw-repo change (`scripts/deploy.sh`), and the implementer
    can't deploy it while lem is off limits. Proposed: I make it on a branch in the dw repo
    as `docs-review`-style text-only tooling, and Don merges it to `develop`. It changes
    nothing the server or plugin serves.
- **One-time switch.** Don stops his hand-started server, and the first
  `deploy_cmd` starts the clone's. A `scripts/setup-mac-loop.sh` makes both clones and
  their venvs, and does nothing if they already exist.
- **Develop mismatch.** `check_lem_on_develop` becomes `check_target_on_develop`, using
  `deploy_cmd`.
- **Implementer settings.** A second file, `agent-settings/implementer.local.json`,
  describes this environment to the auto-mode classifier: no remote box, and
  `deploy_cmd` as the deploy. The guard (implementer role, `HARNEST_TARGET` not lem)
  refuses any `ssh`.

## Prompts

As with the regression run, each role's lem wording stays. Only one role gets a target
section, appended to the system prompt when the target isn't lem:
`agents/implementer/target.md`, which covers the deploy command, no ssh, the claim
hand-over, and MPS timing. The tester's verify and handoff sessions get
`agents/tester/target.md`, which covers:

- timings judged against this server's own history;
- a hand-over to lem when a precondition is lem-only;
- security path equivalents;
- suite cases, per "Suite edits" below.

## Suite edits from the Mac loop (a change to what you approved: rule on it)

You approved the Mac loop without suite edits. This proposes one exception, for you to
accept or strike. If you strike it, the Mac tester proposes every case in its verify
comment, and the lem tester or you add them later.

The tester adds a case when it verifies a fix. From the Mac loop:

- `backend:shared` fix: the tester may add the case, since every suite runs on lem too. A
  shared case that then fails on CUDA is a real finding. The guard allows suite `Edit`
  for the tester role on a non-lem target, but not for the regression role.
  `commit_suite_changes` commits suite files from a Mac-loop tester session. The
  suite-commit lock already serializes it against lem.
- `backend:mps` fix: no suite edit. The case goes in the verify comment, marked
  `proposed case (mps level, harnest#16)`, until an MPS level exists.

## Passes

| pass | Mac loop | why |
|---|---|---|
| implementer triage + fix | yes | |
| tester verify / handoff / answer / closures | yes | |
| reviewer (docs) | yes, unless the lem loop is running | no server; one loop only, so two don't review the same fix |
| curator review | yes, unless the lem loop is running | no server; same reason |
| feature design / decompose (`run-features.sh`) | yes, unless the lem loop is running | read-only; its `dw` calls go to the Mac server |
| tester standing task | **no** (closures still run on their own cadence) | `qa-bible.md` is lem's memory, its series uses lem's qa-cast media, and it is the costliest session. Needs a per-target bible first. |
| tester spec, lead build / closeout | **no**: those issues stay at `wait` on the Mac | a multi-stage feature should be built and verified where CUDA sees it; spec cases go into suites that run on lem |

"The lem loop is running": both loops run on this Mac. At the start of each cycle, the
Mac loop checks `logs/.driver.lock`. The server-free passes stay with the lem loop when
that lock's holder pid is alive and is `run-loop.sh`, not a regression run. The lem loop
always runs them. `SHARED_PASSES=0|1` overrides the check.

## lem loop changes

The same code runs there. What changes for lem:

- it skips `backend:mps` issues and `target:local` claims;
- it claims unclaimed issues as `target:lem`;
- its triage labels backends.

The regression agent's side is reworded in backend terms, because `target:local` now
means a claim, not "filed from the Mac":
- **`agents/regression/target.md`.** "Only `target:local` covers a failure here" becomes:
  - an open issue for the same case covers it when its backend covers this server
    (`shared`, `mps`, or none);
  - the rule never to comment on a lem-claimed issue stays.
- **The guard's filing rule.** It changes as in "Filing": a `backend:` label is required,
  and `owner:implementer` is allowed.
- **Comments.** The guard's comment rule becomes: no comment on an issue claimed
  `target:lem`.

The release gate stops excluding every `target:` issue. It blocks on open regressions
except `backend:mps`, which it lists but doesn't block on (Don can change that).

## Tests

- **`test-classify.sh`:** boards for each eligibility row, per target:
  - a claim;
  - the legacy rule;
  - a claim on a tester-queue issue;
  - the release freeze combined with a claim.
- **`test-drivers.sh`:**
  - the Mac loop claims and fixes a shared issue;
  - it skips a cuda issue and a lem claim;
  - it runs alongside the lem loop's lock;
  - a hand-over swaps the claim;
  - `deploy_cmd` is stubbed;
  - the lem loop skips a `target:local` claim.
- **`test-guard.sh`:**
  - the implementer's ssh is refused on local;
  - a tester suite edit is allowed on local, and a regression one refused;
  - the new filing rule.
- **`test-providers.sh`:** per-target state file names, `deploy_cmd`.

## Out of scope (follow-ups)

- A per-target `qa-bible` and the standing task on the Mac.
- The MPS suite level (harnest#16).
- Lead builds on the Mac.
- Relabeling the open backlog in one go. Triage does it as it meets issues. A one-off
  `gh` sweep is possible if Don wants it sooner.

## Open questions

1. The release gate for `backend:mps`: listed but not blocking (proposed above), or
   blocking?
2. **How CUDA sees a shared fix verified only on MPS.** It merges to `develop`, and lem
   deploys it at the lem loop's next `check_lem_on_develop`. Nothing re-verifies it on
   CUDA, which is the argument that kept lead builds off the Mac. Options:
   - accept lem's next regression run as the check;
   - have the Mac tester close it with a `verified-on:mps` label, and the lem tester
     re-verify such issues when it has a free cycle.

   Proposed: the label, which is cheap and visible, with the re-verify deferred.
3. **The `deploy.sh` fix.** Proposed above: I write it, you merge it. Or you'd rather
   make it yourself.
4. Budgets: MPS is 2-3× slower, so tester sessions wait longer on jobs. Keep
   `TESTER_BUDGET_USD` at 5 for the Mac loop, or give it a per-target default?
