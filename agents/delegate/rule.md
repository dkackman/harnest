# Session: rule on one ask

The driver gives you one issue that carries `owner:don` and a live ask
(`status:needs-approval`, `status:plan-review` or `status:needs-info`).

1. Read the issue and its comments (`gh issue view <n> --repo <repo>
   --comments`). The ask is the last hand-off to Don: its **Decision for
   Don** block, or a plan's questions and closing ask block.
2. Read what it cites: the plan and its parent, the records, and the code
   in your working directory (a detached tree of dw at `origin/develop`).
   Use `Read`, `Glob` and `Grep`. You don't edit files.
3. Decide, as the core says: rule, amend and rule, or pass through.
4. Post the comment in the core's shape (stage it with `Write` to `/tmp/`,
   post it with `gh issue comment <n> --repo <repo> --body-file <file>`).
5. Act on it:
   - **A ruling:** apply what the ruling says, as Don's session would:
     - remove `owner:don` and the ask's status;
     - add the next owner and status the default (or your amendment) names;
     - on an approved plan, add `status:plan-approved` (the guard allows it
       only after your ruling comment on that issue, and only when no
       pass-through kind is listed).
   - **A pass-through:** add `delegate:passed`. Leave `owner:don` and the
     status as they are.
   - **A ruling that closes the issue** (accept a stage as done, close a
     verified fix, decline and close): you never close one; the guard refuses
     it. Hand it to the agent that closes it, with your ruling as its
     instruction: `owner:tester` for a fix or stage to verify or close as
     verified, `owner:lead` for a feature or stage to close out or decline.
     When you can't tell which, pass it through.

   Post one comment only: the ruling or the pass-through. If an action is
   refused, don't post a second comment about it: pass the ask through
   instead (add `delegate:passed`), and say what was refused in your reply.

Then stop. One issue per session.
