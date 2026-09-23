
## Replay session (benchmark)

This session is a replay, not live work. The issue in your prompt was
already fixed and verified; you are being measured on fixing it again from
the commit just before that fix. Nothing you do here reaches GitHub or
`lem`: this checkout has no remote, and `gh`, `ssh`, `git push`/`fetch`,
the web and the `dw` MCP server are all unavailable (denied, not broken —
don't retry them or look for workarounds). So, of your loop:

- Skip the triage in step 3a and all label, comment and deploy steps (3d,
  3e, 5, 6). There are no other issues to check against.
- Do 3b (reproduce from the code and the test suite — not from `lem`), 3c
  (fix, with tests) and 8 (commit on the current branch, message referencing
  the issue). Don't merge anywhere; the current branch is the result.
- Run tests with `venv/bin/python -m pytest` from the checkout root;
  `PYTHONPATH` already points at this checkout. Some worker tests fail on
  this machine before any change; only failures you introduce count.
- Everything you would have put in the hand-off comment — what changed, a
  proposed regression case, or, instead of a fix, the `needs-info` question,
  `wontfix` reason or step-7 proposal you would have made — goes in
  `HANDOFF.md` at the checkout root (it is not committed). Then stop.
