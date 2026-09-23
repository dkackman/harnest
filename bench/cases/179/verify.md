Verified over MCP against dw `0.4.0-beta.4` on `lem` (cuda), workspace `qa-ep17`. Tester agent, model `opus` via provider `anthropic`.

**The exact repro from the body now works.** The same document through both halves of the loop, no key rename:

1. `validate_workflow(workflow={…minimal SD 1.5 t2i, id "alias-179-check"…})` → `valid: true`, `plan.fingerprint: sha256:336b3383d0…`.
2. `run_workflow(workflow={…byte-identical JSON…}, acknowledged_cost={"fingerprint": "sha256:336b3383d0…", "minutes": null, "downloads": []})` → queued as job `62054e5c3a49`, **no** "Provide exactly one of" error. This is the call that failed in the report.
3. `wait_for_job` → `succeeded` in 11.9 s, manifest populated (`alias179-0.0.jpg`), `warnings: []`. So the alias is resolved for real, not merely accepted by the signature.

**Adjacent cases, all as specified in the fix comment:**

- `validate_workflow(workflow_path="templates/text-to-image")` — the stored-name alias, the direction the body asked for on this tool → `valid: true`, real plan with `estimate.basis: "observed"`, `runs: 13`. The alias resolves to the catalog lookup, not to an inline-parse attempt.
- `validate_workflow(workflow=…, inline_workflow=…)` → *"`workflow` and `inline_workflow` are the same thing - provide only one."* Names both parameters, distinct from the exactly-one-of message.
- `run_workflow(workflow_path="templates/text-to-image", name="templates/text-to-image", acknowledged_cost=true)` → *"`workflow_path` and `name` are the same thing - provide only one."* Same treatment on the stored-name pair.
- **Exactly-one-of survives the aliasing**, which was the real risk in an additive change of this shape: `run_workflow(workflow={…}, name="templates/text-to-image")` → *"Provide exactly one of `workflow_path`/`name` (a catalog name or a path to a workflow on the server) or `inline_workflow`/`workflow` (a definition to run as-is)."* And bare `validate_workflow()` with neither a document nor a name → *"Provide exactly one of `workflow`/`inline_workflow` (an inline definition) or `name`/`workflow_path` (a stored workflow)."* Both messages now list both spellings, so the error itself teaches the alias rather than naming one arbitrary half of each pair.
- Both tool descriptions, read from the live schema this session, cross-reference the other tool's naming ("both tools accept both spellings, so a definition or a name checked here can be handed straight to `run_workflow` without renaming a key"). The documentation half of the report is closed too, not just the behavior.

No breaking change observed: the original spellings still work — the calls above used one spelling or the other and none of my existing test shapes had to change.

cleanup: `delete_output("alias-179-check/20260916-131336-41f6921d")`, run directory swept; workspace left as found.

Adding the implementer's proposed case to `regression-suite-smoke.md` now that it is confirmed live over MCP.
