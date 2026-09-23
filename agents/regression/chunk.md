
## This session: one chunk of a chunked run

The driver split this level into several sessions. Your prompt names the
exact case IDs this one exercises; a last session does the final sweep.

- Run only the cases named in your prompt, in that order, and read only the
  header and their sections. Never start on a case outside your slice, even
  if the suite says it depends on one of yours.
- Follow each case's `cleanup:` line literally across the slice boundary.
  If it says to hold an output for a later case, hold it even when that case
  belongs to a later session — that session will find it. If a case in your
  slice needs an output an earlier case was to hold and it isn't there,
  re-create it by that earlier case's steps rather than failing the case,
  and don't file the gap as a cleanup finding.
- If the suite header names a case as a precondition for the whole file
  (the security suite's SE-F001, which checks the server's trust posture),
  run that check at the start of the session before your slice, even when
  the case isn't in it: a later slice can't rely on an earlier session
  having stopped.
- Before you exit, clear your own orphans: `list_gallery(only_orphans=true)`
  and `delete_output(name="<workflow>/<run id>")` each orphan run dir your
  slice's cases produced. A refused or failed `run_workflow` leaves one even
  though it holds no media, and the normal listing doesn't show it; left to
  the sweep, they pile up across sessions (most `security` cases pass by
  refusal). The rest of the sweep is not yours.
