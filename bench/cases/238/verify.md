**Verified** over MCP (tester agent, model `opus` via provider `anthropic`).

What I ran:

1. `list_gallery(workspace="regression-smoke", limit=100)` — the original artifact from the report, `templates/transcribe-audio/20260919-135809-2947b3df/TranscribeAudio-transcribe.0-0.0.txt`, is now listed with `kind: "text"`, `size: 80`, a scoped `url` (`/outputs/...txt?workspace=regression-smoke&v=...`), and `templates/transcribe-audio` appears in `folders`. `total: 2` (was 1). `get_gallery_metadata` on it resolves (`source: output`, `job: {id: a2c06f12a985, status: succeeded}`, `metadata`/`media` null — fine for a text file).
2. Fresh repro in a new workspace `qa-verify-238`: `run_workflow(workflow_path="templates/transcribe-audio", arguments={"input_audio": "asset:qa-cast/hal-voice.wav"}, acknowledged_cost=true)` → job `8c65298c65d1` succeeded in ~7s, manifest = one `.txt`. `list_gallery()` → that file, `kind: "text"`, `size: 48`; `get_output_text` returns the 48-char transcript. `list_gallery(only_orphans=true)` → `runs: []` (correct: the run has a real file). `list_gallery(subfolder="final")` → `files: []` but folder still indexed (consistent with how image/audio runs with `subfolder: ""` behave).
3. Adjacent: `delete_output(<the .txt>)` → `deleted: true, run_swept: 20260920-004421-2fa675b6` — the text file now counts as the run's last media file, so the run directory is swept with it; `only_orphans` afterward is still empty and the workspace is clean.

Matches `expected:` (option 1 — text outputs listed with `kind: "text"` and a view url). Closing as completed.

Not covered: the zip-download deflate-vs-stored change in the hand-off comment is not reachable through any MCP tool (zip download is an HTTP endpoint, and `download_output` writes to the server's own disk), so I did not verify it — it stays covered by the implementer's pytest only.

Adding the proposed smoke regression case next.
