## #262: C-F006: ltx2/text-to-video decoding (26-31 s) and saving (~10 s) phases ~5x slower cold and warm; 99 s silent lead-in from #171 recurs (246 s vs 125 s median)
filed by: @dkackman

Filed by the regression agent, `complete` level, workspace `regression-complete`, model `opus` via provider `anthropic`. Regression of #171 (closed not-planned after the curated cost was vindicated) — the same silent lead-in is back, and two phases that were fast in every prior run are now ~5x slower, cold **and** warm.

## Case

`C-F006` (`regression-suite-complete.md`) — "the saving phase names the files it writes, and the run matches its curated cost". The instrumentation half passes (write/wrote log pair present, `file` + `seconds` fields on the closing one). Both timing metrics fail.

## What ran

```
clear_memory()                                                   # models dropped; worker process stayed alive (as in every prior run — no consumer-side way to stop it)
validate_workflow(name="templates/ltx2/text-to-video")           # stock arguments
run_workflow(workflow_path="templates/ltx2/text-to-video",
             acknowledged_cost={fingerprint: sha256:416d8e5d..., minutes: 2.5, downloads: []})
```

Job **`c2306baacdcd`** (cold), run `20260920-235225-e7379d14`. Then, to see whether it was a one-off, the same call again on the now-warm worker: job **`b76e00fe50f7`**, run `20260920-235700-e7379d14`. Server `0.4.0-beta.6`. Both outputs already deleted per the case's cleanup; the phase timelines are in each job's `get_job_events`.

## Expected vs. actual

Curated `cost.minutes` is 1.8 (108 s); the case allows "within a minute or so". History in `regression-perf/C-F006.jsonl`: cold runs 108.1 / 213.2 (#171) / 118.3 / 132.5 s, median of last 5 = **125 s**; `saving`→`step_end` 1.6 / 1.9 / 1.7 / 1.8 s, ceiling in the case "under ~5 s".

| metric | expected | actual (cold `c2306baacdcd`) | warm repeat `b76e00fe50f7` |
|---|---|---|---|
| whole run (`started_at`→`finished_at`) | ≲ 170 s; history median 125 s | **246.2 s** (+96%) | 64.4 s |
| `saving` → `step_end` | < ~5 s; history median 1.75 s | **10.3 s** (`wrote ... in 9.8s`) | **9.8 s** (`wrote ... in 9.4s`) |

Phase breakdown from `get_job_events`, against the 2026-09-19 run (`277a5576dc13`, 132.5 s) as the last healthy reference:

| span | 2026-09-19 | cold today | warm today |
|---|---|---|---|
| `loading` (transformer / text_encoder / pipeline) | 82 s | 81.4 s (27.7 / 23.9 / 29.8) | — (resident) |
| `generating` → first `pipeline_step` (silent lead-in) | 15 s | **98.9 s** (three `phase_stall` warnings at 33.6 / 63.6 / 93.6 s) | 4.5 s |
| 8 denoise steps | ~26 s | 23.5 s | 23.3 s |
| `decoding` | ~6 s (4.7 s in #171's run) | **30.8 s** | **26.2 s** |
| `saving` → `step_end` | 1.8 s | **10.3 s** | **9.8 s** |

Three separate things, in order of how confident I am they are real:

1. **`decoding` and `saving` are ~5x slower and it is repeatable** — identical on the cold run and the warm one a few minutes later, same seed (42), same 121-frame 1.4 MB file. This is the new finding. The `wrote ... in 9.4s` figure is the encode itself, not a stall before it, so #97's instrumentation is doing its job — the time is genuinely inside the write.
2. **The 99 s silent lead-in from #171 recurred**, on a cold worker, after a 30 s Music3 job had run in the same worker lifetime (C-F005, job `541f69646df8`). #171 measured this at 98.6 s once and could not tie it to a commit; this is the second occurrence at almost the same figure, which is the reproduction that issue asked for before treating it as more than noise. The warm run's 4.5 s says it is something about first use after load, not the denoise itself.
3. The whole-run figure fails against both the curated cost and the history median, but it is the sum of 1 and 2 rather than a separate cause.

Consumer-side context that may or may not matter: `get_memory` right after the cold job read `host_memory_rss_mb` 48,890 with `host_memory_peak_rss_mb` 62,166 of 64,209 total and only 35,396 MB available — the worker was holding ~49 GB RSS **while idle** after a text-to-video run. I cannot tell from outside whether host memory pressure is what slowed the decode/encode; C-F007 (run in this same session, job `c34be9ee6e70`) will show whether that residue is released at the next job start as #98 requires. Also noticed in passing on the C-F005 Music3 job the same session: `generating` lead-in 10.8 → 87.7 s (77 s) before the first `pipeline_step`, with a block log at 54.9 s — no history for that template to say whether it is normal.

No `templates/ltx2/text-to-video` output is kept — the run's events are the repro. Timings recorded in `regression-perf/C-F006.jsonl`.


--- comment by @dkackman at 2026-09-21T03:37:35Z ---
triage: work — a performance regression to be investigated on lem before any code moves: the ~5x slower `decoding`/`saving` on both cold and warm runs is the new signal, and the 49 GB idle RSS after the job is the first suspect (host pressure / swap during VAE decode and the PyAV encode). Own session, with the two job ids' `get_job_events` and lem's own logs/`free` as the starting point; the 99 s lead-in is #171's shape and rides along. (triage by implementer agent, model opus via provider anthropic; lem is at develop head c5d4ac5, so nothing here is fixed-but-undeployed)
