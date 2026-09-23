**Verified** — tester agent, model `opus` via provider `anthropic`, server `0.4.0-beta.6` on `lem`, after the `f5f30ea` deploy.

Re-ran the C-F006 repro in a throwaway workspace `qa-verify-262` (deleted afterwards):

```
clear_memory()                                   # host RSS 2395 MB before the cold run
validate_workflow(name="templates/ltx2/text-to-video")
run_workflow(workflow_path="templates/ltx2/text-to-video", acknowledged_cost={fingerprint: sha256:416d8e5d…, minutes: 2.8, downloads: []})
```

Cold job **`bbd9e8e07849`** (run `20260921-052353-e7379d14`), then a warm one. Note the plain re-run **`f4c187565245`** came back `reused: true` from the step cache in 0.9 s (seeded, identical inputs), so the real warm run is **`0ccc4514ab37`** (run `20260921-052617-c64da411`) with only `prompt` overridden — same drivers (960×544×121), no cache hit.

| span | 2026-09-19 ref | reported cold | reported warm | **cold now** | **warm now** |
|---|---|---|---|---|---|
| `loading` | 82 s | 81.4 s | — | 77.4 s | — |
| `generating` → first `pipeline_step` | 15 s | **98.9 s** | 4.5 s | 7.9 s | ~4 s |
| 8 denoise steps | ~26 s | 23.5 s | 23.3 s | 23.3 s | 23.4 s |
| `decoding` | ~6 s | **30.8 s** | **26.2 s** | 8.2 s | 12.2 s |
| `saving` → `step_end` | 1.8 s | **10.3 s** (wrote in 9.8s) | **9.8 s** (wrote in 9.4s) | **1.6 s** (wrote in 1.3s) | **2.1 s** (wrote in 1.8s) |
| whole run | 132.5 s | **246.2 s** | 64.4 s | **119.6 s** | 42.7 s |

- **Saving phase: fixed.** 1.3 s / 1.8 s encode, back at the historical ~1.5–2 s, on both runs. The warm run's output tripped `audio_near_silent` (-57.49 dBFS), so the #261 probe path was exercised and still stayed in that budget — the shared-probe change holds in the case that fires the warning, not only the quiet one.
- **Whole run** 119.6 s cold — under the case's ≲170 s ceiling and below the 125 s history median. C-F006 passes as written.
- **Silent lead-in did not recur** this session (7.9 s cold, in line with the 15 s reference; nothing like 99 s). Consistent with the implementer's read that it's about first use in a worker lifetime after something else ran — here the worker was freshly cleared with nothing before it. Not reproduced, nothing more to hand over.
- **Decoding** 8.2 s cold / 12.2 s warm: the 5x is gone (was 26–31 s) but it's not clearly back at the ~6 s reference either, and the warm run was the slower one. Same 45 GB idle host RSS after the job (`host_memory_rss_mb` 45,441, peak 61,580, 37,436 available) as the original report noted. Within the case's tolerances, so I'm not opening a new issue on this alone; `regression-perf/C-F006.jsonl` trend checks will catch it if it creeps.

Suggested regression case: not adding a new one — C-F006 in `regression-suite-complete.md` already asserts `saving`→`step_end` under ~5 s on exactly this template, and an LTX-2.5 run is too expensive for the smoke suite.

Closing as verified.
