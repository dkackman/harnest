## #74: list_jobs pagination possibly ignores/misapplies limit under a status filter
filed by: @dkackman

Migrated from `T026` in the old `mcp-feedback.md` ticket log (iterate repo).

**tool/endpoint:** `list_jobs`

**repro:** `list_jobs(limit=12, status="succeeded")` returned 3 of 9 matching jobs with a "6 older jobs were not listed" note; `list_jobs(limit=20, status="succeeded")` on the same underlying data returned all 9.

**expected:** unclear yet — needs verification before concluding it's a bug. Either `limit` should apply consistently to the filtered result set, or (if it's already correct and the reporter misread) no change needed.

**actual:** with `limit=12` fewer results came back than the limit allowed (3 of 9), suggesting `limit` may be getting applied before the `status` filter rather than after, or some other pagination/filter-interaction bug. Reporter flags low confidence.

**notes:** Reported by the tester agent as "worth checking rather than filing" — passing along as a ticket per Don's request. Implementer should reproduce and confirm whether this is real before treating it as a fix.


--- comment by @dkackman at 2026-09-12T19:50:41Z ---
**fixed (implementer, 2026-09-12T19:50Z)** — commit `d7d2aff`, on `develop` @ `b7bd974`, deployed to `lem` and the server restarted at 19:48Z.

Real bug, and your reading was right: `limit` was misapplied. Not "applied before the filter" — the filter ran first and `total` was correct — but the newest-N slice was taken from `len(jobs) - limit`, which goes **negative** once the limit exceeds what matched, and Python then reads that from the end of the list. 9 matching jobs at `limit=12` → `jobs[-3:]` → the last 3, with "6 older jobs were not listed" attached. Exactly what you saw.

It only bites when `len(matched) < limit < 2 * len(matched)`. At `limit=20` against 9, the start index is `-11`, which is past the front of the list and clamps to 0 — so the same data looked correct, which is why it read as a phantom. Good catch filing it as low-confidence rather than not at all.

Verified live on `lem` after the restart, against 160 succeeded jobs:

```
limit=100 → total 160, returned 100
limit=150 → total 160, returned 150
limit=200 → total 160, returned 160   (before the fix: 120)
```

Tests: `tests/test_jobs_listing.py::test_limit_larger_than_the_match_returns_every_match` and `...under_a_status_filter`. Full suite 3762 passed, 5 skipped.

**To verify over MCP:** `list_jobs(status="succeeded")` for the true count N, then `list_jobs(limit=L, status="succeeded")` with L a little above N (say N+3). `returned` must equal N and there must be no `truncated` / `next` note. Worth trying with `workspace` too — same code path, same slice.

