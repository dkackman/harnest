#!/usr/bin/env bash
# The UI's architecture ratchet (lib/arch_ratchet.py's check_ui, guard.py's
# arch_gate) on small fixture repos: a throwaway origin whose develop
# carries a dependency-free stand-in for dw's ui/scripts/arch-metrics.mjs
# and no engine script, so only the UI ratchet is on. Never the real dw.
# The stand-in counts `// complex` lines under ui/src and implements the
# real script's `--compare` and `key: before -> after` lines.
. "$(dirname "$0")/lib.sh"
guard="$HARNEST/agent-settings/hooks/guard.py"
# A rise asks GitHub whether the issue carries arch-approved: #7 does, #8 doesn't
stub_gh 'case "$*" in *"view 7"*) echo true ;; *"view 8"*) echo false ;; *) exit 1 ;; esac'

g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}" >/dev/null 2>&1; }
uiscript() {  # uiscript [compare 1|0]: the stand-in; without compare it predates --compare
  cat <<EOF
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
const UI = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const walk = (d) => readdirSync(d).flatMap((n) => statSync(join(d, n)).isDirectory() ? walk(join(d, n)) : [join(d, n)])
const regressions = (cur, base) => Object.entries(cur)
  .filter(([k, v]) => k in base && v > base[k]).map(([k, v]) => \`\${k}: \${base[k]} -> \${v}\`)
const argv = process.argv.slice(2)
if (${1:-1} && argv[0] === '--compare') {
  const [c, b] = argv.slice(1, 3).map((p) => JSON.parse(readFileSync(p, 'utf8')))
  const lines = regressions(c, b); for (const l of lines) console.log(l); process.exit(lines.length ? 1 : 0)
}
const text = walk(join(UI, 'src')).map((f) => readFileSync(f, 'utf8'))
console.log(JSON.stringify({ complex_functions: text.join('').split('// complex').length - 1,
  files: text.length, detail: { note: 'ignored' } }, null, 2))
EOF
}
mk() {  # mk <dir> <with-ui-script 0|1>: origin + seed + clone, ui/src at one complex marker
  git init -q --bare "$1/origin.git"; git init -q -b develop "$1/seed"
  mkdir -p "$1/seed/dw" "$1/seed/ui/src" "$1/seed/ui/scripts" "$1/seed/docs/stabilization/ui"
  echo a > "$1/seed/dw/a.py"; printf 'x\n// complex\n' > "$1/seed/ui/src/a.ts"
  printf 'ui/node_modules/\n' > "$1/seed/.gitignore"
  printf '{\n  "complex_functions": 1,\n  "files": 1\n}\n' > "$1/seed/docs/stabilization/ui/baseline.json"
  [ "$2" = 1 ] && uiscript > "$1/seed/ui/scripts/arch-metrics.mjs"
  g "$1/seed" add -A; g "$1/seed" commit -m base; g "$1/seed" remote add origin "$1/origin.git"; g "$1/seed" push origin develop
  git clone -q -b develop "$1/origin.git" "$1/work"
  mkdir -p "$1/work/ui/node_modules/eslint"; printf '{"version": "0.0.0"}\n' > "$1/work/ui/node_modules/eslint/package.json"
}
mkdir "$T/a" "$T/b"; mk "$T/a" 1; mk "$T/b" 0
w="$T/a/work"; s="$T/a/seed"
branch() { g "$w" checkout -q -B "$1" origin/develop; }
edit() { mkdir -p "$w/$(dirname "$2")"; printf '%s\n' "$3" >> "$w/$2"; g "$w" add -A; g "$w" commit -m "$1 $2"; }
hrow() {  # hrow <expect> <name> [dir] [issue]: the hand-off from that checkout's HEAD
  out="$(jq -n --arg c "gh issue edit ${4:-8} --remove-label owner:implementer --add-label owner:tester --add-label status:fixed-pending-verify" \
     --arg d "${3:-$w}" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | python3 "$guard" implementer 2>&1 >/dev/null)"
  eq "ui ratchet hand-off: $2" "$1" $?
}

ok "node is on PATH (the UI ratchet runs the script with it)" command -v node

branch ui-worse; edit ui-worse ui/src/b.ts '// complex'
hrow 2 "a complex function added under ui/src"
has "  names the metric and both values" "complex_functions: 1 -> 2" "$out"
has "  says it is the UI's ratchet" "UI" "$out"
has "  names the UI baseline" "docs/stabilization/ui/baseline.json" "$out"
has "  says how to bring it down, in the UI's terms" "split the component" "$out"
fails "  not with the engine's Python hints" grep -q "patch.object" <<<"$out"
branch ui-dw; edit ui-dw dw/b.py 'engine only'
hrow 0 "a change outside ui/ measures no UI rise"
branch ui-same; edit ui-same ui/src/a.ts 'plain line'
hrow 0 "a UI change that moves no metric"

why='baseline: raise complex_functions 1 -> 2

the new widget needs the branch (approved on the issue).'
raise() {  # raise <n> <message>
  printf '{\n  "complex_functions": %s,\n  "files": 1\n}\n' "$1" > "$w/docs/stabilization/ui/baseline.json"
  g "$w" add -A; g "$w" commit -m "$2"
}
branch ui-ok; edit ui-ok ui/src/a.ts '// complex'; raise 2 "$why"
hrow 0 "with arch-approved and the matching UI baseline raise" "$w" 7
hrow 2 "  the same commits without the label" "$w" 8
branch ui-big; edit ui-big ui/src/a.ts '// complex'; raise 3 "$why"
hrow 2 "  a UI raise bigger than the rise" "$w" 7
has "  says by how much" "should raise it to 2, not 3" "$out"

# fail closed: no installed UI tools in the checkout
rm -rf "$w/ui/node_modules"
branch ui-notools; edit ui-notools ui/src/a.ts '// complex'
hrow 2 "the checkout has no ui/node_modules"
has "  names the fix" "npm ci" "$out"
mkdir -p "$w/ui/node_modules/eslint"; printf '{"version": "0.0.0"}\n' > "$w/ui/node_modules/eslint/package.json"

# fail closed: develop's script predates --compare (prints JSON instead)
uiscript 0 > "$s/ui/scripts/arch-metrics.mjs"; g "$s" commit -qam "script without --compare"; g "$s" push origin develop
g "$w" fetch -q origin
branch ui-old; edit ui-old ui/src/a.ts '// complex'
hrow 2 "develop's UI script has no --compare"
has "  says the script cannot compare" "--compare" "$out"
has "  and, since no branch can fix develop's script, to park for Don" "--add-label owner:don" "$out"

# a --compare that crashes (node exits 1, prints nothing) is not a pass
uiscript > "$s/ui/scripts/arch-metrics.mjs"
printf "\nif (process.argv[2] === '--compare-crash') throw new Error('x')\n" >> "$s/ui/scripts/arch-metrics.mjs"
sed -i.bak "s/argv\[0\] === '--compare'/argv[0] === '--never'/" "$s/ui/scripts/arch-metrics.mjs"; rm -f "$s/ui/scripts/arch-metrics.mjs.bak"
printf "if (process.argv[2] === '--compare') throw new Error('compare crashed')\n" | cat - "$s/ui/scripts/arch-metrics.mjs" > "$T/crash.mjs"; cp "$T/crash.mjs" "$s/ui/scripts/arch-metrics.mjs"
g "$s" commit -qam "script whose --compare crashes"; g "$s" push origin develop; g "$w" fetch -q origin
branch ui-crash; edit ui-crash ui/src/a.ts '// complex'
hrow 2 "a --compare that crashes is refused, not passed"
has "  as a tool failure" "fails closed" "$out"
uiscript > "$s/ui/scripts/arch-metrics.mjs"; g "$s" commit -qam "working script again"; g "$s" push origin develop; g "$w" fetch -q origin

# a corrupted cached measurement is measured again, not trusted
branch ui-stamp; edit ui-stamp ui/src/b.ts '// complex'
hrow 2 "a rise, measured and stamped"
for f in "$w/.git/harnest-arch-ui"/*.json; do : > "$f"; done
hrow 2 "  the same rise with every stamp truncated"
has "  still named" "complex_functions: 1 -> 2" "$out"

# a failure that is not a ToolError is a deny, not a traceback the hook ignores
chmod 500 "$w/.git/harnest-arch-ui"; rm -f "$w/.git/harnest-arch-ui"/*.json 2>/dev/null
branch ui-perm; edit ui-perm ui/src/c.ts '// complex'
hrow 2 "the stamp cannot be written (an OSError)"
has "  says the ratchet could not run" "fails closed" "$out"
chmod 700 "$w/.git/harnest-arch-ui"

# a different install measures again: the lockfile is part of the cache key
n1="$(ls "$w/.git/harnest-arch-ui" | wc -l | tr -d ' ')"
printf '{"lockfileVersion": 3, "x": 1}\n' > "$w/ui/node_modules/.package-lock.json"
hrow 2 "  same trees, another install"
ok "  measured afresh (a new stamp)" test "$(ls "$w/.git/harnest-arch-ui" | wc -l | tr -d ' ')" -gt "$n1"

# no UI script on develop: the UI ratchet is off
w2="$T/b/work"; g "$w2" checkout -q -B ui-x origin/develop; echo '// complex' >> "$w2/ui/src/a.ts"; g "$w2" commit -qam x
hrow 0 "the UI ratchet is off while develop has no UI script" "$w2"
# the driver installs the UI's tools when the UI ratchet is on and they are missing
export TICKET_REPO=o/r TICKET_OWNER=me
. "$HARNEST/providers.sh"
HARNEST_LIB="$HARNEST/lib"; LOOP_LOG="$T/loop.log"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "npm $*" >> "%s/npm.log"\n' "$T" > "$T/bin/npm"; chmod +x "$T/bin/npm"
rm -rf "$w/ui/node_modules"
PATH="$T/bin:$PATH" ensure_ui_tools "$w"
has "ensure_ui_tools runs npm ci for ui/ when node_modules is missing" "npm ci --prefix ui" "$(cat "$T/npm.log" 2>/dev/null)"
mkdir -p "$w/ui/node_modules/eslint"; printf '{"version": "0.0.0"}\n' > "$w/ui/node_modules/eslint/package.json"
rm -f "$T/npm.log"; PATH="$T/bin:$PATH" ensure_ui_tools "$w"
eq "  and does nothing when they are there" "" "$(cat "$T/npm.log" 2>/dev/null)"
rm -f "$T/npm.log"; PATH="$T/bin:$PATH" ensure_ui_tools "$w2"
eq "  nor when develop has no UI script" "" "$(cat "$T/npm.log" 2>/dev/null)"
printf '{"lockfileVersion": 3}\n' > "$s/ui/package-lock.json"; g "$s" add -A; g "$s" commit -qm "a lockfile"; g "$s" push origin develop; g "$w" fetch -q origin
rm -f "$T/npm.log"; PATH="$T/bin:$PATH" ensure_ui_tools "$w"
has "  a lockfile on develop it has not installed from: npm ci" "npm ci --prefix ui" "$(cat "$T/npm.log" 2>/dev/null)"
rm -f "$T/npm.log"; PATH="$T/bin:$PATH" ensure_ui_tools "$w"
eq "  and not again for the same lockfile" "" "$(cat "$T/npm.log" 2>/dev/null)"
printf '{"lockfileVersion": 3, "bumped": 1}\n' > "$s/ui/package-lock.json"; g "$s" commit -qam "lockfile bump"; g "$s" push origin develop; g "$w" fetch -q origin
rm -f "$T/npm.log"; PATH="$T/bin:$PATH" ensure_ui_tools "$w"
has "  a bumped lockfile on develop: npm ci again" "npm ci --prefix ui" "$(cat "$T/npm.log" 2>/dev/null)"

# --- both ratchets on at once: develop carries the engine's script and the UI's
export HARNEST_ARCH_TOOLS="json"   # the engine stand-in needs only the standard library
enginescript() {
  cat <<'EOF2'
import argparse, json, pathlib
def measure(root):
    text = [p.read_text() for p in sorted((pathlib.Path(root) / "dw").rglob("*.py"))]
    return {"complex_functions": sum(t.count("# complex") for t in text)}
def regressions(current, baseline):
    return [f"{k}: {v} -> {current[k]}" for k, v in baseline.items() if k in current and current[k] > v]
if __name__ == "__main__":
    p = argparse.ArgumentParser(); p.add_argument("--root"); a = p.parse_args()
    print(json.dumps(measure(a.root), indent=2))
EOF2
}
mkdir "$T/c"; mk "$T/c" 1
c="$T/c/seed"; mkdir -p "$c/scripts"; enginescript > "$c/scripts/arch_metrics.py"
printf 'a\n# complex\n' > "$c/dw/a.py"
printf '{\n  "complex_functions": 1\n}\n' > "$c/docs/stabilization/baseline.json"
g "$c" add -A; g "$c" commit -m "engine ratchet too"; g "$c" push origin develop
w="$T/c/work"; g "$w" fetch -q origin
both() {  # both <branch>: one complex function more on each side
  branch "$1"; edit "$1" dw/a.py '# complex'; edit "$1" ui/src/a.ts '// complex'
}
both dual-bare
hrow 2 "both ratchets rise: refused"
has "  naming the engine's rise" "dw's architecture ratchet" "$out"
has "  and the UI's, in the same refusal" "dw's UI architecture ratchet" "$out"
engine_why='baseline: raise complex_functions 1 -> 2

the engine side of the widget (approved on the issue).'
both dual-half
printf '{\n  "complex_functions": 2\n}\n' > "$w/docs/stabilization/baseline.json"; g "$w" add -A; g "$w" commit -m "$engine_why"
hrow 2 "  the engine's waiver complete, the UI's not" "$w" 7
has "  names the UI's missing raise" "docs/stabilization/ui/baseline.json" "$out"
fails "  and not the engine's, which holds" grep -q "dw's architecture ratchet:" <<<"$out"
raise 2 "$why"
hrow 0 "  both waivers complete" "$w" 7
finish
