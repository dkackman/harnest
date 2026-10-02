#!/usr/bin/env python3
"""PreToolUse guard for the unattended roles (HARNESS-ROADMAP.md R3).

    python3 guard.py implementer|lead|consumer|curator|reviewer   (hook input JSON on stdin)

Turns ticket-protocol invariants that used to live only in prompt text, and
were audited after the fact by audit_issue, into refusals at the moment of
the call. A refusal is exit 2 with the reason on stderr, which Claude Code
hands back to the agent as the tool result, so the agent can correct the
call instead of the loop finding the damage a cycle later.

implementer:
  - no `gh issue close` unless --reason "not planned" (gh's default reason
    is completed, and only the tester closes as completed)
  - no `status:verified` label
  - no removing `owner:don`, nor `status:needs-approval` while `owner:don`
    is on the issue (a human's park; once Don swaps the owner away, a
    leftover status is stale and may be cleared, which asks GitHub)
  - adding an `owner:*` label must remove one in the same call (exactly
    one owner at a time)
  - no push to master, no force push, no branch deletion on origin
  - hand-off gate: adding `status:fixed-pending-verify` needs a clean tree,
    ruff clean on the changed files, the UI's check/lint/test passing when
    ui/ changed, and no pytest failure that isn't also failing on
    HARNEST_BASE_COMMIT (see handoff_gate)
  - dw's architecture, at a hand-off and at any push of develop, on the
    work's own commits (three dots from origin/develop). See arch_gate.
    Each switch is a file on origin/develop, read by lib/:
    - the hot zone (hot-zone.txt, FREEZE or not): no change to a listed
      path, and no label lifts it; the one exception is baseline.json in
      a waived ratchet rise
    - the metrics ratchet (scripts/arch_metrics.py): no metric worse than
      at the merge base. Fails closed when the script can't run. Waived
      only by `arch-approved` with matching paperwork: the same commits
      raise baseline.json by exactly what rose, in a commit that names the
      rise and why (arch_ratchet.waiver_problems)
    - the stabilization freeze (FREEZE): no new file under dw/, dw_mcp/,
      workflows/, prompts/ or plugins/ unless the issue carries
      `arch-approved` (a push checks this only when the driver gave the
      session an issue, HARNEST_ISSUE)
    Also any `gh pr merge`, or `gh api` call to a PR's merge endpoint, into
    develop (or whose base can't be read) while any of the three is on: a
    merge there never shows up as a push. See pr_merge_base
lead (the feature lead's design and decompose sessions, via `guard_settings lead` in providers.sh; its
build and close-out sessions commit and push, so they run with
implementer.json and get the implementer's rules, push checks and
hand-off gate):
  - the implementer's issue rules above (no completed close, no
    status:verified, no lifting a park, one owner at a time)
every role:
  - no adding `status:plan-approved`: approving a feature plan is Don's
    alone (roadmap R11), so no agent can approve the plan it wrote
  - no adding `release` or `release-blocker`: a freeze, and what moves
    during one, are Don's (roadmap R14)
  - no adding `arch-approved` (edit or create): it waives a freeze's
    new-surface refusal, a ratchet rise, and an architecture review's
    blocking finding, all Don's calls
  - no adding `arch-review`, and no removing it except by the reviewer: the
    driver adds it to queue an architecture review of a hand-off that
    changed dw/ or dw_mcp/, and the reviewer's verdict removes it
  - no `security` label on an issue: a security finding goes to a private
    draft advisory (scripts/file-advisory.sh), never the public tracker,
    where it would publish the exploit path (roadmap R14 item 3)
  - no issue text carrying a release marker (`harnest:release-gate`, or a
    waiver, `harnest:release-waive`): run-release.sh records a gate's result
    and Don's waivers that way on the release issue, and every agent posts
    as Don's login, so an agent's copy would read as a gate that passed
curator (suite review sessions, via `guard_settings curator`):
  - no removing `owner:don` (Don's hand-back is his to make)
  - the one-owner rule is not applied: harness-repo issues carry no owner
    label, so escalating one is a bare --add-label owner:don
reviewer (docs review sessions, via `guard_settings reviewer`):
  - may close as completed with no `mcp__dw__` call: it verifies a fix
    that changed only files the server and plugin don't serve, by reading
    them, so there is no MCP call to make
  - never adds `status:verified`: that label claims an MCP check, and a
    reviewed close carries `status:reviewed` instead
  - no lifting a park, and the one-owner rule, as for the implementer
  - in an architecture review (HARNEST_SESSION_KIND=arch), no close at all:
    a review passes the fix on to the tester or bounces it
consumer (tester, regression):
  - closing as completed or adding `status:verified` needs at least one
    `mcp__dw__*` call earlier in the session ("only from a real MCP call").
    One exception: a HANDOFF session (HARNEST_SESSION_KIND=handoff, set by
    run-loop.sh) may close as completed, since it applies a harness-side
    edit with nothing to verify; it still may not add status:verified
  - the same exactly-one-owner rule
every role, claims (harnest#15 part 2): `target:<server>` labels are the
loop driver's claims, and `verified-on:*` says a verification was made
somewhere other than lem:
  - no adding a `target:` label, except the hand-over to lem from another
    server's session: `--remove-label target:<this> --add-label target:lem`
  - no adding `verified-on:*` except by a consumer on another server
implementer on a server other than lem (HARNEST_TARGET, set by run-loop.sh):
  - `ssh` only to its own test bed (HARNEST_TARGET_HOST), to read its log
    and checkout; no `scp` or `rsync`; lem is off limits
  - no running dw's deploy script (`deploy.sh`, even over ssh): the driver
    deploys between sessions, because the session's own MCP connection
    keeps the old server from exiting (#446, 2026-09-26)
consumer on a server other than lem (HARNEST_TARGET and HARNEST_ROLE, set
by run-loop.sh and run-regression.sh; harnest#15). Also runs on Edit and
Write:
  - no Edit/Write to lem's perf history (a top-level
    `regression-perf/*.jsonl`, or another target's directory); its own
    `regression-perf/<target>/` is allowed
  - no Edit/Write to a `regression-suite-*.md` from a regression run: every
    case runs on lem. The loop's tester may add one (a verified
    backend:shared fix; its prompt says when)
  - `gh issue create` carries exactly one `backend:mps` or `backend:shared`
    (a cuda bug can't be observed here), at most one `owner:*`, and no
    `target:` label
  - `gh issue create`/`comment` names the ticket repo (HARNEST_TICKET_REPO),
    with one exception: a suite-change request on the harness repo
    (HARNEST_HARNESS_REPO, default dkackman/harnest) labeled exactly `suite`
    + `status:needs-approval`, which the curator rules on. The 0.5.0 cut
    found a C-F029 amendment stalled two days for want of it
  - no `gh issue comment N` on an issue lem's loop holds (`target:lem`;
    asks GitHub, and any doubt refuses): the tester there reads its latest
    comments while verifying on lem
  - adding `status:verified` also adds `verified-on:mps`

Command matching is textual, on the Bash command line. It is a guard
against the model's mistakes, not against an adversary: a determined agent
could spell a call so this misses it, which audit_issue still catches.
"""
import json, os, re, shlex, shutil, subprocess, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib"))
import freeze  # noqa: E402  (lib/freeze.py, shared with the driver)
import arch_ratchet  # noqa: E402  (lib/arch_ratchet.py, likewise)


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


def still_parked(words):
    """True unless the issue an edit names is known to lack owner:don.

    Removing status:needs-approval lifts a park only while owner:don is on
    the issue. Once Don has handed an issue back by swapping the owner, a
    status he left behind is stale, and the agent now holding it must be
    able to clear it. Only this case asks GitHub; any doubt (no number, gh
    failing) counts as parked, so the rule fails closed.
    """
    nums = [w for w in words[3:] if re.fullmatch(r"#?\d+", w)]
    if not nums:
        return True
    repo = flag_values(words, "--repo", "-R")
    cmd = ["gh", "issue", "view", nums[0].lstrip("#"), "--json", "labels", "--jq", "[.labels[].name] | index(\"owner:don\") != null"]
    if repo:
        cmd += ["--repo", repo[-1]]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    except Exception:
        return True
    return out.returncode != 0 or out.stdout.strip() != "false"


def label_lookup(words, label):
    """Whether the issue this command names carries <label>, as GitHub says:
    True or False, or None when it can't say (no number, gh failing)."""
    nums = [w for w in words[3:] if re.fullmatch(r"#?\d+", w)]
    if not nums:
        return None
    repo = flag_values(words, "--repo", "-R")
    return label_on(nums[0].lstrip("#"), repo[-1] if repo else "", label)


def label_on(num, repo, label):
    """label_lookup for an issue number (and repo, "" for gh's default)."""
    cmd = ["gh", "issue", "view", num, "--json", "labels", "--jq",
           "[.labels[].name] | index(\"%s\") != null" % label]
    if repo:
        cmd += ["--repo", repo]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    except Exception:
        return None
    if out.returncode != 0 or out.stdout.strip() not in ("true", "false"):
        return None
    return out.stdout.strip() == "true"


def issue_has_label(words, label):
    """True only when GitHub says so; any doubt is False (fails closed)."""
    return label_lookup(words, label) is True


def git_push_args(words):
    """(dir from -C or None, the push's arguments), or None if not a git push."""
    if len(words) < 2 or os.path.basename(words[0]) != "git":
        return None
    # skip git's own global options (-C dir, -c k=v)
    i, at = 1, None
    while i < len(words) and words[i] in ("-C", "-c"):
        if words[i] == "-C" and i + 1 < len(words):
            at = words[i + 1]
        i += 2
    if i >= len(words) or words[i] != "push":
        return None
    return at, words[i + 1:]


def pushed_develop(words, cwd):
    """(checkout, source ref) when this is a push to develop, else None.
    A bare `git push [remote]`, or `git push <remote> HEAD`, counts when the
    checkout is on develop."""
    pa = git_push_args(words)
    if not pa:
        return None
    at, args = pa
    top = os.path.join(cwd, at) if at else cwd
    specs = [a for a in args if not a.startswith("-")][1:]  # after the remote
    for a in specs:
        src, _, dst = a.lstrip("+").rpartition(":")
        if dst in ("develop", "refs/heads/develop"):
            return top, src or dst
    if not specs or any(a.lstrip("+") in ("HEAD", "@") for a in specs):
        head = subprocess.run(["git", "-C", top, "rev-parse", "--abbrev-ref", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
        if head == "develop":
            return top, "HEAD"
    return None


def git_push_problem(words):
    pa = git_push_args(words)
    if not pa:
        return None
    args = pa[1]
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

    # The UI's own checks, when this work touched ui/: CI runs them, and
    # before R14 nothing did between a hand-off and the release PR. Type
    # check, lint and unit tests - about 15 s - not the build or e2e.
    # Absolute rather than relative to the base, unlike pytest: they are
    # green on develop by CI's standard, and there is no per-test list to
    # compare. Skipped, not refused, where the checkout can't run them.
    ui_changed = git("diff", "--name-only", "--diff-filter=d", base, "HEAD", "--", "ui/")
    ui_dir = os.path.join(top, "ui")
    if ui_changed and os.path.isdir(os.path.join(ui_dir, "node_modules")) and shutil.which("npm"):
        for script in ("check", "lint", "test"):
            r = subprocess.run(["npm", "run", "--silent", script], cwd=ui_dir, capture_output=True, text=True)
            if r.returncode != 0:
                deny("`npm run %s` fails in ui/ on files this work changed, as CI would:\n%s"
                     % (script, (r.stdout + r.stderr)[-2000:]))

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


def arch_gate(checkout, src, arch_approved=None):
    """dw's architecture at a hand-off or a push of develop: the hot zone,
    the metrics ratchet and, while frozen, new surface, on src's own commits
    (three dots from origin/develop; lib/freeze.py and lib/arch_ratchet.py
    hold the switches). arch_approved() asks GitHub whether the issue carries
    `arch-approved`, and is asked only when a rule could be waived by it;
    None when no issue is known (a push without HARNEST_ISSUE), which waives
    nothing and skips the new-surface rule, as before. The same gate at both
    moments, because a fix is usually merged and pushed before it's handed off."""
    if subprocess.run(["git", "-C", checkout, "rev-parse", "--git-dir"], capture_output=True).returncode:
        return
    is_frozen = freeze.frozen(checkout)
    found = freeze.violations(checkout, src, freeze.hot_zone(checkout, fetch=False), is_frozen)
    try:
        worse = arch_ratchet.check(checkout, src)
    except arch_ratchet.ToolError as e:
        deny(str(e))
    approved = []
    def is_approved():
        if not approved:
            approved.append(arch_approved is not None and arch_approved())
        return approved[0]
    problems = arch_ratchet.waiver_problems(checkout, worse, src) if worse and is_approved() else None
    waived = bool(worse) and problems == []
    park = ("Don't work around it: `gh issue edit N --remove-label owner:<yours> --add-label owner:don "
            "--add-label stabilization`, then comment which rule fired (%s) and on which path, and stop.")
    # baseline.json in an approved rise is the waiver's to judge: refused below unless its paperwork holds
    hot = [p for r, p in found if r == "hot-zone" and not (problems is not None and p == arch_ratchet.BASELINE)]
    if hot:
        deny("this work's own commits change %s, which dw is restructuring (docs/stabilization/hot-zone.txt "
             "on origin/develop; no label lifts this). %s" % (hot[0], park % "hot-zone"))
    new = [p for r, p in found if r == "new-surface"]
    if new and arch_approved is not None and not is_approved():
        deny("dw is in its stabilization freeze (docs/stabilization/FREEZE on origin/develop), and this work's "
             "own commits add %s: new surface, which needs Don's `arch-approved` label on the issue. %s"
             % (new[0], park % "new-surface"))
    if worse and not waived:
        deny("dw's architecture ratchet: " + arch_ratchet.refusal(worse, problems))


def merge_gated(cwd):
    """Whether a PR merge into develop must be refused: true while any of
    arch_gate's switches is on, since a merge on GitHub is never a push
    the gate sees. A switch that can't be read counts as on."""
    try:
        return freeze.frozen(cwd) or bool(freeze.hot_zone(cwd, fetch=False)) or arch_ratchet.active(cwd, fetch=False)
    except arch_ratchet.ToolError:
        return True


def pr_merge_base(words):
    """The base branch of the PR a `gh pr merge [N]` or `gh api
    repos/O/R/pulls/N/merge` merges, as GitHub says; "" when it can't say.
    None when the command is neither."""
    if not (len(words) >= 2 and os.path.basename(words[0]) == "gh"):
        return None
    repo = flag_values(words, "--repo", "-R")
    if words[1:3] == ["pr", "merge"]:
        nums = [w.lstrip("#") for w in words[3:] if re.fullmatch(r"#?\d+", w)]
        cmd = ["gh", "pr", "view", *nums[:1], "--json", "baseRefName", "--jq", ".baseRefName"]
        cmd += ["--repo", repo[-1]] if repo else []
    elif words[1] == "api":
        m = next((re.fullmatch(r"/?repos/([^/]+/[^/]+)/pulls/(\d+)/merge/?", w) for w in words[2:]
                  if re.fullmatch(r"/?repos/[^/]+/[^/]+/pulls/\d+/merge/?", w)), None)
        if not m:
            return None
        cmd = ["gh", "pr", "view", m.group(2), "--repo", m.group(1), "--json", "baseRefName", "--jq", ".baseRefName"]
    else:
        return None
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    except Exception:
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


def session_called_mcp(transcript):
    try:
        with open(transcript) as fh:
            return any('"name":"mcp__dw__' in l.replace(" ", "") for l in fh)
    except OSError:
        return False


# a gate result (harnest:release-gate) or a waiver (harnest:release-waive)
RELEASE_MARKER = "harnest:release-"


def carries_release_marker(words):
    """True when a gh issue comment/create/edit's text holds the marker,
    given inline (--body/-b) or as a file (--body-file/-F) the hook can read."""
    if not (is_gh_issue(words, "comment") or is_gh_issue(words, "create") or is_gh_issue(words, "edit")):
        return False
    if any(RELEASE_MARKER in b for b in flag_values(words, "--body", "-b")):
        return True
    for path in flag_values(words, "--body-file", "-F"):
        try:
            if RELEASE_MARKER in open(path).read():
                return True
        except OSError:
            pass
    return False


def suite_request(words):
    """A suite-change request on the harness repo: `gh issue create --repo
    <HARNEST_HARNESS_REPO>` labeled exactly suite + status:needs-approval.
    The one filing a consumer on another server may make there."""
    repo = flag_values(words, "--repo", "-R")
    labels = sorted(l for v in flag_values(words, "--label", "-l") for l in v.split(","))
    return is_gh_issue(words, "create") and bool(repo) \
        and repo[-1] == os.environ.get("HARNEST_HARNESS_REPO", "dkackman/harnest") \
        and labels == ["status:needs-approval", "suite"]


def other_target():
    """The server this session's loop or run targets, when it isn't lem."""
    t = os.environ.get("HARNEST_TARGET", "lem")
    return "" if t in ("", "lem") else t


def own_host():
    """The ssh host of this session's target (HARNEST_TARGET_HOST, set by the
    driver from target_row), short and lowercased; "" when unknown."""
    return os.environ.get("HARNEST_TARGET_HOST", "").split(".")[0].lower()


def ssh_host(words):
    """The destination host of an ssh command line, short and lowercased:
    the first argument that isn't an option or an option's value."""
    i, takes = 1, set("bcDEeFIiJLlmOoPpQRSWw")
    while i < len(words):
        w = words[i]
        if w.startswith("-") and len(w) > 1:
            i += 2 if (w[-1] in takes and len(w) == 2) else 1
            continue
        return w.split("@")[-1].split(".")[0].lower()
    return ""


def claim_rule(words, target):
    """target: labels are the driver's claims; the one an agent adds is the
    hand-over from another server to lem."""
    claims = [l for l in flag_values(words, "--add-label") if l.startswith("target:")]
    if not claims:
        return
    if target and claims == ["target:lem"] and "target:" + target in flag_values(words, "--remove-label"):
        return
    deny("target: labels are the loop driver's claims. The one change a session makes is "
         "the hand-over to lem: --remove-label target:<this server> --add-label target:lem.")


def target_file_rule(path, cwd, target, role):
    """Refuse a write to lem's suite or perf files from a non-lem session."""
    root = os.path.realpath(os.environ.get("HARNEST_ROOT", ""))
    full = os.path.realpath(os.path.join(cwd, path))
    if not root or os.path.commonpath([root, full]) != root:
        return
    parts = os.path.relpath(full, root).split(os.sep)
    if len(parts) == 1 and parts[0].startswith("regression-suite-") and parts[0].endswith(".md") \
            and role != "tester":
        deny("on the %s server the suite files are read-only: every case in them runs on lem, "
             "so propose a case in the issue or comment instead." % target)
    if parts[0] == "regression-perf" and len(parts) > 1 and not (len(parts) > 2 and parts[1] == target):
        deny("on the %s server, readings go to regression-perf/%s/<case>.jsonl; the rest of "
             "regression-perf/ is another server's history." % (target, target))


def main():
    role = sys.argv[1] if len(sys.argv) > 1 else ""
    data = json.load(sys.stdin)
    cwd = data.get("cwd") or os.getcwd()
    server = other_target()
    target = server if role == "consumer" else ""
    if data.get("tool_name") in ("Edit", "Write"):
        if target:
            target_file_rule(data.get("tool_input", {}).get("file_path", ""), cwd, target,
                             os.environ.get("HARNEST_ROLE", "regression"))
        return
    if data.get("tool_name") != "Bash":
        return
    cmd = data.get("tool_input", {}).get("command", "")
    for words in segments(cmd):
        if role == "implementer" and server:
            lead = 0  # env assignments before the command (FOO=1 ssh ...), not an ssh -o Key=value
            while lead < len(words) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[lead]):
                lead += 1
            cmdw = words[lead:]
            if cmdw and os.path.basename(cmdw[0]) in ("ssh", "scp", "rsync") \
                    and not (os.path.basename(cmdw[0]) == "ssh" and ssh_host(cmdw) == own_host()):
                deny("this loop runs against the %s server: ssh only to its host (%s), to read; no "
                     "scp or rsync; lem is off limits." % (server, own_host() or "unknown"))
            if any(os.path.basename(w) == "deploy.sh" or w.endswith("/deploy.sh") or "deploy.sh " in w for w in cmdw):
                deny("on the %s server the driver deploys develop after your session: your own "
                     "MCP connection would hold the old server open. Merge, push and hand off."
                     % server)
        if is_gh_issue(words, "edit"):
            claim_rule(words, server if role in ("consumer", "implementer") else "")
            if any(l.startswith("verified-on:") for l in flag_values(words, "--add-label")) and not target:
                deny("verified-on: marks a verification made on another server, by that server's tester.")
        if target and is_gh_issue(words, "edit") and adds_verified(words) \
                and "verified-on:mps" not in flag_values(words, "--add-label"):
            deny("on the %s server a verification adds verified-on:mps with status:verified, so lem "
                 "can tell CUDA hasn't re-verified it." % target)
        if target and (is_gh_issue(words, "create") or is_gh_issue(words, "comment")):
            ticket_repo = os.environ.get("HARNEST_TICKET_REPO", "")
            harness_repo = os.environ.get("HARNEST_HARNESS_REPO", "dkackman/harnest")
            repo = flag_values(words, "--repo", "-R")
            if ticket_repo and (not repo or repo[-1] != ticket_repo) and not suite_request(words):
                deny("from the %s server, issues are filed and commented on %s only (--repo %s). "
                     "The one exception is a suite-change request: --repo %s with exactly "
                     "--label suite --label status:needs-approval."
                     % (target, ticket_repo, ticket_repo, harness_repo))
        if target and is_gh_issue(words, "comment") and label_lookup(words, "target:lem") is not False:
            deny("from the %s server, no comment on an issue lem's loop holds (target:lem), or one "
                 "that couldn't be checked: file your own with a backend: label and reference it."
                 % target)
        if target and is_gh_issue(words, "create") and not suite_request(words):
            labels = flag_values(words, "--label", "-l")
            backends = [l for l in labels if l.startswith("backend:")]
            if backends not in (["backend:mps"], ["backend:shared"]) \
                    or any(l.startswith("target:") for l in labels) \
                    or len([l for l in labels if l.startswith("owner:")]) > 1:
                deny("an issue from the %s server carries exactly one backend:mps or backend:shared "
                     "(a cuda bug can't be seen here), one owner, and no target: label (claims are "
                     "the driver's)." % target)
        if (is_gh_issue(words, "create") and "security" in flag_values(words, "--label", "-l")) \
                or (is_gh_issue(words, "edit") and "security" in flag_values(words, "--add-label")):
            deny("a security finding is filed privately, never as a public issue: "
                 "scripts/file-advisory.sh --summary ... --description-file ... --severity ... "
                 "(the implementer: $HARNEST_ROOT/scripts/file-advisory.sh).")
        if carries_release_marker(words):
            deny("a release marker is run-release.sh's record of a gate Don ran or a problem he waived; no agent writes one.")
        if is_gh_issue(words, "edit"):
            if role != "curator":
                owner_rule(words)
            elif "owner:don" in flag_values(words, "--remove-label"):
                deny("removing owner:don is Don's hand-back, not the curator's.")
            if "status:plan-approved" in flag_values(words, "--add-label"):
                deny("status:plan-approved is Don's to add: approving a feature plan is a human decision, "
                     "and no agent may approve a plan, its own or another's.")
            if {"release", "release-blocker"} & set(flag_values(words, "--add-label")):
                deny("release and release-blocker are Don's to add: a freeze, and what may move during "
                     "one, are his calls (R14).")
        added = flag_values(words, "--add-label") if is_gh_issue(words, "edit") else \
            flag_values(words, "--label", "-l") if is_gh_issue(words, "create") else []
        if "arch-approved" in added:
            deny("arch-approved is Don's to add: it waives new surface during a freeze, a ratchet rise and an "
                 "architecture review's blocking finding, each his call.")
        if "arch-review" in added:
            deny("arch-review is the loop driver's: it queues the architecture review of a hand-off that "
                 "changed dw/ or dw_mcp/.")
        if is_gh_issue(words, "edit") and "arch-review" in flag_values(words, "--remove-label") and role != "reviewer":
            deny("only the reviewer removes arch-review, with its verdict: the architecture review comes "
                 "before the tester's.")
        if role == "reviewer":
            if os.environ.get("HARNEST_SESSION_KIND") == "arch" and is_gh_issue(words, "close"):
                deny("an architecture review closes nothing: pass the fix on (remove arch-review) or bounce it.")
            if adds_verified(words):
                deny("status:verified claims an MCP check; a docs review adds status:reviewed instead.")
        if role in ("implementer", "lead", "reviewer"):
            if role != "reviewer" and closes_completed(words):
                deny('only the tester closes an issue as completed. gh closes as completed by default: '
                     'pass --reason "not planned" for wontfix/duplicate.')
            if role != "reviewer" and adds_verified(words):
                deny("status:verified is the tester's to add, from a real MCP call.")
            if is_gh_issue(words, "edit"):
                removed = flag_values(words, "--remove-label")
                if "owner:don" in removed:
                    deny("owner:don / status:needs-approval is a park with the human; only a human lifts it.")
                if "status:needs-approval" in removed and still_parked(words):
                    deny("owner:don / status:needs-approval is a park with the human; only a human lifts it.")
        if role == "implementer":
            problem = git_push_problem(words)
            if problem:
                deny(problem)
            if is_gh_issue(words, "edit") and "status:fixed-pending-verify" in flag_values(words, "--add-label"):
                arch_gate(cwd, "HEAD", lambda: issue_has_label(words, "arch-approved"))
                handoff_gate(cwd)
            base = pr_merge_base(words)
            if base in ("", "develop") and merge_gated(cwd):
                deny("this merges a PR into develop%s on GitHub, where the hot zone, the architecture ratchet "
                     "and the freeze can't see what it adds. Merge it locally and push develop, which they "
                     "check." % ("" if base else " (or its base couldn't be read)"))
            issue = os.environ.get("HARNEST_ISSUE", "")
            push = pushed_develop(words, cwd)
            if push:  # the hot zone and ratchet need no issue; the waiver and new surface do
                arch_gate(push[0], push[1], (lambda: label_on(
                    issue, os.environ.get("HARNEST_TICKET_REPO", ""), "arch-approved") is True) if issue else None)
        elif role == "consumer":
            # A tester HANDOFF session applies a harness-side edit the
            # implementer asked for and closes the issue as done: nothing
            # to run over MCP, so its close is exempt. Adding
            # status:verified is not: that label claims an MCP check.
            handoff = os.environ.get("HARNEST_SESSION_KIND") == "handoff"
            if adds_verified(words) or (closes_completed(words) and not handoff):
                if not session_called_mcp(data.get("transcript_path", "")):
                    deny("verifying (closing as completed / status:verified) needs a real MCP call in this "
                         "session, and this session has made none. Re-run the repro over the dw tools first.")


main()
