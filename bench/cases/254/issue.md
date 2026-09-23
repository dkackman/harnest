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
