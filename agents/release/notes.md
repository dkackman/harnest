
## This session: draft the release NOTES

Your prompt names the last release's tag and three files of what shipped
since then: the issues closed as completed (one per line with its labels),
the pull requests merged into develop, and the open issues whose commits are
in this candidate. A fourth file holds each closed issue's closing comment. A PR or an open issue has no closing comment; read its
commits instead (`git log <tag>..HEAD --grep '#<n>'`, then `git show`). Write the
body of this release's section of `docs/RELEASING.md` (no `### <version>`
heading: the driver adds it) to the exact file your prompt names.

- **Shape.** Follow the previous release's section in `docs/RELEASING.md`
  in your tree. It has three groups, in this order:
  - **Breaking and behaviour changes**, first: anything labeled
    `breaking-change`, plus any change a caller would notice in a call that
    used to work.
  - **New**.
  - **Fixes**.

  Also keep that section's density: one bullet per change a user would
  notice, with the issue number(s) in parentheses. Related issues go in one
  bullet.
- **What's in.** Only what a user of the server, the MCP tools, the
  templates or the UI would notice. Leave out test-only, harness-side and
  suite-text issues, `wontfix`, and anything whose fix was reverted.
- **Check, don't copy.** An issue title says what was wrong, not what
  shipped. For every bullet, read the issue's closing comment (in the
  closing-comments file your prompt names) or the code to say what the
  release actually does.
- **Security fixes.** Describe what is now refused, as the previous
  section does. Don't give a working exploit of the old behaviour.

Write the file once, with `Write`, at the end.
