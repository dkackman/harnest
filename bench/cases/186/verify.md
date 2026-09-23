**Verify: fixed** — the gate is now a pre-flight signal. Tested over MCP against `lem` (dw 0.4.0-beta.6), as model **opus** via provider **anthropic**.

**What I ran** (all `validate_workflow`, inline single-`StableDiffusionPipeline`-step workflows, no cache hits):

1. The fixture from the previous round, `pyannote/speaker-diarization-3.1` (this box's token confirmed refused last round via a live `download_model` 403):
   - `downloads_required[0]` → `{"repo": "pyannote/speaker-diarization-3.1", "gb": 0.0, "gated": "auto", "access_blocked": true}`
   - `warnings` → `"pyannote/speaker-diarization-3.1 is gated and not accessible with this box's Hugging Face token - accept its license at https://huggingface.co/pyannote/speaker-diarization-3.1 before running this workflow"`

   Last round this same call said `access_blocked: false` with no warning. Matches `expected:`.

2. Adjacent, one 4-step workflow, to rule out false positives:

   | repo | `gated` | `access_blocked` |
   |---|---|---|
   | stabilityai/stable-diffusion-3.5-large (gated, token accepted) | `"auto"` | `false` |
   | meta-llama/Llama-3.2-1B (gated, token accepted) | `"manual"` | `false` |
   | stabilityai/sd-turbo (not gated) | `false` | `false` |
   | tester-nonexistent-org/does-not-exist-186 | `null` | `null` |

   No gate warning in that response — correct, nothing is blocked.

3. Mixed 2-step workflow (blocked pyannote + not-gated sd-turbo, with `seed` set so the only warning is the gate): exactly one warning line, naming pyannote only; sd-turbo's entry `false`/`false`. The warning is per blocked entry, not all-or-nothing.

Adding `status:verified`, closing as completed. Adding the proposed regression case to `regression-suite-smoke.md` (S-F044) with `pyannote/speaker-diarization-3.1` as the fixture, noting that the case only holds while this box's token remains un-granted on that repo.

The `databricks/dbrx-instruct` `RepositoryNotFoundError` edge case you flagged is genuinely a different failure mode (404 rather than a hidden gate) and `null`/`null` is an honest "unknown" for it; I'm not filing it — it'd need a caller to care about that particular repo first.
