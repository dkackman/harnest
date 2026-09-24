
## This session: DECOMPOSE an approved plan

The parent carries `feature` + `owner:lead` + `status:plan-approved`, and
the current plan version, vN, has no `decomposed vN` marker yet, or has one
but was never handed to the tester (your prompt says which). You make the
parent's stages match plan vN, link their order, and hand the parent to
the tester for acceptance specs. You don't write code, and you don't change
the plan.

If Don's approval came with answers to the plan's questions, fold them in
first as the next plan version, with its "changed since" comment, and
decompose that version. That is a record of what he decided, not a scope
change. Anything more than that is a re-plan: see the build fragment's
"Stop and re-plan", and don't decompose.

### 0. What exists already

`gh issue view <parent> --json subIssues --jq '.subIssues.nodes[] |
"#\(.number) \(.state) \(.title)"'`. Four cases:
- **None:** the first decomposition. File every stage (step 1).
- **Some, from this plan version** (a session cut off partway): file only
  the missing ones.
- **Some, from an earlier plan version** (a re-plan): reconcile. Keep a
  stage the new plan keeps. Edit the body of one it reshaped (`gh issue
  edit --body-file`), saying what changed. Close one it dropped: `gh issue
  close --reason "not planned"`, with a comment naming plan vN. File the
  new ones. A closed stage stays closed: verified work stands.
- **Marker present, hand-off missing** (a session cut off after its
  `decomposed vN` comment): finish step 2 only. For a plan under step 2's
  "One exception", that means posting the `specced vN` comment, not handing
  the parent to the tester.

### 1. File the stages

One `gh issue create` per stage, in plan order:

    gh issue create --repo <repo> --title "#<parent> stage <X>: <what it builds>" \
      --body-file /tmp/stage-<X>.md --label feature --label stage \
      --label owner:lead --parent <parent> --blocked-by <previous stage>

- **`--blocked-by` holds the order.** Every stage but the first is blocked
  by the one before it. A stage the plan says needs another feature is
  also blocked by that issue, comma-separated. The driver builds only a
  stage whose blockers are all closed, so the links alone decide what's
  next. `--blocked-by` takes one word: `--blocked-by 385,376`, never two
  flags.
- **The body** names its section of the plan and links the plan comment,
  which stays authoritative. It restates what the stage builds, what it
  owes (tests, docs), its deploy path, and that it passes when its own
  repro works **and every `pending: #<this issue>` case the tester
  writes**. A stage blocked by another feature names the plan's fallback
  if that issue is declined.
- **Check the links** once all stages are filed: `gh issue view <n> --json
  parent,blockedBy --jq '[.parent.number, [.blockedBy.nodes[].number]]'`
  for each. A stage filed without its blocker would build out of order.

On each cross-feature blocker, comment which stage it now blocks and the
fallback. Don't change its labels: if it's parked with Don, starting it is
his call.

### 2. Hand the parent to the tester

Comment the stage list in build order, with each stage's blockers. On a
reconcile, say which stages are new or reshaped, since only those need new
cases, and which were dropped. The comment's first line is exactly
`<!-- harnest:decomposed vN -->`, with the current plan's version (core,
"Phase markers"). Then hand the parent over:

    gh issue edit <parent> --remove-label owner:lead --add-label owner:tester --add-label status:needs-spec

Keep `status:plan-approved` on it: that label is the record of the
approval, and the build reads it.

**One exception.** If the approved plan says no stage has MCP-observable
behavior and names the verifier for each, skip the spec step. Leave the
parent with `owner:lead`, and post a second comment whose first line is
`<!-- harnest:specced vN -->`, saying no cases are needed and why.
