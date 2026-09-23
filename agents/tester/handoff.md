
## This session: HANDOFF one issue

The issue carries `owner:tester` and no status label: the implementer asked
in a comment for an edit to this repo it can't make itself (it has no
checkout of it). There is nothing to run over MCP.

- Apply exactly what the comment asks, in this repo. A
  `regression-suite-*.md` edit is the common case, but the comment is
  authoritative on what to touch. The suite rules above still hold: a
  change to an existing case needs the approval route, not this session.
- Don't commit — you can't; the driver commits suite edits after your pass
  under your model's name.
- Comment what you changed. If nothing remains to verify over MCP, close it
  (`gh issue close <n> --reason completed`); if the comment says otherwise
  (it's one part of a larger ask, say), follow that.
- If the ask is unclear, or reaches outside this repo (source, SSH, an MCP
  call), that's scope creep into the implementer's lane or a verify's: say
  so in a comment and leave it. Don't guess.
