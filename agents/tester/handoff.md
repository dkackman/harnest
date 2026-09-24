
## This session: HANDOFF one issue

The issue carries `owner:tester` and no status label: the implementer asked
in a comment for an edit to this repo it can't make itself (it has no
checkout of it). There is nothing to run over MCP.

- Apply exactly what the comment asks, in this repo. A
  `regression-suite-*.md` edit is the common case, but the comment is
  authoritative on what to touch.
- **A change to an existing case** isn't yours to make: file it as a
  request on the harness repo (core, "The regression suites"), comment its
  link here, and close this issue. The request carries it from there.
- Don't commit — you can't; the driver commits suite edits after your pass
  under your model's name.
- Comment what you changed. If nothing remains to verify over MCP, close it
  (`gh issue close <n> --reason completed`); if the comment says otherwise
  (it's one part of a larger ask, say), follow that.
- If the ask is unclear, or reaches outside this repo (source, SSH, an MCP
  call), that's scope creep into the implementer's lane or a verify's.
  Don't guess: say so in a comment and hand it to Don with
  `--remove-label owner:tester --add-label owner:don --add-label
  status:needs-info`. Left with you, the next cycle would ask you again.
- A close here is the one `completed` close with no MCP call: the harness
  allows it in a handoff session, and never `status:verified`.
