## #198: bleed_join's reversed tail has no speech/tonal detection, only a peak>1.0 clip warning
filed by: @dkackman

**tool/endpoint:** \`dw/tasks/audio_utils.py\` \`bleed_join\`

**repro:** Call \`concat_videos\` (or anything using \`bleed_join\`) with \`audio_bleed_ms\` on a shot whose outgoing tail is speech or a tonal/musical element rather than room tone or crowd noise.

**expected:** Some detection or warning when the bled tail is a poor candidate for time-reversal - the docstring's own precondition ("crowd noise and room tone are direction-agnostic, so the reversal itself is not audible") does not hold for speech or pitched material.

**actual:** The only runtime check is \`peak > 1.0\` (clipping). Nothing checks whether the material being reversed is speech-like or tonal. \`docs/TASKS.md\` already concedes the failure mode in its own text ("half-spoken word reads as a stutter whichever direction it runs"), but nothing detects or warns about it - the caller finds out by ear.

Found while re-running an older workflow (predates several recent audio fixes) as a QA exercise; verified against current \`develop\` (\`dw/tasks/audio_utils.py:115-163\`, \`docs/TASKS.md:284\`).

--- comment by @dkackman at 2026-09-17T18:19:46Z ---
triage: batch with #197, #198, #199 — all three are the audio seam path of `concat_videos` (`dw/tasks/concat_videos.py`): #197 is the `previous_result:` chain never passing through `_fit_audio_to_frames` (`dw/tasks/video_utils.py`, today called only from `_decode_audio_video`), #198 and #199 are both `bleed_join` in `dw/tasks/audio_utils.py` (a tonal/speech warning on the reversed tail, and a gain-in-dB knob beside `audio_bleed_ms`). One branch, one deploy, one `docs/TASKS.md` update; #197's session does the work. No duplicates found (#82 covered level matching, not the seam). Note for that session: lem's server is currently down from an interrupted restart (see #196) — bring it up before the tail of this batch, not after.

— triage by the implementer agent running as model `opus` via the `anthropic` provider.

--- comment by @dkackman at 2026-09-17T18:41:49Z ---
Fixed in a0cd11a (merged to develop via 3541cde), deployed to lem and live (confirmed at commit 3541cde, `/api/health` ok).

`bleed_join` (`dw/tasks/audio_utils.py`) now checks the outgoing tail's spectral flatness (geometric-mean-over-arithmetic-mean of the FFT magnitude spectrum, numpy-only via `numpy.fft.rfft` — no new dependency) before reversing it onto the seam. Below `TONAL_FLATNESS_THRESHOLD = 0.3` the material reads as tonal/speech rather than the noise-like room tone or crowd noise a bleed is meant for, and `emit_warning` fires (`kind="bleed_tonal_material"`) so the caller sees it in the job's `warnings` list, not just in the mix — same convention as the existing `audio_no_headroom`/`audio_clipped` warnings. The pre-existing peak>1.0 clip check is left as plain `logger.warning`, unchanged — out of scope here.

Regression tests added: `tests/test_audio_utils.py::TestBleedJoin::test_tonal_material_warns` (pure sine tone fixture, low flatness, expects the warning) and `test_noise_like_material_does_not_warn` (random noise fixture, expects no warning). Suggest adding a smoke check to `regression-suite-smoke.md`: call `bleed_join` (or `concat_videos` with `audio_bleed_ms` set) on two shots where the outgoing shot's tail is speech/dialogue, and confirm the job's `warnings` list contains a `bleed_tonal_material` entry.

Model/provider: sonnet/anthropic.
