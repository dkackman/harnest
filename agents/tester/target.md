## Target: the {{TARGET}} server, not lem

This loop runs against the {{TARGET}} server ({{SERVER}}, {{URL}}), a
dw server on this machine, not lem. lem is a Linux box with a 24 GB CUDA
GPU (RTX 3090) that another loop deploys to, whose storage holds assets,
prompts and job history other agents made there by hand. This server
starts from the same code and bundled templates, and nothing else. It is
also several times slower. Where your role instructions or a suite file
say otherwise, this section wins. The harness guard enforces the label
and file rules below.

### Verifying here

A fix handed to you was deployed to this server (the issue carries
`target:{{TARGET}}`). Verify it here, as usual. A verification adds
`verified-on:mps` next to `status:verified`, in the same command: it tells
lem's loop that CUDA hasn't seen this fix. Your closing comment names the
server and accelerator ({{SERVER}}).

When the repro needs something this server can't provide, don't bounce
the fix. Examples: a fixture only lem has (most `asset:qa-cast/…`,
`asset:cast/…` and `asset:reference_sheet.jpg`), CUDA hardware itself, a
model too large for 64 GB of unified memory shared with the OS. Hand the
issue to lem's loop instead: comment what's missing first (once the issue
is lem's, the guard refuses your comments on it), then keep `owner:tester`
and `status:fixed-pending-verify` and run
`gh issue edit N --remove-label target:{{TARGET}} --add-label target:lem`.
lem deploys `develop`, which has the fix, before its tester runs.

### Timing

Every absolute time in a case or an issue was measured on lem's CUDA GPU.
None of them applies here. A `wait_seconds` reply with
`still_running: true` is expected more often: follow it with
`wait_for_job`, and don't treat it as a finding. A first run that includes
a model download is slow for that reason alone.

### Filing

A new issue gets `owner:implementer` and `backend:mps`. Use
`backend:shared` instead when the bug can't be about the accelerator: a
validation or schema error, a wrong message, a missing field. Never add a
`target:` label; claims are the driver's. Never comment on an issue
labeled `target:lem`: file your own and reference it.

### Suite cases

- A verified fix labeled `backend:shared`: add its case to the suite file
  as usual. It will run on lem too, and a shared case that fails on CUDA
  is a real finding.
- A verified fix labeled `backend:mps`: don't edit a suite file. Put the
  case in your verify comment, under the heading
  `Proposed case (mps level, harnest#16)`.

### Security probes

Paths the security suite probes are Linux paths. `/etc/hostname` and
`/usr/share/pixmaps/` don't exist on macOS, so a bare "not found" proves
nothing. For a *read* probe, use `/etc/hosts` in its place. Never point a
delete or write probe at a real file on this machine. A leaked server path
here looks like `/Users/…` or `/private/…`, as well as `/home/`, `/var/`,
`/srv/` or `/mnt/`.
