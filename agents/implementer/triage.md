
## This session: triage

Your prompt lists every issue waiting for you. The job is to decide, cheaply,
what each one is — not to fix anything: do not reproduce, branch or deploy.
For each listed issue, in order:

1. Read it with `gh issue view <n> --comments`.
2. Run the ownership check ("Filed by someone else") and "Checks before any
   fix". Make any disposition they call for (park, duplicate, already
   rejected). For a fix already on `develop` but not deployed, note the
   commit for the fix session rather than deploying it here.
3. Give each issue its `backend:` label if it has none ("Backend and target
   labels").
4. Read only the source a disposition needs, such as a `grep` to see
   whether two issues share a file.
5. From the issue text, decide whether the fix would add **new engine or
   validation surface**: a new task/command, a new `validate_workflow` rule,
   or a wider argument matrix with unchecked edge cases. This is an earlier,
   lower bar than "Park for Don": escalate when a narrow repro-only
   verification could pass while new code paths remain untested.
6. Leave exactly one `triage:` comment on each issue that still needs work,
   in one of these forms:

- `triage: work` — a self-contained fix; its own session will handle it.
- `triage: batch with #NN, #MM — <one line on why>` — issues sharing a root
  cause, a file, or a deploy that would otherwise restart the server three
  times. Put the same comment on every member of the batch; the
  lowest-numbered member's session does the work, and the driver skips the
  others once that session hands them off.
- `triage: already fixed in <commit> on develop, needs deploy` — the
  per-issue session deploys and hands off without re-fixing.
- `triage: needs-info — <the question>`, with the needs-info labels; this
  issue then gets no fix session.
- `triage: escalate — <one line: what new surface this adds and why it
  needs sign-off before a fix session builds it>`, with the "Park for Don"
  labels. No proposal doc at this stage — that's for Don to ask for if the
  scope isn't clear from the comment. The issue gets no fix session until it
  comes back `owner:implementer` with no status label.

Keep comments short: a fresh session will read them without your context.
