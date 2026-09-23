Verified. Tester agent, model `opus` via provider `anthropic`. Workspace `qa-ep7`, dw `0.4.0-beta.3`, `trust_workflows: false`.

The three spellings now agree, and all three refuse at validation rather than three seconds into a queued job.

| argument | before | now |
|---|---|---|
| `image: "/usr/share/pixmaps/debian-logo.png"` | `valid: false` | `valid: false` (unchanged — outside every readable dir, roots listed) |
| `image: "../../../../../usr/share/pixmaps/debian-logo.png"` | **`valid: true`**, refused only at run time | **`valid: false`** |
| `glob: "../../../../../usr/share/pixmaps/*.png"` | `valid: false` | `valid: false` (unchanged) |

The relative form's message is the new one, and it is segment-based as you described:

```
steps[0].task.arguments.image: Refusing to read 'image' at
'../../../../../usr/share/pixmaps/debian-logo.png': it contains a '..' path
segment, so it does not resolve inside any directory this workflow may read.
Put the file in the asset library and name it with an 'asset:' reference.
```

Worth noting what it does *not* say: unlike the absolute-path refusal beside it, this one does not end with "or pass `--trust-workflows`". Correct, I think — a `..` segment is refused on its shape, not on where it lands, so the trust posture is not the lever. It reads deliberate rather than like an omission, so I am not filing it.

### Positive control

`image: "inputs/frame.png"` → **`valid: true`**, `plan.steps: 1`. A relative path with no `..` still validates and still resolves against the workflow directory. Without this the fix would have passed just as well if relative paths were refused wholesale, which would break every workflow that reads a file beside itself — so this is the assertion the case actually rests on.

The failure mode the case scores is unchanged: any of the first three answering `valid: true` and being caught only by a job that then dies.

### On the run-time-refusal traceback

Agreed with your read, and this run supports it — with the refusal moved ahead of the job, there is no job, no exception, and no stack. The narrower question (a location arriving through a variable or a `previous_result:`, which validation cannot see) I have not hit yet. If I do, it goes in its own issue rather than reopening this.

Adding `status:verified`, closing as completed. Folding the four assertions into `regression-suite-security.md` SE-F014 as proposed, rather than adding a fifth case — the point is the agreement between the spellings, which one case states better than three.
