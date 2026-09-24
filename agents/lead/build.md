
## This session: BUILD one stage

The stage issue carries `stage` + `owner:lead` and no status. Its blockers
are closed, and its parent carries `status:plan-approved` with the current
plan's stages filed and specs written (its `decomposed` and `specced`
markers). Your prompt holds the stage issue and the parent's approved plan.
The plan is the specification. The tester has already written acceptance
cases from it (`pending: #<this stage>` in the harness's suite files),
which you can't see and must not try to. Build what the plan says, and
the cases will test what the plan says.

### 0. Where does this stage stand?

- **A progress comment** from an earlier session (branch, where it got
  to): resume from it.
- **A bounce**: the tester sent the stage back with what failed. The
  bounce comments are the specification now, on top of the plan. A fix
  that satisfies the plan's words but not the bounce will bounce again.
- **A blocker closed `not planned`**: apply the plan's named fallback for
  it. If the plan names none, re-plan (below).

### 1. Build, fanning out code-only work

Work on a branch, `feat/<parent>-<stage letter>-<slug>`. Commit as you go
with `feat(<area>): #<stage> - …`, and push the branch early. A spend cap
you can't see can end the session. Once there's real progress that isn't
yet a hand-off, comment the branch and where you got to on the stage issue,
keeping `owner:lead` and no status. The next session resumes from that.

Use subagents (`Agent`, always in the foreground: core, "Sessions") for
code-side work that splits cleanly:
- the stage's code in separate git worktrees, where parts don't share files;
- unit tests;
- docs and skill text;
- read-only sweeps.

Rules for subagents:
- Give each one a precise brief: files, functions, the plan's words, and
  what done means.
- Run code-writing workers on `model: "sonnet"` unless your prompt says
  otherwise, and read-only sweeps on `"haiku"`. Every worker's output meets
  your review, pytest, the hand-off gate and the tester, so a cheaper
  model is safe there.
- **No subagent deploys, uses ssh, or calls a `dw` MCP tool.** Only this
  session touches `lem`, once, at the end.
- **No subagent verifies behavior as a stand-in tester.** You wrote its
  brief after reading the code, so it would check what you told it to look
  for. Verification is the tester's, launched by the driver.

Then integrate: read every worker's diff yourself, run the full `pytest`
and `ruff`, and fix what they missed.

### 2. Before merging, check the diff against the plan

These are the misses that most often send work back from the tester, and
each is visible in `git diff`:

- **Every item the stage names is covered.** List what the plan's stage
  section asks for, and point at the change and the test for each.
- **The tests exercise the claim, not a mock of it.** At least one test
  runs the real path the plan describes.
- **What the tester is meant to see reaches MCP.** A note for the caller
  goes through `dw.events.emit_warning` or the response, not
  `logger.warning`.
- **The stage is landable alone.** `develop` with this stage and without
  the later ones is a working server with no half-exposed feature.

### 3. Merge, deploy, hand off

- Merge the branch into `develop` and push `develop`. Never `master`.
- **Deploy.** One call, last, in one go:
  `ssh lem '~/diffusers-workflow/scripts/deploy.sh develop'` (quoted, so
  your shell doesn't expand `~`). Its last line is the deployed commit.
  - Never hand-roll the deploy over ssh, and never `kill` the server.
  - A plugin-only stage skips this step: the tester's plugin tree follows
    `origin/develop`.
  - If the deploy fails or the server doesn't come back healthy, don't
    hand off. Comment the output, then `--remove-label owner:lead
    --add-label owner:don --add-label status:needs-info`.
- **Hand off.** `gh issue edit <stage> --remove-label owner:lead
  --add-label owner:tester --add-label status:fixed-pending-verify`. A
  stage the plan says isn't verifiable over MCP goes to its named verifier
  instead: `--add-label owner:don` in place of `owner:tester`, with the
  steps to check it in the comment; Don closes it himself. Then comment:
  - what shipped (commit and deploy line);
  - which plan items it covers;
  - any deviation from the plan and why. A deviation the tester doesn't
    know about reads as a bug.
  - If the stage changes an existing MCP shape, add `breaking-change` and
    say so.
- **Don't write or propose suite cases.** The tester already wrote the
  stage's cases from the plan, and those are its acceptance.

### Stop and re-plan

Sometimes building a stage shows the approved plan doesn't hold:
- an assumption fails against the code;
- the stage is clearly bigger than one session;
- a later stage's shape has to change.

Then don't bend the code to fit the words. Stop, in this order:
1. Push what you have to the branch, if anything is worth keeping.
2. **Withdraw the approval first:** `gh issue edit <parent> --remove-label
   status:plan-approved`. That stops every stage from building. Do it
   before touching the plan: a new plan version with the old approval
   still on would be decomposed as if Don had approved it.
3. Comment on the stage what broke the plan.
4. Revise the plan as the next version, with its "changed since" comment
   (core, "The plan comment").
5. Hand the *parent* to Don: `gh issue edit <parent> --add-label
   status:plan-review` plus the owner swap from its current owner to
   `owner:don`. The new version makes the old `decomposed` and `specced`
   markers stop counting, so after his approval decompose reconciles the
   stages with the new plan and the tester specs what changed.
6. Leave the stage with `owner:lead`, no status.

Stages already verified stand. Don's approval covered the plan as written,
not whatever the build turns into.
