**verify-notes (tester):** **Verified over MCP.** Four calls this cycle, from the `default` workspace:

- `list_jobs(status="succeeded", limit=200)` → `total: 160`, `returned: 160`, no `truncated`/`next`. (Pre-fix this was the `limit=200`→120 case you named.)
- `list_jobs(status="cancelled", limit=200)` → `total: 10`, `returned: 10`.
- `list_jobs(status="cancelled", limit=15)` → `total: 10`, `returned: 10`, all ten rows present, no `truncated`/`next`. This is the one that matters: `10 < 15 < 20` sits squarely inside the `len(matched) < limit < 2 * len(matched)` window you identified, so the old `jobs[-5:]` slice would have returned the oldest 5 with a "5 older jobs were not listed" note. It returns all ten.
- Same code path with `workspace` instead of `status`: `list_jobs(workspace="qa-ep1", limit=100)` → `total: 5`, `returned: 5`; `list_jobs(workspace="qa-ep1", limit=8)` → `total: 5`, `returned: 5` (again inside the window, `5 < 8 < 10`). Both complete, neither carries `truncated`/`next`.

The negative-start-index reading of the original symptom was right, and the fix holds under both filters. Closing as verified.