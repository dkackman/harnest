## #77: LTX skill should recommend save: false on intermediate steps
filed by: @dkackman

Migrated from `T029` in the old `mcp-feedback.md` ticket log (iterate repo).

**tool/endpoint:** LTX plugin skill docs

**repro:** n/a — documentation gap. Only the final deliverable step needs to write output; intermediate steps currently have no guidance against saving.

**expected:** the skill states that intermediates should use `save: false` and only the deliverable should write - reporter estimates this saves ~35 minutes off every long render, and calls out that the failure mode (unnecessary writes slowing things down) is silent otherwise.

**actual:** no such guidance exists in the skill today.

**notes:** Reported by the tester agent (currently active on lem) as the highest-value line it could suggest adding to that skill. Plugin/skill doc fix, implementer to update per repo's plugin deploy path (commit + leave branch, no restart).


--- comment by @dkackman at 2026-09-12T19:51:08Z ---
**fixed (implementer, 2026-09-12T19:50Z)** — commit `3206307`.

**This is a plugin/skill change — no server restart involved.** The tester loads the plugin from my working tree via `--plugin-dir`; the checkout is left on `develop` @ `b7bd974`, which contains it (commit `3206307`). `tests/test_plugin_skills.py` passes, 30 tests.

Added as its own step in the LTX skill's "Run and judge", right after the write-out cost so the reason is next to the rule:

> Every step that writes pays that, so only the ones worth writing should: `"result": {"save": false}` on the rest, as `two-stage` does for `base` and `upscale` and `extend-clip` for `opening` and `opening_frames`. Keep that in anything you compose; depart from it only the way `generative-upscale` does, saving its low-resolution pass so the two sizes can be compared. […] On a long chain it is the largest saving available, and missing it is silent - an unnecessary write looks exactly like a slow render.

Two corrections to the ticket as filed, both in your favour:

- The flag is **`"result": {"save": false}`**, not a step-level `save` — worth having exactly right in the skill, since the step-level spelling validates as an unknown key and does nothing.
- The shipped templates already do this (`two-stage` on `base`/`upscale`, `extend-clip` on `opening`/`opening_frames`), so the gap was guidance for *composed* workflows, not a defect in what you would have run. `generative-upscale` saves both passes on purpose, and the skill now names it as the deliberate exception so the rule doesn't read as "that template is wrong".

I also merged the subfolder convention into the same step, since `save: false` and `final`/`intermediate` are the same decision made twice — what gets written, and where.

**To verify:** compose a chain from the skill cold and check the intermediates come out with `save: false` and only the deliverable writes.

