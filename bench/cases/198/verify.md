**Verify result: fixed — closing as verified.** (tester agent, model `opus` via provider `anthropic`; dw 0.4.0-beta.6 on `lem` at develop `c42acea`, workspace `qa-verify-198`, all runs 2026-09-17.)

Re-ran the bounce matrix plus adjacent cases. Every join is `concat_videos` with `audio_bleed_ms` set; outgoing shot = `asset:qa-cast/ep6-cold-open.mp4` (5.175 s) re-paired via `pair_audio` (`fit: "video"`) with a `loop_audio` bed of the named audio; incoming = `asset:qa-cast/ep4-shot2-desk.mp4` (32 kHz).

| job | step | outgoing tail | target rate | tonal warning? |
|---|---|---|---|---|
| `2e012747bad9` | `join_speech_24k` | `qa-cast/hal-voice.wav` (24 kHz) | 24000 (native) | no — see below |
| `2e012747bad9` | `join_speech_auto` | same | auto → 32 kHz | no |
| `8b7081fd2940` | `join_hal_1000ms` | same, `audio_bleed_ms: 1000` | 24000 | no |
| `0845d533e435` | `join_hal_s0` | hal-voice sliced 0–1 s, looped | 24000 | **yes** — flatness 0.11, harmonicity 0.64 |
| `0845d533e435` | `join_hal_s3` | hal-voice sliced 3–4 s, looped | 24000 | **yes** — flatness 0.30, harmonicity 0.63 |
| `0845d533e435` | `join_hal2` | `uploads/cast/hal-voice.wav` (44.1 kHz) | auto → 44.1 kHz (native) | **yes** — 0.12 / 0.52 |
| `8b7081fd2940` | `join_priya_300ms` | `qa-cast/priya-voice.wav` (24 kHz) | 24000 (native) | **yes** — 0.23 / 0.77 |
| `8b7081fd2940` | `join_priya_1000ms` | same, 1000 ms | 24000 | **yes** — 0.15 / 0.62 |
| `8b7081fd2940` | `join_song_300ms` | `qa-cast/ep15-song.mp3` (44.1 kHz) | auto → 44.1 kHz (native) | **yes** — 0.14 / 0.49 |
| `2e012747bad9` | `join_room_16k` | `uploads/qa-cast/room-bed.wav` (16 kHz) | 16000 (native) | no ✓ |
| `2e012747bad9` | `join_room_44k` | same | 44100 (upsampled ×2.75) | no ✓ (was a false positive at flatness 0.08) |
| `2e012747bad9` | `join_bed11` | `qa-cast/ep11-bed.wav` (32 kHz) | auto → 32 kHz (native) | yes — 0.21 / 0.22 |

**Confirmed:** native-rate speech is now caught (priya at 24 kHz, hal at 24 kHz and 44.1 kHz), music at native rate is caught, and the upsampling false positive on room tone is gone — the exact two gaps from the bounce. The `join_speech_24k` repro from my bounce comment *still* produces no warning, but that turned out to be the fixture, not the detector: the 300 ms tail of that shot lands at 4.875–5.175 s of `hal-voice.wav`, which is an unvoiced/breath stretch (per `get_gallery_metadata` envelope: −23 dBFS RMS there vs −17 dBFS in the first second). Slicing the same file so the tail lands on 0–1 s or 3–4 s fires the warning with harmonicity 0.63–0.64. A 300 ms unvoiced tail reversed onto a seam is the material a bleed handles fine, so not warning there is arguably correct.

**Observation, not a blocker:** `ep11-bed.wav` at its native 32 kHz still flags on flatness alone (0.21 < 0.3; harmonicity 0.22, i.e. not periodic). Per your note this is the case where the threshold should be tuned against the actual asset rather than blind; I can't tell from here whether that bed is genuinely hum-like, so I'm leaving it as a data point rather than a new issue.

Adding regression case C-F033 to `regression-suite-complete.md` (native-rate speech warns; native room tone doesn't; upsampled room tone doesn't). Workspace `qa-verify-198` deleted after this comment.
