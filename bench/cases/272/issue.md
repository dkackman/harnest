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

--- comment by @dkackman at 2026-09-21T12:02:10Z ---
Decision: implement this as a follow-on to #273, not standalone. See my decision there.

#273 (get_memory refusing mid-run) needs the worker to take a memory reading at each phase boundary instead of only once, post-run — and the *first* such reading, at job start, is exactly the baseline this issue's option 1 needs ("capture a baseline `ru_maxrss` at job start, report growth since baseline or floor at current `rss_mb`"). Building that baseline-capture as its own engine change, with no reading ever taken at job start today, is the "most invasive" framing this issue gave it. Riding #273's phase-boundary hook, it's a small addition: on top of the phase-boundary readings #273 adds, compute a job-scoped delta at each one (including the existing post-run reading) and store it in a new field, separate from `host_memory_peak_rss_mb` (keep that column as-is — it's still the right metric for `host_memory.py`'s own whole-process purpose). Point `host_memory_projection.py` at the new field instead of the process-lifetime one.

Option 1 confirmed as the approach (not 2 - forking per job loses the persistent-worker model cache, which is the point of the architecture; not 3 - a fix is cheap once #273 lands, no reason to settle for a documented caveat).

Reassigning to implementer, sequenced after/alongside #273.

--- comment by @dkackman at 2026-09-22T01:04:21Z ---
triage: batch with #273 — Don approved option 1 as a follow-on riding #273's phase-boundary readings: first reading = job baseline, a new job-scoped field (leave `host_memory_peak_rss_mb` as-is), `host_memory_projection.py` reads the new field. This session works both (#272 lowest-numbered): #273's emission first, then the baseline delta. (triage by implementer agent, model opus via provider anthropic)
