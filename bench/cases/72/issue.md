## #72: Failed pipeline loads leak GPU/host memory instead of being released, and leaks accumulate across retries
filed by: @dkackman

Migrated from `T024` in the old `mcp-feedback.md` ticket log (iterate repo).

**tool/endpoint:** pipeline loading/caching path (whatever constructs and caches diffusers pipeline instances, e.g. around `release_pipeline`/`release_models` and the group-offload variant)

**repro:** a pipeline load or a variant load (e.g. a group-offload attempt) fails or is aborted partway through; a subsequent decode comes up short on memory. Reported symptom: "the decode was 1.88 GiB short: it started with 4.2 GB of dead weight, and the group-offload attempt added ~12 GB more of a new pipeline variant that will never be reused."

**expected:** a pipeline (or pipeline variant) that fails to load, or that is superseded by a retry/different variant, is fully torn down and its memory reclaimed before or as part of the next attempt - no dead weight left resident, and no accumulation across repeated failures.

**actual:** each failed/superseded pipeline load leaks its allocated memory; repeated failures accumulate dead weight (observed: 4.2 GB from earlier failures, then +~12 GB from a group-offload variant that was never going to be reused), eventually starving a later decode by ~1.88 GiB.

**expected repro to confirm fix:** force a pipeline load failure (or trigger the group-offload path then abandon it), check GPU/host memory before and after, then retry the decode and confirm no residual allocation remains from the failed attempt.


--- comment by @dkackman at 2026-09-12T19:49:59Z ---
**fixed (implementer, 2026-09-12T19:50Z)** — commit `6e5ea8f`, on `develop` @ `b7bd974`, deployed to `lem` and the server restarted at 19:48Z (healthy: `/api/health` → `status: ok`).

Real, and it was two leaks compounding, not one.

**1. `Pipeline.load` kept whatever it had built when it raised partway.** The load is long: the pipeline itself, then quantization, SDNQ matmuls, LoRAs, the IP-adapter, then placement — any of which can fail. When one did, the caller never received a pipeline, so nothing held a handle to drop, and several GB stayed resident until something else happened to collect. That is your 4.2 GB of dead weight from earlier failures. The load now tears its own attempt down on the way out (`_discard_failed_load`): drops the pipeline, reclaims (`gc.collect()` + `empty_device_cache()`), and unpublishes any component it had already shared — a component shared before the failure would otherwise have been handed to a later step as a component of a pipeline that does not exist. A name it *reused* rather than loaded stays published; that entry belongs to an earlier pipeline that is still alive.

**2. The worker reclaimed on success and on cancellation but not on failure.** No collection, no device-cache empty, and — the part that matches your group-offload symptom — no eviction of cached pipelines the run did not touch. A successful run drops superseded variants; a failed one left them cached, so the ~12 GB variant that was never going to be reused sat there while the next attempt loaded its own on top. Failure now does all three.

**3. The traceback was pinning the frames.** Worth knowing because it makes the other two work: the exception reaches every frame between the handler and the failure, and those frames hold the half-built components as locals. A collection run while the exception is still live frees none of it. The report is a formatted string by the time we clean up, so the traceback is dropped first and the reclaim afterwards has something to reclaim. (A test pins this with a weakref; it fails without the two lines.)

Tests: `tests/test_pipeline_components.py::TestFailedLoadIsTornDown` (2), `tests/test_worker_execute.py` (2). Full suite 3762 passed, 5 skipped.

**How to confirm from your side:** `get_memory` for `gpu_memory_allocated_mb` with the server idle; force a load failure (an oversized request, or a bad component config); `get_memory` again once the error comes back. The figure should return to its idle value rather than staying up, and a second and third failed attempt should not walk it upward. Then run something near the ceiling and confirm it is not short by what the failures used to cost.

Related shipped in the same batch: #75 (release ordering) and #79 (both skills now tell you to check idle allocated memory before a near-ceiling render).

