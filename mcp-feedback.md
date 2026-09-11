# diffusers-workflow MCP — Feedback Log

Rules for both agents:

- Never delete or rewrite another agent's entries — only append new entries or edit the `status` line of an entry you own the next step of.
- Each entry gets a unique ID: `T001`, `T002`, ... increment from the last one in this file.
- `owner` = whose turn it is to act next: `implementer`, `tester`, or `don` (the human).
- Do not start new work if there is an open ticket with `owner: tester` and you are the implementer, or vice versa — that ticket isn't yours yet.
- `wontfix` is the implementer's call, with the reason in `notes:`. The tester may reopen it once with materially new evidence; a second `wontfix` is final.
- `duplicate` closes a ticket in favour of another, named in `notes:`. The implementer triages for duplicates and already-shipped fixes before working a ticket.
- `needs-approval` + `owner: don` parks a ticket pending a human decision. Neither agent touches it — no notes, no re-triage, no early work — but it stays canonical for duplicate detection. It comes back as `open` / `owner: implementer` when approved, or `wontfix`.

---

## T000 (template — copy this block for new tickets)

- **status:** open | fixed-pending-verify | verified | wontfix | duplicate | needs-info | needs-approval
- **owner:** implementer | tester | don
- **reported:** <ISO timestamp>
- **title:** short one-line summary
- **tool/endpoint:** which MCP tool or method this concerns
- **repro:** exact call made (tool name + params, or command run)
- **expected:**
- **actual:**
- **notes:** (implementer fills in on fix: what changed, commit/deploy ref)
- **verify-notes:** (tester fills in on re-test)

---

## T001

- **status:** verified
- **owner:** tester
- **reported:** 2026-09-11T12:14:00Z
- **title:** loop_audio task — room-tone bed under cuts (#2b)
- **tool/endpoint:** new task `loop_audio`; composes with `mix_audio` + `pair_audio`
- **repro:** any cut between shots; the seam has a hole with no ambient bed under it
- **expected:** `loop_audio(source, target_frames, fps, crossfade_ms)` produces a bed of the requested length from a short room-tone source, which `mix_audio` lays under the cut and `pair_audio` attaches. A template (`dialogue-short`) demonstrates the pattern.
- **actual:** no way to generate a bed; the seam hole has no complete fix.
- **notes:** New task `loop_audio(audio, duration_seconds | target_frames+fps, crossfade_ms=250, sample_rate)` in 6a048ba - makes a bed of a requested length out of a short recording, laps joined with an equal-power crossfade so the loop point neither clicks nor ticks, only the last lap trimmed so the bed lands exactly on the length asked for. Composes as `slice_audio` -> `loop_audio` -> `mix_audio` -> `pair_audio`; documented in docs/TASKS.md with that chain, and the `concat_videos` seam advice now points at it as the complete fix.
  Deliberately **not** wired into `dialogue-short`: your own note says the demo wants a bed measured from real H3 output first, and I have no such measurement. That part stays open - if you capture a few seconds of usable room tone from a shot and say what it measured, I will wire the template step.
  Deployed to lem 2026-09-11T15:27Z: `~/diffusers-workflow` moved from `master` to `develop` at 3e026c4 (merge of branch `mcp-feedback-round-1`), server restarted in its screen session with the same command line and confirmed healthy (`/api/health` ok, device cuda, mcp mounted). Full suite on lem: 3374 passed, 5 skipped.
- **verify-notes:** Verified 2026-09-11T15:31Z in workspace `qa-ep1`, job `e22451d960f6` (inline workflow `QaEp1AudioSpine`). The chain runs as documented: `slice_audio` -> `resample_audio` -> `loop_audio`, with `loop_audio(audio=previous_result:resample_a, target_frames=124, fps=25, crossfade_ms=250)` turning a 1.0 s source into a bed of exactly **4.96 s** at 16000 Hz - 124/25 to the sample, so `target_frames`+`fps` does land a bed on a cut exactly.
  The joins are real joins, not butts: `get_gallery_metadata(..., envelope=true)` on the bed shows five per-second bins whose `peak_dbfs` are identical (-28.886, the same lap five times) while bin 4's `rms_dbfs` sits ~3 dB above the others where a crossfade overlaps. `get_task(loop_audio)` matches the signature in your note.
  Still outstanding, and I am not holding this ticket for it: `dialogue-short` does not use `loop_audio`, waiting on a room-tone measurement from real H3 output. I have none - the template cannot complete a run right now (T005, reopened this cycle). I will capture the measurement and file it as its own ticket once a run gets through.

## T002

- **status:** verified
- **owner:** tester
- **reported:** 2026-09-11T12:14:00Z
- **title:** compose_text task — assemble character bibles per shot (#8)
- **tool/endpoint:** new task `compose_text`; consumes `previous_result:compose_shot_n`
- **repro:** authoring any multi-shot template that reuses a character description across shots
- **expected:** character bibles are written once and assembled into each shot's prompt as a task step, so a shot references prior results rather than duplicating text.
- **actual:** the only assembly mechanism would be `{{var}}` interpolation, which the no-interpolation rule in `docs/WORKFLOW_GUIDE.md:285` exists to forbid; authors hand-copy instead. See T007.
- **notes:** New task `compose_text(parts, separator="\n\n", skip_empty=True)` in 0f8d54e. Positional parts, not named: a named form (`{bible} says {line}`) would be the interpolation the engine deliberately does not have, one layer down. Each part is a whole value - `variable:`, `prompt:`, `previous_result:` - joined in order; a null part drops out, so an optional bible can be a variable left null; a part that is not text or a number is an error naming the position, since it means that reference resolved to something other than the text meant.
  A shot then references the composed result: a `compose_text` step named `shot_1_prompt`, and the shot's `prompt` is `previous_result:shot_1_prompt`. Documented in docs/TASKS.md ('Composing Text') and beside the no-interpolation rule in docs/WORKFLOW_GUIDE.md, which is where an author meets the problem.
  Deployed to lem 2026-09-11T15:27Z: `~/diffusers-workflow` moved from `master` to `develop` at 3e026c4 (merge of branch `mcp-feedback-round-1`), server restarted in its screen session with the same command line and confirmed healthy (`/api/health` ok, device cuda, mcp mounted). Full suite on lem: 3374 passed, 5 skipped.
- **verify-notes:** Verified 2026-09-11T15:31Z, workspace `qa-ep1`, job `e22451d960f6`, step `line_a`: `compose_text(parts=["variable:character_a_name", "variable:character_a_line", "variable:optional_note", "variable:take_number"], separator=" ")` with `optional_note` declared null and `take_number` the integer 1. `get_output_text` on the step's file returns `PRIYA The pistachio is gone, Hal. Again. 1` - so both documented edges hold: a null part is dropped and takes its separator with it, a number is written out.
  The shape the ticket was actually about works end to end too: the next step took `"text": "previous_result:line_a"` and spoke the composed block, which is the 'shot references the composed result' pattern rather than interpolation.

## T003

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T12:14:00Z
- **title:** List-driven step count for generation templates (#7)
- **tool/endpoint:** workflow engine — `for_each` over a variable
- **repro:** `music-video` and `dialogue-short` templates; each generates one step per shot
- **expected:** a `shots: [...]` variable fans out generation steps, one per list entry.
- **actual:** step count is fixed in the template; adding a shot means editing the template. `assemble-and-score` already takes a list after PR-1, so the consumer side has precedent.
- **notes:** Still mine - not in this deploy, and not a wontfix. Working it turned up a design decision the ticket does not settle, and half of it would be worse than none:
  A `for_each` that fans a step out per list entry has to answer how the *downstream* step names the group. `previous_result:shot` today means 'that step's result', and a result that is a list drives the **cartesian iteration** the engine already has (4 images x 3 masks = 12 runs) - so a fanned-out group read back through `previous_result:` would run the concat once per shot instead of once over all of them. Gathering and iterating are two different meanings and the reference syntax currently has one. That plus expanded step names, step cache keys (keyed on workflow id + step name), the manifest and the realized workflow is a proposal, not an edit.
  Next cycle: a written proposal in docs/proposals/ for the naming and gather syntax, then the implementation. Nothing needed from you in the meantime.
  From Don: Write the proposal and then hand it to Don as needs-approval
- **verify-notes:**

## T004

- **status:** verified
- **owner:** tester
- **reported:** 2026-09-11T12:14:00Z
- **title:** Per-second level envelope from probe_media (#6)
- **tool/endpoint:** `probe_media(path, envelope=True)`
- **repro:** `probe_media(path)` on any clip
- **expected:** with `envelope=True`, response includes `[rms_dbfs per second]`. Default call (no flag) is unchanged and stays small.
- **actual:** no per-second level data available from the MCP.
- **notes:** `probe_media(path, envelope=True)` in 28afbcf, carried by `GET /api/gallery/{name}/metadata?envelope=true` and MCP `get_gallery_metadata(name, envelope=True)`. Answers `media.envelope = {interval_seconds: 1.0, rms_dbfs: [...], peak_dbfs: [...]}`, one entry per second, from the decode pass the probe already makes - no second pass. Opt-in exactly as you asked: the default call is byte-for-byte what it was.
  Two things to know when you check it. The bins are cut on second boundaries regardless of how the decoder chopped the frames, so `max(peak_dbfs)` equals the whole-track `peak_dbfs` and the per-second power averages back to `mean_dbfs`. And a lossy container (aac/mp3) decodes its own priming and padding, so the list can run one near-silent bin past the reported duration - that is real decoded audio, not a bug.
  Deployed to lem 2026-09-11T15:27Z: `~/diffusers-workflow` moved from `master` to `develop` at 3e026c4 (merge of branch `mcp-feedback-round-1`), server restarted in its screen session with the same command line and confirmed healthy (`/api/health` ok, device cuda, mcp mounted). Full suite on lem: 3374 passed, 5 skipped.
- **verify-notes:** Verified 2026-09-11T15:31Z, workspace `qa-ep1`. `get_gallery_metadata("QaEp1AudioSpine/.../QaEp1AudioSpine-bed.4-0.0.wav", envelope=true)` returns `media.envelope = {interval_seconds: 1.0, rms_dbfs: [5], peak_dbfs: [5]}` over a 4.96 s track - one entry per second, as asked.
  Both invariants you named check out on real data: `max(peak_dbfs)` equals the whole-track `peak_dbfs` exactly (-28.885827371877546 both places), and the per-second rms power-averages back to `mean_dbfs` (I get -49.97 from the five bins against -49.97095 reported). The default call - same tool, no flag, on the `resample_a` file - came back with the old `media` block and no `envelope` key at all, so the opt-in is honoured.
  No lossy-container padding bin to report: this was a wav.

## T005

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T12:14:00Z
- **title:** Template variable names leak the example cast (#11)
- **tool/endpoint:** `dialogue-short` template variables
- **repro:** run `dialogue-short` with characters Priya and Hal; inspect arguments, manifest, and export
- **expected:** role-based names: `character_a_portrait_prompt`, `shot_3_react`, `shot_4_button`, etc. The beat names are the reusable part.
- **actual:** every run carries `howie_portrait_prompt`, `pat_portrait_prompt`, `shot_3_howie_incredulous` through arguments, manifest, and export regardless of cast.
- **notes:** Renamed in e61203b. **Breaking for your scripted calls** - the new names are:
  `howie_portrait_prompt` -> `character_a_portrait_prompt`; `pat_portrait_prompt` -> `character_b_portrait_prompt`; `shot_2_pat_deflects` -> `shot_2_deflect`; `shot_3_howie_incredulous` -> `shot_3_react`; `shot_4_pat_button` -> `shot_4_button`. `shot_1_cold_open` and `shot_5_tag` are unchanged. Step names moved with them: `draw_howie` -> `draw_character_a`, `draw_pat` -> `draw_character_b`, and each shot step takes its variable's name, so a manifest and an export read in roles now.
  Deployed to lem 2026-09-11T15:27Z: `~/diffusers-workflow` moved from `master` to `develop` at 3e026c4 (merge of branch `mcp-feedback-round-1`), server restarted in its screen session with the same command line and confirmed healthy (`/api/health` ok, device cuda, mcp mounted). Full suite on lem: 3374 passed, 5 skipped.
- **verify-notes:** The renames themselves are in, and read well: `get_workflow(variables_only=true)` shows `character_a_portrait_prompt`, `character_b_portrait_prompt`, `shot_2_deflect`, `shot_3_react`, `shot_4_button`, and the full definition shows steps `draw_character_a` / `draw_character_b` with each shot step named for its variable.
  **But the rename missed the last step, and it breaks the template outright.** The `episode` step still reads:
      "videos": ["previous_result:shot_1_cold_open", "previous_result:shot_2_pat_deflects", "previous_result:shot_3_howie_incredulous", "previous_result:shot_4_pat_button", "previous_result:shot_5_tag"]
  Three of those five name steps that no longer exist.
  Two things make this expensive rather than merely wrong. `validate_workflow(name="templates/minimax/dialogue-short")` returns `valid: true, errors: [], warnings: []` - `previous_result:` references are not checked at validation the way `variable:` ones are. And references resolve lazily, per step, at run time: I confirmed that with a two-step probe (job `cb1cf194b3fe`, workspace `qa-ep1`) where step `first` ran to completion and wrote its file before step `second` failed with `Previous result 'first_renamed' not found`.
  So a `dialogue-short` run draws both portraits, generates all five H3 shots - the 42 minutes the catalog entry quotes - and then dies on the concat with no episode assembled. Nothing warns first. Back to you; this is also what blocks T010.

## T006

- **status:** verified
- **owner:** tester
- **reported:** 2026-09-11T12:14:00Z
- **title:** No cheap way to read a stored workflow's variable defaults (#12)
- **tool/endpoint:** `list_workflows`, `get_workflow`
- **repro:** try to confirm `audio_bleed_ms` defaults to 1800 for a stored workflow
- **expected:** some call returns variable names *and* default values without the full workflow body.
- **actual:** `list_workflows` returns `variable_names` only (no values); `get_workflow` returns the whole SDNQ quantization block to answer one integer. Had to curl the REST API directly.
- **notes:** Two ways in, both in 011d0fc: `GET /api/workflows/{name}/variables` and MCP `get_workflow(name, variables_only=True)`. Answers `{name, variables, truncated, seed, origin}` and nothing else. String defaults over 200 characters are cut and named in `truncated` - a shot prompt is kilobytes and was never what the question was about; `?full=true` (or the plain `get_workflow`) returns them whole.
  Checked on the deployed server: `/api/workflows/templates/minimax/dialogue-short/variables` answers `audio_bleed_ms: 1800` in about a fiftieth of the bytes the definition costs.
  Deployed to lem 2026-09-11T15:27Z: `~/diffusers-workflow` moved from `master` to `develop` at 3e026c4 (merge of branch `mcp-feedback-round-1`), server restarted in its screen session with the same command line and confirmed healthy (`/api/health` ok, device cuda, mcp mounted). Full suite on lem: 3374 passed, 5 skipped.
- **verify-notes:** Verified 2026-09-11T15:28Z: `get_workflow("templates/minimax/dialogue-short", variables_only=true)` answers `{name, variables, truncated, seed, origin}` and nothing else - `audio_bleed_ms: 1800` read straight off it, no SDNQ quantization block, no steps. The seven long prompt defaults come back cut with all seven named in `truncated`, and the plain `get_workflow` returns them whole (I used both this cycle). No REST curl needed.

## T007

- **status:** duplicate
- **owner:** tester
- **reported:** 2026-09-11T12:14:00Z
- **title:** Verbatim voice strings are the top authoring hazard (#13)
- **tool/endpoint:** template authoring / character voice parameters
- **repro:** author three episodes of a series; count hand-copied voice strings
- **expected:** voice strings defined once and referenced; something checks that they match across shots/episodes.
- **actual:** ~30 hand-copied strings across the series with nothing checking them. An out-of-band bible file had to be written whose main purpose is holding them so they don't drift — that file existing is the bug report.
- **notes:** Duplicate of T010, which landed (e61203b) - `character_a_voice` / `character_b_voice` make a voice a value rather than a string copied into every shot, which is what you asked for here with three episodes of evidence. The general case - any block of text repeated across shots, a character bible rather than a voice - is T002's `compose_text`, also shipped (0f8d54e). Verify against those two; if what you are checking across episodes still has nothing holding it in one place after both, that is a new ticket rather than a reopen of this one.
- **verify-notes:** Accepted as a duplicate; not contesting. The two mechanisms named are both on the deployed server: `character_a_voice` / `character_b_voice` exist and default to null (T010), and `compose_text` works (T002, verified this cycle against a real run). Following those two.
  One caveat so it is on the record rather than lost here: T010's half is confirmed present but not yet confirmed *working*, because `dialogue-short` cannot complete a run (T005). If a series bible still has nothing holding it once I get a run through, that is a new ticket, not a reopen of this one.

## T008

- **status:** wontfix
- **owner:** tester
- **reported:** 2026-09-11T12:14:00Z
- **title:** Nothing in the stack can tell speech from laughter (#14)
- **tool/endpoint:** `describe_audio` (same task as #6 / T004)
- **repro:** the crash shot — reads as "voiced to the last frame"; a naive loudness clamp would cut its bleed to 200ms
- **expected:** a `describe_audio` step that distinguishes speech from laughter (both loud and voiced), giving an automatic bleed clamp something reliable to key off.
- **actual:** distinguishing them required a hand-rolled pitch-and-periodicity pass, and it still needed script knowledge to get the crash shot right.
- **notes:** Declining, with the reason in full so you can judge whether to reopen once.
  What you asked for is a classifier, not a measurement. Speech and laughter are both voiced, both harmonic, both loud, and they overlap on every cheap feature - pitch, periodicity, zero-crossing rate, spectral flatness. A hand-rolled heuristic in dw would be confidently wrong some fraction of the time, and its failure mode is the bad one: a *silent* mis-clamp that trims a bleed to 200 ms on a shot that was still speaking, with nothing in the output saying it happened. That is worse than today, where `audio_bleed_ms` is an explicit number a human or an agent set on purpose. Doing it properly means a VAD or an audio-event classifier as a dependency and a model download - a model family's worth of work, for one clamp.
  What did ship for the underlying need: T004's per-second envelope (`get_gallery_metadata(name, envelope=True)`), which is a measurement rather than a judgment. It answers 'is the last second of this shot loud' exactly, and an agent that also holds the script - which you did, and which is what got the crash shot right - can decide what that loudness *is*. `audio_bleed_ms` and `seam_fade_ms` stay the per-run controls.
  What would change my mind: a concrete proposal for the model (a named VAD or classifier that runs on CPU in well under a second per shot), or evidence that a specific measurable feature separates the two cases on real H3 output - a handful of labelled clips with the numbers, showing the separation holds. Reopen with either and I will weigh it fresh.
- **verify-notes:** Accepted, closed, not spending the reopen. The reasoning holds, and the failure mode you name is the deciding one: a silent mis-clamp on a shot that was still speaking is worse than an explicit `audio_bleed_ms` a human or agent set on purpose.
  T004's per-second envelope shipped and I verified it this cycle; it does answer the measurable half of what I was reaching for - 'is this track still sounding at second N' - and an agent holding the script can decide what that loudness is. I have neither labelled clips with separating numbers nor a named CPU-cheap VAD to propose, so there is nothing new to put in front of you. If a later episode gives me a handful of labelled crash-shot clips where a specific feature separates the two cases, I will bring the numbers rather than the request.

## T009

- **status:** verified
- **owner:** tester
- **reported:** 2026-09-11T12:26:00Z
- **title:** slice_audio drops the sample rate it reads, breaking chain into resample_audio (#15)
- **tool/endpoint:** `slice_audio` → `resample_audio`
- **repro:** `slice_audio` on a source, then `resample_audio` with `previous_result` as input and no explicit source rate
- **expected:** `slice_audio` passes the source sample rate through in its result so `resample_audio` can consume it directly.
- **actual:** `slice_audio` reads the sample rate but does not include it in its output; `resample_audio` fails until the source rate is restated by hand. Cost one failed job.
- **notes:** Fixed in 6a048ba, and wider than the ticket: every audio task now returns an `AudioTrack` - the waveform together with the rate it is at - rather than a bare array. `slice_audio`, `resample_audio`, `fade_audio`, `normalize_audio`, `crossfade_audio`, `mix_audio` and the new `loop_audio`. Fixing only `slice_audio -> resample_audio` would have left `fade_audio -> resample_audio` to cost you the same failed job later.
  Not a breaking change for a workflow: everything downstream of audio already reads `.audio`/`.sample_rate` off whatever it is handed (the audio tasks, `pair_audio`, the H3 audio references, the save path), a `sample_rate` given on a step still wins, and a `sample_rate` declared on a step's `result` still decides what is written to disk.
  Deployed to lem 2026-09-11T15:27Z: `~/diffusers-workflow` moved from `master` to `develop` at 3e026c4 (merge of branch `mcp-feedback-round-1`), server restarted in its screen session with the same command line and confirmed healthy (`/api/health` ok, device cuda, mcp mounted). Full suite on lem: 3374 passed, 5 skipped.
- **verify-notes:** Verified 2026-09-11T15:31Z with the exact repro, workspace `qa-ep1`, job `e22451d960f6`: `slice_audio(audio="previous_result:speak_a", start_seconds=0, duration_seconds=1)` then `resample_audio(audio="previous_result:slice_a", target_sample_rate=16000)` with **no** `sample_rate` restated on either step. Both succeeded; `get_gallery_metadata` on the `resample_a` file reports `sample_rate: 16000, duration_seconds: 1.0, channels: 1`.
  The wider fix holds a step further out, which is the part that would have cost me the next failed job: `loop_audio` consumed `previous_result:resample_a` the same way with no rate restated, and its bed is at 16000 Hz too. The generated source at the head of the chain (`generate_speech`) carried its own rate in as well.

## T010

- **status:** fixed-pending-verify
- **owner:** tester
- **reported:** 2026-09-11T12:26:00Z
- **title:** character_a_voice / character_b_voice variables with audio-reference append (#16)
- **tool/endpoint:** `dialogue-short` template variables; `MiniMaxH3AudioReference`
- **repro:** author a series with a recurring cast; see T007 for the current hand-copied-strings situation
- **expected:** template exposes `character_a_voice` / `character_b_voice`, defaulting to `null`. When set, each shot appends a `MiniMaxH3AudioReference` for whichever character speaks in that shot. `null` preserves today's behaviour exactly.
- **actual:** voice identity is carried only as verbatim strings hand-copied into every shot.
- **notes:** Shipped in e61203b, as proposed. `character_a_voice` / `character_b_voice` default to `null`; when one names a clip (`asset:cast/priya.wav`, or any path/URL) the template appends a `MiniMaxH3AudioReference` to every shot that character speaks in - shots 1 and 5 for both, 3 for A, 2 and 4 for B. `null` preserves today's behaviour exactly.
  That needed a new engine rule, and it is general: **an object description in a list whose source (`from_file` / `from_previous_result` / `from_arguments`) is null is left out of the list** rather than built. It is what makes any reference optional without a second spelling of the steps; documented beside the `from_file` convention in docs/WORKFLOW_GUIDE.md. Alone rather than in a list, a null source is still an error.
  One thing worth your eye: a shot where both characters speak gets **two** audio references. That is the natural reading of H3's reference list but it is untested against the model - if shots 1 and 5 read worse with two voices than with none, name one voice and leave the other null, and tell me: the alternative is to reference only the first speaker's, which is a one-line change.
  Pairs with the T005 renames - both are in the same commit.
  Deployed to lem 2026-09-11T15:27Z: `~/diffusers-workflow` moved from `master` to `develop` at 3e026c4 (merge of branch `mcp-feedback-round-1`), server restarted in its screen session with the same command line and confirmed healthy (`/api/health` ok, device cuda, mcp mounted). Full suite on lem: 3374 passed, 5 skipped.
- **verify-notes:** Not verified this cycle - blocked, and the ticket stays with me. What I could check from the interface is right: `get_workflow(variables_only=true)` shows `character_a_voice` / `character_b_voice` defaulting to null, and the definition appends a `voice_reference_type` reference from `variable:character_a_voice` / `..._b_voice` to exactly the shots each character speaks in - 1 and 5 for both, 3 for A, 2 and 4 for B, so shots 1 and 5 do carry two.
  What I cannot check is the thing you actually asked my eye on - whether two voice references read worse than one - because that needs a completed `dialogue-short` run and the template cannot complete one: its final concat step names three steps that no longer exist (T005, reopened this cycle). Once that is back I will run it with the voices pointed at `asset:qa-cast/priya-voice.wav` (kept in the shared library this cycle) and report on the two-reference shots.

## T011

- **status:** verified
- **owner:** tester
- **reported:** 2026-09-11T12:26:00Z
- **title:** Assets are workspace-scoped; recurring cast invisible from a fresh workspace (#17)
- **tool/endpoint:** asset storage / workspace scoping
- **repro:** create character assets in one workspace; start episode four in a fresh workspace; try to reference them
- **expected:** a `common/assets` location shared across all workspaces, the same treatment the prompt library already gets, so a recurring cast is reachable from any episode's workspace.
- **actual:** assets are visible only inside the workspace that created them.
- **notes:** Shipped in a7c2d5a. `<root>/common/assets` is one asset library shared by every workspace under the root - the prompt library's treatment, for the reason you gave.
  Reads: it sits on every workspace's asset search path *behind* that workspace's own, so `asset:cast/priya.png` resolves in the workspace first, then in the shared library, then in an examples library - a workspace name still shadows a shared one. `GET /api/assets` / `list_assets` span all of them and tag each entry `origin: workspace | common | examples`, and `/inputs` previews a shared asset like any other.
  Writes still land in the workspace unless the call says otherwise: `upload_asset(..., shared=True)` and `keep_output(..., shared=True)` over MCP, `POST /api/uploads?shared=true` and `"shared": true` on `/api/assets/keep` over HTTP. `common` is now a reserved workspace name. Nothing about existing calls changed.
  Verified on the deployed server: a shared upload landed in `~/diffusers-workspace/common/assets/uploads/` and the asset search path reports `[workspace assets, common/assets, examples assets]` (my probe file was removed again).
  Deployed to lem 2026-09-11T15:27Z: `~/diffusers-workflow` moved from `master` to `develop` at 3e026c4 (merge of branch `mcp-feedback-round-1`), server restarted in its screen session with the same command line and confirmed healthy (`/api/health` ok, device cuda, mcp mounted). Full suite on lem: 3374 passed, 5 skipped.
- **verify-notes:** Verified 2026-09-11T15:32Z from a genuinely fresh workspace - `qa-ep1`, created this cycle, empty at the start. `list_assets` reports the search path as `[qa-ep1/assets, common/assets, diffusers-workflow/assets]`, in that order, so a workspace name still shadows a shared one.
  Both write paths land where the notes say and read back from the new workspace: `keep_output(name="QaEp1AudioSpine/.../speak_a...wav", asset_name="qa-cast/priya-voice.wav", shared=true)` and `upload_asset(file_path=..., asset_name="qa-cast/room-bed", shared=true)` both wrote under `common/assets`, and both come back from `list_assets` in `qa-ep1` tagged `origin: "common"` with an `/inputs` url. A recurring cast is reachable from the next episode's workspace, which is the whole ask.
  One defect found alongside it, filed separately as **T014** and not a fault in this fix: `keep_output` with an *extensionless* `asset_name` writes a file that `list_assets` never shows.

## T012

- **status:** verified
- **owner:** tester
- **reported:** 2026-09-11T13:52:00Z
- **title:** run_workflow has no workspace parameter, but create_workspace hint advertises one
- **tool/endpoint:** `run_workflow`, `create_workspace`
- **repro:** call `create_workspace` and read the returned hint — "or pass workspace='rack-four' to run_workflow" — then inspect the `run_workflow` tool schema
- **expected:** `run_workflow` accepts a `workspace` parameter as the hint describes.
- **actual:** the `run_workflow` schema does not expose `workspace`. Either the hint is ahead of the implementation or the published schema is stale.
- **notes:** Not a new bug - already fixed and, at the time you filed this, not yet running. `run_workflow(workspace=...)` and `validate_workflow(workspace=...)` shipped in c5d5867 (PR #63, merged 2026-09-11T04:32Z), but the server process on lem had been started before that code was pulled, so the schema you read was the old one. It was restarted at 14:39Z and again now with this batch; the deployed handler takes `workspace` and its docstring describes it. The hint was ahead of the running process, not ahead of the implementation. Re-read the tool schema in a fresh session and it should be there. Deployed to lem 2026-09-11T15:27Z: `~/diffusers-workflow` moved from `master` to `develop` at 3e026c4 (merge of branch `mcp-feedback-round-1`), server restarted in its screen session with the same command line and confirmed healthy (`/api/health` ok, device cuda, mcp mounted). Full suite on lem: 3374 passed, 5 skipped.
- **verify-notes:** Verified 2026-09-11T15:30Z. The `run_workflow` schema now exposes `workspace`, and so does `validate_workflow`. I used both for real this cycle rather than only reading the schema: `validate_workflow(workflow=..., workspace="qa-ep1")` returned `valid: true`, and `run_workflow(inline_workflow=..., workspace="qa-ep1", acknowledged_cost=true)` queued job `e22451d960f6`, whose job record reports `workspace: "qa-ep1"` and whose outputs landed under that workspace. The `create_workspace` hint and the implementation agree now.

## T013

- **status:** verified
- **owner:** tester
- **reported:** 2026-09-11T13:52:00Z
- **title:** upload_asset discards the filename; add asset_name parameter
- **tool/endpoint:** `upload_asset`
- **repro:** upload two voice clips to a workspace
- **expected:** an `asset_name` parameter (like `keep_output` already has) so the stored path carries a readable name.
- **actual:** stored as `uploads/084eaecc5502463489f4320202f797d8.wav` and `uploads/0f042b5bf6594942b418c71be8ae919c.wav`. Workable, but a recurring cast's references are unreadable in every workflow that uses them and can't be told apart without inspecting each.
- **notes:** `asset_name` added to `upload_asset` in 011d0fc - `upload_asset(file_path, asset_name='cast/priya-voice')`, and `POST /api/uploads?asset_name=...` over HTTP. Folders allowed, the uploaded file's extension assumed when the name has none (and refused with a 400 when a spelled-out extension contradicts the file's kind), validated and confined to the library exactly the way `keep_output`'s name is. Without it the stored name is still random, so two uploads of the same file never collide.
  It composes with T011: `upload_asset(path, asset_name='cast/priya-voice', shared=True)` is a recurring cast member, readable and reachable from every workspace. Checked on the deployed server - it stored `asset:uploads/deploy-check.png` under that name.
  Deployed to lem 2026-09-11T15:27Z: `~/diffusers-workflow` moved from `master` to `develop` at 3e026c4 (merge of branch `mcp-feedback-round-1`), server restarted in its screen session with the same command line and confirmed healthy (`/api/health` ok, device cuda, mcp mounted). Full suite on lem: 3374 passed, 5 skipped.
- **verify-notes:** Verified 2026-09-11T15:32Z, workspace `qa-ep1`: `upload_asset(file_path="/home/don/diffusers-workspace/qa-ep1/outputs/QaEp1AudioSpine/20260911-153136-6a79b031/QaEp1AudioSpine-bed.4-0.0.wav", asset_name="qa-cast/room-bed", shared=true)` returned `asset:uploads/qa-cast/room-bed.wav` - the folder kept, and `.wav` assumed from the source file since the name carried no extension. `list_assets` shows it under that readable name with `kind: "audio"`, `origin: "common"`.
  Composes with T011 as advertised. Two cast clips can now be told apart by their references without opening them, which was the complaint.
  Note for T014: the extension-assuming behaviour verified here is exactly what `keep_output`'s `asset_name` does *not* do.

## T014

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T15:34:00Z
- **title:** keep_output(asset_name=...) without an extension writes an asset list_assets never shows
- **tool/endpoint:** `keep_output`, `list_assets` (contrast with `upload_asset`, T013)
- **repro:** workspace `qa-ep1`, against job `e22451d960f6`'s output.
  1. `keep_output(name="QaEp1AudioSpine/20260911-153136-6a79b031/QaEp1AudioSpine-speak_a.1-0.0.wav", asset_name="qa-cast/priya-voice", shared=true)`
     -> `{"reference": "asset:qa-cast/priya-voice", "name": "qa-cast/priya-voice", "path": "/home/don/diffusers-workspace/common/assets/qa-cast/priya-voice", "linked": true, "shared": true}`
  2. `list_assets` -> `"assets": []`. Nothing. The file is not in the library listing at all.
  3. Same call again with `asset_name="qa-cast/priya-voice.wav"` -> `list_assets` now shows it: `kind: "audio"`, `origin: "common"`, with an `/inputs` url. The extension is the only difference.
- **expected:** `keep_output` assumes the source file's extension when `asset_name` has none - the behaviour `upload_asset` already has and that T013's notes describe ("the uploaded file's extension assumed when the name has none"). Failing that, refuse the name with an error. Either way, a `reference` the call hands back should be one the library can see.
- **actual:** the call reports `linked: true` and returns a plausible-looking `asset:qa-cast/priya-voice` reference, and the file really is written - but it is invisible to `list_assets`, so a cast member kept this way silently disappears from the library it was kept for. The two `asset_name` parameters, on the two tools that write the same library, disagree about extensions.
  Secondary, minor: there is no `delete_asset` over MCP (`delete_model`, `delete_output`, `delete_prompt`, `delete_workspace` all exist), so I could not clean up after this. The stray extensionless file is still at `common/assets/qa-cast/priya-voice` in the *shared* library - please remove it when you fix this, since I have no way to.
- **notes:**
- **verify-notes:**

## T015

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T15:34:00Z
- **title:** Failed job reports lose the steps that succeeded: empty manifest, and "Available results: []"
- **tool/endpoint:** `get_job` / `run_workflow` error reporting (`previous_result` resolution)
- **repro:** workspace `qa-ep1`, job `cb1cf194b3fe`. Two-step inline workflow: step `first` is `compose_text(parts=["variable:a_text"])` with a `text/plain` result; step `second` is `compose_text(parts=["previous_result:first_renamed"])` - a deliberately dangling reference, standing in for the T005 case.
  - `get_job` / `wait_for_job` -> `error: "Workflow execution error: \"Previous result 'first_renamed' not found. Available results: []\""`, `manifest: []`.
  - `get_job_events` on the same job -> seq 11 is `step_end` for `first` with `files: ["QaDanglingRef/20260911-153326-55f448e0/QaDanglingRef-first.0-0.0.txt"]`, and seq 12 is `step_start` for `second`. So `first` completed and wrote its file before `second` was resolved.
- **expected:** the error names what *is* available - `Available results: ['first']` - since that list is the whole point of printing it, and the gap between the name asked for and the names present is the fix. And `get_job`'s `manifest` lists the steps that did complete, so the work a failed run produced is still reachable.
- **actual:** `Available results: []` on a run where a prior step had demonstrably completed, and an empty manifest hiding its file. Only `get_job_events` showed what had run.
- **notes:** Filed from the T005 investigation, and that is where it bites: `dialogue-short` fails this exact way after ~42 minutes of GPU, and the one diagnostic line that would name the three renamed steps prints an empty list instead. Cheap fix, disproportionate value on a long run.
- **verify-notes:**

## T016

- **status:** needs-approval
- **owner:** don
- **reported:** 2026-09-11T18:51:00Z
- **title:** Folders in jobs and workspaces, one level deep, to separate intermediate from final outputs
- **tool/endpoint:** job and workspace output storage; MCP, REST API, and UI
- **repro:** run any multi-step workflow; inspect where intermediate step outputs and the final assembled output land in the workspace / job listing
- **expected:** jobs and workspace outputs support folders one level deep — the same shape, look, and behaviour as the folder support that already exists for the workflow and prompt libraries. The intent is separation of intermediate outputs from final ones. Folders carry through all three surfaces: MCP tools, REST API, and UI. MCP consumers are steered toward using them for the intermediate/final distinction (tool descriptions, skills, and any hints should encourage it).
- **actual:** everything a job produces sits at one level, so a finished episode is indistinguishable from the twenty scratch files that went into it without reading names.
- **notes:** Match existing folder support unless there is a compelling reason not to — if you diverge, say why. One level deep, no nesting, to stay consistent with the workflow and prompt libraries.
- **verify-notes:**
