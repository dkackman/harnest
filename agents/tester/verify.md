
## This session: VERIFY one issue

The issue carries `owner:tester` + `status:fixed-pending-verify`; the
implementer's hand-off comment says what shipped.

1. If the hand-off comment or the `breaking-change` label flags a breaking
   interface change, adjust your calls to the new shape first. Don't report
   the shape change itself as a new bug unless it seems accidental or
   undocumented.
2. Re-run the exact repro from the issue body and comments, via MCP.
3. Try 1–2 adjacent cases (edge inputs, the original bug's neighbours) to
   catch a partial fix.
4. Record the outcome — this, not a regression case, is the deliverable:
   - **Matches `expected:`.** Add `status:verified`, remove
     `status:fixed-pending-verify`, comment what you ran and confirmed, then
     `gh issue close <n> --reason completed`.
   - **Doesn't.** `gh issue edit <n> --remove-label
     status:fixed-pending-verify --remove-label owner:tester --add-label
     owner:implementer` (no status label = plain reopened), and comment what
     is still wrong, with the call and the response.
   - **Nothing to observe.** The fix changed only text neither the server
     nor the plugin serves (the README, a `docs/` page `list_guides`
     doesn't index), so no MCP call can confirm it. Don't close it and
     don't bounce it: `gh issue edit <n> --add-label docs-review` and
     comment what you checked and why the rest is out of your reach. A
     read-only docs reviewer runs after you this cycle.
   - **A stage or feature parent** is judged differently. See
     "Verifying a feature" below.
5. Only after that, add a regression case if the verify warrants one (next
   section) — including the one the hand-off comment proposed, now that you
   have run it.

### Verifying a feature

Issues labeled `feature` belong to the feature lead (`owner:lead`), not the
implementer. They come in two kinds:

- **A stage** (label `stage`, a sub-issue of a parent). Step 2's repro is
  the stage issue's own, and on top of it the acceptance is **every case
  marked `pending: #<this stage>`** in the suite files (`Grep` for it).
  You or another tester session wrote those cases from the approved plan
  before the code existed. Run each one exactly as written.
  - **All pass.** Remove the `pending: #<this stage>` line from each of
    those cases. That is the one edit to an existing case you make without
    approval, and it turns them into ordinary regression cases. Then close
    the stage as step 4 says.
  - **Any fail.** Bounce to the lead, not the implementer: `gh issue edit
    <n> --remove-label status:fixed-pending-verify --remove-label
    owner:tester --add-label owner:lead`. Comment each failing case ID with
    the call and the response.
  - **A case that is wrong against the plan**, not against the code (it
    asks for something the plan never promised): don't edit it and don't
    count it. Say so in your comment, and file the amendment through the
    suite approval route (`suite` + `status:needs-approval` on the harness
    repo).
- **A feature parent** handed over after its close-out. Every stage is
  closed. Run every case whose `source:` names one of the parent's stages.
  All pass: close the parent as step 4 says. Any fail: bounce to
  `owner:lead` the same way, naming the case. A case still marked
  `pending: #<stage>` for a stage closed `not planned` isn't run: list it
  in one retire request on the harness repo (`suite` +
  `status:needs-approval`).
