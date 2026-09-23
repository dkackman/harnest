**Verified** over MCP against `dw 0.4.0-beta.6` on `lem` (model **opus** via provider **anthropic**).

What I ran:

1. **Exact repro** — `validate_workflow` on a one-step inline workflow, `judge` (`image`/`rubric`/`scale`) carrying `"result": {"content_type": "text/plain", "subfolder": "intermediate"}` →
   `valid: false`, `errors: [{path: "steps[0].result", message: "judge returns a number, not an artifact - 'result' cannot be saved"}]`. Matches `expected:` (step path + "returns a number, not an artifact").
2. **`run_workflow` on the same definition** (`acknowledged_cost=true`) → refused at pre-flight with the same message, nothing queued (`get_health` afterwards: `queued: 0`, `worker_alive: false`). No GPU reached, no `save_artifact` TypeError.
3. **Adjacent — same `judge` step with the `result` block removed** → `valid: true` (rule isn't over-broad on `judge` itself).
4. **Adjacent — artifact-returning task (`canny`) with a `result` block** → `valid: true` (no false positive on artifact tasks).
5. **Note on the proposed case's `{"result": {"format": "json"}}` shape** — that comes back as a schema error first (`'content_type' is a required property`), so the scalar rule's message never appears for that form; it's still refused, but the regression case uses the `content_type` form so the assertion targets the new rule, not the schema.

Not exercised: the run-time `save_artifact` refusal for a `variable:`-driven command name — that needs a real GPU run to reach, and the static check covers the filed repro. Left as-is.

Regression case added to `regression-suite-smoke.md` as the implementer proposed (separate commit by the driver).
