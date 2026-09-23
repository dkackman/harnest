## #124: Media arguments: a relative '..' traversal validates clean and is only refused at run time, while the absolute form and gather_images' glob both refuse at validation
filed by: @dkackman

Found while verifying #114 and #116 this cycle. Tester agent, model `opus` via provider `anthropic`. Workspace `qa-ep7`, dw `0.4.0-beta.3` on `lem`, `get_server_info().trust_workflows == false`.

**No escape — containment holds.** This is about *when* the refusal happens, and about two loaders disagreeing on it.

**tool/endpoint:** `validate_workflow` / `run_workflow`, media arguments (`dw/locations.py` policy as exposed over MCP)

### repro

Three spellings of "read a file outside every dw root", same workspace, same call:

| argument value | `validate_workflow` |
|---|---|
| `image: "/usr/share/pixmaps/debian-logo.png"` | **`valid: false`** — "resolves outside every directory this workflow may read" |
| `glob: "../../../../../usr/share/pixmaps/*.png"` (`gather_images`) | **`valid: false`** — "it contains a '..' path segment" |
| `image: "../../../../../usr/share/pixmaps/debian-logo.png"` | **`valid: true`** |

The third one, run for real — a model-free `get_image_size` step, so it costs nothing:

```
run_workflow(inline_workflow = {"id": "se-f014g", "steps": [{"name": "probe",
  "task": {"command": "get_image_size", "arguments": {
    "image": "../../../../../usr/share/pixmaps/debian-logo.png"}},
  "result": {"content_type": "text/plain", "file_base_name": "se_f014g"}}]})

job 70f3f2ea57bc -> failed at 3.0 s
error: "Workflow execution error: Path contains dangerous pattern matching \.\."
  dw/arguments.py fetch_image -> dw/locations.py validate_media_path
  -> dw/security.py validate_path -> PathTraversalError
```

Same with `image: "../../../../etc/hostname"` and `"../../../../../nonexistent-dw-probe/x.png"` — all `valid: true`, all stopped at run time.

### expected

`validate_workflow` refuses a relative-traversal media argument the same way it refuses the absolute form, at the same moment, with the same message shape. `validate_path`'s `..` rule is evidently reachable from the run path; validation should call the same check the `gather_images` glob loader already calls.

### actual

`valid: true`, then a job that is queued, started, and killed ~3 s in by `PathTraversalError`.

### why it's worth fixing even though nothing escapes

1. **The suite can't tell the two apart from outside.** `regression-suite-security.md` scores "refused too late" as a failure precisely because a refusal that happens after the resolver has been reached is one resolver change away from not happening. Today the absolute spelling is refused by policy and the relative spelling by a downstream assertion; they are not the same guarantee, and `valid: true` is the interface saying they are.
2. **It contradicts the two fixes it sits between.** #114 made the absolute form refuse at validation. #116 made the glob form refuse `..` at validation. This is the same policy in the same batch reaching a different conclusion depending on spelling.
3. **It costs a queued job.** Small here, but `validate_workflow` is documented as "free and instant — always run this before run_workflow", and a caller who does exactly that gets told to go ahead.

Also worth a look while you are in there: the failure returns a full Python traceback with server source paths (`/home/don/diffusers-workflow/dw/...`) in the `traceback` field. Not filing it — SE-F020 passes and no secret is in it, and the traceback is genuinely useful when a job fails for a real reason — but a refusal that is a *policy decision* rather than a crash probably wants the clean error, not the stack.

### sizing

Small. Low severity: no boundary was crossed in any probe. Filing it as correctness-of-the-interface rather than as a security hole, and labelling it `security` only because it is the security suite's SE-F014 that will carry the case.

