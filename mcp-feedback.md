# diffusers-workflow MCP — Feedback Log

Rules for both agents:
- Never delete or rewrite another agent's entries — only append new entries or edit the `status` line of an entry you own the next step of.
- Each entry gets a unique ID: `T001`, `T002`, ... increment from the last one in this file.
- `owner` = whose turn it is to act next: `implementer` or `tester`.
- Do not start new work if there is an open ticket with `owner: tester` and you are the implementer, or vice versa — that ticket isn't yours yet.
- `wontfix` is the implementer's call, with the reason in `notes:`. The tester may reopen it once with materially new evidence; a second `wontfix` is final.

---

## T000 (template — copy this block for new tickets)

- **status:** open | fixed-pending-verify | verified | wontfix | needs-info
- **owner:** implementer | tester
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

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T12:14:00Z
- **title:** loop_audio task — room-tone bed under cuts (#2b)
- **tool/endpoint:** new task `loop_audio`; composes with `mix_audio` + `pair_audio`
- **repro:** any cut between shots; the seam has a hole with no ambient bed under it
- **expected:** `loop_audio(source, target_frames, fps, crossfade_ms)` produces a bed of the requested length from a short room-tone source, which `mix_audio` lays under the cut and `pair_audio` attaches. A template (`dialogue-short`) demonstrates the pattern.
- **actual:** no way to generate a bed; the seam hole has no complete fix.
- **notes:** Small task. The template demo wants a measured bed captured from real H3 output first — do that before wiring it into `dialogue-short`.
- **verify-notes:**

## T002

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T12:14:00Z
- **title:** compose_text task — assemble character bibles per shot (#8)
- **tool/endpoint:** new task `compose_text`; consumes `previous_result:compose_shot_n`
- **repro:** authoring any multi-shot template that reuses a character description across shots
- **expected:** character bibles are written once and assembled into each shot's prompt as a task step, so a shot references prior results rather than duplicating text.
- **actual:** the only assembly mechanism would be `{{var}}` interpolation, which the no-interpolation rule in `docs/WORKFLOW_GUIDE.md:285` exists to forbid; authors hand-copy instead. See T007.
- **notes:** Needs a decision on template syntax (positional parts vs named) — brainstorm before implementing. Set `needs-info` back to tester if the choice needs consumer input.
- **verify-notes:**

## T003

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T12:14:00Z
- **title:** List-driven step count for generation templates (#7)
- **tool/endpoint:** workflow engine — `for_each` over a variable
- **repro:** `music-video` and `dialogue-short` templates; each generates one step per shot
- **expected:** a `shots: [...]` variable fans out generation steps, one per list entry.
- **actual:** step count is fixed in the template; adding a shot means editing the template. `assemble-and-score` already takes a list after PR-1, so the consumer side has precedent.
- **notes:** Engine feature, not a template edit.
- **verify-notes:**

## T004

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T12:14:00Z
- **title:** Per-second level envelope from probe_media (#6)
- **tool/endpoint:** `probe_media(path, envelope=True)`
- **repro:** `probe_media(path)` on any clip
- **expected:** with `envelope=True`, response includes `[rms_dbfs per second]`. Default call (no flag) is unchanged and stays small.
- **actual:** no per-second level data available from the MCP.
- **notes:** Cheap once Task 8 exists. Must be opt-in — same payload lesson as #4 / T006. Also the building block for T008.
- **verify-notes:**

## T005

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T12:14:00Z
- **title:** Template variable names leak the example cast (#11)
- **tool/endpoint:** `dialogue-short` template variables
- **repro:** run `dialogue-short` with characters Priya and Hal; inspect arguments, manifest, and export
- **expected:** role-based names: `character_a_portrait_prompt`, `shot_3_react`, `shot_4_button`, etc. The beat names are the reusable part.
- **actual:** every run carries `howie_portrait_prompt`, `pat_portrait_prompt`, `shot_3_howie_incredulous` through arguments, manifest, and export regardless of cast.
- **notes:** Cosmetic, but it surfaces everywhere and makes the template read as one specific sketch rather than a reusable form. This is a breaking rename for the tester's calls — flag the new names in `notes:` on fix.
- **verify-notes:**

## T006

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T12:14:00Z
- **title:** No cheap way to read a stored workflow's variable defaults (#12)
- **tool/endpoint:** `list_workflows`, `get_workflow`
- **repro:** try to confirm `audio_bleed_ms` defaults to 1800 for a stored workflow
- **expected:** some call returns variable names *and* default values without the full workflow body.
- **actual:** `list_workflows` returns `variable_names` only (no values); `get_workflow` returns the whole SDNQ quantization block to answer one integer. Had to curl the REST API directly.
- **notes:** Same payload theme as #4, on the read path.
- **verify-notes:**

## T007

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T12:14:00Z
- **title:** Verbatim voice strings are the top authoring hazard (#13)
- **tool/endpoint:** template authoring / character voice parameters
- **repro:** author three episodes of a series; count hand-copied voice strings
- **expected:** voice strings defined once and referenced; something checks that they match across shots/episodes.
- **actual:** ~30 hand-copied strings across the series with nothing checking them. An out-of-band bible file had to be written whose main purpose is holding them so they don't drift — that file existing is the bug report.
- **notes:** Restates T002 (#8) with three episodes of evidence behind it. Likely resolved by the same mechanism.
- **verify-notes:**

## T008

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-11T12:14:00Z
- **title:** Nothing in the stack can tell speech from laughter (#14)
- **tool/endpoint:** `describe_audio` (same task as #6 / T004)
- **repro:** the crash shot — reads as "voiced to the last frame"; a naive loudness clamp would cut its bleed to 200ms
- **expected:** a `describe_audio` step that distinguishes speech from laughter (both loud and voiced), giving an automatic bleed clamp something reliable to key off.
- **actual:** distinguishing them required a hand-rolled pitch-and-periodicity pass, and it still needed script knowledge to get the crash shot right.
- **notes:** This is the missing building block for an automatic clamp. Depends on / extends T004.
- **verify-notes:**
