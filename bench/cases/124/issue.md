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


--- comment by @dkackman at 2026-09-13T20:14:01Z ---
Fixed and deployed. Implementer agent, model `opus` via provider `anthropic`.

**Commit** `781a4c8` (merged to `develop` as `ebab468`), deployed to `lem` 2026-09-13 ~20:10Z.

Taken as filed. Your reading of the cause is what it was: the validation-time check tested `os.path.isabs` and did nothing at all for a relative value, on the reasoning that a relative path is under `base_dir` by construction - which is true right up until it climbs out, and then the only thing that catches it is `validate_path` inside the loader, three seconds into a queued job. The two guarantees were not the same guarantee, exactly as you put it.

A relative value carrying a `..` segment is now refused at validation, on the segments, the way `validate_media_glob` already checked a pattern's:

```
validate_workflow(... "image": "../../../../../usr/share/pixmaps/debian-logo.png")
  -> valid: false
  steps[0].task.arguments.image: Refusing to read 'image' at
  '../../../../../usr/share/pixmaps/debian-logo.png': it contains a '..'
  path segment, so it does not resolve inside any directory this workflow
  may read. Put the file in the asset library and name it with an 'asset:'
  reference.
```

Verified live on lem against your exact SE-F014 payload. The three spellings in your table now all answer `valid: false`, and a relative path without `..` still validates and still resolves against the workflow directory, which is the case that had to keep working.

The traceback note: not addressed, and I agree with your reasoning for not filing it - the stack is the right answer when a job fails for a real reason. What made it visible here was a policy refusal arriving as a run-time exception, and this fix removes that particular one by moving the refusal before the job exists. If a policy refusal still reaches run time on some path (a location arriving through a variable or a previous result, which validation cannot see), it will still carry a stack. That is a separate, narrower question - worth its own issue if you hit it.

### Proposed regression case

`regression-suite-security.md`, folded into SE-F014 rather than as a new case, since the point is that the three spellings agree:

- `validate_workflow` with `image: "/usr/share/pixmaps/debian-logo.png"` -> `valid: false`.
- ... with `image: "../../../../../usr/share/pixmaps/debian-logo.png"` -> `valid: false`, error at the argument's path, message naming `'..'`.
- ... with `glob: "../../../../../usr/share/pixmaps/*.png"` -> `valid: false`.
- Positive control: a relative path with no `..` (`"inputs/frame.png"`) -> `valid: true`. Without this the case would pass just as well if relative paths were refused wholesale, which would break every workflow that reads a file beside itself.
- The failure mode the case scores: any of the first three answering `valid: true` and being stopped only by a queued job that then fails.

