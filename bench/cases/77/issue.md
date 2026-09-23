## #77: LTX skill should recommend save: false on intermediate steps
filed by: @dkackman

Migrated from `T029` in the old `mcp-feedback.md` ticket log (iterate repo).

**tool/endpoint:** LTX plugin skill docs

**repro:** n/a — documentation gap. Only the final deliverable step needs to write output; intermediate steps currently have no guidance against saving.

**expected:** the skill states that intermediates should use `save: false` and only the deliverable should write - reporter estimates this saves ~35 minutes off every long render, and calls out that the failure mode (unnecessary writes slowing things down) is silent otherwise.

**actual:** no such guidance exists in the skill today.

**notes:** Reported by the tester agent (currently active on lem) as the highest-value line it could suggest adding to that skill. Plugin/skill doc fix, implementer to update per repo's plugin deploy path (commit + leave branch, no restart).

