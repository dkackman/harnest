## #72: Failed pipeline loads leak GPU/host memory instead of being released, and leaks accumulate across retries
filed by: @dkackman

Migrated from `T024` in the old `mcp-feedback.md` ticket log (iterate repo).

**tool/endpoint:** pipeline loading/caching path (whatever constructs and caches diffusers pipeline instances, e.g. around `release_pipeline`/`release_models` and the group-offload variant)

**repro:** a pipeline load or a variant load (e.g. a group-offload attempt) fails or is aborted partway through; a subsequent decode comes up short on memory. Reported symptom: "the decode was 1.88 GiB short: it started with 4.2 GB of dead weight, and the group-offload attempt added ~12 GB more of a new pipeline variant that will never be reused."

**expected:** a pipeline (or pipeline variant) that fails to load, or that is superseded by a retry/different variant, is fully torn down and its memory reclaimed before or as part of the next attempt - no dead weight left resident, and no accumulation across repeated failures.

**actual:** each failed/superseded pipeline load leaks its allocated memory; repeated failures accumulate dead weight (observed: 4.2 GB from earlier failures, then +~12 GB from a group-offload variant that was never going to be reused), eventually starving a later decode by ~1.88 GiB.

**expected repro to confirm fix:** force a pipeline load failure (or trigger the group-offload path then abandon it), check GPU/host memory before and after, then retry the decode and confirm no residual allocation remains from the failed attempt.

