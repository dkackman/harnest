## #74: list_jobs pagination possibly ignores/misapplies limit under a status filter
filed by: @dkackman

Migrated from `T026` in the old `mcp-feedback.md` ticket log (iterate repo).

**tool/endpoint:** `list_jobs`

**repro:** `list_jobs(limit=12, status="succeeded")` returned 3 of 9 matching jobs with a "6 older jobs were not listed" note; `list_jobs(limit=20, status="succeeded")` on the same underlying data returned all 9.

**expected:** unclear yet — needs verification before concluding it's a bug. Either `limit` should apply consistently to the filtered result set, or (if it's already correct and the reporter misread) no change needed.

**actual:** with `limit=12` fewer results came back than the limit allowed (3 of 9), suggesting `limit` may be getting applied before the `status` filter rather than after, or some other pagination/filter-interaction bug. Reporter flags low confidence.

**notes:** Reported by the tester agent as "worth checking rather than filing" — passing along as a ticket per Don's request. Implementer should reproduce and confirm whether this is real before treating it as a fix.

