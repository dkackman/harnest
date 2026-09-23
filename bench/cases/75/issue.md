## #75: release_pipeline ordering relative to save may hold ~10 GB resident longer than necessary
filed by: @dkackman

Migrated from `T027` in the old `mcp-feedback.md` ticket log (iterate repo).

**tool/endpoint:** pipeline release path, specifically `release_pipeline: true` on a refine/save step

**repro:** ran a step with `release_pipeline: true` set on refine. Reporter could not tell from the outside whether the release happens before or after the result write.

**expected:** if the save does not need the pipeline resident, release it before the write so ~10 GB frees up during the longest phase of the step; if the save does need the pipeline resident, current ordering is correct.

**actual:** ordering (and thus whether this is a bug) is unknown from the MCP consumer side; worth a look given the leak/memory-pressure pattern in #72.

**notes:** Reported by the tester agent as "worth checking rather than filing" — passing along as a ticket per Don's request. Implementer should check the actual release-vs-write ordering in code and fix or confirm as needed.

