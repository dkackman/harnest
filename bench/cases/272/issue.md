## #272: host_memory_peak_rss_mb is process-lifetime, not per-job - poisons host-memory projections in a persistent worker
filed by: @dkackman

Split off from #264 during the fix for that issue's resident-shape regression (which is fixed separately, see #264's hand-off comment).

**Problem:** `host_memory_peak_rss_mb` (`dw/host_memory.py`, `_peak_rss_mb()`) is `resource.getrusage(RUSAGE_SELF).ru_maxrss` - the worker process's monotonic, unresettable high-water mark of resident memory since the process started. That's the right metric for `host_memory.py`'s own stated purpose ("whether a run that has finished released what it took" - a whole-process question, answered by comparing it to current `rss_mb`).

`dw/host_memory_projection.py` (#243, #254) repurposes the same field for a different question it was never designed to answer: "how much host memory did *this specific job* peak at." In `dw.serve`'s persistent worker (kept alive across jobs to cache GPU models), a small job run shortly after a much heavier job inherits the heavier job's lifetime peak in its own reported figure. This directly poisons the released-shape projection in `host_memory_warnings`, which takes `max(peaks)` across history rows: a trivial job can be recorded with a multi-GB "peak" it never actually caused, producing a false warning on a request that would never come close to the ceiling (observed live: #264's repro step 5).

**Why this needs a decision rather than a quick edit:** a real fix means a new per-job memory metric - e.g. capturing a baseline `ru_maxrss` at job start and reporting a job-scoped figure (the growth since baseline, or the job's current `rss_mb` when there was no growth) - which is new engine surface: a new field/column persisted in `jobs.sqlite`, a change to what the worker reports per job (`dw/worker.py`'s `_get_memory_info`), and a change to what `host_memory_projection.py` and (potentially) `observed_cost.py` consume. It also can't fully solve the general case: `ru_maxrss` fundamentally cannot be reset mid-process, so any per-job figure is necessarily an approximation (a job whose own peak stays *below* a still-current high-water mark has no way to be measured exactly - only bounded below by its own `rss_mb`).

**Options for whoever picks this up:**
1. Add a job-scoped memory metric (baseline-before/after delta, floor at current `rss_mb`) as a new field, and switch `host_memory_projection.py` to use it instead of the lifetime peak. Most accurate, most invasive.
2. Cheaper mitigation: have the worker call something equivalent to `torch.cuda.reset_peak_memory_stats()` for host memory between jobs - not possible for `ru_maxrss` directly (POSIX has no reset), but a forked-subprocess-per-job model would give a real per-job peak at the cost of losing the persistent-worker model cache, which is the entire point of the worker architecture. Likely not worth it.
3. Leave the released-shape projection as an intentionally conservative (occasionally over-warning) figure and document the caveat, accepting that it's the "warn, not refuse" module's own worst case rather than fixing the data source.

Filed as `owner:don` / `status:needs-approval` per the implementer's role guidance on changes that add new engine/validation surface, rather than building one of these unasked.

Filed by implementer, model sonnet via provider anthropic, while working #264.
