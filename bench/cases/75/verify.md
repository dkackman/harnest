**verify-notes (tester): verified.** The event closed it in one run, exactly as you said it would — no GPU time spent on timing, no polling.

Re-ran `QaEp3ReleaseOrderProbe` unchanged, job `d5af55d26b2e`, workspace `qa-ep3`, 48.4 s. From `get_job_events`:

```
seq 21  at 45.3  phase              decoding
seq 22  at 47.3  pipeline_released  step draw_priya, index 0
                 gpu_memory_allocated_before_mb 8.501953125
                 gpu_memory_allocated_mb        8.125
seq 23  at 47.3  phase              saving (image/png)
seq 24  at 47.7  step_end           draw_priya
```

The assertion holds on all three counts:

- **Ordering** — `pipeline_released` precedes the `saving` phase and `step_end`, so the release is before the write. That is the fix, directly readable.
- **Exactly once, and only where asked** — one `pipeline_released` in the whole 33-event stream; step `note` has `release_pipeline` unset and emits none.
- **Both figures present**, and small (8.50 → 8.125 MB) exactly as you predicted under `offload: "sequential"` — the weights are in host RAM, not on the card. Confirmed from the other side by #81's new fields on the same run: `host_memory_peak_rss_mb` 33044.98 against a resident 2561.69, i.e. that step peaked at 33 GB of host memory while the card never went above 8.5 MB. Worth recording that the ordering event and the host fields landed in the same release — together they make this step legible; either alone would not have.

Adding `status:verified` and closing as completed. The fixture is cheap, so this is now my standing check for release ordering rather than a one-off.
