
## Close-out

A close-out makes a docs-only commit to `develop` (a branch merged, never
`master`) and never deploys. There are two kinds.

### Declined

The parent is open with `feature` + `owner:lead` + `wontfix`: a design
session recorded Don's "don't build" and left the rest to you.

1. **Keep the analysis for a revival.** `git mv` the design doc to
   `docs/proposals/declined/<slug>.md`. Head it with a status line
   ("declined <date>, #<n>"), why (from the record comment), and any
   corrections the plan found against the old text, so a revival starts
   from the analysis.
2. **Update `docs/proposals/todo.md`.** Move its entry to a "Declined"
   section, and fix any issue range that cited it.
3. **Commit on a branch** (`docs/<n>-decline-<slug>`), merge to `develop`,
   and push. If the issue links no design doc, there's nothing to move:
   skip steps 1–3.
4. **Close its open stages**, if a plan got as far as decomposing: each
   `gh issue close <stage> --reason "not planned"` with a comment naming
   the decline. If any had acceptance cases written (a `specced` marker on
   the parent), file one request on the harness repo to retire them: `gh
   issue create --repo dkackman/harnest --label suite --label
   status:needs-approval`, titled "retire pending cases of declined #<n>",
   listing the stage numbers. The curator removes cases marked `pending:`
   for a stage closed not planned.
5. **Close it:** `gh issue close <n> --reason "not planned" --comment`,
   naming where the design now lives and the commit.

### Built: which turn is this?

All the parent's stage sub-issues are closed, and it carries `owner:lead` +
`status:plan-approved`. Read the thread to tell three turns apart:
- **No design record yet** (no close-out comment of yours): the first time.
  Steps 1–3 below.
- **A tester bounce since your last hand-off, and no fix-forward stage
  filed after it:** the final check failed. See "Back from a failed final
  check".
- **Fix-forward stages filed after the last bounce, all now closed:**
  update the design record (the fix-forward and why), then step 3.

### Built, the first time

1. **Make the design record.**
   - Move the plan into `docs/proposals/complete/<slug>-complete.md`, the
     format the existing `-complete.md` docs use.
   - Record in it what was built, what was deferred and why, what each
     stage cost (read `usage:` figures from the stage comments if they
     name them; otherwise leave cost out rather than guess), and the
     bounces per stage.
   - Delete or retire the old partial doc it supersedes.
   - Update `todo.md`, and any user-facing doc the stages left stale.
2. **Commit on a branch**, merge to `develop`, and push. No deploy: these
   are docs.
3. **Hand the parent to the tester for the feature's last check.** Comment
   what closed, the design record's path, and "verify: run every case
   whose `source:` names one of this feature's stages, and close the
   parent if they all pass". Then `gh issue edit <parent> --remove-label
   owner:lead --add-label owner:tester --add-label
   status:fixed-pending-verify`. Only the tester closes the parent.

### Back from a failed final check

The parent came back from the tester (every stage still closed, a bounce
comment naming failing cases). The design record already exists, so
don't redo it. For each failure, file a fix-forward stage:
`gh issue create --parent <parent> --label feature --label stage --label
owner:lead`, with the failing case ID, the call and the response from the
bounce, and which earlier stage's behavior it concerns. Its acceptance is
the failing case, which already exists, so it needs no new spec. **Then
stop: don't hand the parent off in this session.** The open stage takes
the parent out of the close-out queue. It builds and verifies like any
other, and the parent returns here once it closes, as the third turn
above. If the failure is the plan's own gap rather than a build miss,
re-plan instead (the build fragment's "Stop and re-plan").
