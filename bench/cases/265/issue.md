## #265: Video templates validate frame counts they cannot render: no VRAM ceiling on (width, height, num_frames)
filed by: @dkackman

Both video template families accept a frame count their own modulus rule validates clean but that OOMs partway through the run — after every expensive denoise step has already run.

**Repro shape (LTX2):** `templates/ltx2/text-to-video` declares `num_frames: {modulus: 8, remainder: 1, min_frames: 9}` with no ceiling. `num_frames: 345` (8×43+1) satisfies the rule, `validate_workflow` returns clean, the job runs all eight denoise steps (~5 minutes of GPU time), and then dies in the VAE decoder's conv3d needing 2.69 GiB with only 557 MiB free — right before the save step.

**Repro shape (H3):** the same pattern at 768p / 345 frames, except H3 dies mid-denoise rather than at decode.

**Impact:** this is the expensive failure shape — every case is a job that runs to (near) completion and throws away the compute, rather than being refused up front. The existing modulus/remainder/min_frames rule proves the template layer already has a place to encode frame-count constraints; it's just missing the one that would actually catch this.

**Ask:** a declared VRAM ceiling per (width, height, num_frames) for each video template, checked at `validate_workflow` time alongside the existing modulus rule, so a config that can't fit the decode gets refused for free before any GPU time is spent.

Related: #TBD (device-placement asymmetry that makes the LTX2 failure specifically worse) — filing separately since the fixes are independent, but the LTX2 repro above is shared context for both.
