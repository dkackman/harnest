
## This session: REVIEW one docs-only fix

1. **Find what shipped.** The hand-off comment names the commit(s). Run
   `git show --stat <sha>` and `git show <sha>` for each. Confirm each
   commit is in your tree's history (`git log --oneline -40`; your tree is
   `develop`). A commit that isn't there hasn't reached `develop`: bounce
   it (step 4) saying so.
2. **Not yours.** If the diff also changes anything the server or plugin
   serves — code, `plugins/dw/` (skills), templates, or a guide file (the
   `GUIDES` table in `dw/server/guides.py` lists them) — the tester can
   observe it: remove `docs-review` and leave the issue with the tester
   (`gh issue edit <n> --remove-label docs-review`), with a comment naming
   the served file. Stop.
3. **Check it against the issue.** Read the changed files as they stand in
   your tree, not only the diff: a sentence can be right in the hunk and
   contradicted three paragraphs later. For each thing the issue says is
   wrong:
   - is it fixed, and is every other place the same claim appears fixed too
     (`Grep` the tree for the old wording and its close variants)?
   - is the new text true? Where it describes server behavior, check it
     against what the server says of itself (`get_server_info`,
     `get_schema`, `get_guide`, `list_tasks`), not against your
     expectation. Where it describes this harness (the agent loop), the
     issue and its comments are your evidence.
   - does it introduce a new error: a broken link or anchor, a stale name,
     a claim with no source?
4. **Record the outcome.**
   - **Right.** `gh issue edit <n> --remove-label
     status:fixed-pending-verify --remove-label docs-review --add-label
     status:reviewed`, comment what you read (commit, files, the lines that
     now say what) and what you checked it against, then `gh issue close
     <n> --reason completed`.
   - **Wrong or incomplete.** `gh issue edit <n> --remove-label
     status:fixed-pending-verify --remove-label docs-review --remove-label
     owner:tester --add-label owner:implementer`, and comment each problem
     with the file, the line as it stands and what it should say.
   - **Can't tell** (the claim rests on a decision only Don can confirm):
     swap `owner:tester` for `owner:don`, keep the other labels, and
     comment the one question he has to answer, ending with how to hand it
     back: to `owner:tester` for another review, or close it himself.
