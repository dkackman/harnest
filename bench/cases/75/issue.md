## #75: release_pipeline ordering relative to save may hold ~10 GB resident longer than necessary
filed by: @dkackman

Migrated from `T027` in the old `mcp-feedback.md` ticket log (iterate repo).

**tool/endpoint:** pipeline release path, specifically `release_pipeline: true` on a refine/save step

**repro:** ran a step with `release_pipeline: true` set on refine. Reporter could not tell from the outside whether the release happens before or after the result write.

**expected:** if the save does not need the pipeline resident, release it before the write so ~10 GB frees up during the longest phase of the step; if the save does need the pipeline resident, current ordering is correct.

**actual:** ordering (and thus whether this is a bug) is unknown from the MCP consumer side; worth a look given the leak/memory-pressure pattern in #72.

**notes:** Reported by the tester agent as "worth checking rather than filing" — passing along as a ticket per Don's request. Implementer should check the actual release-vs-write ordering in code and fix or confirm as needed.


--- comment by @dkackman at 2026-09-12T19:50:45Z ---
**fixed (implementer, 2026-09-12T19:50Z)** — commit `2e2ac05`, on `develop` @ `b7bd974`, deployed to `lem` and the server restarted at 19:48Z.

Checked the ordering: it was **after** the write, so your suspicion was right and the ~10 GB was held through the longest phase of the step.

The save does not need the pipeline — `Result` holds artifacts that are already in host memory by then, and nothing in `Result.save` touches the pipeline object — so the release now happens between `step.run` and `result.save`.

Two details that matter for what you will measure:

- Popping the pipeline from the cache was never enough on its own: the run loop's own local still referenced the step's action, so the weights stayed reachable regardless. Clearing that is now part of the release.
- The release reclaims on the spot (`gc.collect()` + `empty_device_cache()`) rather than waiting for the end-of-step cleanup, which is the whole point — otherwise the memory is "released" but not returned until after the write anyway.

To be straight about the size of the win: this does not lower the **peak** — nothing else is competing for the card while a step writes. What it buys is that the card is free during a phase that can run tens of minutes (see #76: ~4 s/frame at 1536x896), which matters on a shared box, and it shortens the window in which a crash during the write strands 10 GB.

A sub-workflow step's manifest is now read before the release so the rollup into job history is unaffected.

Tests: `tests/test_pipeline_caching.py::test_release_pipeline_happens_before_the_result_is_written` (asserts the pipeline is gone from the cache at the moment `save` is called). Full suite 3762 passed, 5 skipped.

**To verify from your side:** run a two-step workflow with `release_pipeline: true` on the first step and poll `get_memory` during the write-out phase — `gpu_memory_allocated_mb` should drop when the step's generation finishes rather than when its file appears. `get_job_events` timestamps bracket the window.

