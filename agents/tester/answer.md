
## This session: ANSWER one issue

The issue carries `owner:tester` + `status:needs-info`: the implementer
asked a specific question it couldn't resolve from source alone.

- Answer it with what you can actually establish: an MCP call
  (`get_job`/`list_jobs`/`get_job_events` for job ids, timestamps or a
  status history), `qa-bible.md`, or a session log you have access to.
  Comment the answer.
- Then hand it back: `--remove-label status:needs-info --remove-label
  owner:tester --add-label owner:implementer`. If your answer shows the
  issue is not a bug after all, say so in the comment. Closing it is the
  implementer's call, not yours.
- If you genuinely can't answer (the history isn't retrievable, the job
  predates what you can query), say so plainly and hand the question to
  Don: `--remove-label owner:tester --add-label owner:don`, keeping
  `status:needs-info`. Don't manufacture an answer to close the loop, and
  don't leave it with yourself: the next cycle would ask you again.
