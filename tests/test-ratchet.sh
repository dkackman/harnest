#!/usr/bin/env bash
# The architecture ratchet (lib/arch_ratchet.py, guard.py's ratchet_gate) on
# small fixture repos: a throwaway origin whose develop carries a stdlib-only
# stand-in for dw's scripts/arch_metrics.py. Never the real dw checkout.
# The stand-in counts marker lines, and copies regressions() verbatim.
. "$(dirname "$0")/lib.sh"
guard="$HARNEST/agent-settings/hooks/guard.py"
export HARNEST_ARCH_TOOLS="json"   # the stand-in needs nothing beyond the standard library
# A rise asks GitHub whether the issue carries arch-approved: #7 does, #8 doesn't
stub_gh 'case "$*" in *"view 7"*) echo true ;; *"view 8"*) echo false ;; *) exit 1 ;; esac'

g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}" >/dev/null 2>&1; }
script() {  # script <version-tag>: the stand-in, whose only difference between versions is what it counts
  cat <<EOF
import argparse, json, pathlib, sys
# $1
def measure(root):
    root = pathlib.Path(root)
    text = [p.read_text() for p in sorted((root / "dw").rglob("*.py"))]
    metrics = {"modules": len(text), "complex_functions": sum(t.count("# complex") for t in text)}
    $2
    return metrics
def regressions(current, baseline):
    worse = []
    for name, before in baseline.items():
        now = current.get(name)
        if before is None or now is None:
            continue
        if now > before:
            worse.append(f"{name}: {before} -> {now}")
    return worse
if __name__ == "__main__":
    p = argparse.ArgumentParser(); p.add_argument("--root"); a = p.parse_args()
    print(json.dumps(measure(a.root), indent=2))
EOF
}
mk() {  # mk <dir> <with-script 0|1>: origin + seed + clone, develop at one complex marker
  git init -q --bare "$1/origin.git"; git init -q -b develop "$1/seed"
  mkdir -p "$1/seed/dw" "$1/seed/scripts"
  printf 'a\n# complex\n' > "$1/seed/dw/a.py"; echo b > "$1/seed/dw/b.py"; echo x > "$1/seed/README.md"
  [ "$2" = 1 ] && script v1 "" > "$1/seed/scripts/arch_metrics.py"
  g "$1/seed" add -A; g "$1/seed" commit -m base; g "$1/seed" remote add origin "$1/origin.git"; g "$1/seed" push origin develop
  git clone -q -b develop "$1/origin.git" "$1/work"
}
mkdir "$T/a" "$T/b"; mk "$T/a" 1; mk "$T/b" 0
w="$T/a/work"; s="$T/a/seed"
branch() { g "$w" checkout -q -B "$1" origin/develop; }
edit() { mkdir -p "$w/$(dirname "$2")"; printf '%s\n' "$3" >> "$w/$2"; g "$w" add -A; g "$w" commit -m "$1 $2"; }
# hrow <expect> <name> [dir] [issue]: the hand-off, from that checkout's HEAD; the message lands in $out
hrow() {
  out="$(jq -n --arg c "gh issue edit ${4:-8} --remove-label owner:implementer --add-label owner:tester --add-label status:fixed-pending-verify" \
     --arg d "${3:-$w}" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | python3 "$guard" implementer 2>&1 >/dev/null)"
  eq "ratchet hand-off: $2" "$1" $?
}
# prow <expect> <name> <command>: a push; the fixture has no HARNEST_ISSUE, which the freeze push check needs
prow() {
  out="$(jq -n --arg c "$3" --arg d "$w" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | python3 "$guard" implementer 2>&1 >/dev/null)"
  eq "ratchet push: $2" "$1" $?
}
hrow_rc() { jq -n --arg c "gh issue edit 8 --add-label status:fixed-pending-verify" --arg d "$w" \
  '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | python3 "$guard" implementer >/dev/null 2>&1; }
lift() { g "$s" pull -q origin develop; }

ok "the fixture is not frozen, so nothing below rides on the freeze" bash -c "! python3 '$HARNEST/lib/freeze.py' active '$w'"

# a regression is refused, naming the metric with both values and the way out
branch fix-worse; edit fix-worse dw/a.py '# complex'
hrow 2 "a complex function added"
has "  names the metric and both values" "complex_functions: 1 -> 2" "$out"
has "  says how to bring it down" "patch.object" "$out"
has "  says what to do if it can't: park for Don" "--add-label owner:don --add-label status:needs-approval" "$out"
has "  says only Don's label, with a baseline raise, waives it" "Only Don's \`arch-approved\` waives it, and only with a matching docs/stabilization/baseline.json raise" "$out"
# unchanged, and an improvement, are allowed
branch fix-same; edit fix-same README.md 'more'
hrow 0 "no metric moved"
branch fix-better; g "$w" rm -q dw/a.py; printf 'a\n' > "$w/dw/a.py"; g "$w" add -A; g "$w" commit -m better
hrow 0 "a metric improved"
branch fix-mixed; edit fix-mixed dw/c.py 'new module'
hrow 2 "one metric up (modules) is enough, even beside an unchanged one"
has "  the message says which" "modules: 2 -> 3" "$out"

# --- the one waiver (stage C): a new dw/ module raises `modules`. Refused
# without arch-approved; with it, only when the same commits raise
# baseline.json by exactly what rose, in a commit naming the rise and why.
# The hot zone covers docs/stabilization/, and stays out of the way only
# for a waived raise.
mkdir -p "$s/docs/stabilization"
printf '{\n  "modules": 2,\n  "complex_functions": 1\n}\n' > "$s/docs/stabilization/baseline.json"
printf 'docs/stabilization/\n' > "$s/docs/stabilization/hot-zone.txt"
g "$s" add -A; g "$s" commit -m "baseline and hot zone"; g "$s" push origin develop; g "$w" fetch -q origin
raise() {  # raise <modules> <message>: a commit setting baseline.json's modules
  printf '{\n  "modules": %s,\n  "complex_functions": 1\n}\n' "$1" > "$w/docs/stabilization/baseline.json"
  g "$w" add -A; g "$w" commit -m "$2"
}
why='baseline: raise modules 2 -> 3

dw/c.py is the new owner of the X rule (approved on the issue).'
branch mod-bare; edit mod-bare dw/c.py 'new module'
hrow 2 "a new dw/ module, without arch-approved"
has "  names the metric and both values" "modules: 2 -> 3" "$out"
hrow 2 "  with arch-approved but no baseline.json raise" "$w" 7
has "  says the paperwork is missing" "does not raise it" "$out"
branch mod-ok; edit mod-ok dw/c.py 'new module'; raise 3 "$why"
hrow 0 "  with arch-approved and the matching raise" "$w" 7
hrow 2 "  the same commits without the label: refused (the hot zone, then the ratchet)" "$w" 8
has "  by the hot zone first" "hot-zone.txt" "$out"
g "$w" checkout -q -B develop mod-ok
prow_issue() { out="$(jq -n --arg c "git push origin develop" --arg d "$w" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' \
  | HARNEST_ISSUE="$1" python3 "$guard" implementer 2>&1 >/dev/null)"; eq "ratchet push (HARNEST_ISSUE=$1): $2" "$3" $?; }
prow_issue 7 "the waived rise, pushed from its issue's session" 0
prow_issue "" "the same push from a session with no issue" 2
branch mod-big; edit mod-big dw/c.py 'new module'; raise 5 "$why"
hrow 2 "  a raise bigger than the rise" "$w" 7
has "  says by how much" "should raise it to 3, not 5" "$out"
branch mod-terse; edit mod-terse dw/c.py 'new module'; raise 3 "baseline: raise modules 2 -> 3"
hrow 2 "  a raise whose commit gives no why (no body)" "$w" 7
has "  says so" "says why in its body" "$out"
branch mod-extra; edit mod-extra dw/c.py 'new module'
printf '{\n  "modules": 3,\n  "complex_functions": 2\n}\n' > "$w/docs/stabilization/baseline.json"; g "$w" add -A
g "$w" commit -m "$why"
hrow 2 "  a raise of a metric that didn't rise" "$w" 7
has "  names it" "raises complex_functions, which did not rise" "$out"
branch mod-replace; g "$w" rm -q dw/b.py; edit mod-replace dw/c.py 'replaces b'
hrow 0 "a module that replaces another raises nothing" "$w" 8
g "$s" rm -q docs/stabilization/hot-zone.txt; g "$s" commit -m "no hot zone"; g "$s" push origin develop; g "$w" fetch -q origin

# develop improves while a session runs (a marker goes away): a branch cut
# before it, with a neutral change of its own, is not blamed, merged or not
branch fix-old; edit fix-old README.md 'neutral'
printf 'a\n' > "$s/dw/a.py"; g "$s" commit -qam "refactor: one less complex function"; g "$s" push origin develop
g "$w" fetch -q origin
hrow 0 "cut before an improvement, not merged with it"
g "$w" merge -q --no-edit origin/develop
hrow 0 "merged a newer develop's improvement, none of its own change"
# ...and a regression of its own is still caught against its merge base
edit fix-old dw/a.py '# complex'
hrow 2 "the merged branch's own regression"
has "  measured from the merge base (develop itself, once merged)" "complex_functions: 0 -> 1" "$out"

# the script on develop is what counts, not the branch's own copy: an older
# one that doesn't know a metric can't hide it, and a rewritten one can't lie
branch fix-old-script
script v0 "" | sed 's/^    metrics = .*$/    metrics = {"modules": len(text)}/' > "$w/scripts/arch_metrics.py"; g "$w" add -A; g "$w" commit -m "older script"
edit fix-old-script dw/a.py '# complex'
hrow 2 "a regression under a branch whose script is older (measured by develop's)"
has "  counted by develop's script" "complex_functions: 0 -> 1" "$out"
branch fix-liar
printf 'import json, sys\nprint(json.dumps({"modules": 0, "complex_functions": 0}))\n' > "$w/scripts/arch_metrics.py"; g "$w" add -A; g "$w" commit -m liar
edit fix-liar dw/a.py '# complex'
hrow 2 "a branch that rewrites the script to report zeros"
# develop's script grows a metric; a branch measured with it is compared on it, key by key
script v2 'metrics["todos"] = sum(t.count("# todo") for t in text)' > "$s/scripts/arch_metrics.py"; g "$s" commit -qam "metrics v2"; g "$s" push origin develop
branch fix-todo; edit fix-todo dw/b.py '# todo'
hrow 2 "a metric only develop's script knows"
has "  named with both values" "todos: 0 -> 1" "$out"

# a push of develop is checked the same way, with no issue in the session
branch fix-push; edit fix-push dw/a.py '# complex'
g "$w" checkout -q -B develop fix-push
prow 2 "develop carrying a regression" 'git push origin develop'
has "  push message names it" "complex_functions: 0 -> 1" "$out"
prow 2 "the same push, spelled fix-push:develop" 'git push origin fix-push:develop'
prow 0 "a push of a topic branch is not develop" 'git push origin fix-push'
branch fix-push2; edit fix-push2 README.md 'ok'; g "$w" checkout -q -B develop fix-push2
prow 0 "develop with no regression" 'git push origin develop'

# a script that can't run fails closed, with the install command; so do missing tools
printf 'import grimp_absent_from_this_venv\n' | cat - "$s/scripts/arch_metrics.py" > "$T/broken.py"
cp "$T/broken.py" "$s/scripts/arch_metrics.py"; g "$s" commit -qam "script needs a tool"; g "$s" push origin develop
branch fix-broken; edit fix-broken README.md 'neutral'
hrow 2 "the script fails to import"
has "  names the missing tool" "grimp_absent_from_this_venv" "$out"
has "  gives the install command" "pip install -e '.[dev]'" "$out"
HARNEST_ARCH_TOOLS="json some_tool_nobody_installed" hrow 2 "a required tool is not installed"
has "  names it before running anything" "some_tool_nobody_installed" "$out"
ok "  ready says so, and lists it" bash -c "HARNEST_ARCH_TOOLS='json some_tool_nobody_installed' python3 '$HARNEST/lib/arch_ratchet.py' ready '$w' | grep -q some_tool_nobody_installed"
ok "  ready is quiet when the tools import" python3 "$HARNEST/lib/arch_ratchet.py" ready "$w"
# ...and a garbage script (prints no JSON) is the same
printf 'print("not json")\n' > "$s/scripts/arch_metrics.py"; g "$s" commit -qam "script prints nothing useful"; g "$s" push origin develop
hrow 2 "the script prints no JSON"

# no script on origin/develop: the ratchet is off, and asks for nothing
w2="$T/b/work"; g "$w2" checkout -q -B fix-x origin/develop; echo more >> "$w2/dw/a.py"; g "$w2" commit -qam x
hrow 0 "the ratchet is off while develop has no script" "$w2"
HARNEST_ARCH_TOOLS="json some_tool_nobody_installed" hrow 0 "  and its tools aren't asked for then" "$w2"
ok "  ready is quiet then" python3 "$HARNEST/lib/arch_ratchet.py" ready "$w2"

# origin/develop that can't be read is a broken environment, not "off": the
# clone that just passed above (no script on develop) has its remote broken
g "$w2" remote set-url origin "$T/nowhere.git"
hrow 2 "the fetch of origin/develop fails (remote unreachable)" "$w2"
has "  says the baseline could not be read" "baseline could not be read" "$out"
has "  says how to fix it" "git fetch origin" "$out"
g "$w2" remote remove origin
hrow 2 "no origin remote at all" "$w2"
has "  same message" "baseline could not be read" "$out"
git init -q -b develop "$T/bare-clone"; g "$T/bare-clone" -c commit.gpgsign=false commit -q --allow-empty -m x
git init -q --bare "$T/empty.git"; g "$T/bare-clone" remote add origin "$T/empty.git"
hrow 2 "origin exists but has no develop branch" "$T/bare-clone"
fails "  ready refuses to call that ready" python3 "$HARNEST/lib/arch_ratchet.py" ready "$T/bare-clone"

# the cache keys on tree, script and tool versions: same trees, changed
# script -> measured again; same script, other versions -> measured again
mkdir "$T/c"; mk "$T/c" 1; w="$T/c/work"; s="$T/c/seed"
branch fix-cache; edit fix-cache dw/a.py '# complex'
hrow 2 "cache: first measurement"
has "  counts one marker each" "complex_functions: 1 -> 2" "$out"
n1="$(ls "$w/.git/harnest-arch" | wc -l | tr -d ' ')"
hrow 2 "cache: repeated, from the stamps"
eq "  a repeat adds no stamp" "$n1" "$(ls "$w/.git/harnest-arch" | wc -l | tr -d ' ')"
script v1b 'metrics["complex_functions"] *= 10' > "$s/scripts/arch_metrics.py"; g "$s" commit -qam "script counts differently"; g "$s" push origin develop
hrow 2 "cache: same trees, changed script"
has "  re-measured by the new script" "complex_functions: 10 -> 20" "$out"
ok "  and stamped separately" test "$(ls "$w/.git/harnest-arch" | wc -l | tr -d ' ')" -gt "$n1"
ok "cache_key: same inputs, same key; any one changed, another key" python3 - "$HARNEST/lib" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); from arch_ratchet import cache_key as k
base = k("t1", "script", {"ruff": "1"})
assert base == k("t1", "script", {"ruff": "1"})
assert len({base, k("t2", "script", {"ruff": "1"}), k("t1", "script2", {"ruff": "1"}), k("t1", "script", {"ruff": "2"}), k("t1", "script", {"ruff": "1", "grimp": "1"})}) == 5
PY

# results are cached by tree, so a repeated hand-off measures nothing new
ok "the measurements are stamped in the checkout's git dir" bash -c "ls '$w/.git/harnest-arch' | grep -q json"
finish
