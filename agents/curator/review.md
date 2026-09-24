
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
- **Retirement of a pending case whose stage won't be built.** The case
  still carries `pending: #N`, and stage #N is closed `not planned` (a
  declined feature or a re-plan dropped it). It describes behavior that
  never shipped, so the record settles it. Remove the whole case. Check
  #N's state yourself, and `Grep` for every `pending: #N`.

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
- never a `pending:` line, except by removing the whole case under the
  pending-case retirement above;
- never a `regression-perf/` file.

A retirement deletes the whole case section. Don't commit; the driver
commits after your session, naming this issue.

### 4. Record it and set the issue's state

Comment once on the issue, in Markdown, structured like this — one line
naming your model and provider first, then one `###` heading per item
(its case ID and ruling), each with its own short bullet list underneath.
Never one run-on paragraph with inline labels like "WHY:"/"EVIDENCE:" —
that reads as a wall of text. Use headings and line breaks instead:

    Curator review by <model> (<provider>).

    ### SE-F031 — approved and applied
    - **Why:** the edit narrows a probe, which the request framed as a
      stale reference; it's actually a contradiction the record settles.
    - **Evidence:** dkackman/diffusers-workflow#409, closed completed +
      status:verified (parent #407); #407 plan v2 Q2 says a class is
      always OK, a dtype only under a dtype key.
    - **Edit:** lines 344-346 collapse to one probe: `...`; line 351's
      parenthetical changes to `...`.

    ### <next item> — denied
    - **Why:** ...

  For an escalated item, use the same per-item shape but end its bullets
  with **Recommendation** and **Exact edit** instead of applying anything.
  Keep each bullet to one or two sentences — cite issue numbers and line
  numbers rather than restating the case.

Then:
- **Everything approved, or some approved and the rest denied:** `gh issue
  close <n> --reason completed`. Your ruling comment says which item went
  which way.
- **Everything denied:** `gh issue edit <n> --add-label wontfix`, then
  `gh issue close <n> --reason "not planned"`. The requester may refile
  once with new evidence. A second denial is final.
- **Anything escalated:** leave the issue open, and apply and record the
  rest. Then `gh issue edit <n> --add-label owner:don`. The same comment
  already gives Don what he needs for the escalated items (analysis,
  recommendation, exact edit) — don't write a second one.

The issue then waits for him. Don't touch it again.
