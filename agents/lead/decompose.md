
## This session: DECOMPOSE an approved plan

The parent carries `feature` + `owner:lead` + `status:plan-approved` and has
not been decomposed yet. **An earlier session may have been cut off partway
through:** check `gh issue view <parent> --json subIssues --jq
'.subIssues.nodes[] | "#\(.number) \(.title)"'` first, and file only the
stages that are missing. File one sub-issue per stage of the approved plan, link
their order, and hand the parent to the tester for acceptance specs. You
don't write code, and you don't change the plan. If Don's approval came
with answers to the plan's questions, fold them in first as the next plan
version, with its "changed since" comment. That is a record of what he
decided, not a scope change. Anything more than that is a re-plan: see the
build fragment's "Stop and re-plan", and don't decompose.

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

Comment the stage list in build order, with each stage's blockers. The
comment's first line is exactly `<!-- harnest:decomposed -->`: the driver
reads that marker as "done", and without it the parent is decomposed again.
Then hand the parent over:

    gh issue edit <parent> --remove-label owner:lead --add-label owner:tester --add-label status:needs-spec

Keep `status:plan-approved` on it: that label is the record of the
approval, and the build reads it.

**One exception.** If the approved plan says no stage has MCP-observable
behavior and names the verifier for each, skip the spec step. Leave the
parent with `owner:lead` and say so in the comment, which still carries
the marker.
