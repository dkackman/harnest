
## This session: fix one issue

Your prompt names the issue and carries its text; the driver confirmed it
still had `owner:implementer` and no `status:*` label just before starting
you. If a `triage:` comment on it says `batch with #NN ...`, this session
works all of those together: one branch, one deploy, a hand-off comment on
each — resuming from any progress comment an earlier session on the batch
left. Don't pull an unlisted issue in because it looks related; that's what
triage is for, and the other issue's own session is about to start.

### Checks

No `backend:` label on the issue? Add one first ("Backend and target
labels"). Then run "Checks before any fix" above, unless a `triage:` comment
already did — then trust it. `triage: already fixed in <commit> on develop, needs deploy`
means deploy and hand off without re-fixing. If a check ends in a
disposition other than a fix, make it and stop.

### Reproduce

Reproduce it if possible using the code and the logs on `lem` (SSH in, check
logs, run the server locally if needed). Do not rely solely on the tester's
repro text if you can verify independently.

### Fix

- Work on a branch, committing as you go with a message referencing the
  issue number (e.g. `fix(mcp): #42 - correct param validation for
  generate_image`).
- **Leave a resumable trail.** The spend cap can cut you off without
  warning. Push your branch as you go; once you have real progress that
  isn't yet a hand-off, comment the branch name and where you got to on the
  issue (keep `owner:implementer`, no status label). A session that resumes
  it starts from that comment, not from zero.
- Before merging, check your diff against the issue. These are the misses
  that have most often sent a fix back from the tester, and each is visible
  in `git diff` without running anything:
  - **Every item the issue names is covered.** List what it asks for (each
    tool, task, template, docstring copy, probe shape) and point at the
    change and the test for each. Fixing one copy of a docstring, or one of
    two sibling tasks the issue names, covers only that one.
  - **The tests exercise the claim, not a mock of it.** A test that stubs
    the very function, shape or dtype the issue is about passes whatever
    the real code does. At least one test runs the real path the issue
    describes.
  - **What the tester is meant to see reaches MCP.** A warning or note for
    the caller goes through `dw.events.emit_warning` (or the job's
    equivalent), not `logger.warning`, which only reaches the server log.
  - **The hand-off comment will match the diff.** Every claim you are about
    to make ("crops source pixels", "warns on mismatch") must be true of the
    code as committed; if something is only partly done, say so.
- When the fix is committed and its tests pass, merge the branch into
  `develop` (fast-forward or merge commit) and push `develop`. Do this
  *before* deploying, not "once verified": your session ends before the
  tester runs, and `lem` can only be on one commit — a cycle hands off
  several fixes, so a branch deployed on its own is wiped out by the next
  session's deploy. A verify that fails comes back as a fix-forward on
  `develop`. Never merge to `master`.
- Fixes to the `dw` plugin (skills, metadata under `plugins/dw/`) ship the
  same way — merge to `develop` and push — but need no server restart: the
  driver refreshes the tester's plugin copy from `origin/develop` before
  every tester pass, and a branch-only skill fix never reaches it.
- If the fix is one of the decisions under "Park for Don", write a proposal
  (`docs/proposals/` in the repo) instead of the fix, commit it, put its
  path in the parking comment, and stop.

### Deploy

One call, after pushing `develop`, done last and in one go — a session that
dies between stopping the server and restarting it leaves the tester with
"MCP unreachable":

    ssh lem '~/diffusers-workflow/scripts/deploy.sh develop'

Quote it — unquoted, your local shell expands `~` to your Mac home before
ssh sends it. Always deploy `develop`, never your branch. The script
fetches, fast-forwards, reinstalls only if `pyproject.toml` changed, waits
for any running job, restarts the server (systemd unit if installed, else
its `screen` session) and polls health; its last line is the deployed
commit. Don't hand-roll any of that over ssh — no `git pull`, `pgrep`,
`kill`, `screen`, or `sleep` loops — and never `kill -9` the server. The log
is `journalctl --user -u dw-serve` (unit) or `~/dw-serve.log` (screen).
Don't restart the server except to deploy, and confirm it is healthy before
you exit: the tester runs right after you.

If ssh fails, or the script fails or the server doesn't come back healthy,
don't force it and don't hand off: put the script's output in a comment,
add `status:needs-info`, and swap `owner:implementer` for `owner:don`. No
session picks up an `owner:implementer` issue that carries a status label,
so leaving it with you strands it. A plugin-only fix skips this step.

### Hand off

- `gh issue edit <n> --remove-label owner:implementer --add-label
  owner:tester --add-label status:fixed-pending-verify`
- `gh issue comment <n>` with what changed and how it shipped (commit hash
  or diff summary, deploy or plugin-only, timestamp). In a batch, comment on
  each issue exactly what shipped for *it*, so the tester can tell which fix
  it is verifying.
- If every file the fix changed is text neither the server nor the plugin
  serves (the README, a `docs/` page that isn't a guide in the `GUIDES`
  table of `dw/server/guides.py`, other repository prose), add the
  `docs-review` label in the same edit. The tester can't see those files,
  so a read-only reviewer checks them instead. A skill, template, guide,
  docstring or error message is served: no label.
- If the fix breaks the MCP interface (new required param, renamed tool,
  changed response shape), add the `breaking-change` label and say so
  explicitly: the tester's calls are written against the old shape.
- If the fix touches something basic enough that a future regression in it
  would be bad and easy to miss, propose a regression case in the same
  comment: which suite file it belongs in (`regression-suite-smoke.md` for
  fast/fundamental/general-purpose, `regression-suite-complete.md` for
  general-purpose but slower/edge-case-y,
  `regression-suite-model-specific.md` for tied-to-one-model,
  `regression-suite-security.md` for a fix that closed a boundary escape),
  the exact call(s) to make, and the expected result. Don't write it
  yourself: the suite files live in the harness repo, which you don't have
  checked out, and a case isn't confirmed behavior until the tester has run
  it over MCP — the tester adds it when it verifies. Most fixes are one-off
  and warrant no case.
- If a fix makes an *existing* case too expensive to keep running, or no
  longer meaningful, file that on the harness repo — `gh issue create
  --repo dkackman/harnest`, labeled `suite` + `status:needs-approval`,
  naming the case id and why — rather than asking the tester to drop it.
