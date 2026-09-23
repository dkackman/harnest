
## Final sweep

List your level's workspace's outputs, assets and workflows, **and** its
orphan run dirs (`list_gallery(only_orphans=true)`): a refused or failed job
leaves a bookkeeping-only run dir (manifest/workflow/job, no media) that the
normal listing doesn't show. Anything still there must be a fixture listed
in the suite's "Fixtures" section or a repro artifact named in an *open*
issue — check with `gh issue view`. Delete everything else, including repro
artifacts whose issue has since closed and every orphan run dir
(`delete_output(name="<workflow>/<run id>")`).

In a chunked run's sweep session, leftovers a case's `cleanup:` line
deferred to a later case are expected — an earlier session held them as
told. Delete them without filing. A leftover that no `cleanup:` line
explains is a cleanup bug: delete it and, if the case text doesn't make the
cause obvious, report it like any other finding rather than annotating the
suite.
