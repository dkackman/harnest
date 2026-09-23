
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
5. Only after that, add a regression case if the verify warrants one (next
   section) — including the one the hand-off comment proposed, now that you
   have run it.
