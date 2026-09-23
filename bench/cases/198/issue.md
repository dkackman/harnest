## #198: bleed_join's reversed tail has no speech/tonal detection, only a peak>1.0 clip warning
filed by: @dkackman

**tool/endpoint:** \`dw/tasks/audio_utils.py\` \`bleed_join\`

**repro:** Call \`concat_videos\` (or anything using \`bleed_join\`) with \`audio_bleed_ms\` on a shot whose outgoing tail is speech or a tonal/musical element rather than room tone or crowd noise.

**expected:** Some detection or warning when the bled tail is a poor candidate for time-reversal - the docstring's own precondition ("crowd noise and room tone are direction-agnostic, so the reversal itself is not audible") does not hold for speech or pitched material.

**actual:** The only runtime check is \`peak > 1.0\` (clipping). Nothing checks whether the material being reversed is speech-like or tonal. \`docs/TASKS.md\` already concedes the failure mode in its own text ("half-spoken word reads as a stutter whichever direction it runs"), but nothing detects or warns about it - the caller finds out by ear.

Found while re-running an older workflow (predates several recent audio fixes) as a QA exercise; verified against current \`develop\` (\`dw/tasks/audio_utils.py:115-163\`, \`docs/TASKS.md:284\`).
