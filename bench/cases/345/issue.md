## #345: validate_workflow passes a pipeline step whose component_type diffusers does not export, and quotes its download; the run dies 3 s in (same class as #285's task.command)
filed by: @dkackman

**tool/endpoint:** validate_workflow (and the plan's downloads_required)
**repro:** `validate_workflow(inline_workflow={"id":"x","steps":[{"name":"g","pipeline":{"configuration":{"component_type":"QwenImage21Pipeline"},"from_pretrained_arguments":{"model_name":"Qwen/Qwen-Image-2.1"},"arguments":{"prompt":"a cat"}},"result":{"content_type":"image/png"}}]})`. Also try any misspelled name, for example `"StableDiffusionXLPipline"`.
**expected:** `valid: false`, with an error at `steps[0].pipeline.configuration.component_type` saying diffusers exports no such class and naming the nearest matches (difflib over `list_pipelines()`). No `downloads_required` quote for a workflow that cannot load.
**actual:** `valid: true` with a 30.9 GB `downloads_required` quote. The run then failed in 3 s with "module diffusers has no attribute QwenImage21Pipeline". `get_class("QwenImage21Pipeline")` answers "diffusers exports no class named 'QwenImage21Pipeline'", which is the check validate skips. (Here the cause was a diffusers older than the model, but the engine cannot tell that from a typo, and the caller has already quoted the size to the user.)
**code:**
- `dw/introspection.py:755-817` `workflow_argument_warnings` resolves `component_type` only to check call arguments. `unknown_call_arguments` (`:352-369`) returns `[]` when `load_pipeline_class` raises, so an unknown class gives no complaint at all.
- `dw/introspection.py:113-142` `load_allowed_class` already produces the right message and respects the dotted-module allowlist.
- `dw/type_helpers.py:6-15`: the runtime uses a bare `getattr(diffusers, name)`, so any bare name that `load_allowed_class` cannot resolve is a guaranteed run failure.
- Precedent: `task_signature_errors` (`dw/introspection.py:540+`, #285) turned an unregistered `task.command` into a validate error.
**proposed fix:** Add a validate error pass beside `task_signature_errors`. For each pipeline step whose `configuration.component_type` is a bare name (matches `_NAME_PATTERN`, not `{...}`-escaped), or a dotted name on `ALLOWED_MODULES`, call `load_allowed_class`. Report its ValueError at `steps[n].pipeline.configuration.component_type`, with up to 3 close matches from `list_pipelines()`/`list_classes()`. Leave dotted names outside the allowlist alone: validate must not import untrusted modules, and the trust gate already covers them. Apply the same pass to scheduler `scheduler_type` and quantization `config_type` wherever the schema carries them, resolved against `list_classes("schedulers")`/`("quantization")` including `sdnq.SDNQConfig`. When this error is present, skip the `downloads_required`/estimate block, or mark it moot. Run it over `workflows/**/*.json` to make sure no catalog entry trips it (as #285 did). Proposed smoke case: the inline repro above returns `valid: false` at that path.
**source:** dw-findings-ledger DW-12 (G#3), triaged 2026-09-22 against develop f11ac2a

---
Filed from Don's dw findings ledger (`dw-findings-ledger.html`, DW-12). First-pass triage for applicability and value against open/closed issues and `develop` @ f11ac2a by claude-opus-5-5 via anthropic (interactive session with Don; code-checking subagents inherited that model).

--- comment by @dkackman at 2026-09-22T22:12:50Z ---
triage: escalate — a new validate_workflow rule (component_type must resolve via load_allowed_class, with suggestions) and a change to when downloads_required is quoted. Strong precedent in #285, but it is new validation surface over dotted names/allowlist, so sign-off first. (claude-opus-5-5 via anthropic, triage session)

--- comment by @dkackman at 2026-09-22T22:17:47Z ---
**Disposition (Don, 2026-09-22): approved.** This is a new validate rule, approved here; it's the same shape as #285.

**Scope:**
- `validate_workflow` resolves each pipeline step's `component_type` with **the same resolver the runtime uses** (`load_allowed_class` / the allowlist path), so the rule can never refuse something that would have run.
- A name that doesn't resolve is an error at `steps[N].pipeline.configuration.component_type`, with up to three close-match suggestions (e.g. difflib against the exportable names).
- A step that fails this check contributes nothing to `downloads_required`, so no download is quoted for a pipeline that can't exist.
- The error must be distinct from the allowlist/security refusal ("not allowed" vs "does not exist").

**Tests:**
- A misspelled class is refused with a suggestion.
- A real class is accepted.
- An allowlisted-but-absent class and a present-but-disallowed class get different messages.
- Downloads aren't quoted for the refused step.

(Recorded by claude-opus-5-5 via anthropic in the triage session with Don.)
