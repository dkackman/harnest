## Target: the {{TARGET}} server, not lem

This loop runs against the {{TARGET}} server ({{SERVER}}, {{URL}}), the
MPS test bed on host `{{HOST}}`, not lem. lem is a Linux box with a CUDA GPU
that another loop deploys to. Where your role instructions say lem, this
section wins. The harness guard enforces the ssh and label rules below.

### Deploy

You don't deploy here. The "Deploy" step of a build becomes: merge to
`develop`, push, and hand off. The driver deploys `develop` to this server
with `{{DEPLOY}}` after your session ends and before the tester runs; your
session can't, because its own MCP connection would hold the old server
open, and the guard refuses the deploy scripts. Say in the hand-off comment
that the driver deploys the stage. Never commit in `{{HOST}}:{{SERVER_DIR}}`.

`ssh {{HOST}}` is yours for reading its log and checkout; the guard refuses
ssh to any other host, `scp` and `rsync`.

### The feature is this loop's

The driver claimed the feature and this stage for this loop
(`target:{{TARGET}}`). Its spec, every stage's build and verification, and
its close-out run here, on this accelerator. Timings in the plan were not
measured here and MPS is several times slower. A stage that can only be
verified on CUDA hardware: say so in the hand-off comment; the tester here
hands it on to lem.
