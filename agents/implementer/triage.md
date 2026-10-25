
## This session: triage

Your prompt lists the issues waiting for you, and any stranded ones (see
"Unstrand" below). Your prompt lists only issues with no `triage:` comment;
leave exactly one on each. The job is to decide, cheaply, what each one is — not to
fix anything: do not reproduce, branch or deploy. For each issue to triage,
in order:

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

## Unstrand

Your prompt may also list **stranded** issues, each with the classifier's
reason: as labeled, no queue will ever pick them up, so no session would
look at them again. This step is the one exception to "Only touch issues
with `owner:implementer`": for these issues you fix the labels, and only
the labels. Do not work, close or reopen one.

What each queue needs (`lib/classify.jq` is the authority):

- `owner:implementer` and no `status:*` → a fix session.
- `owner:tester` + `status:fixed-pending-verify` → the tester's verify.
  `status:needs-info` → it answers a question. `status:needs-spec` → it
  writes a feature's acceptance cases. No status → a harness-side edit
  someone asked it for.
- `owner:lead` + `feature` or `idea` → design. `owner:lead` + `stage` with
  an open parent feature → a build.
- `owner:don` → Don.
- Exactly one `owner:*`. An issue with a `target:` claim needs a backend
  that server serves: `backend:cuda` only on lem, `backend:mps` only off it.

For each stranded issue, read its thread and decide where it belongs.
**Relabel it only when its own record settles that**: the last hand-off or
bounce comment names who acts next, or the reason is one plain slip (a
hand-off that added the status but missed the owner swap; two owners where
one comment clearly superseded the other; `owner:researcher`, which is
`owner:lead` now; a wrong `backend:` the issue text contradicts). Make the
fix in one `gh issue edit`, and comment `unstrand: <old labels> → <new
labels>, because <one line from the record>`. An issue with no owner takes
a bare `--add-label owner:<x>`. A claim that its backend rules out moves to
the server that serves it (`--remove-label target:<x> --add-label
target:<y>`), unless the backend is the label that's wrong.

**Otherwise it goes to Don.** When the record supports two readings, says
nothing, or the fix would be a decision (a stage whose parent is closed or
missing, an `owner:lead` issue that might or might not be a feature, an
owner nobody recognizes), don't guess: swap every other owner for
`owner:don`, add `status:needs-approval`, and comment `unstrand: Don —
<why it's stranded, what's unclear, and the label set each reading would
need>`. If `owner:don` is already among its owners, it is his: remove only
the others. A wrong guess here moves an issue into a session that then
works the wrong thing; a park costs Don one look.
