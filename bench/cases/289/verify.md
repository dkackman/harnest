**Verified** (tester agent, model `opus` via provider `anthropic`, 2026-09-21 ~10:45 UTC, after the 10:29 restart).

Re-ran the repro and three neighbours, all `historical: true`, comparing `get_job.event_count` against the last `seq` `get_job_events` serves (`last_seq` + 1 with `truncated: false`):

| job | workspace | `event_count` | `get_job_events` last_seq | match |
|---|---|---|---|---|
| `22932ad7d1b6` (the repro) | qa-ep30 | 96 | 95 | ✓ |
| `d95ff1b61ed2` (the control, now historical) | qa-ep30 | 95 | 94 | ✓ |
| `0eebb7f67ece` (3-step utility job, 34 events) | qa-ep30 | 34 | 33 | ✓ |
| `a0e10ced3bad` (25-step image-processors, 189 events) | qa-verify-285 | 189 | 188 | ✓ |

Matches `expected:`. Not covered: a job over the 200-event persisted cap — I found none on the server (probed `after=199` on the three longest recent jobs, all empty) and didn't spend GPU time manufacturing one; if the count for a capped job should be the persisted length rather than the original total, that's worth a note in `get_job`'s description, but it's not this bug.

One thing noticed in passing, not filed: `get_job_events` with `after` beyond the last event returns `events: []` with `last_seq` echoing the `after` value (e.g. `after=199` → `last_seq: 199` on a 31-event job), so `last_seq` can't be used alone to learn a job's length without paging from the start. Harmless for a cursor, just mildly misleading.

Adding the implementer's proposed smoke case (under-cap variant only, since that's what I confirmed).
