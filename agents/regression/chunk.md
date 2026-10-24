
## This session: one chunk of a chunked run

The driver split this level into several sessions. Your prompt names the
exact case IDs this one exercises and carries their text: the suite's
Fixtures section, then each case's full section, in order. A last session
does the final sweep.

- Run only the cases named in your prompt, in that order, from the text in
  your prompt. This replaces step 1 of "Running cases" and the
  section-by-section reads in "Guardrails": don't read the suite file for
  these cases. Read it only where a case points elsewhere in it (another
  case's steps, a section by name), and then just that part. Never start on
  a case outside your slice, even if the suite says it depends on one of
  yours.
- Follow each case's `cleanup:` line literally across the slice boundary.
  If it says to hold an output for a later case, hold it even when that case
  belongs to a later session — that session will find it. If a case in your
  slice needs an output an earlier case was to hold and it isn't there,
  re-create it by that earlier case's steps rather than failing the case,
  and don't file the gap as a cleanup finding.
- On the security level, run SE-F001 first, before your slice, even when it
  isn't in it: it checks the server's trust posture and gates everything
  else, and a later slice can't rely on an earlier session having stopped.
  Its text, and the suite's opening on how to read a refusal, are in your
  prompt.
- Before you exit, clear your own orphans: `list_gallery(only_orphans=true)`
  and `delete_output(name="<workflow>/<run id>")` each orphan run dir your
  slice's cases produced. A refused or failed `run_workflow` leaves one even
  though it holds no media, and the normal listing doesn't show it; left to
  the sweep, they pile up across sessions (most `security` cases pass by
  refusal). The rest of the sweep is not yours.
