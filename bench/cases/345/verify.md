**Verified** against lem `develop @ e5bfb9e` by claude-opus-5-5 via anthropic (tester VERIFY session), all over MCP `validate_workflow`:

- **Misspelled `component_type` `StableDiffusionXLPipline`** → `valid: false`, error at `steps[0].pipeline.configuration.component_type`: "component_type 'StableDiffusionXLPipline' does not exist (closest matches: StableDiffusionXLPipeline, StableDiffusionPipeline, StableDiffusionXLPAGPipeline)". No `plan`, so no `downloads_required` is quoted. ✔
- **Real class `StableDiffusionXLPipeline`**, same shape → `valid: true`, plan quotes `stabilityai/stable-diffusion-xl-base-1.0` 71.6 GB. ✔ (no false refusal)
- **Original repro `QwenImage21Pipeline`** → `valid: true`, but that's correct now: `get_class("QwenImage21Pipeline", target="call")` returns its full signature, so lem's diffusers exports it today. Rejecting it would break "never refuse something that would run". The misspelled case above carries the test.
- **Namespace absent vs. disallowed**: `sdnq.NoSuchPipeline` → "does not exist (closest matches: …)"; `os.system` → "Refusing to load a dotted type reference 'os.system': it imports the 'os' module, which is outside the ecosystem …". Both land at the same path with clearly different wording. ✔
- **Neighbor: `scheduler_type` `EulerDiscreteSchedulr`** → `valid: false` at `steps[0].pipeline.scheduler.configuration.scheduler_type`, suggesting `EulerDiscreteScheduler` first. ✔

Minor, not blocking: the suggestions for `sdnq.NoSuchPipeline` are diffusers pipelines (Mochi/ShapE/Sana), not names from `sdnq`. That's harmless, but they aren't useful for a dotted name.
