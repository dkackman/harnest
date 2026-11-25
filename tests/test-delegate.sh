#!/usr/bin/env bash
# R19's escalation delegate, outside the guard (test-guard.sh) and the
# classifier (classify-cases.json): run-loop.sh's delegate_record, which
# logs a ruling to logs/delegate.jsonl from the comment the session posted,
# and run-digest.sh's delegate_section, which lists them for Don.
. "$(dirname "$0")/lib.sh"
L="$T/logs"; mkdir -p "$L"
# shellcheck disable=SC2034  # read by the evaluated functions
TICKET_REPO=dkackman/diffusers-workflow DELEGATE_MODEL=claude-opus-5-5 LOGS="$L" LAST_SESSION="$L/last"
printf 'usage: turns=3 duration=20s cost=$0.17 ctx_peak=30k\n' > "$LAST_SESSION"
eval "$(sed -n '/^delegate_record() {/,/^}/p' "$HARNEST/run-loop.sh")"
eval "$(sed -n '/^delegate_section() {/,/^}/p' "$HARNEST/run-digest.sh")"
gh() { printf '%s' "$GHOUT"; }

GHOUT='{"createdAt":"2026-11-25T18:00:00Z","body":"**Ruling (delegate for Don, 2026-11-25): approved, Q2 amended.**\nKinds: scope, `none`\n\nDelegate changed: Q2 narrowed"}'
delegate_record 1600
GHOUT='{"createdAt":"2026-11-25T18:05:00Z","body":"**Passed to Don (delegate, 2026-11-25): a taste verdict.**\nKinds: taste"}'
delegate_record 1601
GHOUT='{"createdAt":"2026-11-25T18:06:00Z","body":"triage: something else"}'
delegate_record 1602
GHOUT='{"createdAt":"2026-11-25T18:07:00Z","body":"**Ruling (delegate for Don, 2026-11-25): the default.**\nKinds: record"}'
delegate_record 1603

eq "record: one line per ruling, none for another comment" 3 "$(wc -l < "$L/delegate.jsonl" | tr -d ' ')"
eq "record: an amendment" amended "$(jq -r 'select(.issue == 1600) | .outcome' "$L/delegate.jsonl")"
eq "record: a pass-through" passed "$(jq -r 'select(.issue == 1601) | .outcome' "$L/delegate.jsonl")"
eq "record: a ruling at the default" ruled "$(jq -r 'select(.issue == 1603) | .outcome' "$L/delegate.jsonl")"
eq "record: kinds, backticks dropped" "scope,none" "$(jq -r 'select(.issue == 1600) | .kinds | join(",")' "$L/delegate.jsonl")"
eq "record: the session's cost" 0.17 "$(jq -r 'select(.issue == 1600) | .cost' "$L/delegate.jsonl")"
eq "record: the first line, without bold" "Ruling (delegate for Don, 2026-11-25): approved, Q2 amended." \
  "$(jq -r 'select(.issue == 1600) | .line' "$L/delegate.jsonl")"

# shellcheck disable=SC2034  # read by delegate_section
DIGEST_DELEGATE_HOURS=1000000 board=$'1700\tdelegate:rule\t-\tfor the delegate\n1701\tdon\t-\tx'
out="$(delegate_section)"
has() { case "$out" in *"$1"*) echo yes ;; *) echo no ;; esac; }
eq "digest: the section" yes "$(has '## Delegate rulings')"
eq "digest: how to overrule" yes "$(has 'overrule:')"
eq "digest: an amendment, with its kinds" yes "$(has '#1600 amended (scope, none)')"
eq "digest: a pass-through" yes "$(has '#1601 passed (taste)')"
eq "digest: what waits for the delegate now" yes "$(has '1 ask(s) wait for the delegate now')"
# shellcheck disable=SC2034
DIGEST_DELEGATE_HOURS=0 board=''
eq "digest: nothing in the window and nothing waiting, no section" "" "$(delegate_section)"
finish
