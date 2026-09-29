#!/usr/bin/env python3
"""The architecture-metrics ratchet (stage B): a session's own commits may not
make any of dw's scripts/arch_metrics.py numbers worse.

    python3 lib/arch_ratchet.py check <checkout> [src]   exit 0 ok, 1 regressed, 2 tool failure
    python3 lib/arch_ratchet.py ready <checkout>         exit 0 when the tools import (or the ratchet is off)

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
"""
import hashlib, importlib.util, json, os, re, shutil, subprocess, sys, tempfile

REF = "origin/develop"
SCRIPT = "scripts/arch_metrics.py"
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


def active(checkout, fetch=True):
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
    return _git(checkout, "cat-file", "-e", "%s:%s" % (REF, SCRIPT)).returncode == 0


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


def _archive(checkout, treeish, dest):
    git = subprocess.Popen(["git", "-C", checkout, "archive", treeish], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
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
    try:
        return json.loads(r.stdout)
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


def refusal(worse):
    """The message a regression earns: each metric, then the way out."""
    return ("this work's own commits make dw's architecture metrics worse than their merge base with %s: %s. "
            "Bring the number back down in this session: split the function, remove the duplicate, reuse an "
            "existing module instead of adding one, patch with `patch.object` or an injected fake instead of a "
            "`patch(\"dw...\")` string. If that is not possible: `gh issue edit N --remove-label owner:<yours> "
            "--add-label owner:don --add-label stabilization`, comment the metric and why, and stop. No label "
            "waives the ratchet." % (REF, "; ".join(worse)))


if __name__ == "__main__":
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 2 else ("", [])
    try:
        if cmd == "check":
            worse = check(args[0], *args[1:2])
            print("\n".join(worse))
            sys.exit(1 if worse else 0)
        if cmd == "ready":
            missing = _missing(python_for(args[0])) if active(args[0]) else []
            print(" ".join(missing))
            sys.exit(1 if missing else 0)
    except ToolError as e:
        print("arch_ratchet: %s" % e, file=sys.stderr)
        sys.exit(2)
    sys.exit("usage: arch_ratchet.py check <checkout> [src] | ready <checkout>")
