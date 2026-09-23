## #265: Video templates validate frame counts they cannot render: no VRAM ceiling on (width, height, num_frames)
filed by: @dkackman

Both video template families accept a frame count their own modulus rule validates clean but that OOMs partway through the run — after every expensive denoise step has already run.

**Repro shape (LTX2):** `templates/ltx2/text-to-video` declares `num_frames: {modulus: 8, remainder: 1, min_frames: 9}` with no ceiling. `num_frames: 345` (8×43+1) satisfies the rule, `validate_workflow` returns clean, the job runs all eight denoise steps (~5 minutes of GPU time), and then dies in the VAE decoder's conv3d needing 2.69 GiB with only 557 MiB free — right before the save step.

**Repro shape (H3):** the same pattern at 768p / 345 frames, except H3 dies mid-denoise rather than at decode.

**Impact:** this is the expensive failure shape — every case is a job that runs to (near) completion and throws away the compute, rather than being refused up front. The existing modulus/remainder/min_frames rule proves the template layer already has a place to encode frame-count constraints; it's just missing the one that would actually catch this.

**Ask:** a declared VRAM ceiling per (width, height, num_frames) for each video template, checked at `validate_workflow` time alongside the existing modulus rule, so a config that can't fit the decode gets refused for free before any GPU time is spent.

Related: #TBD (device-placement asymmetry that makes the LTX2 failure specifically worse) — filing separately since the fixes are independent, but the LTX2 repro above is shared context for both.

--- comment by @dkackman at 2026-09-21T03:37:54Z ---
triage: escalate — this adds a new validation surface: a per-template declared VRAM ceiling over (width, height, num_frames), a new `variable_constraints`-like rule in `validate_workflow`, and the numbers would be per-GPU and per-offload-configuration (a ceiling true for the 3090 with the transformer pinned is false with group_offload, which is exactly what #266 proposes changing). A repro-only verification (345 frames refused) would pass while the whole matrix of sizes and cards stays unchecked. Needs sign-off on shape before a fix session builds it: declared table vs. measured from history (the #243 host-memory projection is the precedent for the latter), and whether it refuses or warns. Parked with owner:don. (triage by implementer agent, model opus via provider anthropic)

--- comment by @dkackman at 2026-09-21T11:58:10Z ---
Decision: declared per-template ceiling, not measured from history, and it refuses rather than warns.

**Declared, not measured:** the #243 host-memory projection precedent (extrapolate from observed history) doesn't transfer to this case's actual goal. That precedent projects a *bigger instance of a shape already run once* (32 entries from an observed 1-entry run). A VRAM ceiling needs to catch a (width, height, num_frames) combination that has *never been run before* — that's exactly #265's repro (345 frames, never tried, dies at decode after 5 minutes of denoise). A measured-from-history approach can only warn on a repeat of a failure already suffered once; it can't prevent the first one, which is the whole point of "refused for free before any GPU time is spent." So this wants a declared formula/table per template, the same way `cost` already declares curated per-device minutes (`templates/ltx2/text-to-video.json` already has `cost_drivers: ["num_frames", "width", "height"]` — this extends that existing convention with a peak-VRAM relationship instead of a wall-clock one), calibrated from real repro data points like #265's own (2.69 GiB needed for VAE decode conv3d, 557 MiB free at 345 frames on a 24 GB card).

**Refuse, not warn:** unlike the host-memory projection (soft, "might exceed 90% of RAM and thrash," explicitly a warning C-F040 pins as never becoming a refuse), a VRAM ceiling for a fixed GPU model is a deterministic OOM, not a probabilistic one — the same (width, height, num_frames) on the same card either fits or it doesn't. The cost of over-refusing a config that would narrowly have fit is small; the cost of not refusing is a 5-minute GPU run thrown away at the last step. `validate_workflow` should refuse, alongside the existing `num_frames` modulus rule.

**Depends on #266, not the other way around:** the ceiling number is a function of what's resident in VRAM at decode time, which is exactly what #266 is about changing. See my decision there — I'd sequence #266's device-placement change first, then calibrate #265's declared numbers against the resulting profile, not the current one.

Reassigning to implementer. Shape: extend `variable_constraints`/`cost_drivers` with a declared VRAM formula or table per template, checked against the device's `cost.vram_gb`, refusing like the existing `num_frames` rule.

--- comment by @dkackman at 2026-09-22T01:04:18Z ---
triage: batch with #266 — Don's decisions on both are in (approved, back with implementer). Sequenced: #266 first (switch `templates/ltx2/text-to-video` transformer from pinned cuda + `preserve_device_placement` to `offload: "model"`, verify on lem with the 345-frame repro that the transformer leaves VRAM before VAE decode and denoise timing holds), then #265's declared per-template VRAM ceiling (refuse, not warn; checked in `validate_workflow` beside the `num_frames` modulus rule, against `cost.vram_gb`) calibrated against the offloaded profile. One branch, one deploy; #265's session works both. (triage by implementer agent, model opus via provider anthropic)
