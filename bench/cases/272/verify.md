**Verified** against lem `develop @ d5e3725`, in workspace `qa-verify-272`.

What I ran (over MCP):
1. `run_workflow(workflow_path="templates/prompt-weighting", ...)` → job `fb77c0f322e6`. It failed with CUDA OOM while loading FLUX.1-schnell (unrelated to this issue, noted below), but it served as the "heavy" neighbour: its `Released cached models` log shows 31.8 GB returned to the OS from whatever ran before, and the process-lifetime `host_memory_peak_rss_mb` in the worker was already **61811 MB**.
2. Immediately after, same worker, no restart: `run_workflow(workflow_path="templates/text-to-image", arguments={"prompt": "a small green pear"})` → job `6ad4f4781fce`, succeeded in 8.6 s.
3. `get_job_events(job_id="6ad4f4781fce")` — every `memory` event now carries both fields:

| phase | `host_memory_rss_mb` | `host_memory_peak_rss_mb` (lifetime) | `host_memory_job_peak_rss_mb` (new) |
|---|---|---|---|
| loading (first reading = baseline) | 1898.8 | 61811.3 | 1898.8 |
| generating | 1911.8 | 61811.3 | 1911.8 |
| decoding | 2076.0 | 61811.3 | 2076.0 |
| saving | 2098.2 | 61811.3 | 2098.2 |
| post-run | 2098.8 | 61811.3 | 2098.8 |

That's exactly the intended split: the trivial SD1.5 job reports a ~2.1 GB job-scoped peak (floored at its own rss, since it caused no growth against the inherited high-water mark) while the process-lifetime field still shows the inherited 61.8 GB. Before this fix the small job would have been recorded at 61.8 GB and poisoned the released-shape projection. `host_memory_peak_rss_mb` is unchanged in meaning, as Don asked.

Adjacent check: the failed heavy job's readings (`fb77c0f322e6`) show the baseline captured at its first phase-boundary reading (1890 MB, both fields consistent), so the baseline is taken per job, not carried from the previous one.

Not verified here: the actual `host_memory_warnings` projection outcome (would need a workflow near the host ceiling); I'm treating the field it now reads as confirmed by the data above. Side observation, not this issue: `templates/prompt-weighting` OOMs on the 24 GB card loading FLUX.1-schnell unquantized (23.25 GB in-process) — filing separately.

Adding the implementer's suggested regression case to `regression-suite-complete.md`.

Verified by tester agent, model opus via provider anthropic.
