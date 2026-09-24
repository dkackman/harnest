# Regression suite — dw MCP server — security level

Checks that the server's boundaries hold against a hostile-but-authorized
MCP consumer: nothing an agent sends through the API should read, write,
delete, fetch, or *execute* anything the server didn't mean to expose. Not
about workspaces — a workspace is a namespace, not a security boundary, and
this is a single-user system — but about escaping the server and its API
altogether. Every case here is run with the server's **default** security
posture (`--trust-workflows` off, no `DW_TRUST_WORKFLOWS`), because that's
the posture whose guarantees actually matter; a case that only holds with a
flag flipped isn't a guarantee. SE-F001 checks that posture and gates
everything else: run it first in every session, including each slice of a
chunked run, and stop if it says the server is trusted. Opt-in only:
`./run-regression.sh security` (or `all`). Sibling suites:
[`regression-suite-smoke.md`](regression-suite-smoke.md),
[`regression-suite-complete.md`](regression-suite-complete.md),
[`regression-suite-model-specific.md`](regression-suite-model-specific.md).

**What belongs here** (vs. the functional suites): a case whose *failure*
means an agent got past a boundary — code ran that shouldn't have, a file
outside the server's own roots was read/written/deleted/enumerated, a
request left the box for a host the workflow chose, or a secret showed up
in a response. A tool merely misbehaving (wrong result, crash, slow) is a
functional case and belongs in `smoke`/`complete`, even if the input was
weird. Cases here are deliberately hostile inputs; they are never destructive
by design — each probe targets something that would be harmless even if the
boundary failed (a read of a stock system file, a write into `/tmp`, a
loopback fetch), never a real payload.

**How to read a result.** Most cases have two ways to fail, and the second
is the subtle one: (1) the hostile input *worked*; (2) the input was
rejected, but the error shows it was rejected *too late* — after an import
was attempted, a file was opened, or a request went out. A
`ModuleNotFoundError`, a `FileNotFoundError` naming the probe path, or an
HTTP status from the probe URL are all failures even though the job didn't
succeed. The `expected:` lines say what a refusal must look like; anything
else is a finding. Never work around a refusal to "see what happens" — the
refusal *is* the pass.

Workspace: `regression-security`. Case IDs use the `SE-` prefix (`SE-F001`,
`SE-P001`, ...) so they never collide with `S-`/`C-`/`M-` IDs — the
regression agent's duplicate-issue search is keyed on the full prefixed ID.
Issues filed from this file carry the `security` label in addition to
`regression`. Full run mechanics (fixtures vs. outputs, cleanup, the final
sweep) live in `agents/regression/`, not here.

Maintained by the regression agent, run via `run-regression.sh`, and grown
by the implementer/tester too (see "Adding a case" below). Each case is
intent + expected result, not a pinned tool/param name — confirm the exact
call shape against the live tool schema each run, since the server evolves.
This file only ever grows with new cases and fixtures; it holds the durable
test, never a log of runs. A case that passes gets no edit — status for a
failure lives on the GitHub Issue it produced, and a measurement — a `-P`
case's timing, or anything a case's `metrics:` line names — lives in
`regression-perf/<case>.jsonl` (see `regression-perf/README.md`); neither is
a note appended here. No agent may delete, weaken, or rewrite
an existing case, including one it thinks has become too expensive, too
noisy, or no longer meaningful — see "Removing a case" below. In
particular, a probe with no documented limit to test against (no
`maxLength`, no cap in the schema) is a gap to file, not a reason to retire
the case.

## Adding a case

The implementer and the tester both grow these suites, not just the
regression agent. A case belongs here if its failure is a boundary escape
(see "What belongs here" above); otherwise pick the functional suite per
`regression-suite-smoke.md`'s "Where a case belongs". Use the existing case
format (intent + `expected:` + `cleanup:`, plus `metrics:` when a number
the case yields — a size, a count — matters as a trend and should be logged
in `regression-perf/`; seed that file with the reading you just took, and do
the same for a new `-P` case's timing), the next unused
`SE-Fnnn`/`SE-Pnnn` ID, and a `source:` line naming who added it and why
(e.g. `source: implementer, fix for #42` or `source: tester, found while
running agents/tester/standing-task.md`). Make the probe harmless even if the boundary is
broken — target `/tmp`, loopback, or a stock system file, never anything
that would damage the box if the check fails. State both failure modes:
what "it worked" looks like *and* what "refused too late" looks like. No
separate approval step for adding one.

## Removing a case

No agent may remove or rewrite an existing case on its own judgment. If a
case looks too expensive, too flaky against things outside the server's
control, or no longer meaningful, or its `expected:` predates a verified
fix, propose dropping or changing it with a GitHub Issue on the harness
repo, `dkackman/harnest` (where this file lives, not the ticket repo),
naming the case id, the reasoning and the evidence (the issue that changed
the behavior), labeled `suite` + `status:needs-approval`. Every agent files
this directly, the implementer included (it has no suite files checked out
to edit anyway), and so does the curator's audit (`run-curate.sh`). Leave
the case exactly as written until it's ruled on.

A curator review session (`run-loop.sh`) rules on each request:
- it **applies** what the record settles: a stale reference, or an
  expectation that a verified or `breaking-change` issue changed on
  purpose;
- it **denies** an edit that would make a failing case pass with no such
  record;
- it **escalates** judgment calls to Don (`owner:don`): cost against
  coverage, moves and merges, retirements from an audit, the security
  suite beyond a stale reference, and anything touching more than 3 cases.

The one edit made without a request is the tester removing a feature
stage's `pending: #NN` line when that stage verifies.

## Not covered here

Things a consumer-only agent can't exercise, listed so nobody assumes they
are. These belong in the `diffusers-workflow` repo's own pytest suite (the
implementer's territory), not in a live-server run:

- Auth itself: a wrong/missing bearer token → 401, the refusal to start
  `--mcp` on a non-loopback bind without a token, Origin/Host rejection,
  and the token-less `/outputs`/`/inputs` static routes. The agent's own
  connection is fixed by the driver; it can't vary its token or headers.
- Behavior with `--trust-workflows` **on** (everything in "Code execution
  gate" is expected to pass through in that mode — by design).
- Symlink escapes (planting a symlink inside a workspace needs box access).
- Decoder bombs (a crafted giant-pixel PNG needs a file the agent can't
  author; there is no pixel-count clamp on `get_output_image`/gallery
  thumbnails as of 2026-09-13 — noted here so it isn't forgotten).
- Link-local/RFC1918 SSRF targets other than loopback: a fetch to
  `169.254.169.254` on a LAN with no such host hangs until the 300 s
  request timeout, which would stall the run; loopback (SE-F018) proves
  the same policy gap without the wait. (2026-09-13 earlier: SE-F018 failed —
  loopback *was* fetched — so for one run this exclusion rested on nothing but
  the stall. **2026-09-13 later: #115 fixed and verified, SE-F018 passes, and
  the refusal message names link-local explicitly alongside loopback and
  private ranges. The original reasoning is restored** — this stays excluded
  because the probe would stall the run, and the boundary is again believed to
  hold on SE-F018's evidence.)
- A 25,000-character variable value (SE-F022's withdrawn long-string probe) as a single literal:
  the agent cannot emit one inside a tool call without blowing its output
  budget. The schema has no `maxLength` on argument values at any level, so
  the question is answered statically instead; see SE-F022.

## Fixtures

Durable contents of `regression-security` that persist across runs. Add a
line when a case starts relying on one; remove the line (and the fixture)
when nothing uses it anymore.

- (none yet)

Repro artifacts currently held in `regression-security` for open issues (not
fixtures — delete when the issue closes):

- (none — the six held for #114 and #116 were deleted 2026-09-13 when those
  issues were verified and closed. `list_gallery(workspace="regression-security")`
  should report `total: 0`.)

(none outside the workspaces — the two SE-F016 probe files from 2026-09-13
were removed by the implementer in #113.)

## Code execution gate (default: untrusted)

The server resolves class/module/constant names from workflow JSON by
import. Untrusted, every dotted name outside the diffusers ecosystem
(`diffusers`, `torch`, `transformers`, `accelerate`, `peft`, `sdnq`, ... —
whatever the live server's error message enumerates) must be refused, and
so must the two from_pretrained arguments that download and run code from
the Hub. A refusal is only a pass if it comes from the trust gate, *before*
any import: the message should say the workflow is untrusted / outside the
ecosystem. `ModuleNotFoundError`, `ImportError`, `AttributeError` on the
probe name, or any trace of the probe having executed, is a fail.

### SE-F001 — server states its security posture — **RUN THIS FIRST**
This is the precondition for the whole file, not one case among many. Every
other case here is defined to run on the default untrusted posture, and every
refusal they check for names `--trust-workflows` as the way to turn it off. A
pass on a trusted server therefore means nothing.
`get_server_info`.
expected: the response carries `auth_required` (true on the regression target —
it runs with a token) *and* `trust_workflows`. **If `trust_workflows` is
`true`, stop: do not run the rest of this file and do not report passes.** If
the field is absent, that is the finding — file it as "server doesn't expose
trust posture; security suite can't verify it's running on defaults", run the
rest anyway, and state that assumption in every issue this run files.
Reporting the field is not itself a disclosure: the refusal messages already
name the flag.
cleanup: none (read-only).
source: harness, initial security suite 2026-09-13.

### SE-F002 — dotted `*_type` outside the ecosystem is refused
`validate_workflow` (then `run_workflow` if validation lets it through)
with an inline workflow whose scheduler or component type is a dotted name
outside the ecosystem — on an otherwise minimal, valid workflow (copy the
shape of a bundled template, e.g. `templates/text-to-image`). The two
places these live, confirmed against the live schema 2026-09-13:
`steps[].pipeline.configuration.component_type` (e.g. `"os.system"`) and
`steps[].pipeline.scheduler.configuration.scheduler_type` (e.g.
`"subprocess.Popen"`). Note `scheduler_type` is *not* a member of
`pipeline.configuration` — putting it there gets "Additional properties are
not allowed", which is a schema error, not the trust gate, and proves
nothing.
Expect `validate_workflow` to return `valid: true` for all of these —
dotted names are resolved at load, not at validation — so the run is the
real test, not an escalation.
expected: refused with the trust-gate message ("outside the ecosystem",
"--trust-workflows", or the live equivalent). Fail if validation passes
*and* the job fails only at load with an import/attribute error on the
probe name (it was imported), or if the job runs.
cleanup: none if refused; if a job was enqueued, `cancel_job` and delete
anything it produced.
source: harness, initial security suite 2026-09-13.

### SE-F003 — `pre_load_modules` outside the ecosystem is refused
Inline workflow with `pre_load_modules: ["subprocess"]` (harmless if
imported — it's already loaded in any Python process — but out of
ecosystem), and a second attempt with a module that does not exist,
`["dw_security_probe_nonexistent"]`.
expected: both refused with the trust-gate message. The nonexistent one is
the diagnostic: if it comes back as `ModuleNotFoundError`, the gate ran
*after* the import attempt (or not at all) — fail.
`pre_load_modules` sits at `steps[].pipeline.configuration.pre_load_modules`.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.

### SE-F004 — `constant:` reference outside the ecosystem is refused
A workflow argument valued `constant:os.environ` (would leak the server's
environment, including any HF token, into the job) and `constant:sys.argv`.
expected: refused with the trust-gate message before any import. Fail if
the job runs, if the error text contains anything that looks like an
environment variable value, or if the refusal is "constant is not
callable/not found" (that means it was resolved first).
A `constant:` goes in a pipeline `arguments` entry; `cross_attention_kwargs`
is a convenient carrier on SD1.5.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.

### SE-F005 — `trust_remote_code` is refused untrusted
Inline workflow whose pipeline or a component's `from_pretrained_arguments`
sets `trust_remote_code: true` (any small model; it should never get as far
as loading).
expected: refused with the trust-gate message naming `trust_remote_code`.
Fail if the job starts loading the model (a download or a load step in
`get_job_events`) before failing, or runs.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.

### SE-F006 — `custom_pipeline` is refused untrusted
As SE-F005 with `custom_pipeline: "lpw_stable_diffusion"` (a real community
pipeline name — a refusal must not depend on the name being bogus).
expected: refused with the trust-gate message naming `custom_pipeline`;
same fail conditions as SE-F005.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.

### SE-F007 — dotted `config_type`/`dtype` outside the ecosystem is refused
Inline workflow using a quantization/cache config block whose
`config_type` is `"os.path.join"`, and separately a component `dtype` of
`"builtins.eval"`.
expected: both refused with the trust-gate message. Same fail conditions as
SE-F002.
Components are named keys directly on the pipeline object, not entries under
a `components` property — `config_type` lives at
`steps[].pipeline.<component name>.quantization_config.configuration.
config_type` (`quantization_config` also requires an `arguments` property,
even if empty). Putting it under a `components` list gets "unknown property
'components'", which is a schema error, not the trust gate, and proves
nothing (the same trap SE-F002 notes for `scheduler_type` placement). For
the dtype probe, `torch_dtype: "builtins.eval"` in
`from_pretrained_arguments` is the simplest carrier.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.

### SE-F008 — in-ecosystem dotted names still work (negative control)
Inline workflow with `scheduler_type: "diffusers.EulerDiscreteScheduler"`
(fully dotted, in ecosystem) — `validate_workflow` only, no run.
expected: validation passes (or fails for an unrelated reason clearly not
the trust gate). This proves SE-F002–F007 are refusals from a working
allowlist, not a gate that's stuck refusing everything.
Caveat: `validate_workflow` returns `valid: true` for the *hostile* dotted
names too (the gate fires at load, not at validation), so this control only
proves the in-ecosystem name isn't rejected — the allowlist itself is
demonstrated by F002–F007 refusing at run time, not by this passing.
cleanup: none (validation only).
source: harness, initial security suite 2026-09-13.

### SE-F009 — `remote_text_encoder.url` cannot point off-policy
The `remote_text_encoder` block makes the server POST to a URL the
workflow chooses, with its Hub token attached, and deserialize the reply.
Five probes, all `validate_workflow` only — every one must be refused there,
free, before any load (`run_workflow` only if validation lets one through,
which is itself the finding): (a) `url: "file:///etc/hostname"` → refused on
the **scheme** rule (an untrusted workflow may only reach an `https`
endpoint, because the request carries this machine's HuggingFace token);
(b) `url: "http://127.0.0.1:8765/api/server"` → refused on the same scheme
rule, never reaching the host rule; (c) `url: "https://127.0.0.1:8765/encode"`
→ refused on the **host** rule ("resolves to 127.0.0.1, an address inside
this deployment (loopback, link-local or private)"); (d) **hostname, not
literal** — `https://localhost:8765/encode` → refused, "localhost resolves to
127.0.0.1". This is the one that proves the check is on the *resolved*
address; a rule that only pattern-matched `127.0.0.1` would pass every other
probe here and fail this one; (e) **control** — `https://huggingface.co/encode`
→ `valid: true`, plan returned. Without it the case cannot tell a policy from
the feature having been disabled outright.
expected: (a)–(d) `valid: false` at `steps[0].pipeline.remote_text_encoder.url`
with the rule named; (e) valid. Fail — and file as high severity — if any
error reports an HTTP status, a content type, "did not return embeddings", or
`requests`' own "No connection adapters" from the probe URL: that means the
URL reached the HTTP client, the request went out carrying the token, and
the reply was handed to the deserializer (#112 was exactly this, and it
fired only after the pipeline had fully loaded). Also fail if `file://` is
accepted at all.
**Never probe a real external host.** The original form of (c) — any
`http://` URL to a host that isn't a known inference endpoint — is retired
permanently: while the gate is broken the request exfiltrates a live
credential to a third party, and once it works the loopback forms prove the
same thing. The credential-scoping half of #112 (token attached only for
`huggingface.co` / `huggingface.cloud` / `hf.space`) is **not observable
from a consumer** and is deliberately not probed — observing it is the
exfiltration this case exists to prevent; it belongs in the dw repo's pytest
suite.
Shape note: `remote_text_encoder` sits on a `pipeline` object, which requires
`configuration` (with `component_type`), `from_pretrained_arguments` and
`arguments` — a draft missing those fails schema validation before the URL
is ever looked at, which reads like a pass and is not one. Confirm the error
path is the `.url` one above.
cleanup: none if refused; otherwise `cancel_job` and delete outputs.
source: harness, initial security suite 2026-09-13.

## Filesystem containment

Every name a tool takes that becomes a path on the server must resolve
inside the root that tool serves (outputs, assets, prompts, workflows,
workspaces). A traversal or absolute-path probe must come back as a clean
validation error ("invalid name", "not allowed", "outside ...") — never as
`FileNotFoundError`/"no such file" naming the probe path (the path was
tried), and never with content.

### SE-F010 — output names can't traverse
Against this workspace, call each of `get_output_image`, `get_output_text`,
`get_gallery_metadata`, `delete_output`, `keep_output` with names
`../../../../etc/hostname`, `/etc/hostname`, `..%2f..%2fetc%2fhostname`,
`~/.bashrc`, and `outputs/../../etc/hostname`.
expected: every call is a clean validation error; no bytes/text returned;
no delete reported as succeeding. Fail on any content, on a "file not
found" that echoes a normalized version of the probe, or on `keep_output`
creating an asset with a traversed name (check `list_assets` after).
Two refusal styles are both acceptable: `get_output_image`/`get_output_text`
answer a bare "Not Found" (no path echoed), while `get_gallery_metadata`,
`delete_output` and `keep_output` give explicit containment errors ("Path
contains dangerous pattern matching \.\.", "Path outside allowed
directory: …"). The bare form discloses less but also proves less; for
certainty there, run the same probe against a name that *does* exist and
confirm it still returns nothing.
cleanup: none; if `keep_output` did create something, delete it and name it
in the issue.
source: harness, initial security suite 2026-09-13.

### SE-F011 — workflow and prompt names can't traverse or go absolute
`get_workflow`, `validate_workflow` (by name), `delete_workflow`,
`save_workflow`, `get_prompt`, `save_prompt`, `delete_prompt` with names
`../../../etc/hostname`, `/etc/hostname`, and (for `get_workflow`) the
absolute path of a real file outside every workflow source — use the
server's own `directories.workflows` path from `get_server_info` and go one
level up to its parent, e.g. `<parent>/pyproject.toml`.
expected: all clean validation errors; `save_*` creates nothing (check
`list_workflows`/`list_prompts` after); `get_workflow` on the
outside-source absolute path is refused as outside every source, not
served. Fail on any content or any created file.
**For the `save_*` probes, do not use `../../../etc/hostname`** — if
containment fails that clobbers the box's hostname file, which breaks this
suite's own rule that a probe stay harmless when the boundary does not
hold. Use `../../../../tmp/dw-se-f011-probe` and `/tmp/dw-se-f011-abs`
instead. The read-only probes (`get_*`, `delete_*`) can keep the `/etc`
targets: they create nothing.
cleanup: delete anything a `save_*` created, and name it in the issue.
source: harness, initial security suite 2026-09-13.

### SE-F012 — asset names can't traverse
Generate one small output (cheapest image template, minimal steps), then
`keep_output` it with `asset_name` values `../escaped.png`,
`/tmp/escaped.png`, `~/escaped.png`, and `a/b/c/d/e/escaped.png` (deeper
than the documented folder limit). Then `delete_asset` with `../x.png` and
`/etc/hostname`.
expected: every call is a clean validation error; `list_assets` afterwards
shows nothing new. Fail if any asset appears, or a delete reports success.
**The probe extension must match the generated output's extension.** The
kind check runs before the name check, so `../escaped.png` against a `.jpg`
output is rejected with "asset_name … does not match the kept file's kind
(.jpg)" — which says nothing about containment and silently passes the case
for the wrong reason. Generate a `.jpg` and probe with `.jpg` names (or
match whatever the cheapest template emits).
cleanup: delete the generated output; delete any stray asset and name it
in the issue.
source: harness, initial security suite 2026-09-13.

### SE-F013 — workspace names can't traverse, go absolute, or be hidden
`create_workspace` with `../escaped`, `/tmp/escaped`, `.hidden`,
`regression-security/../escaped`, and an empty string. `use_workspace` with
`../default` and `/`.
expected: every call refused cleanly; `list_workspaces` unchanged; the
session's current workspace unchanged. Fail if any workspace is created
(and if so, do **not** `delete_workspace` it — it may be pointing outside
the workspace root; name it in the issue and leave it).
cleanup: none.
source: harness, initial security suite 2026-09-13.

### SE-F014 — media arguments can't name arbitrary server files
Inline image-to-image (or any workflow with an `image`/`audio` input) whose
input is a raw absolute path on the server rather than an `asset:`/
`output:` reference: (a) a path that very likely exists on a Linux box,
with an allowed extension, outside every dw root — try
`/usr/share/pixmaps/debian-logo.png` and
`/usr/share/icons/hicolor/48x48/apps/python3.png` (the agent can't list
the server's disk, so try both); (b) a path that certainly does not exist:
`/nonexistent-dw-probe/x.png`.
expected: (a) and (b) refused *identically* at `validate_workflow`, as
outside the allowed roots, the messages differing only in the path
("Refusing to read 'image' at '<path>': it resolves outside every directory
this workflow may read (…). Put the file in the asset library and name it
with an 'asset:' reference") — the refusal must not depend on whether the
file exists. Fail if (a) runs (the file was read) or if (b) comes back as
"file not found" while (a) proceeds further (existence was checked, i.e.
the path was accepted; #114 was this, and (a) produced a 48x48 output
decoded from the server's own file). The same applies to a `from_file`
argument.
Two further probes, both cheap:
- **A task argument, not only a pipeline one.** `get_image_size` (an image
  processor — loads no model, ~3 s, costs nothing) with the same absolute
  path → the identical refusal at `steps[0].task.arguments.image`. This
  checks the policy sits in the loader rather than on the pipeline path,
  and it is far cheaper than the img2img form, which wants a 12 GB
  `stabilityai/sd-turbo` download — prefer it as the primary probe.
- **The relative spelling**, scored separately:
  `image: "../../../../../usr/share/pixmaps/debian-logo.png"` → refused at
  validation the same way (#124: containment always held, but this form
  once validated `valid: true` and only failed at run time with
  `PathTraversalError`; refused-too-late is a failure by this file's rule).
The refusal message enumerates five absolute server paths. Judged
acceptable, not a finding: a refusal a caller can act on has to say where
it may read, and `get_server_info().directories` already reports four.
cleanup: `cancel_job` and delete outputs if anything ran.
source: harness, initial security suite 2026-09-13.

### SE-F015 — `gather_images`/`gather_videos` glob can't leave the workspace
Inline task-only workflow (no model) whose `gather_images` step has
`glob: "/usr/share/pixmaps/*.png"` — bounded, cheap, and outside every dw
root; then `glob: "../../**/*.png"`.
expected: both refused at validation as outside the allowed roots. Fail if
the job runs and its events/logs report "Found N images" for N > 0, or if
it runs at all — an empty glob result is still an accepted glob. Never use
an unbounded pattern like `/**/*.png` here; it would walk the whole disk.
Shape confirmed 2026-09-13: a task step, `{"command": "gather_images",
"arguments": {"glob": "…"}}`.
expected message shape: the absolute form is refused as expanding *under*
`/usr/share/pixmaps`, outside every readable directory — it reports the
expansion root rather than the pattern, which is the right thing to check,
since the pattern's literal prefix decides where it walks. Probe the
relative spelling `../../../../../usr/share/pixmaps/*.png` as well: refused
on "contains a '..' path segment".
The `../../**/*.png` probe stays **permanently unrun**: it is covered by the
`..` rule without being executed, and relative to the workflows directory it
resolves to the whole workspace root, so if containment ever broke again it
would gather hundreds of files across every workspace (including the
tester's `qa-*`) and leave that many outputs to clean up, for no information
the bounded probes haven't already given. Never use an unbounded pattern
here.
cleanup: `cancel_job` and delete outputs if anything ran.
source: harness, initial security suite 2026-09-13.

### SE-F016 — `download_output` can't write outside the server's roots
This tool "downloads to local disk". When the MCP server is mounted inside
`dw.serve` (as it is on the regression target), *local* means the server's
own filesystem. Generate one small output, then `download_output` it with
`destination` `/tmp/dw-se-f016-probe.png`, `~/dw-se-f016-probe.png`, and
`/tmp/../tmp/dw-se-f016-probe2.png`.
expected: refused — either the tool declines an absolute/home destination
over HTTP transport, or it confines the destination to the workspace. Fail
if any call reports a file written (the tool returns the path it wrote):
that's an arbitrary-location write on the box by name. These probes land in
`/tmp` and are harmless, but the agent cannot remove them — say so in the
issue.
Expected refusal shape (post-#113): "Refusing to write /tmp/… - this MCP
endpoint is served by dw.serve, so the file would land on the server, where
a destination is confined to the workspace (…). Pass a relative destination,
or …". For the `~` probe the message must show the `~` **already resolved**
to the home directory — expanded *before* the containment test, not after,
which is what let it through originally. The `..` probe is refused on the
`..` rule.
A legal **relative** destination is deliberately **not** probed: the only
way to test it is to write a file into the workspace on `lem` that a
consumer-only agent has no tool to remove. That leg belongs in the dw
repo's pytest suite (see "Not covered here"). Every probe here is a refusal,
which is what keeps the case clean to re-run.
Do **not** extend this case to `overwrite=true`: absolute destination plus
overwrite is an arbitrary file overwrite as the server user, which cannot be
made harmless. Note the exposure in the issue instead.
cleanup: delete the generated output.
source: harness, initial security suite 2026-09-13.

## Network egress

The server fetches media from URLs a workflow names. Scheme policy must
block anything that isn't `http`/`https`, and host policy must stop the
server being used as a proxy into its own loopback/LAN.

### SE-F017 — non-http schemes are refused
Inline workflow with an `image` (and separately `from_file`) input of
`file:///etc/hostname`, `ftp://127.0.0.1/x.png`, and
`data:image/png;base64,iVBORw0KGgo=`.
expected: all refused at validation as a disallowed scheme (or, for the
`data:` URL, as not a path/URL at all). Fail if any runs or if the error
indicates the target was opened/fetched.
Read the mechanism before trusting a pass. As of 2026-09-13 (0.4.0-beta.3)
these validate `valid: true` and fail at run time as *contained relative
paths* — "Path does not exist:
…/regression-security/workflows/file:/etc/hostname" — because an
unrecognised scheme is simply treated as a filename and joined under the
workflows directory. Nothing escaped, but that is safe by accident, not by
policy: there is no scheme allowlist on media arguments (contrast
`remote_text_encoder.url`, SE-F009, which has one since #112), so this case
can start failing the moment the media resolver learns a new scheme. Report
that shape as a pass with the mechanism named, so a later run can tell a
policy appearing from the accident continuing.
cleanup: `cancel_job` and delete outputs if anything ran.
source: harness, initial security suite 2026-09-13.

### SE-F018 — loopback URLs are refused (SSRF)
Inline workflow with an `image` input of `http://127.0.0.1:8765/api/server`
and `http://localhost:8765/api/server` — the server itself, so the probe is
harmless and answers instantly.
expected: refused at validation by host policy (loopback / private ranges
not allowed as media sources). Fail if the error is a decode error
("cannot identify image file", "not an image", a JSON body in the message)
or an HTTP status from the probe URL — that means the server fetched from
its own loopback on the workflow's behalf (#115: the 401 JSON body was
wrapped in `BytesIO` and handed to PIL, and only its not being an image
stopped the job). The passing shape is `valid: false` at
`steps[0].pipeline.arguments.image`, "Refusing to fetch 'image' from '…':
127.0.0.1 resolves to 127.0.0.1, an address inside this deployment
(loopback, link-local or private)" — refused at validation, by host policy,
naming the *resolved* address. It is the same policy object that answers for
`remote_text_encoder.url` (SE-F009), where the hostname form is also
checked. A pass here is what lets the `169.254.169.254` case stay in "Not
covered here".
cleanup: `cancel_job` and delete outputs if anything ran.
source: harness, initial security suite 2026-09-13.

### SE-F019 — model identifiers are Hub repo ids, not paths or URLs
`download_model` (with `acknowledged_cost` true — the probe must reach the
validator, and an invalid id never downloads) with `repo_id` values
`../../etc`, `/etc/passwd`, `http://127.0.0.1:8765/`, and
`org/name/../../x`. Then the same shapes as `model_name`/`repo_id` inside
an inline workflow, via `validate_workflow`.
Add `https://evil.example.com/model` to the workflow-side shapes — it is
validate-only, so no request is made.
expected: every one refused as an invalid repo id ("Repo id must be in the
form 'repo_name' or 'namespace/repo_name'"), with no download started
(`list_downloads` shows nothing new), and `download_model` and
`validate_workflow` refusing in the same words — dw applies its own check to
workflows rather than leaving containment to diffusers' parsing (#117: the
path shapes once validated clean and were caught only by diffusers at run
time, which would have loaded a real model directory by absolute path).
Fail if a download entry appears, or if a workflow validation accepts a
path- or URL-shaped model id.
Put the probe where the argument really lives: `model_name` is under
`from_pretrained_arguments`, not on the `pipeline` object. A `model_name`
written at pipeline level is **silently ignored** (#123), so a probe placed
there proves nothing and reads as a false pass.
cleanup: `cancel_download` anything that appeared and name it in the issue.
source: harness, initial security suite 2026-09-13.

## Secrets and disclosure

### SE-F020 — no secret ever appears in a response
`get_server_info`, `get_health`, `get_memory`, `get_diffusers_state`, and
the `get_job` / `get_job_events` of a deliberately failed job (SE-F005's
refusal is fine to reuse, or a job with a bogus model name).
expected: no response contains a bearer token, an HF token (`hf_` followed
by ≥20 alphanumerics), an `Authorization` header value, or an environment
dump. `auth_required` may be reported as a boolean; the token value never
is. Tracebacks in a failed job's events may contain server file paths — not a
failure on a single-user box, and not worth an issue on their own.
cleanup: delete the failed job's outputs if any.
source: harness, initial security suite 2026-09-13.

### SE-F030 — an unknown gallery name is refused without echoing a server path
The gallery lookup shared by `get_gallery_metadata` (and the thumbnail /
download / delete routes behind it) used to put the server's resolved absolute
filesystem path in its 404 body, straight from the path validator's exception
text (#247). The refusal must name what the caller sent, not where the server
looked. Harmless probe: the names below exist nowhere.
expected: `get_gallery_metadata(name="does-not-exist/0000/nope.png")` → an error
whose text contains `does-not-exist/0000/nope.png` and **no** absolute path (no
segment starting with `/home/`, `/var/`, `/srv/`, `/mnt/`, or the workspace root
`get_server_info` reports); the 0.4.x wording is `Unknown file:
does-not-exist/0000/nope.png`. Same with `name="../../etc/passwd"` → refused, the
error echoes `../../etc/passwd` at most, and never a resolved `/etc/passwd` or a
workspace-root-prefixed path. A positive control that a *real* `list_gallery`
`name` still resolves is S-F119's job (smoke), not this case's.
"It worked" looks like the error (or any response) carrying `/home/…` or the
workspace's `outputs` directory. "Refused too late" does not apply — this is a
read-only lookup; any leak is the failure.
cleanup: none (read-only).
source: tester, verified in #247 on 2026-09-19 over MCP as model `opus` via
provider `anthropic` — both names returned `Unknown file: <name as sent>` with
no server path.

## Destructive scope and limits

Deletes must stay inside what the caller owns, and documented caps must be
enforced *before* work is enqueued — a cap that only bites after the fan-out
happened is a flood, not a limit.

### SE-F021 — the default workspace can't be deleted, nor a read-only asset
`delete_workspace("default", acknowledged_cost=true)`; `delete_workspace`
with a name that doesn't exist; `delete_asset` on a shared/bundled asset
(pick one from `list_assets` that isn't in this workspace's own library —
an example/common asset); `delete_workflow("templates/text-to-image")`.
expected: every call refused (the default workspace and read-only sources
answer with a permission-style error, the nonexistent name with not-found);
`list_workspaces`, `list_assets`, `list_workflows` unchanged afterwards.
Fail on any successful delete. Never call `delete_workspace` on any
regression or `qa-` workspace here.
**The `delete_asset` probe needs a genuinely read-only asset.** Run it only
against one whose `list_assets` origin is a read-only examples source (e.g.
`/home/don/diffusers-workflow/assets`). Do **not** pick an `origin: common`
asset: the shared library is writable and currently holds the tester's
`qa-cast/*` fixtures, so if the boundary failed the probe would destroy
another agent's work — not harmless. Skip the probe and say so when no
read-only asset is present, as on 2026-09-13.
cleanup: none.
source: harness, initial security suite 2026-09-13.

### SE-F022 — documented input caps refuse at validation, not after
(a) `validate_workflow` with a `for_each` of one more entry than the
documented maximum (`get_schema` section `steps` carries it as
`for_each.maxItems`; 32 as of 2026-09-13), using the cheapest workflow
shape; (b) a `run_workflow` of (a) if validation let it through.
expected: (a) refused at validation, at path `steps[N].for_each`; (b) never
reached. Fail if (a) validates and `run_workflow` enqueues per-entry work
before failing — check `list_jobs` for a burst. The message says only "is
too long" without stating the cap — a usability wart, not a failure.
Long-string probe **withdrawn** (was probe (b) until 2026-09-13): the
schema has no `maxLength` on argument values at any level, so there is no
documented cap for a probe to test *against*. A long value is simply
accepted, which makes it a resource-exhaustion question, not a boundary
escape — and this file's own "What belongs here" puts that in
`smoke`/`complete`, not here. If a cap is ever introduced, reinstate the
probe against the documented number.
cleanup: `cancel_job` anything enqueued; delete outputs.
source: harness, initial security suite 2026-09-13.

### SE-F023 — a sub-workflow `path` can't escape the workflow sources
The schema says of `steps[].workflow.path`: "A path outside every source is
refused." Probe it. `validate_workflow` with a step whose `workflow.path`
is `../../../etc/hostname`, `/etc/hostname`, and the absolute path of a
real file outside every workflow source (take `directories.workflows` from
`get_server_info`, go up to its parent, e.g. `<parent>/pyproject.toml`).
Also `builtin:../../x.json`, since `builtin:` is a second resolution root.
expected: each refused at validation as outside every source, at path
`steps[0].workflow.path`, with the message listing where it looked — and
never any file content, nor a parse error that shows the target was read
(a YAML/JSON syntax error naming the probe file means it was opened).
Fail if a composition is planned, or if `/etc/hostname` produces a "not
valid JSON"-style error rather than an out-of-source refusal.
cleanup: none (validation only).
source: regression agent (opus/anthropic), gap found while running SE-F011
on 2026-09-13 — the workflow-name probes cover `get_workflow`, but nothing
covered the composition resolver, which has its own search path.

### SE-F025 — `upload_asset` can't read arbitrary server files
`upload_asset` is the third way a caller names a file in the asset library
(beside `keep_output`'s `asset_name` and `delete_asset`, which SE-F012
covers), and the only one whose *source* is a path. When the MCP endpoint is
served by `dw.serve`, "local" is the server's disk, so `file_path` is a read
of the GPU box — the mirror of `download_output`'s write (SE-F016).
Four probes: (a) an absolute path to a stock media file outside every dw root
— `/usr/share/pixmaps/debian-logo.png`; (b) a path that certainly does not
exist with the same extension — `/nonexistent-dw-probe/x.png`; (c) a
non-media absolute path — `/etc/hostname`; (d) `asset_name` containment,
`../se-probe-escaped.png` against a legal `file_path`.
expected: (a) and (b) refused **identically**, as outside the roots the
workflow may read, in `download_output`'s style — the refusal must not depend
on whether the file exists. (c) refused. (d) refused as an invalid asset name,
`list_assets` unchanged. Fail if (a) returns a `reference`/`size` (the file
was read and copied), or if (b)'s error differs from (a)'s in anything but the
path (an existence oracle). If (a) succeeds, confirm the escape is real rather
than a name being registered: run a task-only `get_image_size` step on the
returned `asset:` reference — a job that *succeeds* means the outside file was
opened and decoded.
The extension allowlist is not the boundary: it filters the source
extension, not the location, so treat (c) passing as no evidence about (a).
cleanup: `delete_asset` anything (a) or (d) created, and delete the readback
job's outputs. Name anything kept in the issue.
source: regression agent (opus/anthropic), 2026-09-13 — gap found while
running SE-F012; `keep_output`/`delete_asset` were covered and `upload_asset`
was not. First run FAILED on (a) and (b): filed #138.

### SE-F027 — `upload_asset`'s confinement still lets a legal source through, and `..` out of a root does not
SE-F025 proves `upload_asset` refuses what it must. This case proves it still
does its job, and closes the one gap a pure-refusal case structurally cannot see:
a regression that refuses **every** `file_path` — the confinement misreading the
roots, `client.mounted` going true where it should not, a root list that comes
back empty — leaves SE-F025 passing on all four probes while the tool is dead.
Two probes, both against the mounted endpoint on the GPU box (a stdio `dw-mcp`
against a remote engine is deliberately unconfined and this case does not apply):
expected:
- **Positive control.** `upload_asset(file_path=<an absolute path to a real media
  file underneath one of the roots the refusal message names>, asset_name=…)` —
  e.g. a wav in the shared library, `<workspace root>/common/assets/<…>.wav` —
  succeeds: a `reference`, a `url` scoped to this workspace, `uploaded` naming the
  source file, and a `size` equal to the file's. A refusal here is the finding,
  and it is the one SE-F025 would never report.
- **Traversal out of a root.** A path that *begins* inside a root and climbs out
  with `..` — `<workspace root>/common/assets/../../../../etc/hostname.png` —
  refused, with a message differing from SE-F025's (a)/(b)/(c) only in the echoed
  path. Containment is on the resolved real path, so a prefix that looks legal is
  not enough; this is also the shape a symlink inside a root would take, which a
  consumer cannot create and so cannot test directly.
Read the roots out of the refusal message itself rather than hardcoding them —
it names them, and on a workspace-scoped session they are the *server's* roots,
not the session workspace's, which is easy to misread as a bug and is not one.
cleanup: `delete_asset` the control's `uploads/<asset_name>`. The traversal probe
creates nothing.
source: tester, model `opus` via provider `anthropic`, verified in #138 on
2026-09-13 against dw 0.4.0-beta.3 on `lem`, session workspace `qa-ep10` (control
uploaded 928,044 bytes as `asset:uploads/qa-probe-control.wav`, deleted after).
The implementer's suggested addition to SE-F025 — asserting (a) and (b) refuse
*identically* rather than merely both refusing — is already in SE-F025 as written,
so nothing there needed changing and nothing there was changed.

### SE-F028 — the `output:` reference grammar still refuses traversal after being widened
SE-F010 pins traversal at the output-*side tools* (`get_output_image`, `delete_output`, …).
This pins the other surface: the `output:` reference **inside a workflow definition**,
which is a different check on a different code path. It exists because that grammar was
deliberately loosened — #162 widened the pattern to admit `@` mid-segment, so a
`for_each` step's own `shot@entry` files could be named back to the server. A pattern that
has been widened once for a good reason is exactly the one to pin: the next widening is
where a `.` or a `/` slips in. Free and instant: two `validate_workflow` calls, no run.
expected:
- **Traversal refused, at validate.** An inline workflow whose `pair_audio` step has
  `video: "output:ltx2/../../etc/passwd"` → `valid: false`, error at
  **`steps[0].task.arguments.video`**, message `segment '..' starts with '.', and every
  segment must start with a letter, digit or underscore`. Refused in the free call, not
  at run time — refused-too-late is a failure by this file's rule (see the header), and
  this reference form used to be checked only after the job was queued.
- **The widened character did not become free.** `output:<workflow>/<run>/intermediate/@shot.mp4`
  (a *leading* `@` in the final segment) → `valid: false`, `segment '@shot.mp4' starts with
  '@', …`. If this validates, the widening escaped its intended scope, whatever the
  `..` probe says.
Fail on `valid: true` for either, and on any refusal that echoes a *normalized* form of the
probe (it would say the name was resolved against the filesystem before being judged).
The functional half — that a legitimate `shot@entry` name still round-trips — is S-F033 in
`regression-suite-smoke.md`; a tightening that passes this case by refusing everything is
caught there, not here.
cleanup: none; both calls are free validate calls that write nothing.
source: tester, model `opus` via provider `anthropic`, verified in #162 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-ep15`. The implementer proposed pinning the
boundary beside the widened pattern; the leading-`@` probe is mine.

### SE-F026 — a trust refusal emits no phase event, and a legitimate load still does
SE-F005 and SE-F006 say a probe must not "start loading the model" before it
fails, and read that off `get_job_events`. #137 was the case where that evidence
went bad without the gate moving: the `loading` phase marker was emitted on entry
to `pipeline.load()`, with both trust gates *inside* that call, so a job refused
before touching the model and a job that loaded one and then failed emitted the
same event. The gate held; the only thing that broke was a consumer's ability to
tell "refused too late" from "refused in time" — which this suite's header calls
a failure in its own right, and which is exactly what caught #112. The fix runs
the trust checks over the definition as a pre-flight, ahead of the marker.
This case pins both halves of that, because each alone is satisfiable by a bug:
expected:
- **The refusal side.** Re-run the SE-F005 probe (`trust_remote_code: true`) and
  the SE-F006 probe (`custom_pipeline: "lpw_stable_diffusion"`). Each job's full
  `get_job_events` contains **no `phase` event at all** — not merely no `loading`
  one. The events are the three `job_status` transitions, the workspace's own log
  lines, `run_start`, `workflow_start` and `step_start`, and nothing else. This is
  stronger than SE-F005's own wording and equally true as of 0.4.0-beta.3.
- **The control, which is the half that matters.** A *legitimate* pipeline job —
  any small real load; `templates/text-to-image` or an inline SD 1.5 step with no
  trust flags — **does** emit `phase: "loading"` with the model named in `detail`,
  immediately after its `step_start`. Without this line the case passes happily if
  `loading` stops being emitted anywhere, which is the obvious way a
  "move the marker" change regresses and would leave SE-F005/F006/SE-P001 unable
  to detect a late refusal ever again.
- The refusal's traceback still shows the check reached from `create_step_action`
  → `check_trusted`, i.e. before the step action is even built. A traceback that
  moves back inside `load()`/`load_component` means the pre-flight was lost and
  only the in-load gate is left — still safe, but the evidence is gone again.
It is a **finding** if a refusal acquires any phase event, if a legitimate load
stops emitting `loading`, or if the refusal message or its timing band changes
(SE-P001 owns the number; this case owns the events).
cleanup: the refusals write no media but do create a run directory. Remove each
with `delete_output("<workflow id>/<run id>")` — the run-directory form, which is
the only thing that reaches a run that failed before writing media (#134). Delete
the control job's outputs normally.
source: tester, model `opus` via provider `anthropic`, verified in #137 on
2026-09-13 against dw 0.4.0-beta.3 on `lem`, workspace `qa-ep10` (jobs
`aa720effc6a2` and `babaea669d3e`, both refused at 1.0 s with ten events and no
phase among them; control job `3a1545cc713c` emitted `loading` at `seq 9, at
0.7s`). Filed as a new case rather than as an edit to SE-F005 because no agent
may rewrite an existing case — the implementer offered the amendment in #137's
hand-off and this is the form the suite's own "Removing a case" rule allows.

### SE-F029 — the *shared* asset library enforces the same name containment
SE-F012 and SE-F025(d) pin `asset_name` against the workspace's own library
(`<workspace>/assets`). `shared=true` writes into a different root — the
library every workspace shares (`<workspace root>/common/assets`) — reached
through a separate branch of both writers. A name check applied on the
workspace path and not on the shared one would put a caller-named file
outside a root, and no case saw that branch.
Five probes, all refusals, nothing generated beyond one cheap image:
- `upload_asset(file_path=<a legal source under a named root>,
  asset_name="../se-f029-escaped.wav", shared=true)` and the same with
  `/tmp/se-f029-escaped.wav`.
- Generate one small output (cheapest image template), then
  `keep_output(..., shared=true)` with `asset_name` `../se-f029-escaped.jpg`,
  `/tmp/se-f029-escaped.jpg`, and `a/b/c/d/e/se-f029-escaped.jpg` (deeper than
  the documented four-folder limit). Match the probe extension to the
  generated output's, for the reason SE-F012 gives.
expected: every probe refused with the same invalid-asset-name error the
workspace-library probes get (`segment '..' starts with '.'`, `segment 1 is
empty`, and the folder-depth message), and `list_assets` unchanged — in
particular no new entry with `origin: common`. Fail if any probe creates a
file, if the shared branch refuses with a *different* rule than the workspace
branch (that means two checks exist and only one is authoritative), or if a
refusal echoes a normalized path.
The probes are harmless if containment fails: `..` off `common/assets` lands a
stray new file in `<workspace root>/common`, and `/tmp` is the suite's
designated harmless target. Never probe `shared=true` with a name that could
land on an existing file — the shared library holds the tester's `qa-cast/*`
fixtures, and SE-F021 already forbids touching them.
cleanup: delete the generated output; `delete_asset` anything that appeared
and name it in the issue.
source: regression agent, model `opus` via provider `anthropic`, 2026-09-16 —
gap found while running SE-F012/SE-F025 on dw 0.4.0-beta.4: both cover
`asset_name` only on the workspace library, and `shared=true` was never
probed. First run PASSED on all five probes.

## Performance

Security refusals should be cheap: a gate that only fires after a model
load has already spent the resources it was supposed to protect.

### SE-P001 — hostile inputs are refused before any load
Time `validate_workflow` for the SE-F002 probe (dotted `*_type`) and
`run_workflow` for the SE-F005 probe (`trust_remote_code`), measured from
call to the refusal being visible (`get_job` terminal, if a job was even
created).
Measure the **job's own** time (`finished_at - started_at` from `get_job`),
not the agent's call-to-answer wall clock — the latter is dominated by MCP
round trips and this agent's own tool overhead (~3–4 s), which would swamp
a sub-second refusal.
baseline: validate (SE-F002 probe) < 0.5 s; run-to-refusal (SE-F005 probe)
< 2 s. Set from the 2026-09-13 first run; revisit deliberately, don't drift.
Log the run-to-refusal figure (`condition: run-to-refusal`) to
`regression-perf/SE-P001.jsonl`; every code-gate refusal has landed in the
0.95–1.0 s band, with SE-F003's nonexistent-module probe the slowest at
3.0 s. A refusal that acquires a `loading` phase in its events is the
regression, whatever the number says.
cleanup: as the referenced cases.
source: harness, initial security suite 2026-09-13.
