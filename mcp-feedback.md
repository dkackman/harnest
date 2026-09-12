# diffusers-workflow MCP — Feedback Log (frozen 2026-09-12)

**Superseded.** Tickets moved to GitHub Issues on `dkackman/diffusers-workflow` on 2026-09-12; see
`CLAUDE.md`'s "Ticket protocol" section. This file and `mcp-feedback-archive.md` are kept only as a
historical record of everything filed before the migration — never edited again. The active tickets
below (T016, T022–T031) were carried forward as Issues #69–#79.

Rules for both agents (historical, no longer in effect):

- Never delete or rewrite another agent's entries — only append new entries or edit the `status` line of an entry you own the next step of.
- Each entry gets a unique ID: `T001`, `T002`, ... increment from the last one in this file.
- `owner` = whose turn it is to act next: `implementer`, `tester`, or `don` (the human).
- Do not start new work if there is an open ticket with `owner: tester` and you are the implementer, or vice versa — that ticket isn't yours yet.
- `wontfix` is the implementer's call, with the reason in `notes:`. The tester may reopen it once with materially new evidence; a second `wontfix` is final.
- `duplicate` closes a ticket in favour of another, named in `notes:`. The implementer triages for duplicates and already-shipped fixes before working a ticket.
- `needs-approval` + `owner: don` parks a ticket pending a human decision. Neither agent touches it — no notes, no re-triage, no early work — but it stays canonical for duplicate detection. It comes back as `open` / `owner: implementer` when approved, or `wontfix`.
- A ticket that reaches `verified`, `wontfix`, or a settled `duplicate` is moved out to `mcp-feedback-archive.md` (same block, verbatim) to keep this file to active work. Check the archive as well as this file for duplicate detection and history — it is not stale. Never edit an archived ticket; a reopened `wontfix` or new evidence against a closed ticket becomes a new ticket here that references the old ID.

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
  **From Don (2026-09-11):** Do not implement yet. Write a proposal in `docs/proposals/` (the T003 doc, `list-driven-steps.md`, is the model: the ask as filed, why it is more than an edit, the shape, what it does not do, phasing, open questions), commit it to `develop`, then set this ticket to `needs-approval` / `owner: don` with the path and commit ref in these notes. Cover at minimum: how a workflow step names its destination folder and what the default is (everything at the top level, as today, must keep working); how the manifest, `get_job`, `list_jobs` and the workspace asset listing expose the folder; how `asset:` and `previous_result:` references address a foldered output; what the REST API and UI surfaces change, mapped one-to-one onto the existing workflow/prompt library folder support; what, if anything, is a breaking MCP change; and how tool descriptions / plugin skills steer an agent toward the intermediate/final split.
  **From the implementer (2026-09-12T00:55Z):** Proposal written, not implemented. `docs/proposals/output-folders.md`, commit `29e8b6b`, on `develop` as `10b9d27` (pushed). Covers every point asked for: `folder` on a step's `result` block with no default (an unfoldered workflow writes exactly what it writes today); `folder` on each manifest entry plus an `outputs` grouping on `get_job`; `list_jobs` deliberately unchanged, since a row carrying file lists is what T018 just cut; `previous_result:` unaffected (it names a step, not a path) and `output:` gaining one segment with **no resolver change**, because the file part of an output name already accepts a relative path; the gallery keeping `folder` as the workflow identity and gaining a separate `group` axis plus `?group=`; no breaking MCP or REST change anywhere, all additive; and four steering places in the order an agent meets them, of which the templates matter most because agents compose by copying one.
  Two things to read before approving. **The reason it is more than an edit** is not that it adds a field: it is that the output tree already has a positional layer - `<workflow identity>/<run id>/<file>` - that `strip_run_id`, `output:` and the gallery filter all read by position, so a segment inserted between the run id and the file name has to be handed to each of them deliberately or the gallery starts listing `Gyre/final` and `Gyre/intermediate` as two workflows and yesterday's `output:` references stop resolving. **And one open question is a divergence from your ticket**: the workflow and prompt libraries are not one level deep - both walk the tree and a name is a relative path of any depth (`templates/minimax/reference-to-video` is a real catalog name). So "the same shape as the libraries" and "one level, no nesting" point opposite ways. The proposal recommends allowing a path and making one level the *convention* in templates and the guide; that is question 1 in the doc and it is your call. Questions 2 and 3 (whether the `outputs` grouping is worth its redundancy, and whether a one-step workflow should default to `final` - recommended no, it would move existing files) are smaller.
- **verify-notes:**

## T022

- **status:** fixed-pending-verify
- **owner:** tester
- **reported:** 2026-09-12T00:55:00Z
- **title:** The ~87 s between `phase generating` and the first `pipeline_step` reads as a hung job under T021's own pacing rule
- **tool/endpoint:** `wait_for_job` / `get_job` `progress` block (the T021 feature, on the deployment at `develop` @ `10b9d27`)
- **repro:** workspace `qa-ep2`, job `063a4ce94c9b`, `templates/minimax/reference-to-video`, `subject=asset:qa-cast/priya-portrait.jpg`, `voice=asset:qa-cast/priya-voice.wav`, `num_inference_steps: 20`, 124 frames. Polled with `wait_for_job(job_id, timeout_seconds=55)`, one call per 55 s.
  The two polls that sit inside the window, verbatim:

      {"phase": "generating", "phase_detail": "MiniMaxAI/MiniMax-H3",
       "seconds_in_phase": 7.2,  "seconds_since_event": 7.2}     # event_count 12

      {"phase": "generating", "phase_detail": "MiniMaxAI/MiniMax-H3",
       "seconds_in_phase": 64.3, "seconds_since_event": 64.3}    # event_count 12, unchanged

  and the poll after it:

      {"phase": "generating", "seconds_in_phase": 124.3, "seconds_since_event": 16.5,
       "denoise_step": 4, "denoise_total_steps": 19}             # event_count 16

  The event log confirms the gap is real and not a reporting artefact: `seq 11 phase generating` is followed by `seq 12 pipeline_step 1/19` roughly 87 s later. Nothing is emitted in between.
- **expected:** a caller following the rule T021's `notes:` states — "`denoise_step` moving = slow but healthy; `seconds_since_event` climbing with nothing else changing = nothing is happening" — should not be told a healthy run is stuck. Either something moves in that window (the phase could be finer: the pre-loop work inside `generating` is presumably encoding the reference image and the voice clip, and a `phase` of its own would make `seconds_in_phase` reset and the caller's question answerable), or `progress` carries something that distinguishes "before the denoise loop" from "the denoise loop has stopped advancing" — a `denoise_started: false`, or `denoise_step: null` present-but-null rather than the key being absent.
  The cheapest correct thing may just be documentation: say in the `wait_for_job` docstring that `generating` has a lead-in of up to ~90 s on H3 before the first denoise step, so `seconds_since_event` past a minute is only alarming *once `denoise_step` has appeared*. That is a one-line change and it makes the rule as stated true.
- **actual:** two consecutive polls, 55 s apart, byte-identical apart from the clock, `event_count` frozen at 12, no `denoise_step` key — which is the documented signature of a wedged job. It was in fact mid-render and finished normally 6 minutes later. I only knew to keep waiting because I had just read the ticket that shipped the feature; a caller who had not would have been weighing `cancel_job` on a healthy 8-minute run.
  Strictly smaller than T021 was — the window is ~87 s rather than 7m45s, and every other part of that fix does what it says (verified, see T021's `verify-notes:`). Filing it because the rule the docs now state is the thing that misfires, and the fix may be to the sentence rather than to the code. Treat as small; I have no workaround problem, only a confidence one.
- **notes:** Fixed, not documented-around - though the docs changed too. `Job.progress()` now always carries `denoise_step`/`denoise_total_steps`, `null` until the denoise loop starts, instead of the keys only appearing once there was a count. That makes the two states you could not tell apart distinguishable by value: `denoise_step: null` under `generating` is the pipeline's pre-loop work (encoding the prompt and any reference image or audio, ~90 s on H3) and nothing will be emitted until the loop starts; a `denoise_step` that is a number and stops moving while `seconds_since_event` climbs is the stuck case. It never returns to null mid-loop - `step_start` resets it for the next workflow step.
  Response-shape note for your scripts: the two keys are now *always present* in the `progress` block of `get_job` and `wait_for_job`, with a `null` value where they were previously absent. A check written as `"denoise_step" in progress` now answers true during the lead-in; `progress.get("denoise_step") is not None` is the test that means what the old key-presence check meant.
  The rule is restated to match in the `wait_for_job` and `get_job` docstrings, docs/MCP.md and docs/SERVER.md: `seconds_since_event` only says something once `denoise_step` is a number, or in any phase other than `generating`.
  Commit 5173a48 on `mcp-feedback-round-6`, merged to `develop` as 0c4ecb2 and pushed; 3512 tests pass (two in tests/test_job_progress.py rewritten for null-not-absent, one added that pins the lead-in against a stalled loop). Deployed to `lem` by `git pull` + SIGINT/restart of `python -m dw.serve` in the screen session at 2026-09-12T01:35Z; `/api/server` answers and the MCP mount is up.
- **verify-notes:** **Half-verified, staying `fixed-pending-verify` / `owner: tester`** - not because anything is wrong, but because the server went unreachable mid-run before I could see the second half (T023). Nothing here contradicts the fix; do not re-do it.
  What I did confirm, from real calls this cycle, workspace `qa-ep3`, job `2594a9236e61` (`templates/minimax/reference-to-video`, `subject=asset:qa-cast/hal-portrait.jpg`, `voice=asset:qa-cast/hal-voice.wav`, 20 steps, 124f), polled `wait_for_job(job_id, timeout_seconds=55)`:

      {"phase": "loading", "phase_detail": "pipeline: MiniMaxAI/MiniMax-H3",
       "seconds_in_phase": 50.8, "seconds_since_event": 50.8,
       "denoise_step": null, "denoise_total_steps": null}      # event_count 9

      {"phase": "generating", "phase_detail": "MiniMaxAI/MiniMax-H3",
       "seconds_in_phase": 8.8, "seconds_since_event": 8.8,
       "denoise_step": null, "denoise_total_steps": null}      # event_count 11

  Both keys are present-with-null rather than absent, in `loading` and in the `generating` lead-in - which is the exact state that read as a hang, and it now says so by value. The docstring change landed too and is visible from the consumer side: `wait_for_job`'s schema description now carries "null until the denoise loop starts - which is how a slow run and a stuck one tell apart between two otherwise identical polls", with the ~90 s H3 lead-in named. Read as a consumer with no other context, that sentence answers the question I could not answer last cycle.
  Outstanding for next cycle, both cheap: (a) see `denoise_step` transition from null to a number in the same run, and (b) confirm it does not return to null mid-loop. The third poll would have shown (a); it errored with a client-side timeout and every call after that failed to connect. I have no reason to doubt either, but I have not seen them, so I am not setting `verified` off reasoning.

---

## T023

- **status:** needs-info
- **owner:** implementer
- **reported:** 2026-09-12T01:15:00Z
- **title:** MCP server became unreachable mid-render and stayed down - an 8-minute H3 job is unobservable and possibly lost
- **tool/endpoint:** the whole MCP mount - `wait_for_job`, then `get_health` and `get_server_info` alike
- **repro:** workspace `qa-ep3` (created this cycle), job `2594a9236e61`, `templates/minimax/reference-to-video`, `subject=asset:qa-cast/hal-portrait.jpg`, `voice=asset:qa-cast/hal-voice.wav`, stock `num_inference_steps: 20` / 124 frames. Queued at 2026-09-12T01:03:50Z, ran normally through `loading` and into `generating` (two clean `wait_for_job(timeout_seconds=55)` polls, quoted in T022's `verify-notes:`). The call sequence from there, verbatim:

      wait_for_job("2594a9236e61", timeout_seconds=55)  -> "The operation timed out."
      wait_for_job("2594a9236e61", timeout_seconds=45)  -> "Unable to connect. Is the computer able to access the url?"
      get_health()                                      -> "Unable to connect. Is the computer able to access the url?"
      get_health()                                      -> "Unable to connect. Is the computer able to access the url?"
      get_server_info()                                 -> "Unable to connect. Is the computer able to access the url?"

  The first failure is a different error from the four after it: a timeout on a call that had been returning in exactly 55.0 s twice in a row, then hard connection refusal from that point on, including from `get_health`, which does no work and had answered fine at the top of the cycle.
- **expected:** the server stays up for the duration of a job it accepted, and a client that loses it can find out what happened to the job once it is back. Failing that, `get_health` - the one call whose whole job is answering "is it alive" - should be the last thing to stop working, not fail identically to everything else.
- **actual:** the server accepted an ~8-minute job, ran it for ~2 minutes, and then stopped answering entirely. I cannot tell from the MCP interface whether the render is still going on a healthy worker behind a dead HTTP mount, whether the process died and took the job with it, or whether the box went away - all three give me the same connection error. Stopping testing here per my guardrails.
  Two things worth checking while you are in there, both visible only from your side:
  1. `get_health` reported `"worker_alive": false` at 2026-09-12T01:02Z, with `status: "ok"`, `queued: 0`, `current_job: null`, on an idle server that then accepted and started this job fine. If `worker_alive: false` on an idle-but-healthy server is normal (worker spawned per job), the field is misleading as a health signal; if it is not normal, it may be the first sign of whatever went wrong ~7 minutes later. Either way it is worth a look, and it is the only anomaly I have from before the fall.
  2. Whatever the cause, `2594a9236e61` is a job in `qa-ep3` that no client can now resolve. If it survived, say so in `notes:` and I will pick it up; if it did not, say that too and I will re-run the shot rather than wait on it.
- **notes:** 2026-09-12T01:10Z (impl) — **Not a server bug: the `lem` box itself is down.** Confirmed from my side, no fix deployed, nothing changed in the repo this cycle.
  - `ssh don@lem` -> `connect to host lem port 22: Host is down`. `ping lem` -> `sendto: Host is down`, 3/3 packets lost. DNS still resolves (`lem.lan` -> 192.168.1.194), so the name is fine and the machine is not answering at the IP layer at all. No alternate route configured (no tailscale, no second Host entry in `~/.ssh/config`).
  - That accounts for the failure shape you saw exactly: the first `wait_for_job` timed out (TCP connection already dead, client waited out its own 55 s), and from then on every call — `get_health` included — got connection-refused, because there is no process and no host to refuse differently. `get_health` cannot be "the last thing to stop working" when the box carrying it is gone; a liveness call degrades gracefully only against a sick server, not an absent one. No server-side change would have made that cycle observable.
  - **Q1, `worker_alive: false` on an idle server — normal, not a precursor.** The worker is a subprocess spawned on demand: `WorkerManager.ensure_worker` (`dw/repl_worker.py:35`) starts it only when a job needs it, and `/api/health` (`dw/server/app.py:2632`) reports the literal truth — `worker_active and worker_process.is_alive()`. On an idle server with no job yet run (or after a `memory clear` / idle restart) that is legitimately `false`, and the server accepting and starting your job right afterwards is the expected behaviour, not a recovery. So it is unrelated to the fall. I agree the field reads as a health signal when it is really a "is a model process resident right now" signal; that is a real (small) reporting wart, but it is a separate ticket from this one and I am not folding a rename/semantics change into an outage report — file it separately if you want it pursued.
  - **Q2, job `2594a9236e61` in `qa-ep3`:** I cannot resolve it either — the sqlite job store and the run directory both live on `lem`. Treat it as lost and re-run the shot; do not wait on it. If the box comes back I will check `jobs.sqlite` for its final state and say so here, but assume no output survived: the render was ~2 min into an ~8 min job and nothing is written until a step completes.
  - **Blocked on don:** `lem` needs to be powered back on / brought back on the network before anything can be deployed or verified. Holding this ticket with me (per the deploy-failure guardrail) rather than handing it to the tester, since re-testing is impossible until the box is up. Tester: do not re-test this cycle; you will only re-file "MCP unreachable".
- **verify-notes:**

## T024

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-12T10:27:00Z
- **title:** Failed pipeline loads leak GPU/host memory instead of being released, and leaks accumulate across retries
- **tool/endpoint:** pipeline loading/caching path (whatever constructs and caches diffusers pipeline instances, e.g. around `release_pipeline`/`release_models` and the group-offload variant)
- **repro:** a pipeline load or a variant load (e.g. a group-offload attempt) fails or is aborted partway through; a subsequent decode comes up short on memory. Reported symptom: "the decode was 1.88 GiB short: it started with 4.2 GB of dead weight, and the group-offload attempt added ~12 GB more of a new pipeline variant that will never be reused."
- **expected:** a pipeline (or pipeline variant) that fails to load, or that is superseded by a retry/different variant, is fully torn down and its memory reclaimed before or as part of the next attempt - no dead weight left resident, and no accumulation across repeated failures.
- **actual:** each failed/superseded pipeline load leaks its allocated memory; repeated failures accumulate dead weight (observed: 4.2 GB from earlier failures, then +~12 GB from a group-offload variant that was never going to be reused), eventually starving a later decode by ~1.88 GiB.
- **expected repro to confirm fix:** force a pipeline load failure (or trigger the group-offload path then abandon it), check GPU/host memory before and after, then retry the decode and confirm no residual allocation remains from the failed attempt.
- **notes:**
- **verify-notes:**

## T025

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-12T10:29:00Z
- **title:** Assess whether a task exists (or should exist) for decoding latents in batches
- **tool/endpoint:** decode path / task catalog (e.g. wherever VAE decode is exposed as a task)
- **repro:** n/a — this is an investigation/design ticket, not a repro of a bug.
- **expected:** implementer determines whether a batched-latent-decode task already exists; if not, assesses whether one has general value (e.g. lower peak memory during decode, relevant to the T024 memory-pressure symptom) and reports the finding either way.
- **actual:** unknown whether such a task exists today.
- **notes:** If the answer is no and there's no general value, close as `wontfix` with reasoning in `notes:`. If there's value, either implement it or write it up as a proposal per the `needs-approval` path if it's a bigger design change.
- **verify-notes:**

## T026

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-12T11:01:00Z
- **title:** list_jobs pagination possibly ignores/misapplies limit under a status filter
- **tool/endpoint:** `list_jobs`
- **repro:** `list_jobs(limit=12, status="succeeded")` returned 3 of 9 matching jobs with a "6 older jobs were not listed" note; `list_jobs(limit=20, status="succeeded")` on the same underlying data returned all 9.
- **expected:** unclear yet — needs verification before concluding it's a bug. Either `limit` should apply consistently to the filtered result set, or (if it's already correct and the reporter misread) no change needed.
- **actual:** with `limit=12` fewer results came back than the limit allowed (3 of 9), suggesting `limit` may be getting applied before the `status` filter rather than after, or some other pagination/filter-interaction bug. Reporter flags low confidence.
- **notes:** Reported by the tester agent as "worth checking rather than filing" — passing along as a ticket per Don's request. Implementer should reproduce and confirm whether this is real before treating it as a fix.
- **verify-notes:**

## T027

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-12T11:01:00Z
- **title:** release_pipeline ordering relative to save may hold ~10 GB resident longer than necessary
- **tool/endpoint:** pipeline release path, specifically `release_pipeline: true` on a refine/save step
- **repro:** ran a step with `release_pipeline: true` set on refine. Reporter could not tell from the outside whether the release happens before or after the result write.
- **expected:** if the save does not need the pipeline resident, release it before the write so ~10 GB frees up during the longest phase of the step; if the save does need the pipeline resident, current ordering is correct.
- **actual:** ordering (and thus whether this is a bug) is unknown from the MCP consumer side; worth a look given the leak/memory-pressure pattern in T024.
- **notes:** Reported by the tester agent as "worth checking rather than filing" — passing along as a ticket per Don's request. Implementer should check the actual release-vs-write ordering in code and fix or confirm as needed.
- **verify-notes:**

## T028

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-12T11:01:00Z
- **title:** LTX skill's write-out warning should state the actual rate, not "minutes"
- **tool/endpoint:** LTX plugin skill docs (write-out/long-render warning text)
- **repro:** skill currently says "writing a 121-frame 1536x896 clip takes minutes... the job is not stuck." Accurate at 121 frames, but a reader extrapolating to a longer render (e.g. 481 frames) has no way to scale that and may wrongly suspect a hang.
- **expected:** the warning states the per-frame rate (e.g. ~4.2 s/frame) so a reader can compute the expected wait for any frame count (e.g. ~34 min at 481 frames) instead of guessing.
- **actual:** warning only gives an anecdotal duration for one specific frame count, not a rate.
- **notes:** Reported by the tester agent (currently active on lem); plugin/skill doc fix, implementer to update per repo's plugin deploy path (commit + leave branch, no restart).
- **verify-notes:**

## T029

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-12T11:01:00Z
- **title:** LTX skill should recommend save: false on intermediate steps
- **tool/endpoint:** LTX plugin skill docs
- **repro:** n/a — documentation gap. Only the final deliverable step needs to write output; intermediate steps currently have no guidance against saving.
- **expected:** the skill states that intermediates should use `save: false` and only the deliverable should write - reporter estimates this saves ~35 minutes off every long render, and calls out that the failure mode (unnecessary writes slowing things down) is silent otherwise.
- **actual:** no such guidance exists in the skill today.
- **notes:** Reported by the tester agent (currently active on lem) as the highest-value line it could suggest adding to that skill. Plugin/skill doc fix, implementer to update per repo's plugin deploy path (commit + leave branch, no restart).
- **verify-notes:**

## T030

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-12T11:01:00Z
- **title:** music3 skill should spell out that the model fills its duration ceiling
- **tool/endpoint:** music3 plugin skill docs (`audio_duration` guidance)
- **repro:** n/a — documentation gap. Skill documents `audio_duration` as a ceiling and says to "ask for more than the piece needs," but doesn't spell out the operative consequence.
- **expected:** the skill states that the generated arc stretches to fill the budget, so a caption targeting e.g. ~20s under a 22s ceiling will get cut short/distorted; recommend setting the ceiling to at least 1.5x the intended length.
- **actual:** the consequence is implied but not stated, so an author under-sizing the ceiling gets a surprising result.
- **notes:** Reported by the tester agent (currently active on lem). Plugin/skill doc fix, implementer to update per repo's plugin deploy path (commit + leave branch, no restart).
- **verify-notes:**

## T031

- **status:** open
- **owner:** implementer
- **reported:** 2026-09-12T11:01:00Z
- **title:** LTX and music3 skills should mention worker memory hygiene before near-ceiling renders
- **tool/endpoint:** LTX and music3 plugin skill docs
- **repro:** n/a — documentation gap, related to the leak pattern in T024.
- **expected:** both skills advise checking idle `gpu_memory_allocated_mb` via `get_health`/`get_server_info` before a near-ceiling render; a non-trivial idle figure should prompt a worker restart rather than a retry, since each failed attempt leaks more (see T024).
- **actual:** neither skill currently mentions this check.
- **notes:** Reported by the tester agent (currently active on lem). Plugin/skill doc fix, implementer to update per repo's plugin deploy path (commit + leave branch, no restart). Related: T024 leak ticket makes this advice load-bearing, not just nice-to-have.
- **verify-notes:**
