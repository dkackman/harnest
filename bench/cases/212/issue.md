## #212: validate_workflow: refuse result block on judge (scalar-returning) steps
filed by: @dkackman

Split from #209 part 1 (approved by Don; part 2 of #209 stays parked as `owner:don`/`status:needs-approval`).

**tool/endpoint:** `run_workflow` / `validate_workflow`

**repro:** A `judge` step carrying a `result` block:

```json
"result": {"content_type": "text/plain", "subfolder": "intermediate"}
```

(a natural thing to write — the guide's Result Configuration section describes saving text, and `judge`'s score output looks like a fit.)

**expected:** `validate_workflow` refuses `result` on a step whose command returns a scalar rather than an artifact (`steps[N].result`, e.g. "judge returns a number, not an artifact") — caught before queueing.

**actual:** `validate_workflow` → `valid: true`. The job then runs its full fan-out (4 stills, ~2 min GPU in the original repro, job `7f238fbcc108`) and fails only at the end:

```
Workflow execution error: write() argument must be str, not float
  dw/result.py, save_artifact: file.write(artifact)
```

Removing the `result` block fixes it. This is a "refused too late" case — the pre-flight should catch it rather than burning a GPU run.

Prefer a general check (any scalar-returning task rejects `result`) over a `judge`-specific special case, so it also covers future scalar-returning tasks.

Filed by triage per Don's approval to release this half of #209 independently.

--- comment by @dkackman at 2026-09-18T02:15:09Z ---
triage: work — self-contained, already approved by Don as the released half of #209, so no escalation despite being a new `validate_workflow` rule (model opus via provider anthropic). Not a duplicate of #209 part 2 (null-resolving threshold/index stays parked `owner:don`). Pointers for the fix session: `register_command` (`dw/tasks/task.py:35`) carries no notion of what a command returns, so the general check the issue asks for needs a registry-level declaration (e.g. a `returns="scalar"` kind on `judge` and any other scalar task) that a rule in `validation_errors` reads to refuse `steps[N].result` — not a name match on `judge`. Also make the run-time path (`save_artifact`, `dw/result.py`) refuse a non-artifact with a named error rather than `write() argument must be str, not float`, since a `variable:`-driven command name reaches it past validation. Kept separate from #213 (same tester probe, different files and a much heavier fix) so each session has its full budget.

--- comment by @dkackman at 2026-09-18T11:47:28Z ---
triage: already fixed in da32153 on branch `fix/212-scalar-result-validation` (pushed to origin), not yet on develop, not deployed. The fix session should resume from that branch rather than re-fix: it adds `returns="scalar"` to `register_command` (`dw/tasks/task.py`, `judge` declares it), a `dw/scalar_result_validation.py` rule wired into `validation_errors` (`dw/workflow.py`), and a named refusal in `save_artifact` (`dw/result.py`); `tests/test_scalar_result_validation.py` (6 tests) passes. Remaining: run the full suite, merge to develop, deploy to lem, hand off to owner:tester with a regression proposal. Still confirmed as `work` and kept separate from #213. (model opus via provider anthropic)
