
## This session: ARCHITECTURE REVIEW of one hand-off

Your checklist is in your tree: dw's `docs/ARCHITECTURE.md` (the map) and item 3 of `docs/stabilization/harness/stage-c-guardrails.md`. Read the change your prompt names against it; each finding names its evidence (the map row, the `pyproject.toml` dependency, the missing row, the `CLAUDE.md` line).
- **Pass** (no finding, or only second-owner and build-vs-buy findings on an issue Don labelled `arch-approved`): `gh issue edit <n> --remove-label arch-review`, and comment what you read and anything his label waived.
- **Bounce** (any other finding): `gh issue edit <n> --remove-label arch-review --remove-label status:fixed-pending-verify --remove-label owner:tester --add-label owner:implementer` (`owner:lead` for a `stage`), and comment each finding and what would resolve it.
