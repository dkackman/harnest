#!/usr/bin/env python3
"""PreToolUse guard for the unattended roles (HARNESS-ROADMAP.md R3).

    python3 guard.py implementer|lead|consumer     (hook input JSON on stdin)

Turns ticket-protocol invariants that used to live only in prompt text, and
were audited after the fact by audit_issue, into refusals at the moment of
the call. A refusal is exit 2 with the reason on stderr, which Claude Code
hands back to the agent as the tool result, so the agent can correct the
call instead of the loop finding the damage a cycle later.

implementer:
  - no `gh issue close` unless --reason "not planned" (gh's default reason
    is completed, and only the tester closes as completed)
  - no `status:verified` label
  - no removing `owner:don` or `status:needs-approval` (a human's park)
  - adding an `owner:*` label must remove one in the same call (exactly
    one owner at a time)
  - no push to master, no force push, no branch deletion on origin
  - hand-off gate: adding `status:fixed-pending-verify` needs a clean tree,
    ruff clean on the changed files, and no pytest failure that isn't also
    failing on HARNEST_BASE_COMMIT (see handoff_gate)
lead (the feature lead's design and decompose sessions, via lead.json; its
build and close-out sessions commit and push, so they run with
implementer.json and get the implementer's rules, push checks and
hand-off gate):
  - the implementer's issue rules above (no completed close, no
    status:verified, no lifting a park, one owner at a time)
every role:
  - no adding `status:plan-approved`: approving a feature plan is Don's
    alone (roadmap R11), so no agent can approve the plan it wrote
curator (suite review sessions, via curator.json):
  - no removing `owner:don` (Don's hand-back is his to make)
  - the one-owner rule is not applied: harness-repo issues carry no owner
    label, so escalating one is a bare --add-label owner:don
consumer (tester, regression):
  - closing as completed or adding `status:verified` needs at least one
    `mcp__dw__*` call earlier in the session ("only from a real MCP call")
  - the same exactly-one-owner rule

Command matching is textual, on the Bash command line. It is a guard
against the model's mistakes, not against an adversary: a determined agent
could spell a call so this misses it, which audit_issue still catches.
"""
import json, os, re, shlex, subprocess, sys


def deny(msg):
    print(f"Blocked by the harness guard (R3): {msg}", file=sys.stderr)
    sys.exit(2)


def segments(cmd):
    """Split a shell line into simple commands on ; & | ( ) and unquoted
    newlines, respecting quotes, so text inside a comment body is never
    read as a command."""
    lex = shlex.shlex(cmd, posix=True, punctuation_chars="();<>|&\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    out, cur = [], []
    try:
        for tok in lex:
            if tok and set(tok) <= set("();|&\n"):
                if cur:
                    out.append(cur)
                cur = []
            else:
                cur.append(tok)
    except ValueError:  # unbalanced quote: fall back to a plain split
        return [part.split() for part in re.split(r"(?:&&|\|\||[;|\n])", cmd) if part.split()]
    if cur:
        out.append(cur)
    return out


def flag_values(words, *names):
    """Values of --name X / --name=X / -n X, split on commas as gh does."""
    vals = []
    for i, w in enumerate(words):
        for n in names:
            if w == n and i + 1 < len(words):
                vals += words[i + 1].split(",")
            elif w.startswith(n + "="):
                vals += w[len(n) + 1:].split(",")
    return [v.strip() for v in vals]


def is_gh_issue(words, sub):
    return len(words) >= 3 and os.path.basename(words[0]) == "gh" and words[1] == "issue" and words[2] == sub


def owner_rule(words):
    added = [l for l in flag_values(words, "--add-label") if l.startswith("owner:")]
    removed = [l for l in flag_values(words, "--remove-label") if l.startswith("owner:")]
    if len(added) > 1:
        deny("an issue carries exactly one owner:* label; this adds %s." % ", ".join(added))
    if added and not removed:
        deny("an issue carries exactly one owner:* label, so adding %s must remove the current owner "
             "in the same command (--remove-label owner:<current> --add-label %s)." % (added[0], added[0]))


def closes_completed(words):
    if not is_gh_issue(words, "close"):
        return False
    reason = flag_values(words, "--reason", "-r")
    return not reason or reason[-1].lower().replace("_", " ") != "not planned"


def adds_verified(words):
    return is_gh_issue(words, "edit") and "status:verified" in flag_values(words, "--add-label")


def git_push_problem(words):
    if len(words) < 2 or os.path.basename(words[0]) != "git":
        return None
    # skip git's own global options (-C dir, -c k=v)
    i = 1
    while i < len(words) and words[i] in ("-C", "-c"):
        i += 2
    if i >= len(words) or words[i] != "push":
        return None
    args = words[i + 1:]
    if any(a in ("-f", "--force", "--force-with-lease", "--mirror", "--delete", "-d") or a.startswith("--force")
           for a in args):
        return "no force pushes, mirror pushes or remote branch deletion."
    for a in args:
        if a.startswith("+"):
            return "no force pushes (a +refspec is one)."
        dst = a.split(":")[-1]
        if a.startswith(":"):
            return "no remote branch deletion."
        if dst in ("master", "refs/heads/master"):
            return "never push to master; merge to develop and push develop."
    return None


def handoff_gate(cwd):
    """No new pytest failures and no new ruff findings on HEAD, relative to
    HARNEST_BASE_COMMIT (origin/develop when the driver started the session).

    Relative, not absolute, because develop is not always green: on
    2026-09-22 it failed two tests and ruff after a run of hand-offs each
    added a little, and an absolute gate would block every later hand-off
    for failures that issue didn't cause. Results are stamped per tree
    (HEAD's) and per base commit in the checkout's .git, so a repeated
    hand-off or a batch costs one run.
    """
    def git(*a, at=cwd):
        return subprocess.run(["git", "-C", at, *a], capture_output=True, text=True).stdout.strip()
    top = git("rev-parse", "--show-toplevel")
    base = os.environ.get("HARNEST_BASE_COMMIT", "")
    if not top or not base or not git("rev-parse", "--verify", "-q", base + "^{commit}"):
        return  # no baseline to compare against: don't block on a guess
    if git("status", "--porcelain", "--untracked-files=no"):
        deny("hand-off with uncommitted changes to tracked files. Commit (and merge/push develop) "
             "first, so what the tester verifies is what was tested.")
    tree = git("rev-parse", "HEAD^{tree}")
    gitdir = git("rev-parse", "--absolute-git-dir")
    stamp = os.path.join(gitdir, "harnest-handoff-ok")
    if os.path.exists(stamp) and open(stamp).read().split() == [tree, base]:
        return
    py = os.path.join(top, "venv", "bin", "python")

    # ruff, on the .py files this work changed only.
    changed = [f for f in git("diff", "--name-only", "--diff-filter=d", base, "HEAD", "--", "*.py").splitlines()
               if f.startswith(("dw/", "dw_mcp/", "tests/"))]
    if changed:
        for args in (["check"], ["format", "--check"]):
            r = subprocess.run([py, "-m", "ruff", *args, *changed], cwd=top, capture_output=True, text=True)
            if r.returncode != 0 and "No module named ruff" not in r.stderr:
                deny("`ruff %s` fails on files this work changed, as CI would:\n%s"
                     % (" ".join(args), (r.stdout + r.stderr)[-2000:]))

    def failures(root):
        r = subprocess.run([py, "-m", "pytest", "-q", "-rfE", "-p", "no:cacheprovider"], cwd=root,
                           capture_output=True, text=True, env=dict(os.environ, PYTHONPATH=root))
        return set(re.findall(r"^(?:FAILED|ERROR) (\S+)", r.stdout, re.M)), r

    base_file = os.path.join(gitdir, "harnest-base-failures-" + base)
    if not os.path.exists(base_file):
        wt = os.path.join(gitdir, "harnest-base-tree")
        subprocess.run(["git", "-C", top, "worktree", "remove", "--force", wt], capture_output=True)
        subprocess.run(["git", "-C", top, "worktree", "add", "--detach", wt, base], capture_output=True, check=True)
        try:
            os.symlink(os.path.join(top, "venv"), os.path.join(wt, "venv"))
            base_failed, _ = failures(wt)
        finally:
            subprocess.run(["git", "-C", top, "worktree", "remove", "--force", wt], capture_output=True)
        with open(base_file, "w") as fh:
            fh.write("\n".join(sorted(base_failed)) + "\n")
    base_failed = {l.strip() for l in open(base_file) if l.strip()}
    head_failed, r = failures(top)
    if r.returncode not in (0, 1):  # 2+ = interrupted, usage or collection error
        deny("pytest did not complete on HEAD (exit %d):\n%s" % (r.returncode, r.stdout[-2000:]))
    new = sorted(head_failed - base_failed)
    if new:
        deny("tests that pass on %s fail on HEAD, so this hand-off would cost the tester a cycle. "
             "Fix them first (a flaky one can be retried: rerun the hand-off command):\n%s"
             % (base[:10], "\n".join(new[:30])))
    with open(stamp, "w") as fh:
        fh.write(tree + " " + base + "\n")


def session_called_mcp(transcript):
    try:
        with open(transcript) as fh:
            return any('"name":"mcp__dw__' in l.replace(" ", "") for l in fh)
    except OSError:
        return False


def main():
    role = sys.argv[1] if len(sys.argv) > 1 else ""
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Bash":
        return
    cmd = data.get("tool_input", {}).get("command", "")
    cwd = data.get("cwd") or os.getcwd()
    for words in segments(cmd):
        if is_gh_issue(words, "edit"):
            if role != "curator":
                owner_rule(words)
            elif "owner:don" in flag_values(words, "--remove-label"):
                deny("removing owner:don is Don's hand-back, not the curator's.")
            if "status:plan-approved" in flag_values(words, "--add-label"):
                deny("status:plan-approved is Don's to add: approving a feature plan is a human decision, "
                     "and no agent may approve a plan, its own or another's.")
        if role in ("implementer", "lead"):
            if closes_completed(words):
                deny('only the tester closes an issue as completed. gh closes as completed by default: '
                     'pass --reason "not planned" for wontfix/duplicate.')
            if adds_verified(words):
                deny("status:verified is the tester's to add, from a real MCP call.")
            if is_gh_issue(words, "edit"):
                removed = flag_values(words, "--remove-label")
                if "owner:don" in removed or "status:needs-approval" in removed:
                    deny("owner:don / status:needs-approval is a park with the human; only a human lifts it.")
        if role == "implementer":
            problem = git_push_problem(words)
            if problem:
                deny(problem)
            if is_gh_issue(words, "edit") and "status:fixed-pending-verify" in flag_values(words, "--add-label"):
                handoff_gate(cwd)
        elif role == "consumer":
            if (closes_completed(words) or adds_verified(words)) and not session_called_mcp(data.get("transcript_path", "")):
                deny("verifying (closing as completed / status:verified) needs a real MCP call in this "
                     "session, and this session has made none. Re-run the repro over the dw tools first.")


main()
