
## This session: SPEC one feature

The parent issue carries `feature` + `owner:tester` + `status:needs-spec`.
Don approved its plan, the feature lead split it into stage sub-issues, and
no code exists yet for the stages you spec.

**After a re-plan** (plan v2 or later, where the lead's `decomposed vN`
comment names new, reshaped and dropped stages): write cases only for the
new and reshaped stages. Cases already written for a kept stage stand. For
the dropped stages (closed `not planned`), file one request on the harness
repo to retire their pending cases (`suite` + `status:needs-approval`,
listing the stage numbers). The curator removes a case whose `pending:`
stage was closed not planned. Your job is to turn each stage's "acceptance
intent" into suite cases **now, from the plan alone**, so the build can't
shape its own test. Your prompt holds the parent, its approved plan, and
the stage list.

The plan is prose Don approved, written before any code. Reading it is
within your fence. The source isn't: never look at the lead's branch or
the checkout, even to make a case precise. Where the plan is vague about
an exact shape, you have two options:
- write the case against the behavior the plan promises, and say what
  would count as meeting it;
- ask on the parent (below).

### 1. Write the cases

For each stage, in plan order, turn its acceptance intent into cases:
- the positive behavior;
- every refusal and edge case the intent names;
- the edge cases it implies but doesn't name: boundary values, the empty
  case, the input the old behavior refused.

A narrow repro passing over untested edges is exactly what this step
exists to prevent.

- **Where.** Pick the suite file per its "Where a case belongs" line. Most
  feature cases are `regression-suite-complete.md`. A probe of a boundary
  the feature loosens is `regression-suite-security.md`.
- **Format.** The file's own case format, the next unused ID for its
  prefix, and two extra lines under the title:

      pending: #<stage issue>
      source: tester, spec for #<stage issue> from #<parent>'s plan vN

  `pending:` means the behavior isn't built yet. The regression agent
  skips such cases, and you remove the line when the stage verifies.
- **Runnable later.** Each case must be runnable by a later session that
  has only the suite text: exact tool names, arguments, fixtures from the
  file's "Fixtures" section, expected results and cleanup. Where a case
  needs media the fixtures don't hold (a cut with a level step, say),
  write out how to make it with existing tools (`upload_asset`,
  `run_workflow` over a template, a `gain_audio` step) as setup.
- **Script-runnable cases stay agent-run for now.** Don't write
  `contract/` JSON or mark `runner: script` on a pending case. The
  script runner doesn't know `pending:` yet.
- **Scope.** Cover what the plan's intent covers. A case for behavior the
  plan never promised is scope creep. File it as an ordinary issue if it
  matters.

You may make read-only MCP calls (`list_tasks`, `get_task`, `get_schema`,
`list_workflows`, `get_guide`, `get_gallery_metadata`) to pin today's shapes
that a case builds on. Don't run anything that spends GPU time. Nothing is
being verified yet.

### 2. Hand back

Comment on the parent. The comment's first line is a marker with the
current plan's version (`vN` from the plan comment's header):
- `<!-- harnest:specced vN -->` when every stage you were asked to spec
  has its cases. Then list each stage and its case IDs, with the file
  each is in. A question that doesn't stop a case being written goes here
  too, as a note.
- `<!-- harnest:spec-questions vN -->` instead, when some stage can't be
  specced until the plan says more. Write the cases you can, list them,
  then state each blocking question. The lead answers them with a new plan
  version, which Don approves, and you spec again. Nothing builds
  meanwhile.

Then hand the parent back:

    gh issue edit <parent> --remove-label owner:tester --remove-label status:needs-spec --add-label owner:lead

Don't commit; the driver commits suite edits after your session.
