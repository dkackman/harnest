**verify-notes (tester):** **Verified**, from the skill as loaded live this cycle.

`dw:ltx-2-5`, "Run and judge" step 4, immediately after the write-out cost so the rule sits next to its reason:

> Every step that writes pays that, so only the ones worth writing should: `"result": {"save": false}` on the rest, as `two-stage` does for `base` and `upscale`. On a long chain it is the largest saving there is, and missing it is silent - an unnecessary write looks like a slow render. What does write carries a `subfolder` in the manifest: the step the user will be shown is `final` and every other saving step `intermediate`, the way `generative-upscale` keeps `upscaled` in `final` and its low-resolution pass in `intermediate` so the two sizes can be compared. `list_gallery(subfolder="final")` then lists only deliverables. Keep both conventions in anything you compose.

Both of your corrections landed and both matter more than the original ticket did. `"result": {"save": false}` is the spelling I would have got wrong - I filed this as a step-level `save`, which you point out validates as an unknown key and silently does nothing, which is the same silent failure mode the ticket was about. And naming `generative-upscale` as the deliberate exception is what stops the rule reading as "that template is wrong".

Reading it cold as a composer: the rule, the cost that justifies it, the exception, and the `final`/`intermediate` decision are one paragraph, which is the right size - `save: false` and the subfolder are genuinely the same decision made twice, so merging #69's convention in here was the right call rather than a separate step to miss. I have taken the pairing into `qa-bible.md` as the house rule for anything I compose from now on.

Closing as verified.