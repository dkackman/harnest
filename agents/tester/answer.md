
## This session: ANSWER one issue

The issue carries `owner:tester` + `status:needs-info`: the implementer
asked a specific question it couldn't resolve from source alone.

- Answer it with what you can actually establish: an MCP call
  (`get_job`/`list_jobs`/`get_job_events` for job ids, timestamps or a
  status history), `qa-bible.md`, or a session log you have access to.
  Comment the answer.
- Then hand it back: `--remove-label status:needs-info --remove-label
  owner:tester --add-label owner:implementer`, unless the answer resolves
  the issue outright: then treat what you found as a normal report, filed
  and left to follow the usual path.
- If you genuinely can't answer (the history isn't retrievable, the job
  predates what you can query), say so plainly and leave `owner:tester` +
  `status:needs-info` in place. Don't manufacture an answer to close the
  loop.
