## #179: validate_workflow takes 'workflow'/'name'; run_workflow takes 'inline_workflow'/'workflow_path' — four names for two things in one documented loop
filed by: @dkackman

tool/endpoint: validate_workflow, run_workflow

repro (workspace `qa-ep17`, tester agent, model `opus` via provider `anthropic`):

1. `validate_workflow(workflow={...inline JSON...})` → `valid: true`, returns `plan.fingerprint`.
2. Carry the same JSON straight into the run half of the documented loop:
   `run_workflow(workflow={...same JSON...}, acknowledged_cost={"fingerprint": "sha256:3035d3f4...", "minutes": null, "downloads": []})`
3. Response:

```
Error executing tool run_workflow: Provide exactly one of `workflow_path` (a catalog name or a path to a workflow on the server) or `inline_workflow` (a definition to run as-is).
```

4. Re-sending byte-identical JSON under the key `inline_workflow` succeeds (job `589964f1a8db`).

expected: the two halves of validate→run name the same two concepts the same way, or at minimum `run_workflow` accepts `workflow` as an alias for `inline_workflow` (and `validate_workflow` accepts `inline_workflow`/`workflow_path`), so a validated document can be moved to the run call without an edit.

actual: four parameter names for two concepts —

| concept | validate_workflow | run_workflow |
|---|---|---|
| inline JSON document | `workflow` | `inline_workflow` |
| stored catalog entry | `name` | `workflow_path` |

Neither tool's description mentions that the other half uses a different key; `validate_workflow` says "Give exactly one of `workflow` or `name`" and `run_workflow` says "Give exactly one of `workflow_path` ... or `inline_workflow`", each internally consistent and mutually silent. The server instructions describe validate→run as one loop, which is exactly the framing that makes the key change surprising.

Cost is one wasted round trip per inline authoring session. It is cheap here because the error message is good and names the right keys, but it is a guaranteed toll on every agent that follows the documented loop for the first time, and it is the kind of thing that gets papered over with a "remember to rename the key" note in an agent's memory file rather than fixed. Aliases would be a non-breaking fix; renaming would not, so treat the alias direction as the cheap one.

notes: filed by the tester agent while running `TESTER_TASK.agent.md` (episode 17), model `opus` via provider `anthropic`.
