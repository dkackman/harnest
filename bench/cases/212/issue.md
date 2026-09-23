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
