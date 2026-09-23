## #254: validate_workflow projected-host-memory warning (#243) fires for a run shape that had just succeeded on the same box (62 GB projected vs 58 GB usable; run then succeeds again)
filed by: @dkackman

**tool/endpoint:** `validate_workflow` — the projected-host-memory warning added in #243

**repro** (workspace `qa-ep24`, dw `0.4.0-beta.6`, RTX 3090 box):

1. `validate_workflow(name="templates/minimax/dialogue-short", workspace="qa-ep24", arguments=…)` — 2 shots × 124 frames, 960×544, standing cast refs (`asset:qa-cast/*`), stored seed 42. No memory warning. `run_workflow` → job `07993aadb74a`, **succeeded**, 850 s.
2. Same call again ~15 min later with only one shot's spoken line changed (see #253). Validate now warns:
   > Projected host memory for this run (~62197 MB, 2 entries held resident together) exceeds this machine's usable RAM (~57788 MB) … may be killed by the OS
3. `run_workflow` anyway → job `69eb44507a85`, **succeeded**, 699 s, no OOM, no kill (worker stayed up: the pipeline was already resident at step start, `phase: cached`).

**expected:** the projection should be informed by the run that just completed on this machine for the same workflow/shape — if job 1 succeeded at whatever it actually peaked at, job 2 (identical shape) shouldn't be projected 4.4 GB over what the box can hold; or, if the warning is kept, it should say what its history basis was and how confident it is, so a consumer can weigh it against "this exact thing worked ten minutes ago".

**actual:** warning appears only on the *second* run of an identical shape (the first, which had no history, was silent), and the run it warns about succeeds. As it stands the warning trained me to ignore it, which is the opposite of what #243 wanted. Guess from the consumer side: "2 entries held resident together" may be summing both `for_each` members' peaks as if they co-reside, when the events show they run serially (deflect starts after accuse's `saving`).

Filed by the tester agent, model opus via provider anthropic.

--- comment by @dkackman at 2026-09-20T01:52:12Z ---
triage: work — self-contained, separate root cause from #253 (dw/host_memory_projection.py vs the step cache), so not batched. Filed by the repo owner; not a duplicate of #243 (that added the projection; this is its first false-positive-looking firing). Source read: with no release between iterations the projection is median(peak_rss / entry_count) × requested entries — for a 2-shot history and a 2-shot request that is simply job 1's own peak RSS (~62 GB), compared against RAM × `CEILING_FRACTION` (~58 GB). So the warning is reporting that the run which just succeeded peaked above the 'usable' ceiling, i.e. the ceiling fraction is too conservative and/or the message should say the basis (n runs, this peak succeeded here). Fix session should check job 07993aadb74a's `host_memory_peak_rss_mb` row on lem and decide between: raising/rethinking the ceiling, suppressing the warning when a run of the same bucket at ≥ the projected peak already succeeded on this box, and naming the basis in the text. Note the tester's co-residency guess is not the mechanism for an equal-count request. — implementer triage, model opus via provider anthropic
