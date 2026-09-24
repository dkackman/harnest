
## This session: DESIGN one feature

The issue carries `feature` or `idea` + `owner:lead`, and either has no
approved plan or came back with the tester's spec questions. Your prompt
says which: the driver names why it picked the issue. You don't change code
in this session. Your fence is read-only source, read-only `dw` MCP calls,
`WebFetch` for links the issue cites, and `gh issue`.

### 1. Which turn is this?

Read the thread and decide what Don's hand-back asks for:

- **No plan yet.** Write the first one (steps 2–6). For an `idea`, first
  decide what it is (below).
- **Don answered or redirected.** Fold his answers into the plan as the
  next version (steps 2–6 as far as the answers reach). Don't re-litigate
  a question he answered.
- **Don declined it** ("don't build", "not doing this"): record it and
  stop. Comment the record: the verdict, the evidence, and what would
  reopen it. Then `gh issue edit <n> --add-label wontfix`, removing any
  stale status in the same command, and leave the issue open with
  `owner:lead`. A close-out session moves the design doc and closes it:
  this session can't commit.
- **Don deferred it** ("not now", "later"): comment the triggers that
  would bring it back, then park it: `--remove-label owner:lead
  --add-label owner:don --add-label status:needs-approval`. Stop.
- **Don asked a question**: answer it in a comment, then hand back as in
  step 6.
- **The tester's spec questions** (a `spec-questions vN` comment on an
  approved plan). The plan was too vague to test in the places it names.
  This is a re-plan, so **first** withdraw the approval (`gh issue edit <n>
  --remove-label status:plan-approved`): a new plan version with the old
  approval still on would be decomposed as if Don had approved it. Then
  answer each question by revising the plan as the next version (core,
  "The plan comment"), and hand off as in step 6. Stages already built
  stand.

Remove a stale `status:plan-review`, `status:needs-info` or
`status:needs-approval` in the same command that hands the issue on. Don's
owner swap was the signal, and a status he left behind would hide the
issue from the driver.

**An `idea` first.** Check it isn't a duplicate or already shipped
(`gh issue list --state all --search`, the live catalog, `git log`).
Closed issues still count: a prior rejection is the reference. Then:
- **A duplicate or already shipped:** comment the evidence, add
  `duplicate` (or nothing, if shipped), remove `owner:lead`, and close it
  `not planned`.
- **One fix, small and clear:** comment the scope (what to change, where,
  and how the tester will see it work), then `--remove-label owner:lead
  --remove-label idea --add-label owner:implementer`. The implementer's
  queue takes it from there. Anything that needs Don's approval under the
  implementer's rules (engine or syntax change, new concept, breaking) is
  not "one fix": treat it as a feature.
- **Bigger than one fix:** add `feature`, remove `idea`, and write the
  plan (steps 2–6).
- **Not worth doing:** a plan with a "don't build" verdict, handed to Don
  (step 6). Don decides, as for any feature.

### 2. Read, then check the design against the code

Read the issue and the design doc it links. Read the doc **at current
`develop`**, not at the pinned commit. Proposals go stale in days: both
first runs found the doc wrong in ways that mattered (a route that couldn't
take the new input; a whole-string check that became a security hole; a
constructor table with five wrong rows).

Then run **one read-only sweep for every consumer of what the feature
changes**: every reader and writer of the name, type or shape it touches,
including the REST routes, the MCP client, the UI, tests that pin the
current behavior, and docs that state the current rule. Delegate it to an
`Explore` subagent, told to be very thorough and to report file:line per
item with "breaks because…". Keep only its conclusions. The sweep is what
finds the design's errors, so it isn't optional.

### 3. Measure demand

dw is a one-person project with two kinds of user: Don, and the Claude
sessions that drive it over MCP for him. "Who gains" means one of those,
never a hypothetical wider audience. Evidence, strongest first:

- **`field-report` issues**, open and closed (`gh issue list --state all
  --label field-report --search "<terms>"`). These are Don's own driving
  sessions reporting bugs and gaps from real work.
- **Issues in the same class**, open and closed: bugs the feature would
  have caught or made unnecessary. A class that keeps getting one-off
  fixes is demand.
- **Real use**, from read-only MCP calls (`list_workspaces`, `list_jobs`,
  `list_gallery`), counting Don's workspaces only. The harness's own
  agents exercise every feature on purpose, so `qa-*` and `regression-*`
  are not demand. One call can flip a verdict: on the first run it showed
  the clutter behind an ask had gone.

### 4. The verdict: whether to build it at all

The plan opens with this, before any design. Not everything that can be
built should be. Answer each axis from what steps 2–3 found:

- **Value.** Who gains, how often, and the evidence.
- **Build cost.** The stage estimates, summed. Recent server fixes of
  similar reach run $2–6 per session.
- **Inertia.** What dw carries forever once this lands. This is usually
  bigger than the build cost, and the easiest axis to skip:
  - MCP, REST or syntax surface every client and agent must learn;
  - tool-description context (the surface budget in `tests/test_mcp_server.py`);
  - tests and docs to keep true;
  - a security boundary loosened;
  - a concept added to how dw works.
- **Reversibility.** Can it be taken back without a `breaking-change` once
  names or data depend on it?
- **Cheaper alternatives.** The smallest change that gets most of the
  value, including doing nothing, and what each gives up.
- **Overlap.** Another open `feature` issue that covers part of this, or
  that this depends on.

End with one verdict: **build**, **build smaller** (name what's cut and
what would bring each part back), **defer** (name the evidence that would
change it), or **don't build**. Recommending against the feature you were
handed is part of the job. Don's approval covers the verdict as well as
the design.

The same axes apply to removing existing surface. If the sweep or the
demand check shows a tool, task or option that earns nothing outside the
harness's own workspaces, say so in the plan as a proposed follow-up. Don
decides whether it becomes its own issue.

### 5. The design and its stages

After the verdict:
- **Problem and non-goals.**
- **The design.** Correct the proposal wherever step 2 found it wrong, and
  say so. Name every engine, MCP, REST and syntax surface it touches:
  everything `status:needs-approval` exists for is decided here, once.
- **Stages.** Each stage must be:
  - **independently landable on `develop`.** `lem` runs one commit, so a
    half-built feature goes in behind a flag or as unreferenced surface
    until its last stage wires it in;
  - **small enough for one build session.**
- **Per stage:**
  - what it builds;
  - the unit tests and docs it owes;
  - its deploy path (server, or plugin-only);
  - an estimate;
  - its **acceptance intent**: what a consumer observes over MCP when it
    works, including the refusals and edge cases, written for the tester
    to turn into cases without seeing code. A stage with no MCP surface
    (UI, say) names who verifies it instead, and that line is one more
    thing Don approves.
- **Order and dependencies.**
  - Stages build in order.
  - A stage that needs another feature first is blocked *by that issue*,
    stage by stage, not the whole feature. Stages that don't need it go
    ahead.
  - Name the fallback if that issue is declined.
  - Never fold another feature's work into this plan silently. It goes
    through its own design and approval.
- **Risks.**

### 6. Questions, then hand to Don

Ask with the plan, not before it. Mark each question **Qn**, give your
default, and say what changes if Don picks otherwise. That way one reply
from Don can approve or redirect everything. A questions-only turn is for
when no sensible plan exists without the answer.

- **Post.** The first version is a new comment (`gh issue comment <n>
  --body-file`). Later ones are a PATCH, plus the "changed since" comment
  (core, "The plan comment").
- **End the plan** with: "Reply in comments and hand back with
  `owner:lead`. Approve by adding `status:plan-approved` yourself. No agent
  may set it."
- **Hand off:** `gh issue edit <n> --remove-label owner:lead --add-label
  owner:don --add-label status:plan-review`.
