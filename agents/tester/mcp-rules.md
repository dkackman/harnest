
## MCP house rules

Durable rules for working the `dw` tools, learned the expensive way. Every
session that calls them loads this; the bible keeps only episode state.

**Waiting**
- `wait_seconds` per family ("Working the MCP" gives the call): `55` by
  default (images, audio, LTX, utility chains); `1500` for MiniMax H3
  video, in one call (the cap is 1800). A `still_running: true` reply is
  followed by `wait_for_job`, never by a second run.
- Don't `cancel_job` a video job under 15 minutes of silence: H3 passes go
  quiet for long stretches and finish. Read `get_job_events` first; a
  cancel throws away the GPU time already spent.

**Workspaces**
- Pass `workspace=` on every call that takes one. The session pin
  (`use_workspace`) is shared state another call or a deleted workspace
  can move (deleting the pinned workspace drops the pin to `default`), and
  `rerun_job` runs in the job's original workspace whatever the pin says.

**Discovery, cheaply**
- `list_models` in its summary form (the default); ask for detail on one
  model only when a case needs it. The full listing is a large result on
  every turn after it.
- `get_gallery_metadata` only on video outputs, where `fps`,
  `duration_seconds` and `frame_count` are what you check; for anything
  else the job's own output listing already says what you need. Its one
  other use: before `keep_output`, an "Unknown asset" reply means the name
  is free.

**Reading outputs**
- `get_output_image` refuses `asset:` references (#445); pass the job's
  output. `get_output_frames` takes either.
- Warnings live in `job.warnings` and `get_job_events`, not in the
  `run_workflow` reply.

**Running and pricing**
- `validate_workflow(arguments=...)` before every run; bind its
  `acknowledged_cost={"fingerprint","minutes","downloads":[]}`, and
  `minutes: null` when its basis is `unknown`.
- `assess_output` is free and takes `asset:`; prefer it to eyeballing a
  frame for seams and dead air.
