# classify.jq: the ticket protocol's state machine, in one place (roadmap R12).
#
# Input: {owner: "<login>", issues: [<open issue>...]}, each issue as
# `gh issue list --json number,title,labels,author,parent,blockedBy,subIssuesSummary`
# gives it, plus `markers`: the first line of each harnest marker comment
# (`<!-- harnest:<kind> vN -->`) by the owner, for feature and idea issues.
# issue_snapshot (providers.sh) builds it.
#
# Output: one object per issue:
#   {number, queue, reason, parent}
# where queue is the session that runs next, or where the issue waits:
#   implementer:fix
#   tester:verify  tester:handoff  tester:answer  tester:spec
#   reviewer:docs  a fix that changed only files neither the server nor the
#              plugin serves (README, docs/ outside the guides), so the
#              tester can't observe it: read-only source review instead
#   lead:design  lead:decompose  lead:build  lead:closeout
#   don        parked with Don; reason says why
#   wait       a legitimate pause: blocked, or its parent isn't building yet
#   external   filed by another login and not yet parked; park_external_issues
#              parks it. Once Don hands a parked one back, it is ordinary.
#   stranded   no queue selects it and nothing will: a protocol hole to fix
#
# A release freeze (roadmap R14): while an open issue labeled `release`
# exists (Don's, owner:don, titled with the version), every agent queue
# (implementer, tester, lead, reviewer) holds its issues at `wait` except
# the ones labeled `release-blocker`. The release issue itself is Don's.
# The driver reads the freeze from that row, to hold the tester's standing
# task too, which no issue queues.
#
# A loop runs against one server (`target` in the snapshot, lem when it is
# absent; harnest#15). An issue another loop holds, or whose backend this
# server can't serve, waits here: see the target post-filter at the end. The
# design is docs/superpowers/specs/2026-09-26-mac-loop-design.md.
#
# Every driver queue, the digest and the post-session audit read this.
# Changing who acts on what means changing this file. Its fixtures live in
# tests/ (R12 phase C).
#
# A feature's phase comes from versioned markers against its plan version P
# (the `plan vP` comment, edited in place):
#   decomposed vP      decompose filed the stages for plan vP
#   specced vP         the tester wrote their acceptance cases (or decompose
#                      recorded that the plan needs none)
#   spec-questions vP  the tester found the plan too vague to test
# A re-plan bumps P, so every marker for the old version stops counting and
# decompose and spec run again for the new one.

def names: [.labels[].name];
# Statuses addressed to Don: a park, a plan waiting on his review, a question
# for him. Once he hands the issue back (swaps owner:don for an agent's
# owner) they are stale, and never decide a queue: the owner label is the
# only signal. The agent now holding the issue clears them.
def don_statuses: ["status:needs-approval", "status:plan-review"];
def has($l): names | index($l) != null;
def statuses: names | map(select(startswith("status:")));
def owners: names | map(select(startswith("owner:")));
# target:<server> is a loop's claim on an issue it took (the driver adds it);
# backend:<shared|cuda|mps> is what the bug is about. Both labels at once
# means two loops claimed it in the same moment: lem keeps it, and the other
# loop's driver removes its own label.
def claims: names | map(select(startswith("target:")) | ltrimstr("target:"));
def backend: (names | map(select(startswith("backend:")) | ltrimstr("backend:")) | .[0]) // "";
def holder: claims | if index("lem") != null then "lem" else .[0] end;
def serves($t; $b): ($b == "" or $b == "shared") or ($b == "cuda" and $t == "lem") or ($b == "mps" and $t == "local");

def marker_versions($kind):
  [ (.markers // [])[]
    | capture("^<!-- harnest:(?<k>[a-z-]+)(?: v(?<v>[0-9]+))? -->")
    | select(.k == $kind) | (.v // "0" | tonumber) ];
def plan_version: (marker_versions("plan") | max) // 0;
def marked($kind): plan_version as $p | marker_versions($kind) | index($p) != null;

# What an owner:lead feature parent needs next, or why it waits.
def parent_phase:
  if has("wontfix") then {queue: "lead:closeout", reason: "declined"}
  elif (has("status:plan-approved") | not) then {queue: "lead:design", reason: "no approved plan"}
  elif (marked("decomposed") | not) then {queue: "lead:decompose", reason: "plan v\(plan_version) not decomposed"}
  elif marked("specced") then
    (if (.subIssuesSummary.total // 0) > 0
        and .subIssuesSummary.completed == .subIssuesSummary.total
     then {queue: "lead:closeout", reason: "every stage closed"}
     else {queue: "wait", reason: "building", building: true} end)
  elif marked("spec-questions") then {queue: "lead:design", reason: "the tester's spec questions on plan v\(plan_version)"}
  else {queue: "lead:decompose", reason: "decomposed but never handed to the tester"} end;

.owner as $me
| (.target // "lem") as $target
| (.issues | map({key: (.number | tostring), value: .}) | from_entries) as $open
| ([.issues[] | select(any(.labels[]; .name == "release")) | .number] | min) as $release
| .issues[]
| . as $i
| (owners) as $o
| (statuses) as $st
| ({number, parent: (.parent.number // null)} +
  if .author.login != $me and (has("status:needs-approval") | not)
     and ((.markers // []) | index("<!-- harnest:external-parked -->") == null) then
    {queue: "external", reason: "filed by @\(.author.login), not yet parked"}
  elif ($o | length) != 1 then
    {queue: "stranded", reason: "owner labels: \($o | join(",") | if . == "" then "none" else . end)"}
  elif has("release") then
    if $o[0] == "owner:don" then {queue: "don", reason: "release freeze: \(.title)"}
    else {queue: "stranded", reason: "a release issue is owner:don's, not \($o[0])'s"} end
  elif $o[0] == "owner:don" then
    {queue: "don", reason: ($st | join(",") | if . == "" then "no status" else . end)}
  elif $o[0] == "owner:implementer" then
    # needs-info on an implementer's issue is a question Don was asked (a
    # failed deploy) and has handed back: stale too.
    ($st - don_statuses - ["status:needs-info"]) as $live
    | if ($live | length) == 0 then
        {queue: "implementer:fix", reason: (if ($st | length) > 0 then "ready (stale \($st | join(",")) to clear)" else "ready" end)}
      else {queue: "stranded", reason: "owner:implementer with \($live | join(","))"} end
  elif $o[0] == "owner:tester" then
    if has("status:fixed-pending-verify") and has("docs-review") then {queue: "reviewer:docs", reason: "docs-only fix, not observable over MCP"}
    elif has("status:fixed-pending-verify") then {queue: "tester:verify", reason: "handed off"}
    elif has("status:needs-spec") then {queue: "tester:spec", reason: "plan approved and decomposed"}
    elif has("status:needs-info") then {queue: "tester:answer", reason: "question from the implementer"}
    elif (($st - don_statuses) | length) == 0 then {queue: "tester:handoff", reason: "harness-side edit requested"}
    else {queue: "stranded", reason: "owner:tester with \($st | join(","))"} end
  elif $o[0] == "owner:lead" then
    if has("stage") then
      ($open[(.parent.number // -1) | tostring]) as $p
      | [(.blockedBy.nodes // [])[] | select(.state == "OPEN") | .number] as $blockers
      | if (($st - don_statuses - ["status:needs-info"]) | length) > 0 then {queue: "stranded", reason: "stage with owner:lead and \($st | join(","))"}
        elif .parent == null then {queue: "stranded", reason: "stage with no parent"}
        elif $p == null then {queue: "stranded", reason: "stage whose parent #\(.parent.number) is closed"}
        elif ($blockers | length) > 0 then {queue: "wait", reason: "blocked by \($blockers | map("#\(.)") | join(","))"}
        elif ($p | [.labels[].name | select(startswith("owner:"))]) != ["owner:lead"] then
          {queue: "wait", reason: "parent #\($p.number) is with \($p | [.labels[].name | select(startswith("owner:"))] | join(","))"}
        elif ($p | parent_phase | .building) == true then {queue: "lead:build", reason: "ready to build"}
        else {queue: "wait", reason: "parent #\($p.number): \($p | parent_phase | .reason)"} end
    elif has("feature") or has("idea") then
      parent_phase | del(.building)
    else {queue: "stranded", reason: "owner:lead on an issue that is neither a feature nor an idea"} end
  elif $o[0] == "owner:researcher" then
    {queue: "stranded", reason: "owner:researcher is retired: hand it to owner:lead"}
  else {queue: "stranded", reason: "unknown owner \($o[0])"} end)
| if $release != null
     and (.queue | test("^(implementer|tester|lead|reviewer):"))
     and ($i | has("release-blocker") | not)
  then .reason = "release freeze (#\($release)): not a release-blocker (\(.queue) after it)"
     | .queue = "wait"
  else . end
# The target post-filter. Server-free queues (a design, a decompose, a docs
# review) run in whichever loop runs them. A feature's spec, builds and
# close-out run on lem only. The rest belong to the loop holding the claim;
# an unclaimed fix to any loop whose server its backend allows; and an
# unclaimed issue past the implementer to lem, which is where everything
# handed off before claims existed was deployed.
| if .queue == "wait" or (.queue | test("^(implementer|tester|lead|reviewer):") | not) then .
  elif (.queue | IN("lead:design", "lead:decompose", "reviewer:docs")) then .
  elif ($i | claims | length) > 0 and (serves($i | holder; $i | backend) | not) then
    .reason = "target:\($i | holder) on a backend:\($i | backend) issue" | .queue = "stranded"
  elif (.queue | IN("tester:spec", "lead:build", "lead:closeout")) and $target != "lem" then
    .reason = "target: \(.queue) runs on lem only" | .queue = "wait"
  elif ($i | claims | length) > 0 then
    if ($i | holder) == $target then . else .reason = "target:\($i | holder) holds it" | .queue = "wait" end
  elif .queue == "implementer:fix" then
    if serves($target; $i | backend) then . else .reason = "target: backend:\($i | backend) is not served here" | .queue = "wait" end
  elif $target == "lem" then .
  else .reason = "target: handed off before claims existed, so deployed to lem" | .queue = "wait" end
