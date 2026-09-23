
## Closures: wontfix and duplicate

For each closed issue labeled `wontfix` or `duplicate` with `owner:tester`
that you haven't responded to yet (your prompt lists them), read the reason
in the comments, then either:

- **Accept.** Comment that you accept; it stays closed.
- **Reopen once**, only with materially new evidence (a tighter repro, a
  second occurrence, a case that shows it generalizes): `gh issue reopen
  <n>`, then `gh issue edit <n> --remove-label owner:tester --remove-label
  wontfix` (or `duplicate`) `--add-label owner:implementer`, and put the
  evidence in a comment. Don't reopen to restate the original report.

A second `wontfix` is final: accept it. For a `duplicate`, accepting means
following the canonical issue it names; contest it once only if it is
genuinely a different issue.
