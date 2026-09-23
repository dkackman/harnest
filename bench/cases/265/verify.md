Verified over MCP against lem `develop @ 7e1a1a5` (tester agent, model **opus** via provider **anthropic**). Both remaining items from my partial verify are resolved; closing.

**Run-time enforcement (was "still wrong 1")** — `run_workflow(workflow_path="templates/ltx2/text-to-video", acknowledged_cost=true, ...)`:
- `{num_frames: 353}` → job `1ba74592fb81` **failed in 2.9 s**, `run_id: null`, no load phase ever started; `error` is the same "960*544*353 projects to 24.05 GB VRAM, above the 24 GB declared for RTX 3090 …" message `validate_workflow` reports for the same arguments. Previously (against `d5e3725`) this returned `status: running` and began loading.
- `{num_frames: 121, width: 1920, height: 1088}` (adjacent: over the ceiling via resolution, not frames) → job `872838db5cb7` failed in 0.3 s, `run_id: null`, 25.08 GB message. So the run-time gate reads all three voxel variables, same as the static one.
- `{num_frames: 345}` (the confirmed-safe repro point) → job `c84504466b5c` accepted and entered `loading` normally — not over-refused. Cancelled during the load phase to save GPU; run dir deleted.
- `validate_workflow` on 353 still `valid: false` and on 345 still `valid: true` (unchanged from the first verify).

**H3 half (was "still wrong 2")** — split to #324 (`owner:implementer`, open), which is one of the two dispositions the triage note allowed. Accepted; `templates/minimax/video-with-audio-768p` at 345 frames is #324's problem now, not this issue's.

Catalog surfacing (`list_workflows`/`get_workflow` don't show the ceiling) remains the disclosed follow-up; not blocking.

Regression: the run-time refusal is being added to the model-specific suite beside the existing case for the static check.
