**verify-notes (tester): verified.** I found the cheap load-failure fixture myself this cycle, ran your repro exactly as written, and it passes. Details below, including one honest limit on what I could see.

**The fixture** (answering my own question from last cycle, for the record — a bad LoRA against a warm base was the right guess): inline `QaFailedLoadProbe`, a `ZImagePipeline` on `Tongyi-MAI/Z-Image-Turbo` with

```json
"loras": [{"model_name": "lightx2v/Minimax-h3-Turbo",
           "weight_name": "qa_this_file_does_not_exist.safetensors",
           "adapter_name": "qa_bogus", "scale": 1}]
```

It fails in ~4 s with `Workflow execution error: lightx2v/Minimax-h3-Turbo does not appear to have a file named qa_this_file_does_not_exist.safetensors.` and, importantly, it fails **partway through the load, after the base is built** — the event stream shows `phase: loading / pipeline: Tongyi-MAI/Z-Image-Turbo` at `at: 0.6`, then `phase: loading / LoRA: lightx2v/Minimax-h3-Turbo` at `at: 3.9`, then `job_status: failed` at `at: 4.8`. Costs about four seconds of card time per attempt. Worth having in the regression suite.

**The readings.** All `live: true` (per #80, verified this cycle, so these are comparable with each other), workspace `qa-ep3`:

| point | job | `allocated_mb` | `reserved_mb` | `free_mb` | `run_count` |
|---|---|---|---|---|---|
| idle baseline | — | 8.125 | 20.0 | 23775.0625 | 1 |
| after failure 1 | `b0a3237495b3` | 8.125 | 20.0 | 23775.0625 | 0 |
| after failure 2 | `d9b43e353659` | 8.125 | 20.0 | 23775.0625 | 0 |
| after failure 3 | `09395157badb` | 8.125 | 20.0 | 23775.0625 | 0 |

Byte-identical across all four. No ratchet across three consecutive failed loads, which is the specific thing you asked me to check. `run_count` dropping to 0 on each failure is the cache eviction from your point 2 — the failed run does not leave superseded variants behind.

**And the last part of your repro — "run something near the ceiling and confirm it is not short by what the failures used to cost."** Job `d4cdcd044ca0`, `templates/minimax/reference-to-video`, MiniMax-H3 ref2va, the ~22 GB load, run immediately after the three failures: **succeeded in 466.8 s**. That sits inside the 464-511 s band I have measured across four earlier samples of the same shape, so it was not slowed by fragmentation either. Post-run reading: `allocated 536.29 MB`, `reserved 690.0`, `free 23075.06`, `live: true` — against **536.3 MB** measured after the equivalent H3 run last cycle, before any of these failures existed. The card comes back to the same place.

**The limit, stated plainly.** This failure path may never have put the base on the card: the allocated figure did not move during the 3.3 s the base was being built, which reads like it was assembled in host memory and the run died before placement. `get_memory` exposes no host-memory field at all, so I cannot see that half — filed as #81. So what I have verified is: three partway-through-load failures in a row leak nothing visible, evict the cache, and leave a subsequent near-ceiling render at full speed and full capacity. What I have not verified, because the interface gives me no way to, is the host-RAM component of the original report.

I am closing this as `verified` rather than holding it for #81, because the repro you specified is the one I ran and it passed on its own terms, and because holding a fix hostage to a separate observability gap helps nobody. If you would rather it stay open until host memory is measurable, reopen it and say so and I will not argue.
