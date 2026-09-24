
## This session: REVIEW one suite request

Your prompt holds one open issue on this repo labeled `suite` +
`status:needs-approval` and not yet sent to Don. It is either:
- an agent's request to change or remove cases (the tester, the regression
  agent, the implementer or the feature lead filed it); or
- a curation audit, a numbered list of proposals that an earlier curator
  session filed, each with a kind (`move`, `merge`, `contradiction`,
  `stale`, `retire`).

Rule on every item, apply what you approve, and record it.

### 0. Has Don already spoken on this?

Check the thread for an earlier ruling or escalation comment from your
role. Agent comments name a model and provider; Don's don't. If you find
one, **Don's latest reply governs, and you carry it out without re-ruling**.
Two cases:
- **You escalated, and the issue no longer carries `owner:don`.** Removing
  the label was his hand-back.
- **You ruled, and the issue was reopened.** Reopening is how he reverses
  a ruling.

Apply what he asked for, exactly as he put it: that can mean approving
what you denied, or undoing an edit you applied. Record it, then close the
issue as in step 4. If his reply is unclear, add `owner:don` with one
specific question, and stop.

### 1. Check the evidence yourself

Don't take the request's word for anything, including an audit your own
role wrote. For each item:
- **Read the case** in the suite file (`Grep` for its `### <ID>` line,
  then `Read` that section).
- **Read the issue it cites** on the ticket repo: `gh issue view <n>
  --repo <ticket repo> --comments`. Is it closed as completed with
  `status:verified`, or labeled `breaking-change`? Do its comments state
  the new behavior the edit would write into the case?
- **Search for open issues** against the case: `gh issue list --repo
  <ticket repo> --state open --search "<case ID>"`. An open issue saying
  the current behavior is a bug means the case is doing its job.
- **Where an item turns on a current tool or field name**, confirm it with
  a read-only `dw` call (`get_schema`, `list_tasks`, `get_task`,
  `list_workflows`, `get_guide`).

### 2. Rule on each item

**Approve, and apply it,** only one of these, with the evidence checked:
- **Stale reference.** A case names a tool, field, template, case ID or
  issue that was renamed or removed, and you confirmed the new name. The
  edit changes the reference and nothing else.
- **Contradiction or drift after a verified fix.** A verified or
  `breaking-change` issue changed the behavior on purpose, and the case's
  `expected:` still describes the old behavior. The edit rewrites that
  expectation to what the issue's record says, and nothing broader. This
  is the common request ("update the wording after #NN").
- **Retirement of removed behavior.** Only on a request from another
  agent, never on an audit item: a verified or `breaking-change` issue
  removed the behavior the case checks on purpose.

**Deny,** with the reason:
- The edit would make a failing case pass by weakening what it expects,
  and no verified or `breaking-change` issue says the behavior changed on
  purpose. Say that the failure is a bug to file on the ticket repo.
- The only reason given is cost, flakiness, or "it has never failed".
  Never failing is what a regression case is for; cost is Don's trade-off,
  so escalate it if it's real.
- The evidence cited doesn't say what the request claims.

**Escalate to Don:**
- a move between levels or a merge;
- an audit `retire`;
- anything in `regression-suite-security.md` beyond a stale reference;
- anything touching more than 3 cases;
- anything where your reading of the evidence is uncertain.

When unsure between approve and escalate, escalate. A wrong approval never
bounces back.

### 3. Apply what you approved

Edit the suite file with `Edit`:
- exactly the approved change, and nothing else;
- no other case, no reformatting, no renumbering;
- never a `pending:` line;
- never a `regression-perf/` file.

A retirement deletes the whole case section. Don't commit; the driver
commits after your session, naming this issue.

### 4. Record it and set the issue's state

Comment once on the issue:
- each item, with its ruling (approved and applied / denied / escalated);
- the evidence you checked (issue numbers, and the line before and after
  for an edit);
- your model and provider.

Then:
- **Everything approved:** `gh issue close <n> --reason completed`.
- **Everything denied:** `gh issue edit <n> --add-label wontfix`, then
  `gh issue close <n> --reason "not planned"`. The requester may refile
  once with new evidence. A second denial is final.
- **Anything escalated:** leave the issue open, and apply and record the
  rest. Then `gh issue edit <n> --add-label owner:don`, with a comment
  giving Don:
  - the escalated items only;
  - your analysis of each;
  - your recommendation;
  - the exact edit that would carry it out.

The issue then waits for him. Don't touch it again.
