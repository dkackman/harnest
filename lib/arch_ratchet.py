#!/usr/bin/env python3
"""The architecture-metrics ratchet (stage B): a session's own commits may not
make any of dw's scripts/arch_metrics.py numbers worse.

    python3 lib/arch_ratchet.py check <checkout> [src]   exit 0 ok, 1 regressed, 2 tool failure
    python3 lib/arch_ratchet.py ready <checkout>         exit 0 when the tools import (or the ratchet is off)
    python3 lib/arch_ratchet.py active <checkout>        exit 0 while on, 1 off, 2 can't tell (no fetch)

"Worse" is HEAD (or src) against its merge base with origin/develop, never
against docs/stabilization/baseline.json: the refactor improves develop while
sessions run, and a branch cut before an improvement must not be blamed for
missing it (the same "own commits" rule as lib/freeze.py's three dots).

Both trees are measured with the script as it stands on origin/develop, run
as `python <script> --root <tree>`, so a branch whose own copy is older still
counts by today's rules. Measurements are cached per tree, keyed on the script's sha256 and the tools'
versions too (cache_key). Trees come out of `git archive`, never a checkout in
the session's worktree. The comparison is the script's own regressions(),
loaded from that same file, key by key, skipping a key either side lacks.

On while scripts/arch_metrics.py exists on origin/develop, FREEZE or not.
A script that cannot run raises ToolError: the caller fails closed. guard.py
(hand-off, push of develop) and the driver (ensure_arch_tools) both use this.

One waiver (stage C): Don's `arch-approved` on the issue, honoured only with
its paperwork (waiver_problems): the same commits raise
docs/stabilization/baseline.json by exactly the metrics that rose, in a
commit whose message names each and says why. That check is the only
reader of baseline.json; the detector never compares against it.
"""
import hashlib, importlib.util, json, os, re, shutil, subprocess, sys, tempfile

REF = "origin/develop"
SCRIPT = "scripts/arch_metrics.py"
BASELINE = "docs/stabilization/baseline.json"
# The UI's half (dw's UI stabilization Phase 4): measured by its own node
# script, compared by that script's `--compare`, waived the same way
UI_SCRIPT = "ui/scripts/arch-metrics.mjs"
UI_BASELINE = "docs/stabilization/ui/baseline.json"
PYPROJECT = "pyproject.toml"
INSTALL = "pip install -e '.[dev]'"
# What the script imports beyond the standard library (grimp comes with
# import-linter), and the module each is imported as.
# HARNEST_ARCH_TOOLS overrides the list, for tests that measure a stdlib-only fixture script.
TOOLS = tuple(os.environ.get("HARNEST_ARCH_TOOLS", "grimp networkx pylint pygount ruff").split())


class ToolError(Exception):
    """The metrics script couldn't run; the message names the fix."""


def _git(checkout, *args, **kw):
    return subprocess.run(["git", "-C", checkout, *args], capture_output=True, text=True, **kw)


def active(checkout, fetch=True, script=SCRIPT):
    """True when origin/develop carries the script, False when it is readable
    and doesn't. Off only in that second case: a failed fetch, a missing
    remote or an unreadable origin/develop is a broken environment, and
    raises ToolError so the caller refuses (an old ref would be a guess)."""
    fix = "run `git fetch origin develop` in %s and check that `origin` is reachable" % checkout
    if fetch:
        r = _git(checkout, "fetch", "-q", "origin", "develop")
        if r.returncode != 0:
            raise ToolError("the baseline could not be read: fetching origin/develop failed (%s). The "
                            "architecture ratchet fails closed: %s." % (r.stderr.strip()[-200:] or "no detail", fix))
    if _git(checkout, "rev-parse", "-q", "--verify", REF + "^{commit}").returncode != 0:
        raise ToolError("the baseline could not be read: %s does not resolve. The architecture ratchet "
                        "fails closed: %s." % (REF, fix))
    return _git(checkout, "cat-file", "-e", "%s:%s" % (REF, script)).returncode == 0


def python_for(checkout):
    """The interpreter dw runs on: the checkout's venv, else this one."""
    top = _git(checkout, "rev-parse", "--show-toplevel").stdout.strip() or checkout
    venv = os.path.join(top, "venv", "bin", "python")
    return venv if os.path.exists(venv) else sys.executable


def _install_hint(python):
    return "install dw's dev extras: `%s -m %s` from the dw checkout" % (python, INSTALL)


def _missing(python):
    """The tools `python` can't import, by module name."""
    code = "import importlib.util as u; print(' '.join(m for m in %r if u.find_spec(m) is None))" % (TOOLS,)
    r = subprocess.run([python, "-c", code], capture_output=True, text=True)
    return r.stdout.split() if r.returncode == 0 else list(TOOLS)


DISTRIBUTIONS = ("ruff", "grimp", "networkx", "pylint", "pygount")


def _versions(python):
    """Installed version of each tool the script leans on, under `python`."""
    code = ("import importlib.metadata as m, json\nout = {}\nfor d in %r:\n try: out[d] = m.version(d)\n"
            " except m.PackageNotFoundError: out[d] = None\nprint(json.dumps(out))" % (DISTRIBUTIONS,))
    r = subprocess.run([python, "-c", code], capture_output=True, text=True)
    return json.loads(r.stdout) if r.returncode == 0 else {}


def cache_key(tree, script_text, versions):
    """One measurement's identity: the tree, the exact script that counted it,
    and the tools' versions, so a changed script or a reinstall re-measures."""
    parts = [tree, hashlib.sha256(script_text.encode()).hexdigest(), json.dumps(versions, sort_keys=True)]
    return hashlib.sha256("\n".join(parts).encode()).hexdigest()


def _load_regressions(script):
    try:
        spec = importlib.util.spec_from_file_location("arch_metrics_develop", script)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)  # stdlib imports only at the top of the script
        return mod.regressions
    except Exception as e:  # a script that can't even load is a tool failure, not a pass
        raise ToolError("scripts/arch_metrics.py did not load (%s: %s). The architecture ratchet fails closed." % (type(e).__name__, e))


def _archive(checkout, treeish, dest, paths=()):
    git = subprocess.Popen(["git", "-C", checkout, "archive", treeish, *paths], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    tar = subprocess.run(["tar", "-x", "-C", dest], stdin=git.stdout, capture_output=True)
    git.stdout.close()
    if git.wait() or tar.returncode:
        raise ToolError("could not extract %s from %s: %s" % (treeish, checkout, (git.stderr.read() + tar.stderr)[-300:].decode(errors="replace")))


def _measure(script, tree, python):
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}  # grimp must see `tree`'s dw, not another
    r = subprocess.run([python, script, "--root", tree], capture_output=True, text=True, cwd=tree, env=env)
    if r.returncode != 0:
        gone = re.search(r"No module named '([\w.]+)'", r.stderr)
        what = "needs %s, which is not installed" % gone.group(1).split(".")[0] if gone else "failed (exit %d): %s" % (r.returncode, r.stderr[-400:].strip())
        raise ToolError("scripts/arch_metrics.py %s. The architecture ratchet fails closed: %s." % (what, _install_hint(python)))
    try:  # the JSON comes first; `warning:` lines for a module near the size ceiling follow it
        return json.JSONDecoder().raw_decode(r.stdout.lstrip())[0]
    except ValueError:
        raise ToolError("scripts/arch_metrics.py printed no JSON: %s" % r.stdout[-300:])


def check(checkout, src="HEAD", python=None):
    """[] when src's own commits made no metric worse (or the ratchet is off),
    else 'metric: before -> after' lines. Raises ToolError when it can't say
    (including an origin/develop that can't be read: see active)."""
    if not active(checkout):
        return []
    python = python or python_for(checkout)
    missing = _missing(python)
    if missing:
        raise ToolError("the architecture ratchet needs %s, which %s cannot import. It fails closed: %s."
                        % (", ".join(missing), python, _install_hint(python)))
    base = _git(checkout, "merge-base", REF, src).stdout.strip()
    if not base:
        raise ToolError("no merge base between %s and %s, so the ratchet can't tell what this work changed." % (REF, src))
    trees = [_git(checkout, "rev-parse", "-q", "--verify", r + "^{tree}").stdout.strip() for r in (base, src)]
    if not all(trees):
        raise ToolError("could not read the trees of %s and %s." % (base[:10], src))
    if trees[0] == trees[1]:
        return []
    script_text = _git(checkout, "show", "%s:%s" % (REF, SCRIPT)).stdout
    versions = _versions(python)
    gitdir = _git(checkout, "rev-parse", "--absolute-git-dir").stdout.strip()
    cache = os.path.join(gitdir, "harnest-arch")
    os.makedirs(cache, exist_ok=True)
    work = tempfile.mkdtemp(prefix="harnest-arch-")
    try:
        script = os.path.join(work, "arch_metrics.py")
        with open(script, "w") as fh:
            fh.write(script_text)
        measured = []
        for tree in trees:  # by tree, so an unchanged tree (or a repeated hand-off) is measured once
            stamp = os.path.join(cache, cache_key(tree, script_text, versions) + ".json")
            if os.path.exists(stamp):
                measured.append(json.load(open(stamp)))
                continue
            dest = os.path.join(work, tree)
            os.mkdir(dest)
            _archive(checkout, tree, dest)
            metrics = _measure(script, dest, python)
            shutil.rmtree(dest, ignore_errors=True)
            with open(stamp, "w") as fh:
                json.dump(metrics, fh)
            measured.append(metrics)
        return _load_regressions(script)(measured[1], measured[0])
    finally:
        shutil.rmtree(work, ignore_errors=True)


UI_INPUTS = ("ui", "dw/references.py")  # what the UI script reads: its tree, and the prefixes' owner


def _ui_tools(checkout):
    """node, and the checkout's ui/node_modules (ESLint), or ToolError."""
    top = _git(checkout, "rev-parse", "--show-toplevel").stdout.strip() or checkout
    modules = os.path.join(top, "ui", "node_modules")
    fix = "run `npm ci --prefix ui` in %s" % top
    node = shutil.which("node")
    if node is None:
        raise ToolError("the UI architecture ratchet needs node, which is not on PATH. It fails closed: install "
                        "Node, then %s." % fix)
    if not os.path.exists(os.path.join(modules, "eslint", "package.json")):
        raise ToolError("the UI architecture ratchet needs ui/node_modules (ESLint), which %s does not have. "
                        "It fails closed: %s." % (top, fix))
    return node, modules


def _ui_versions(node, modules):
    """What a measurement depends on besides the tree and the script: node,
    and the whole installed toolchain - the lockfile npm wrote, so a parser
    bump that leaves eslint's own version alone still measures afresh."""
    node_version = subprocess.run([node, "--version"], capture_output=True, text=True).stdout.strip()
    try:
        eslint = json.load(open(os.path.join(modules, "eslint", "package.json"))).get("version")
    except (OSError, ValueError):
        eslint = None
    try:
        with open(os.path.join(modules, ".package-lock.json"), "rb") as fh:
            installed = hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        installed = None
    return {"node": node_version, "eslint": eslint, "installed": installed}


def _read_stamp(stamp):
    """A cached measurement, or None when it is missing or unreadable (a
    write cut short) - then it is measured again rather than trusted."""
    try:
        with open(stamp) as fh:
            metrics = json.load(fh)
    except (OSError, ValueError):
        return None
    return metrics if isinstance(metrics, dict) and metrics else None


def _write_stamp(stamp, metrics):
    tmp = stamp + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(metrics, fh)
    os.replace(tmp, stamp)


RISE = re.compile(r"^\S+: \S+ -> \S+$")


def _ui_tree(checkout, treeish, work, script_text, modules):
    """An extracted tree with develop's UI script in place and the checkout's
    node_modules beside it, so its imports (ESLint) resolve. Returns ui/."""
    dest = tempfile.mkdtemp(dir=work)
    present = [p for p in UI_INPUTS if _git(checkout, "cat-file", "-e", "%s:%s" % (treeish, p)).returncode == 0]
    _archive(checkout, treeish, dest, present)
    ui = os.path.join(dest, "ui")
    os.makedirs(os.path.join(ui, "scripts"), exist_ok=True)
    os.symlink(modules, os.path.join(ui, "node_modules"))
    with open(os.path.join(ui, UI_SCRIPT[len("ui/"):]), "w") as fh:
        fh.write(script_text)
    return ui


def check_ui(checkout, src="HEAD"):
    """check, for the UI: [] when src's own commits made none of the UI's
    metrics worse than at their merge base (or the UI ratchet is off), else
    'metric: before -> after' lines - develop's ui/scripts/arch-metrics.mjs
    measures both trees and its `--compare` says which rose. Raises
    ToolError when it can't say."""
    if not active(checkout, script=UI_SCRIPT):
        return []
    base = _git(checkout, "merge-base", REF, src).stdout.strip()
    if not base:
        raise ToolError("no merge base between %s and %s, so the UI ratchet can't tell what this work changed." % (REF, src))

    def inputs(rev):
        return [_git(checkout, "rev-parse", "-q", "--verify", "%s:%s" % (rev, path)).stdout.strip() for path in UI_INPUTS]
    if inputs(base) == inputs(src):
        return []
    node, modules = _ui_tools(checkout)
    script_text = _git(checkout, "show", "%s:%s" % (REF, UI_SCRIPT)).stdout
    versions = _ui_versions(node, modules)
    gitdir = _git(checkout, "rev-parse", "--absolute-git-dir").stdout.strip()
    cache = os.path.join(gitdir, "harnest-arch-ui")
    os.makedirs(cache, exist_ok=True)
    work = tempfile.mkdtemp(prefix="harnest-arch-ui-")
    try:
        measured = []
        for rev in (base, src):
            tree = _git(checkout, "rev-parse", "-q", "--verify", rev + "^{tree}").stdout.strip()
            stamp = os.path.join(cache, cache_key(tree, script_text, versions) + ".json")
            if _read_stamp(stamp) is not None:
                measured.append(stamp)
                continue
            ui = _ui_tree(checkout, rev, work, script_text, modules)
            r = subprocess.run([node, UI_SCRIPT[len("ui/"):]], capture_output=True, text=True, cwd=ui)
            if r.returncode != 0:
                raise ToolError("ui/scripts/arch-metrics.mjs failed (exit %d): %s. The UI architecture ratchet "
                                "fails closed: run `npm ci --prefix ui` in the dw checkout." % (r.returncode, r.stderr[-400:].strip()))
            try:
                metrics = json.JSONDecoder().raw_decode(r.stdout.lstrip())[0]
            except ValueError:
                raise ToolError("ui/scripts/arch-metrics.mjs printed no JSON: %s" % r.stdout[-300:])
            metrics.pop("detail", None)
            _write_stamp(stamp, metrics)
            measured.append(stamp)
        ui = _ui_tree(checkout, src, work, script_text, modules)
        r = subprocess.run([node, UI_SCRIPT[len("ui/"):], "--compare", measured[1], measured[0]],
                           capture_output=True, text=True, cwd=ui)
        # The contract: exit 0 and nothing printed, or exit 1 and only rise
        # lines. Anything else - a crash (node exits 1 too), a script that
        # predates --compare and prints JSON - is a failure, never a pass
        lines = [line for line in r.stdout.splitlines() if line.strip()]
        if not ((r.returncode == 0 and not lines)
                or (r.returncode == 1 and lines and all(RISE.match(line) for line in lines))):
            raise ToolError("develop's ui/scripts/arch-metrics.mjs could not compare two measurements (exit %d: %s). "
                            "The UI architecture ratchet fails closed until it can: develop's script needs a working "
                            "--compare." % (r.returncode, (r.stderr.strip() or r.stdout.strip())[-200:] or "no output"))
        return lines
    finally:
        shutil.rmtree(work, ignore_errors=True)


def _number(text):
    try:
        return json.loads(text)
    except ValueError:
        return None


def waiver_problems(checkout, worse, src="HEAD", baseline=BASELINE):
    """The `arch-approved` waiver's paperwork for these regressions (check's
    lines): [] when src's own commits raise baseline.json by exactly the
    metrics that rose, each by the amount it rose, and every raised key is
    named, with its new value, in the message of a commit that changes the
    file, which also has a body (the why). Else what is missing, one line each."""
    rose, problems = {}, []
    for line in worse:
        m = re.match(r"^(\S+): (\S+) -> (\S+)$", line)
        old, new = (_number(m.group(2)), _number(m.group(3))) if m else (None, None)
        if not all(isinstance(v, (int, float)) for v in (old, new)):
            problems.append("%r is not a numeric rise the waiver can match" % line)
            continue
        rose[m.group(1)] = (old, new)
    base = _git(checkout, "merge-base", REF, src).stdout.strip()

    def baseline_at(rev):
        r = _git(checkout, "show", "%s:%s" % (rev, baseline))
        try:
            return json.loads(r.stdout) if r.returncode == 0 else None
        except ValueError:
            return None
    before, after = baseline_at(base) if base else None, baseline_at(src)
    if after is None:
        return ["%s is missing or unreadable at %s" % (baseline, src)]
    before = before or {}
    raised = {k: v for k, v in after.items()
              if isinstance(v, (int, float)) and (not isinstance(before.get(k), (int, float)) or v > before[k])}
    for k, (old, new) in sorted(rose.items()):
        if k not in raised:
            problems.append("%s rose %s -> %s, and %s does not raise it" % (k, old, new, baseline))
            continue
        want = new if not isinstance(before.get(k), (int, float)) else before[k] + (new - old)
        if raised[k] != want:
            problems.append("%s rose by %s, so %s should raise it to %s, not %s"
                            % (k, new - old, baseline, want, raised[k]))
    for k in sorted(set(raised) - set(rose)):
        problems.append("%s raises %s, which did not rise" % (baseline, k))
    log = _git(checkout, "log", "--format=%B%x1e", "%s..%s" % (base, src), "--", baseline).stdout if base else ""
    messages = [m.strip() for m in log.split("\x1e") if m.strip()]
    for k in sorted(set(raised) & set(rose)):
        if not any(re.search(r"\b%s\b" % re.escape(k), m) and re.search(r"\b%s\b" % re.escape(str(raised[k])), m)
                   and len(m.splitlines()) > 1 for m in messages):
            problems.append("no commit changing %s names the %s rise to %s and says why in its body"
                            % (baseline, k, raised[k]))
    return problems


def refusal(worse, problems=None, baseline=BASELINE, what="dw's architecture metrics"):
    """The message a regression earns: each metric, then the way out.
    problems: the waiver's missing paperwork, when the issue carries the label."""
    out = ("this work's own commits make %s worse than their merge base with %s: %s. "
           "Bring the number back down in this session: split the function, remove the duplicate, reuse an "
           "existing module instead of adding one, patch with `patch.object` or an injected fake instead of a "
           "`patch(\"dw...\")` string. " % (what, REF, "; ".join(worse)))
    if problems:
        return out + ("The issue carries `arch-approved`, but the waiver's paperwork is incomplete: %s. Raise "
                      "%s by exactly the metrics that rose, in a commit whose message names each rise (key and "
                      "new value) and, in its body, why." % ("; ".join(problems), baseline))
    return out + ("If the rise is needed (a planned new module): `gh issue edit N --remove-label owner:<yours> "
                  "--add-label owner:don --add-label status:needs-approval`, comment the metric and why, and stop. "
                  "Only Don's `arch-approved` waives it, and only with a matching %s raise." % baseline)


if __name__ == "__main__":
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 2 else ("", [])
    try:
        if cmd == "check":
            worse = check(args[0], *args[1:2])
            print("\n".join(worse))
            sys.exit(1 if worse else 0)
        if cmd == "check-ui":
            worse = check_ui(args[0], *args[1:2])
            print("\n".join(worse))
            sys.exit(1 if worse else 0)
        if cmd == "active-ui":  # the UI ratchet's switch, as of the last fetch
            sys.exit(0 if active(args[0], fetch=False, script=UI_SCRIPT) else 1)
        if cmd == "active":  # the driver's switch, as of the last fetch
            sys.exit(0 if active(args[0], fetch=False) else 1)
        if cmd == "ready":
            missing = _missing(python_for(args[0])) if active(args[0]) else []
            print(" ".join(missing))
            sys.exit(1 if missing else 0)
    except ToolError as e:
        print("arch_ratchet: %s" % e, file=sys.stderr)
        sys.exit(2)
    sys.exit("usage: arch_ratchet.py check|check-ui <checkout> [src] | ready|active|active-ui <checkout>")
