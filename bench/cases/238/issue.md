## #238: list_gallery omits text-only runs in both normal and only_orphans mode, so a .txt deliverable is invisible to the regression sweep
filed by: @dkackman

**Found by:** regression agent, final-sweep session of the chunked `smoke` run, 2026-09-19, model `opus` via provider `anthropic`, workspace `regression-smoke`.

## What happened

Step 5 of the sweep lists the workspace's outputs to decide what to delete. `list_gallery(limit=100)` in `regression-smoke` returned **one** file:

- `templates/generate-speech/20260919-135803-e2e59ab5/GenerateSpeech-speak.0-0.0.wav` (`folders: ["", "templates/generate-speech"]`)

and `list_gallery(only_orphans=true)` returned `runs: []`.

But #237 names a second repro artifact in the same workspace, and it is still there — `get_output_text("templates/transcribe-audio/20260919-135809-2947b3df/TranscribeAudio-transcribe.0-0.0.txt")` returns the 80-character transcript, `text/plain; charset=utf-8`, not truncated. So a run whose only file is a `.txt` is:

- not in the normal `list_gallery` listing (no `templates/transcribe-audio` folder appears at all), and
- not in `only_orphans` mode either, which by its own doc excludes "a run that wrote any file at all - a text-shape prompt, a utility's side output".

Net: a text-only run (`transcribe-audio`, `expand-prompt`, `image-to-text`, any `text`-shape workflow) is invisible to both listing modes, so the sweep — and any consumer trying to leave a workspace as it found it — cannot discover it, and can only `delete_output` it if it already knows the name from the job that made it. That is the same shape as #170 (files `usage` counts that no listing tool can enumerate), one level down: this time the file is a real deliverable, not a sidecar.

## Expected

Either `list_gallery` lists text outputs (with `kind: "text"`, alongside image/audio/video), or `only_orphans` is widened to include runs with no media file. The first seems right: `get_output_text` already treats the file as an output, and the gallery's `url` field would give a text deliverable a view link like every other kind.

## Repro (any workspace)

1. `run_workflow(workflow_path="templates/transcribe-audio", arguments={"input_audio": "asset:qa-cast/hal-voice.wav"})` → succeeds, one `.txt` in the job's manifest.
2. `list_gallery()` → the run's folder is absent. `list_gallery(only_orphans=true)` → absent.
3. `get_output_text(<manifest name>)` → the text is there.

Not filed against a case ID — no suite case asserts gallery visibility of text outputs — but it's a sweep-correctness gap. The two `regression-smoke` artifacts above were left in place, as #237 (open) asks.


--- comment by @dkackman at 2026-09-19T23:38:23Z ---
triage: batch with #238, #242, #246 — three small, independent, self-contained fixes; batched so one branch and one deploy restarts lem once. For #238: `_gallery_entries` in dw/server/app.py lists only `MEDIA_KINDS` (image/video/audio from the security allowlists); add `.txt` as kind `text` so a text deliverable is listed with a view url like every other kind (the `only_orphans` doc is then still correct). Check the MCP `list_gallery`/`get_gallery_metadata` docstrings mention the new kind. (triage by implementer agent, model opus via provider anthropic)
