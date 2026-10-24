#!/usr/bin/env python3
"""PreToolUse guard for the unattended roles (HARNESS-ROADMAP.md R3).

Shell assumption: the agents' Bash tool runs $SHELL (zsh on this machine); bash-3.2's
`$(cat <<'EOF' ... )` ending at the first `)`, and word splitting of an unquoted $VAR,
are not modelled.

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
    one owner at a time), unless GitHub says the issue has none: triage's
    unstrand step gives a stranded issue its first owner (asks GitHub)
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
implementer and lead, further (spec B.1/B.5/B.6):
  - a comment or issue body (--body-file, -F, gh api -f body=@file, --input)
    from stdin or a file missing or unreadable at call time: the guard cannot
    check a marker it cannot read
  - `gh` or `git push` as a later bare word of another command (`watch gh
    issue ...`); a gh api write's endpoint outside [A-Za-z0-9_./-]; the PR
    merge endpoint with any method but PUT
every role: `env -S`/`--split-string` is expanded, and its command held to every rule
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

import codecs
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib"))
import arch_ratchet  # noqa: E402  (lib/arch_ratchet.py, likewise)
import freeze  # noqa: E402  (lib/freeze.py, shared with the driver)


def deny(msg):
    print(f"Blocked by the harness guard (R3): {msg}", file=sys.stderr)
    sys.exit(2)


HOOK_CWD = ""  # the tool call's cwd, set by main(): relative body-file paths are the agent's, not the hook's
SOLE_COMMAND = False  # main(): the gh call is the only command on the line, bar heredoc writes of its body file
HEREDOC_PATHS = []  # the files `cat > PATH <<EOF` writes on that line
ENV_CHDIR = False  # command_words(): an env -C/--chdir prefix was stripped from the current segment
# A heredoc write of a body file: `cat > PATH <<'D'`, `cat >PATH <<"D"` or `tee PATH <<'D'`.
# Quoted delimiter only (the body is then literal, never expanded); PATH plain path characters,
# optionally after one $VAR/${VAR} (never IFS); nothing after the delimiter but /dev/null or 2>&1.
HEREDOC_HEADER = re.compile(
    r"(?:cat[ \t]*>|tee[ \t]+)[ \t]*((?!-)(?:\$(?!\{?IFS\b)(?:\{\w+\}|\w+))?[A-Za-z0-9_./-]+)"
    r"[ \t]*<<(-?)[ \t]*(['\"])(\w+)\3(?:[ \t]*(?:>[ \t]*/dev/null|2>&1))*[ \t]*\n"
)


CAT_SUB = re.compile(r"\$\([ \t]*cat[ \t]+<<[ \t]*(['\"])(\w+)\1[ \t]*\n")
# a line that may redefine cat (a function, an alias, a hashed path, a PATH, a sourced
# file, zsh's path/aliases/functions arrays): its "$(cat <<'D' ...)" is not literal
CAT_REDEF = re.compile(
    r"\w+\s*\(\s*\)|\bfunction\s+\w+|(?<![\w./-])(?:alias|enable|builtin|hash|eval|source|autoload|fpath)(?![\w.-])"
    r"|(?:^|[;&|(\n])[ \t]*\.[ \t]|\bPATH=|\bpath\+?=|\bpath\[|\baliases\[|\bfunctions\[|\bcommands\["
    r"|(?<![\w./-])functions\s+-c\b"
)
CAT_REDEFINED = False  # set by inline_cat_subs: the line may redefine cat, so nothing was rewritten


def inline_cat_subs(cmd):
    """cmd with each "$(cat <<'D' ... D)" inside double quotes replaced by its
    output, escaped for the double quotes: a quoted-delimiter heredoc is
    literal, so the substitution is exactly that text (less trailing
    newlines), and every rule then reads it as the value it is. The walk
    stops at the first substitution or backtick of any other shape, and never
    starts on a line that may redefine cat (CAT_REDEF): there the substitution
    stays live, for the rules to read and refuse. The redefinition is looked
    for outside the heredoc bodies, so prose like foo() in a body is text."""
    global CAT_REDEFINED
    out, bodies, i, n, dq = [], [], 0, len(cmd), False
    while i < n:
        c = cmd[i]
        m = CAT_SUB.match(cmd, i) if dq else None
        if m:
            delim, k, end = m.group(2), m.end(), None
            while k <= n:  # the body ends at the first line that is exactly the delimiter
                e = cmd.find("\n", k)
                e = n if e < 0 else e
                if cmd[k:e] == delim:
                    t = re.match(r"[ \t\n]*\)", cmd[e:])
                    end = e + t.end() if t else None
                    break
                k = e + 1
            if end is not None:
                body = cmd[m.end() : max(m.end(), k - 1)].rstrip("\n")
                out.append(re.sub(r'([\\"$`])', r"\\\1", body))
                bodies.append(len(out) - 1)
                i = end
                continue
        if c == "`" or cmd[i : i + 2] == "$(":
            break
        if c == "\\":
            out.append(cmd[i : i + 2])
            i += 2
            continue
        if c == "'" and not dq:
            e = cmd.find("'", i + 1)
            if e < 0:
                break
            out.append(cmd[i : e + 1])
            i = e + 1
            continue
        if c == '"':
            dq = not dq
        out.append(c)
        i += 1
    outside = "".join(x for k, x in enumerate(out) if k not in bodies) + cmd[i:]
    if bodies and (CAT_REDEF.search(outside) or CAT_REDEF.search(UNQUOTE.sub("", outside))):
        CAT_REDEFINED = True
        return cmd
    return "".join(out) + cmd[i:]


SHELLS = r"(?<![\w.-])(?:bash|sh|zsh|dash|ksh|eval|source)(?![\w.-])|(?<![\w./-])\.(?=[ \t])"


def live_text(text):
    """The parts of text bash substitutes in: unquoted and double-quoted text,
    without single-quoted strings, $'...' strings, or the bodies of
    quoted-delimiter heredocs fed to a command that is not a shell."""
    out, i, n, dq, pending, line_start = [], 0, len(text), False, [], 0
    while i < n:
        c, two = text[i], text[i : i + 2]
        if c == "\\":
            out.append(" ")
            i += 2
        elif not dq and c == "'":
            e = text.find("'", i + 1)
            i = n if e < 0 else e + 1
            out.append(" ")
        elif not dq and (two == "$'" or two == '$"'):
            if two == '$"':
                out.append(" $'' ")
                dq = True
                i += 2
                continue
            k = i + 2
            while k < n and text[k] != "'":
                k += 2 if text[k] == "\\" else 1
            i = k + 1
            out.append(" $'' ")  # kept as a mark: $'...' decodes escapes bash-side
        elif c == '"':
            dq = not dq
            out.append(c)
            i += 1
        elif not dq and (m := re.match(r"<<-?[ \t]*(['\"])(\w+)\1", text[i:])):
            if not re.search(SHELLS, text[line_start:i]):
                pending.append((m.group(2), two == "<<" and text[i + 2 : i + 3] == "-"))
            out.append(" ")
            i += m.end()
        elif not dq and c == "\n" and pending:
            k = i + 1
            for delim, dash in pending:  # skip each body to its delimiter line
                while k < n:
                    e = text.find("\n", k)
                    e = n if e < 0 else e
                    line = text[k:e]
                    k = e + 1
                    if (line.lstrip("\t") if dash else line) == delim:
                        break
            pending = []
            out.append("\n")
            i = line_start = k
        else:
            if not dq and (c in ";|&\n"):
                line_start = i + 1
            out.append(c)
            i += 1
    return "".join(out)


def heredoc_cut(cmd):
    """(cmd with each heredoc write cut out, the paths written). A shell-aware
    walk: a header counts only at a real command position (the start, or after
    an unquoted, unescaped newline, ;, && or || outside a comment), and its
    body ends at the first line that is exactly the delimiter, as bash ends it.
    Anything the walk cannot follow ($(, `, ${...}, another <<) stops the
    cutting, so the rest of the line is checked as commands."""
    out, paths = [], []
    i, keep, at_cmd, n = 0, 0, True, len(cmd)
    while i < n:
        if at_cmd:
            j = i
            while j < n and cmd[j] in " \t":
                j += 1
            m = HEREDOC_HEADER.match(cmd, j)
            if m:
                delim, dash = m.group(4), m.group(2) == "-"
                k, end = m.end(), None
                while k <= n:
                    e = cmd.find("\n", k)
                    e = n if e < 0 else e
                    line = cmd[k:e]
                    if (line.lstrip("\t") if dash else line) == delim:
                        end = min(e + 1, n)
                        break
                    k = e + 1
                if end is not None:
                    out.append(cmd[keep:j] + "\n")
                    paths.append(m.group(1))
                    i = keep = end
                    continue
        c = cmd[i]
        two = cmd[i : i + 2]
        if two in ("$(", "<<") or c == "`" or (two == "${" and not re.match(r"\$\{\w+\}", cmd[i:])):
            break  # cannot follow: no further cuts
        if c == "\\":
            at_cmd = False
            i += 2
        elif c == "'":
            e = cmd.find("'", i + 1)
            if e < 0:
                break
            at_cmd, i = False, e + 1
        elif two == "$'":
            k = i + 2
            while k < n and cmd[k] != "'":
                k += 2 if cmd[k] == "\\" else 1
            if k >= n:
                break
            at_cmd, i = False, k + 1
        elif c == '"':
            k = i + 1
            while k < n and cmd[k] != '"':
                if cmd[k] == "`" or cmd[k : k + 2] in ("$(", "${"):
                    return "".join(out) + cmd[keep:], paths
                k += 2 if cmd[k] == "\\" else 1
            if k >= n:
                break
            at_cmd, i = False, k + 1
        elif c == "#" and (i == 0 or cmd[i - 1] in " \t\n;&|()<>"):
            e = cmd.find("\n", i)
            if e < 0:
                break
            at_cmd, i = True, e + 1
        elif c in "\n;" or two in ("&&", "||"):
            at_cmd = True
            i += 1 if c in "\n;" else 2
        elif c in " \t":
            i += 1
        else:
            at_cmd = False
            i += 1
    out.append(cmd[keep:])
    return "".join(out), paths


def resolve(path):
    return os.path.join(HOOK_CWD or os.getcwd(), path)


UNQUOTE = re.compile(r"[\"'\\]")  # what bash drops from a word: quotes and backslashes
UNBALANCED = False  # set by segments() when a line had an unmatched quote


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
    except ValueError:  # unbalanced quote: fall back to a plain split, quote characters dropped
        global UNBALANCED
        UNBALANCED = True
        parts = re.split(r"[;&|()<>\n]", cmd)
        return [w for w in ([UNQUOTE.sub("", x) for x in part.split()] for part in parts) if w]
    if cur:
        out.append(cur)
    return out


SUBSTITUTION = re.compile(r"(?<!\\)\$\(([^()]*)\)|(?<!\\)`((?:\\.|[^`\\])*)`")


def substitutions(cmd):
    """(segments, inner texts, residual) of the commands inside $(...) and
    `...`, innermost first, which segments() leaves inside one word when they
    are quoted or backticked: a command substitution runs even inside double
    quotes. Escaped ones (\\`, \\$() are text. The residual is the line with
    every one read cut out. Read only for the rules: an apostrophe inside one
    is not an unbalanced quote on the line."""
    global UNBALANCED
    out, inner, prev, flag = [], [], None, UNBALANCED
    while prev != cmd:
        prev = cmd = re.sub(r"\$\(\([^()]*\)\)", " ", cmd)  # $((...)) arithmetic runs nothing
        for m in SUBSTITUTION.finditer(cmd):
            text = m.group(1) if m.group(1) is not None else m.group(2)
            inner.append(text)
            out += segments(text)
        cmd = SUBSTITUTION.sub(" ", cmd)
    UNBALANCED = flag
    return out, inner, cmd


GH_WORD = r"(?<![\w.-])(?:gh|git)(?![\w.-])"
EXPANDS = re.compile(r"\$[\w{(@*#?!$=-]|`")  # a $ that bash fills in, or a backtick
GH_VALUE_FLAGS = ("--repo", "-R", "--body", "-b", "--body-file", "-F", "--title", "-t", "--search", "-S")
GH_VALUE_FLAGS += ("--jq", "-q", "--json", "--milestone", "--assignee", "--hostname")
REDIRECT = re.compile(r"\d*[<>]+&?")


def ansi_decode(body):
    try:
        return codecs.decode(re.sub(r"\\c.", "", body).encode("latin-1", "backslashreplace"), "unicode_escape")
    except (UnicodeDecodeError, ValueError):
        return body


def shell_words(text):
    """(segments, decoded line, saw $'/$" quoting) of a shell line, read the way
    bash quotes it. A word is {"deq": its text with quotes removed and $'...'
    decoded, "unq": its unquoted characters (each quoted or escaped run as _),
    "exp": it holds an expansion outside single quotes, "zsh": ${=/$= in it}."""
    segs, cur = [], []
    w = {"deq": "", "unq": "", "exp": False, "zsh": False, "raw": ""}
    ansi, i, n = False, 0, len(text)

    def flush(end_seg=False):
        nonlocal w, cur
        if w["raw"]:
            cur.append(w)
        w = {"deq": "", "unq": "", "exp": False, "zsh": False, "raw": ""}
        if end_seg and cur:
            segs.append(cur)
            cur = []

    def dq_end(k):  # index of the closing " from k (inside the quotes), honouring backslashes
        while k < n and text[k] != '"':
            k += 2 if text[k] == "\\" else 1
        return min(k, n)

    while i < n:
        c, two = text[i], text[i : i + 2]
        if c == "\\":
            w["raw"] += text[i : i + 2]
            w["unq"] += "_"
            w["deq"] += text[i + 1 : i + 2]
            i += 2
        elif c == "'":
            e = text.find("'", i + 1)
            e = n if e < 0 else e
            w["raw"] += text[i : e + 1]
            w["deq"] += text[i + 1 : e]
            w["unq"] += "_"
            i = e + 1
        elif two == "$'":
            k = i + 2
            while k < n and text[k] != "'":
                k += 2 if text[k] == "\\" else 1
            ansi = True
            w["raw"] += text[i : k + 1]
            w["deq"] += ansi_decode(text[i + 2 : k])
            w["unq"] += "_"
            i = k + 1
        elif c == '"' or two == '$"':
            ansi = ansi or c == "$"
            start = i + (2 if c == "$" else 1)
            e = dq_end(start)
            body = text[start:e]
            w["raw"] += text[i : e + 1]
            w["deq"] += body
            w["unq"] += "_"
            live = re.sub(r"\\.", "", body)  # \$ and \` are text inside double quotes
            w["exp"] = w["exp"] or bool(EXPANDS.search(live))
            w["zsh"] = w["zsh"] or bool(re.search(r"\$\{?=", live))
            i = e + 1
        elif c == "`" or two in ("$(", "${"):
            close, depth, k = {"`": "`", "$(": ")", "${": "}"}[c if c == "`" else two], 0, i + 1
            opener = "(" if two == "$(" else "{"
            while k < n:
                if text[k] == "\\":
                    k += 2
                    continue
                if c != "`" and text[k] == opener:
                    depth += 1
                elif text[k] == close and (c == "`" or depth <= 1):
                    break
                elif c != "`" and text[k] == close:
                    depth -= 1
                k += 1
            w["raw"] += text[i : k + 1]
            w["deq"] += text[i : k + 1]
            w["unq"] += "_"
            w["exp"] = True
            w["zsh"] = w["zsh"] or two == "${" and text[i + 2 : i + 3] == "="
            i = k + 1
        elif c == "$" and i + 1 < n and re.match(r"[\w@*#?!$=-]", text[i + 1]):
            m = re.match(r"\$(\w+|.)", text[i:])
            w["raw"] += m.group(0)
            w["deq"] += m.group(0)
            w["unq"] += "_"
            w["exp"] = True
            w["zsh"] = w["zsh"] or text[i + 1] == "="
            i += len(m.group(0))
        elif c in " \t\r":
            flush()
            i += 1
        elif c in "\n;&|()":
            flush(end_seg=True)
            i += 1
        elif c in "<>":
            flush()
            m = REDIRECT.match(text, i)
            cur.append(
                {"deq": m.group(0), "unq": m.group(0), "exp": False, "zsh": False, "raw": m.group(0), "redir": 1}
            )
            i = m.end()
        elif c == "#" and not w["raw"]:
            e = text.find("\n", i)
            i = n if e < 0 else e
        else:
            w["raw"] += c
            w["unq"] += c
            w["deq"] += c
            i += 1
    flush(end_seg=True)
    return segs, " ".join(" ".join(x["deq"] for x in g) for g in segs), ansi


def expansion_rules(text, role=""):
    """Rules on how bash builds a word, for every role: $'...'/$"..." quoting,
    brace expansion, ${...} holding gh/git, a variable assigned gh/git, zsh's
    ${=L} splitting, and a variable standing in for a gh flag or label. For the
    source-blind roles (consumer, curator, reviewer) no git word may hold a
    brace: --git{-dir,}=X would slip past consumer_git_rule's flag check."""
    segs, decoded, ansi = shell_words(text)
    if ansi and "$''" in live_text(text) and re.search(GH_WORD, decoded):
        deny("$'...' quoting is not allowed in a gh/git command: write the word plainly.")
    if re.search(r"\$\{[^}]*?(?<![\w.])(?:gh|git)(?![\w.-])", text):
        deny("${...} may not hold gh or git: run the command directly.")
    for words in segs:
        for x in words:
            if x["zsh"]:
                deny("${=VAR} / $=VAR splits a variable into words the guard never sees: write the literal.")
            if re.match(r"[A-Za-z_]\w*=(?:\S*/)?(?:gh|git)(?![\w.-])", x["deq"]):
                deny("a variable may not hold gh or git: run the command directly.")
        plain = [x for k, x in enumerate(words) if not x.get("redir") and not (k and words[k - 1].get("redir"))]
        deq = [x["deq"] for x in plain]  # redirections and their targets are not arguments
        body = plain[len(deq) - len(command_words(deq)) :]
        if not body or os.path.basename(body[0]["deq"]) not in ("gh", "git"):
            continue
        braced = [bool(re.search(r"\{[^{}]*(?:,|\.\.)[^{}]*\}", x["unq"])) for x in body]
        brace_msg = (
            "brace expansion ({a,b}, {a..b}) in a gh/git command makes words the guard never sees: write each out."
        )
        if os.path.basename(body[0]["deq"]) == "git":
            j = 1  # git's own options, then the subcommand: no brace up to it (git {pu,}sh is a push)
            while j < len(body) and body[j]["deq"].startswith("-"):
                j += 2 if body[j]["deq"] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace") else 1
            if any(braced[: j + 1]) or (role in ("consumer", "curator", "reviewer") and any(braced)):
                deny(brace_msg)
            if not any(x["deq"] == "push" for x in body[j:]):
                continue  # a git read: a brace in its arguments writes nothing the guard rules on
        if any(braced):
            deny(brace_msg)
        if os.path.basename(body[0]["deq"]) != "gh":
            continue
        body_rule(body)
        if any(x["exp"] and "harnest:" in x["deq"] for x in body):
            deny("harnest: text and an expansion in one gh word: the marker would be built after the guard reads it.")
        allowed, j = set(), 1  # gh's leading flags, then the subcommand and the positional after it
        while j < len(body) and body[j]["deq"].startswith("-") and len(body[j]["deq"]) > 1:
            j += 2 if body[j]["deq"] in ("-R", "--repo", "--hostname") else 1
        if j < len(body):
            allowed.add(j + 1 if body[j]["deq"] == "api" else j + 2)
        if j + 1 < len(body) and body[j + 1]["deq"] in ("list", "status"):
            continue  # a read filter: a variable there labels nothing
        for k, x in enumerate(body):
            if k and x["exp"] and k not in allowed:
                prev = body[k - 1]["deq"]
                flag = x["deq"].split("=", 1)[0] if x["deq"].startswith("-") else None
                if prev not in GH_VALUE_FLAGS and flag not in GH_VALUE_FLAGS:
                    deny("an unquoted variable may not stand in for a gh flag or label: write the literal.")


def flag_values(words, *names):
    """Values of --name X / --name=X / -n X, split on commas as gh does."""
    vals = []
    for i, w in enumerate(words):
        for n in names:
            if w == n and i + 1 < len(words):
                vals += words[i + 1].split(",")
            elif w.startswith(n + "="):
                vals += w[len(n) + 1 :].split(",")
            elif len(n) == 2 and w.startswith(n) and len(w) > 2:  # pflag's attached form: -Fvalue, -F=value
                vals += w[2:].removeprefix("=").split(",")
    if any(n.endswith("label") or n == "-l" for n in names):  # GitHub labels are case-insensitive
        vals = [v.lower() for v in vals]
    return [v.strip() for v in vals]


def is_gh_issue(words, sub):
    return len(words) >= 3 and os.path.basename(words[0]) == "gh" and words[1] == "issue" and words[2] == sub


def owner_rule(words):
    added = [l for l in flag_values(words, "--add-label") if l.startswith("owner:")]
    removed = [l for l in flag_values(words, "--remove-label") if l.startswith("owner:")]
    if len(added) > 1:
        deny("an issue carries exactly one owner:* label; this adds %s." % ", ".join(added))
    if added and not removed and owner_count(words) != 0:
        deny(
            "an issue carries exactly one owner:* label, so adding %s must remove the current owner "
            "in the same command (--remove-label owner:<current> --add-label %s)." % (added[0], added[0])
        )


def one_issue(words):
    """[the issue number] a gh issue command names, or [] when it names
    anything else. gh issue edit takes several issues, as numbers or URLs,
    so a check that read only the first number would vet one issue and let
    the edit land on another. Any second number-like or issue-URL word (a
    second issue, a flag value such as --title 9) makes it ambiguous, and
    every caller fails closed on []."""
    refs = [w for w in words[3:] if re.fullmatch(r"#?\d+", w) or re.search(r"/issues/\d+", w)]
    if len(refs) != 1 or not re.fullmatch(r"#?\d+", refs[0]):
        return []
    return refs


def owner_count(words):
    """How many owner:* labels the issue an edit names carries, as GitHub
    says, or None when it can't say. An issue with none (stranded) may be
    given its first owner by a bare add; any doubt fails closed."""
    nums = one_issue(words)
    if not nums:
        return None
    repo = flag_values(words, "--repo", "-R")
    cmd = [
        "gh",
        "issue",
        "view",
        nums[0].lstrip("#"),
        "--json",
        "labels",
        "--jq",
        '[.labels[].name | select(startswith("owner:"))] | length',
    ]
    if repo:
        cmd += ["--repo", repo[-1]]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    except Exception:
        return None
    if out.returncode != 0 or not out.stdout.strip().isdigit():
        return None
    return int(out.stdout.strip())


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
    nums = one_issue(words)
    if not nums:
        return True
    repo = flag_values(words, "--repo", "-R")
    cmd = [
        "gh",
        "issue",
        "view",
        nums[0].lstrip("#"),
        "--json",
        "labels",
        "--jq",
        '[.labels[].name] | index("owner:don") != null',
    ]
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
    nums = one_issue(words)
    if not nums:
        return None
    repo = flag_values(words, "--repo", "-R")
    return label_on(nums[0].lstrip("#"), repo[-1] if repo else "", label)


def label_on(num, repo, label):
    """label_lookup for an issue number (and repo, "" for gh's default)."""
    cmd = ["gh", "issue", "view", num, "--json", "labels", "--jq", '[.labels[].name] | index("%s") != null' % label]
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
    return at, words[i + 1 :]


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
        head = subprocess.run(
            ["git", "-C", top, "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True
        ).stdout.strip()
        if head == "develop":
            return top, "HEAD"
    return None


def git_push_problem(words):
    pa = git_push_args(words)
    if not pa:
        return None
    args = pa[1]
    if any(
        a in ("-f", "--force", "--force-with-lease", "--mirror", "--delete", "-d") or a.startswith("--force")
        for a in args
    ):
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
        deny(
            "hand-off with uncommitted changes to tracked files. Commit (and merge/push develop) "
            "first, so what the tester verifies is what was tested."
        )
    tree = git("rev-parse", "HEAD^{tree}")
    gitdir = git("rev-parse", "--absolute-git-dir")
    stamp = os.path.join(gitdir, "harnest-handoff-ok")
    if os.path.exists(stamp) and open(stamp).read().split() == [tree, base]:
        return
    py = os.path.join(top, "venv", "bin", "python")

    # ruff, on the .py files this work changed only.
    changed = [
        f
        for f in git("diff", "--name-only", "--diff-filter=d", base, "HEAD", "--", "*.py").splitlines()
        if f.startswith(("dw/", "dw_mcp/", "tests/"))
    ]
    if changed:
        for args in (["check"], ["format", "--check"]):
            r = subprocess.run([py, "-m", "ruff", *args, *changed], cwd=top, capture_output=True, text=True)
            if r.returncode != 0 and "No module named ruff" not in r.stderr:
                deny(
                    "`ruff %s` fails on files this work changed, as CI would:\n%s"
                    % (" ".join(args), (r.stdout + r.stderr)[-2000:])
                )

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
                deny(
                    "`npm run %s` fails in ui/ on files this work changed, as CI would:\n%s"
                    % (script, (r.stdout + r.stderr)[-2000:])
                )

    def failures(root):
        r = subprocess.run(
            [py, "-m", "pytest", "-q", "-rfE", "-p", "no:cacheprovider"],
            cwd=root,
            capture_output=True,
            text=True,
            env=dict(os.environ, PYTHONPATH=root),
        )
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
        deny(
            "tests that pass on %s fail on HEAD, so this hand-off would cost the tester a cycle. "
            "Fix them first (a flaky one can be retried: rerun the hand-off command):\n%s"
            % (base[:10], "\n".join(new[:30]))
        )
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
        worse_ui = arch_ratchet.check_ui(checkout, src)
    except arch_ratchet.ToolError as e:
        deny(str(e))
    except Exception as e:  # a traceback would be a non-blocking hook error: fail closed here instead
        deny(
            "dw's architecture ratchet could not run (%s: %s). It fails closed: fix the checkout (permissions, "
            "disk, node) and hand off again." % (type(e).__name__, e)
        )
    approved = []

    def is_approved():
        if not approved:
            approved.append(arch_approved is not None and arch_approved())
        return approved[0]

    problems = arch_ratchet.waiver_problems(checkout, worse, src) if worse and is_approved() else None
    waived = bool(worse) and problems == []
    problems_ui = (
        arch_ratchet.waiver_problems(checkout, worse_ui, src, arch_ratchet.UI_BASELINE)
        if worse_ui and is_approved()
        else None
    )
    waived_ui = bool(worse_ui) and problems_ui == []
    park = (
        "Don't work around it: `gh issue edit N --remove-label owner:<yours> --add-label owner:don "
        "--add-label stabilization`, then comment which rule fired (%s) and on which path, and stop."
    )
    # baseline.json in an approved rise is the waiver's to judge: refused below unless its paperwork holds
    hot = [
        p
        for r, p in found
        if r == "hot-zone"
        and not (problems is not None and p == arch_ratchet.BASELINE)
        and not (problems_ui is not None and p == arch_ratchet.UI_BASELINE)
    ]
    if hot:
        deny(
            "this work's own commits change %s, which dw is restructuring (docs/stabilization/hot-zone.txt "
            "on origin/develop; no label lifts this). %s" % (hot[0], park % "hot-zone")
        )
    new = [p for r, p in found if r == "new-surface"]
    if new and arch_approved is not None and not is_approved():
        deny(
            "dw is in its stabilization freeze (docs/stabilization/FREEZE on origin/develop), and this work's "
            "own commits add %s: new surface, which needs Don's `arch-approved` label on the issue. %s"
            % (new[0], park % "new-surface")
        )
    # Both ratchets in one refusal, so a fix to one is not handed off only to meet the other
    refused = []
    if worse and not waived:
        refused.append("dw's architecture ratchet: " + arch_ratchet.refusal(worse, problems))
    if worse_ui and not waived_ui:
        refused.append(
            "dw's UI architecture ratchet: "
            + arch_ratchet.refusal(
                worse_ui, problems_ui, arch_ratchet.UI_BASELINE, "the UI's architecture metrics", arch_ratchet.UI_HINTS
            )
        )
    if refused:
        deny(" | ".join(refused))


def merge_gated(cwd):
    """Whether a PR merge into develop must be refused: true while any of
    arch_gate's switches is on, since a merge on GitHub is never a push
    the gate sees. A switch that can't be read counts as on."""
    try:
        return (
            freeze.frozen(cwd)
            or bool(freeze.hot_zone(cwd, fetch=False))
            or arch_ratchet.active(cwd, fetch=False)
            or arch_ratchet.active(cwd, fetch=False, script=arch_ratchet.UI_SCRIPT)
        )
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
        m = next(
            (
                re.fullmatch(r"/?repos/([^/]+/[^/]+)/pulls/(\d+)/merge/?", w)
                for w in words[2:]
                if re.fullmatch(r"/?repos/[^/]+/[^/]+/pulls/\d+/merge/?", w)
            ),
            None,
        )
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
            if RELEASE_MARKER in open(resolve(path)).read():
                return True
        except OSError:
            pass
    return False


def marker_through_punctuation(cmd):
    """The release marker on a gh line, read through quotes, $(, ), backticks and
    backslashes, or `harnest:release` with an expansion or quote straight after it."""
    if not re.search(r"(?<![\w.-])gh(?![\w.-])", UNQUOTE.sub("", cmd)):
        return False
    bare = re.sub(r"\$\(|[)`\"'\\]", "", cmd)
    return RELEASE_MARKER in cmd or RELEASE_MARKER in bare or bool(re.search(r"harnest:release[$`\"'\\]", cmd))


BODY_SUB_MSG = "a body may not be read from a file through a substitution: use --body-file"


BODY_FLAGS = ("--body", "-b")
BODY_PREFIXES = ("--body=", "body=", "-fbody=", "-Fbody=", "--field=body=", "--raw-field=body=")
# the substitutions a body may hold: a timestamp or a commit id, nothing that reads a file or runs more
BODY_SUB_OK = re.compile(r"\s*(?:date|git\s+rev-parse)(?:\s[^;&|`$()<>\n]*)?")
FULL_CMD = ""  # the whole command line, set by main(): where a body's $VAR is assigned


def body_words(body):
    """The words of a gh segment (shell_words dicts) that are inline body values."""
    out = []
    for k, x in enumerate(body):
        d = x["deq"]
        if (k and body[k - 1]["deq"] in BODY_FLAGS) or d.startswith(BODY_PREFIXES):
            out.append(x)
        elif d.startswith("-b") and len(d) > 2 and not d.startswith("--"):  # pflag's attached -bVALUE
            out.append(x)
    return out


def substitution_texts(live):
    """The command text of each $(...) and `...` in live text (quotes already resolved)."""
    out, i, n = [], 0, len(live)
    while i < n:
        if live[i] == "`":
            e = live.find("`", i + 1)
            e = n if e < 0 else e
            out.append(live[i + 1 : e])
            i = e + 1
        elif live[i : i + 2] == "$(":
            depth, k = 1, i + 2
            while k < n and depth:
                depth += {"(": 1, ")": -1}.get(live[k], 0)
                k += 1
            out.append(live[i + 2 : k - 1])
            i = k
        else:
            i += 1
    return out


# an assigned value bash fills in from nothing but text: quoted or bare pieces, and
# inside double quotes only escapes and $NAME/${NAME} (each checked in turn)
ASSIGNED_VALUE = re.compile(
    r"""(?:'[^']*'|"(?:[^"\\$`]|\\.|\$\{?[A-Za-z_]\w*\}?)*"|\\.|[^\s$`'"\;&|()<>])*(?=[\s;&|)]|$)"""
)


def literal_assignment(name, line, depth=0):
    """True when every assignment of name on the line is text (or a date/git
    rev-parse substitution), counting a `for name in WORDS` over literal words,
    and there is at least one. A $VAR inside a double-quoted value must be
    literal too."""
    found = False
    for m in re.finditer(r"(?<![\w$-])for\s+%s\s+in\s+([^;\n]*)" % re.escape(name), line):
        if re.search(r"[$`'\"\\]", m.group(1)):
            return False
        found = True
    for m in re.finditer(r"(?<![\w$-])%s=" % re.escape(name), line):
        rest, found = line[m.end() :], True
        sub = re.match(r"""["']?\$\(([^()]*)\)["']?(?=[\s;&|)]|$)""", rest)
        if sub and BODY_SUB_OK.fullmatch(sub.group(1)):
            continue
        v = ASSIGNED_VALUE.match(rest)
        if not v:
            return False
        inner = re.findall(r"(?<!\\)\$\{?([A-Za-z_]\w*)", re.sub(r"'[^']*'", " ", v.group(0)))
        if any(n == name or depth > 3 or not literal_assignment(n, line, depth + 1) for n in inner):
            return False
    return found


def body_rule(body):
    """An inline gh body is checked as the text gh will get: a substitution in it
    may only be date or git rev-parse, and a $VAR in it must be assigned a plain
    literal on the same line. Anything else (a file read through $(cat ...),
    $(<...), a printf, a variable filled from a command) would carry text the
    guard never read."""
    for x in body_words(body):
        live = live_text(x["raw"])
        for sub in substitution_texts(live):
            if not BODY_SUB_OK.fullmatch(sub):
                deny(BODY_SUB_MSG)
        for name in re.findall(r"\$\{?([A-Za-z_]\w*)", re.sub(r"\$\([^()]*\)|`[^`]*`", " ", live)):
            if not literal_assignment(name, FULL_CMD):
                deny(BODY_SUB_MSG)


def suite_request(words):
    """A suite-change request on the harness repo: `gh issue create --repo
    <HARNEST_HARNESS_REPO>` labeled exactly suite + status:needs-approval.
    The one filing a consumer on another server may make there."""
    repo = flag_values(words, "--repo", "-R")
    labels = sorted(l for v in flag_values(words, "--label", "-l") for l in v.split(","))
    return (
        is_gh_issue(words, "create")
        and bool(repo)
        and repo[-1] == os.environ.get("HARNEST_HARNESS_REPO", "dkackman/harnest")
        and labels == ["status:needs-approval", "suite"]
    )


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
    deny(
        "target: labels are the loop driver's claims. The one change a session makes is "
        "the hand-over to lem: --remove-label target:<this server> --add-label target:lem."
    )


def target_file_rule(path, cwd, target, role):
    """Refuse a write to lem's suite or perf files from a non-lem session."""
    root = os.path.realpath(os.environ.get("HARNEST_ROOT", ""))
    full = os.path.realpath(os.path.join(cwd, path))
    if not root or os.path.commonpath([root, full]) != root:
        return
    parts = os.path.relpath(full, root).split(os.sep)
    if len(parts) == 1 and parts[0].startswith("regression-suite-") and parts[0].endswith(".md") and role != "tester":
        deny(
            "on the %s server the suite files are read-only: every case in them runs on lem, "
            "so propose a case in the issue or comment instead." % target
        )
    if parts[0] == "regression-perf" and len(parts) > 1 and not (len(parts) > 2 and parts[1] == target):
        deny(
            "on the %s server, readings go to regression-perf/%s/<case>.jsonl; the rest of "
            "regression-perf/ is another server's history." % (target, target)
        )


SHELL_KEYWORDS = ("do", "then", "else", "elif", "if", "while", "until", "{", "!", "nohup")
# commands that run another command, and the options of theirs that take a value
PREFIX_COMMANDS = {
    "env": ("-u", "-C", "-P", "--unset", "--chdir"),
    "time": (),
    "command": (),
    "exec": ("-a",),
    "nice": ("-n", "--adjustment"),
    "timeout": ("-s", "-k", "--signal", "--kill-after"),
}


def command_words(words):
    """The words from the real command on: leading NAME=value assignments,
    shell keywords (do, if, while, ...) and prefix commands with their options
    (env -i, time -p, exec -a NAME, ...) are not the command."""
    global ENV_CHDIR
    ENV_CHDIR = False
    i = 0
    while i < len(words):
        w = words[i]
        name = os.path.basename(w)
        if w in SHELL_KEYWORDS or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", w):
            i += 1
        elif name in PREFIX_COMMANDS:
            i += 1
            while i < len(words) and words[i].startswith("-") and len(words[i]) > 1:
                if name == "env" and re.match(r"--s|-[A-Za-z]*S", words[i]):
                    # -S/--split-string (or any abbreviation of it) re-splits and expands its string
                    deny("env -S is not allowed: run the command directly.")
                if name == "env" and re.match(r"--c|-[A-Za-z]*C", words[i]):
                    ENV_CHDIR = True
                i += 2 if words[i] in PREFIX_COMMANDS[name] else 1
            if name == "timeout" and i < len(words) and re.fullmatch(r"[0-9.]+[smhd]?", words[i]):
                i += 1
        else:
            break
    words = words[i:]
    if words and os.path.basename(words[0]) == "gh":  # gh's leading flags: move them behind the subcommand
        j, moved = 1, []
        while j < len(words) and words[j].startswith("-") and len(words[j]) > 1:
            n = 2 if words[j] in ("-R", "--repo", "--hostname") and j + 1 < len(words) else 1
            moved += words[j : j + n]
            j += n
        words = [words[0]] + words[j:] + moved
    return words


ARG_GH_MSG = "gh/git may not be an argument of another command: run it directly."


GH_IN_WORD = r"(?<![\w.-])gh(?![\w.-]).*?(?<![\w.-])(?:issue|api|pr)(?![\w.-])"
GIT_PUSH_IN_WORD = r"(?<![\w.-])git(?![\w.-]).*?(?<![\w.-])push(?![\w.-])"


def wrapper_rule(words):
    """A shell wrapper (bash -c, eval, xargs, su -c), or a command that takes
    one as an argument (find -exec sh -c, sudo bash -c, ssh host "gh ..."),
    hands gh or a push to a shell the label and push rules never see."""
    name = os.path.basename(words[0])
    if name in ("gh", "git"):
        return
    names = [os.path.basename(w) for w in words]
    has_c = lambda j: any(re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", w) for w in words[j + 1 :])  # noqa: E731
    wraps = any(n in ("eval", "xargs", "su") or (n in ("bash", "sh", "zsh") and has_c(j)) for j, n in enumerate(names))
    text = " ".join(words[1:])
    if wraps and (re.search(r"(?<![\w.-])gh(?![\w.-])", text) or re.search(r"\bgit\s+push\b", text)):
        deny(
            "%s runs gh or git push where the guard cannot read it: run the gh or git command directly, "
            "one issue per call." % name
        )
    for j, w in enumerate(words[1:], 1):
        if os.path.basename(w) == "gh" and words[j + 1 : j + 2] and words[j + 1] in ("issue", "api", "pr"):
            deny(ARG_GH_MSG)
        if os.path.basename(w) == "git" and git_push_args(words[j:]):
            deny(ARG_GH_MSG)
        w = UNQUOTE.sub("", re.sub(r"\\[nt]", " ", w))  # $'a\ngh ...' reaches the shell as a newline
        if re.search(r"\s", w) and (re.search(GH_IN_WORD, w, re.S) or re.search(GIT_PUSH_IN_WORD, w, re.S)):
            deny(ARG_GH_MSG)


# pulls/N/merge is pr_merge_base's to judge; a comment edit is the lead's plan PATCH
API_MERGE = re.compile(r"repos/[^/]+/[^/]+/pulls/\d+/merge")
API_COMMENT_EDIT = re.compile(r"repos/[^/]+/[^/]+/issues/comments/\d+")
API_VALUE_FLAGS = ("--method", "--header", "--field", "--raw-field", "--template", "--jq", "--hostname", "--cache")
API_VALUE_FLAGS += ("--input", "--preview", "-X", "-H", "-f", "-F", "-t", "-q", "-p")
API_FIELD_FLAGS = ("--field", "--raw-field", "-f", "-F")


def api_parse(args):
    """(method, field values, input files, positional words) of gh api's arguments."""
    method, fields, inputs, pos = "GET", [], [], []
    i = 0
    while i < len(args):
        w = args[i]
        flag, val = None, None
        if w.startswith("--") and "=" in w:
            flag, val = w.split("=", 1)
        elif w.startswith("--") or (w.startswith("-") and len(w) == 2):
            flag = w
            if flag in API_VALUE_FLAGS:
                i += 1
                val = args[i] if i < len(args) else ""
        elif w.startswith("-") and len(w) > 2 and w[:2] in API_VALUE_FLAGS:
            flag, val = w[:2], w[2:]
        else:
            pos.append(w)
        if flag in ("-X", "--method"):
            method = val
        elif flag in API_FIELD_FLAGS:
            fields.append(val)
        elif flag == "--input":
            inputs.append(val)
        i += 1
    return method, fields, inputs, pos


UNREADABLE_BODY_MSG = "body must be inline or a readable file: the guard cannot check a marker it cannot read."


RIDE_ALONG_VERBS = ("comment", "edit", "close", "reopen", "view")


def ride_along_ok(words):
    """A segment that may share a line with a body-file call: a plain `gh issue
    comment|edit|close|reopen|view` (or the body-file `create` itself), with no
    assignment or prefix command before it and no --web/--editor, which run a
    browser or editor command that could rewrite the body file."""
    if len(words) < 3 or words[0] != "gh" or words[1] != "issue":
        return False
    if words[2] not in RIDE_ALONG_VERBS and not (words[2] == "create" and flag_values(words, "--body-file", "-F")):
        return False
    return not any(re.match(r"--(web|editor)\b|-[A-Za-z]*[we][A-Za-z]*$", w) for w in words[3:])


IFS_MSG = "$IFS is not allowed in a command word: bash splits it where the guard reads one word."
EXPANSION = r"\$(?:\{[^}]*\}|\w+|.)"


def ifs_rule(text, segs):
    """$IFS (or any expansion inside a gh/git word, g${X}h, gh$E) is split or
    filled in by bash after the guard has read the word."""
    if re.search(r"\$\{?IFS\b", text):
        deny(IFS_MSG)
    for words in segs:
        for w in words:
            if "$" in w and not re.search(r"\s", w) and re.match(r"(gh|git)(?![\w.-])", re.sub(EXPANSION, "", w)):
                deny("an expansion inside a gh or git word is filled in after the guard reads it: write the word out.")


def redirects_ok(words):
    """No `>`/`>>` redirect to a file but /dev/null (the heredoc writes are cut out already)."""
    for k, w in enumerate(words):
        if w and set(w) <= set("<>") and ">" in w:
            if k + 1 >= len(words) or words[k + 1] != "/dev/null":
                return False
    return True


def unreadable_body_rule(paths):
    """Refuse a comment body the guard cannot vouch for: stdin, a missing or
    unreadable file, a path bash would expand (~) or env -C would move, or a
    file that is not read the way the guard read it (see main: SOLE_COMMAND).
    A file the same line writes with `cat > PATH <<EOF` is checked as raw text."""
    for path in paths:
        if "~" in path:
            deny("a body file path may not contain ~: write the full path.")
        if path in HEREDOC_PATHS:
            continue
        try:
            if path == "-" or not os.path.isfile(resolve(path)):
                raise OSError
            open(resolve(path)).close()
        except OSError:
            deny(UNREADABLE_BODY_MSG)
    if paths and (ENV_CHDIR or not SOLE_COMMAND or any(h not in paths for h in HEREDOC_PATHS)):
        deny("a body file must be the only command on the line: the guard reads it before gh does.")


def api_text_has_marker(fields, inputs):
    for v in fields:
        if RELEASE_MARKER in v:
            return True
        if "=@" in v:
            inputs = inputs + [v.split("=@", 1)[1]]
    for path in inputs:
        try:
            if RELEASE_MARKER in open(resolve(path)).read():
                return True
        except OSError:
            pass
    return False


def implementer_api_rule(words):
    """gh api is a read for these roles; a write (any method but GET, or any
    field) bypasses every gh issue rule. Two writes are allowed: the PR merge
    that pr_merge_base judges, and the lead's plan-comment PATCH (never with a
    release marker in it)."""
    if len(words) < 3 or os.path.basename(words[0]) != "gh" or words[1] != "api":
        return
    method, fields, inputs, pos = api_parse(words[2:])
    if len(pos) != 1:
        deny("gh api takes one endpoint; write the call with exactly one, and pass the rest as flags.")
    if method.upper() == "GET" and not fields and not inputs:
        return
    endpoint = pos[0].strip("/")
    unreadable_body_rule([v.split("=@", 1)[1] for v in fields if "=@" in v] + inputs)
    if not re.fullmatch(r"[A-Za-z0-9_./-]+", endpoint):
        deny("a gh api write names its endpoint in plain path characters only (no ?, #, &, % or spaces).")
    if API_MERGE.fullmatch(endpoint):
        if method.upper() != "PUT":
            deny("the PR merge endpoint takes PUT only.")
        return
    if API_COMMENT_EDIT.fullmatch(endpoint) and method.upper() == "PATCH":
        if api_text_has_marker(fields, inputs):
            deny(
                "a release marker is run-release.sh's record of a gate Don ran or a problem he waived; "
                "no agent writes one."
            )
        return
    deny(
        "gh api writes (a method other than GET, or -f/-F/--field/--input) go round the gh issue rules: "
        "use gh issue edit/comment/close. The one gh api write is the lead's plan-comment PATCH "
        "(repos/<o>/<r>/issues/comments/<id>)."
    )


def consumer_git_rule(words):
    """The consumer is source-blind: no repository command pointed at another tree."""
    if os.path.basename(words[0]) != "git":
        return
    for w in words[1:]:
        if w in ("--git-dir", "--work-tree", "-C", "--no-index") or w.startswith(("--git-dir=", "--work-tree=")):
            deny(
                "the consumer reads no source: --git-dir/--work-tree/-C/--no-index reach another tree. "
                "Work through the dw tools and the issue text."
            )


CONSUMER_ISSUE_SUBCOMMANDS = ("view", "list", "create", "comment", "edit", "close", "reopen", "status")


ROLES = ("implementer", "lead", "consumer", "curator", "reviewer")


def main():
    role = sys.argv[1] if len(sys.argv) > 1 else ""
    if role not in ROLES:
        deny("unknown guard role %r: the hook is configured with a role name it does not know." % role)
    data = json.load(sys.stdin)
    cwd = data.get("cwd") or os.getcwd()
    server = other_target()
    target = server if role == "consumer" else ""
    if data.get("tool_name") in ("Edit", "Write"):
        if target:
            target_file_rule(
                data.get("tool_input", {}).get("file_path", ""),
                cwd,
                target,
                os.environ.get("HARNEST_ROLE", "regression"),
            )
        return
    if data.get("tool_name") != "Bash":
        return
    cmd = data.get("tool_input", {}).get("command", "")
    global FULL_CMD
    FULL_CMD = cmd
    stripped, written = heredoc_cut(inline_cat_subs(cmd))  # a quoted-delimiter heredoc body is data, not commands
    subsegs, inner, residual = substitutions(stripped)
    segs = segments(stripped) + subsegs
    ifs_rule(stripped, segs)
    for text in [stripped] + inner:
        expansion_rules(text, role)
    unread = live_text(residual)
    left = bool(re.search(r"(?<!\\)(?:\$\(|`)", unread))
    while re.search(r"\([^()]*\)", unread):
        unread = re.sub(r"\([^()]*\)", " ", unread)
    # a $( or backtick left over, or (once a substitution was read) a stray ) that a case
    # pattern or a comment inside it would explain: the substitution was not read whole
    bare = UNQUOTE.sub("", stripped)
    gh_or_push = any(
        re.search(r"(?<![\w.-])gh(?![\w.-])", t) or re.search(r"(?<![\w.-])git(?![\w.-])[\s\S]*?\bpush\b", t)
        for t in (stripped, bare)
    )
    if gh_or_push and (left or (inner and ")" in unread)):
        deny(
            "a command substitution the guard cannot read (parentheses inside $(...)) on a gh/git line: run gh directly."
        )
    global HOOK_CWD, SOLE_COMMAND
    HOOK_CWD = data.get("cwd") or ""
    HEREDOC_PATHS[:] = written
    rest = re.sub(r"\d*>&\d+", " ", stripped)
    rsegs = segments(rest)
    SOLE_COMMAND = (
        bool(rsegs)
        and (len(rsegs) == 1 or all(ride_along_ok(g) for g in rsegs))
        and "`" not in rest
        and "$(" not in rest
        and "harnest:" not in rest
        and RELEASE_MARKER not in cmd
        and all(redirects_ok(g) for g in rsegs)
    )
    if CAT_REDEFINED and re.search(GH_WORD, UNQUOTE.sub("", cmd)):
        deny("this line may redefine cat (a function, alias, hash, PATH, ...), so its $(cat <<EOF) runs: split it.")
    if marker_through_punctuation(cmd):
        deny(
            "a release marker is run-release.sh's record of a gate Don ran or a problem he waived; no agent writes one."
        )
    if UNBALANCED and re.search(r"(?<![\w.-])gh(?![\w.-])", UNQUOTE.sub("", stripped)):
        deny("unbalanced quote in a gh command: write it on one line with matched quotes.")
    for words in segs:
        words = command_words(words)
        if not words:
            continue
        if role == "consumer":
            consumer_git_rule(words)
        if role in ("implementer", "lead"):
            implementer_api_rule(words)
        if role in ("implementer", "lead"):
            wrapper_rule(words)
        if role == "implementer" and server:
            lead = 0  # env assignments before the command (FOO=1 ssh ...), not an ssh -o Key=value
            while lead < len(words) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[lead]):
                lead += 1
            cmdw = words[lead:]
            if (
                cmdw
                and os.path.basename(cmdw[0]) in ("ssh", "scp", "rsync")
                and not (os.path.basename(cmdw[0]) == "ssh" and ssh_host(cmdw) == own_host())
            ):
                deny(
                    "this loop runs against the %s server: ssh only to its host (%s), to read; no "
                    "scp or rsync; lem is off limits." % (server, own_host() or "unknown")
                )
            if any(os.path.basename(w) == "deploy.sh" or w.endswith("/deploy.sh") or "deploy.sh " in w for w in cmdw):
                deny(
                    "on the %s server the driver deploys develop after your session: your own "
                    "MCP connection would hold the old server open. Merge, push and hand off." % server
                )
        if (
            role == "consumer"
            and len(words) >= 3
            and os.path.basename(words[0]) == "gh"
            and words[1] == "issue"
            and words[2] not in CONSUMER_ISSUE_SUBCOMMANDS
        ):
            deny("gh issue %s is not a consumer action (delete, transfer, lock, pin, develop are Don's)." % words[2])
        if is_gh_issue(words, "edit"):
            claim_rule(words, server if role in ("consumer", "implementer") else "")
            if any(l.startswith("verified-on:") for l in flag_values(words, "--add-label")) and not target:
                deny("verified-on: marks a verification made on another server, by that server's tester.")
        if (
            target
            and is_gh_issue(words, "edit")
            and adds_verified(words)
            and "verified-on:mps" not in flag_values(words, "--add-label")
        ):
            deny(
                "on the %s server a verification adds verified-on:mps with status:verified, so lem "
                "can tell CUDA hasn't re-verified it." % target
            )
        if target and (is_gh_issue(words, "create") or is_gh_issue(words, "comment")):
            ticket_repo = os.environ.get("HARNEST_TICKET_REPO", "")
            harness_repo = os.environ.get("HARNEST_HARNESS_REPO", "dkackman/harnest")
            repo = flag_values(words, "--repo", "-R")
            if ticket_repo and (not repo or repo[-1] != ticket_repo) and not suite_request(words):
                deny(
                    "from the %s server, issues are filed and commented on %s only (--repo %s). "
                    "The one exception is a suite-change request: --repo %s with exactly "
                    "--label suite --label status:needs-approval." % (target, ticket_repo, ticket_repo, harness_repo)
                )
        if target and is_gh_issue(words, "comment") and label_lookup(words, "target:lem") is not False:
            deny(
                "from the %s server, no comment on an issue lem's loop holds (target:lem), or one "
                "that couldn't be checked: file your own with a backend: label and reference it." % target
            )
        if target and is_gh_issue(words, "create") and not suite_request(words):
            labels = flag_values(words, "--label", "-l")
            backends = [l for l in labels if l.startswith("backend:")]
            if (
                backends not in (["backend:mps"], ["backend:shared"])
                or any(l.startswith("target:") for l in labels)
                or len([l for l in labels if l.startswith("owner:")]) > 1
            ):
                deny(
                    "an issue from the %s server carries exactly one backend:mps or backend:shared "
                    "(a cuda bug can't be seen here), one owner, and no target: label (claims are "
                    "the driver's)." % target
                )
        if (is_gh_issue(words, "create") and "security" in flag_values(words, "--label", "-l")) or (
            is_gh_issue(words, "edit") and "security" in flag_values(words, "--add-label")
        ):
            deny(
                "a security finding is filed privately, never as a public issue: "
                "scripts/file-advisory.sh --summary ... --description-file ... --severity ... "
                "(the implementer: $HARNEST_ROOT/scripts/file-advisory.sh)."
            )
        if role in ("implementer", "lead") and (
            is_gh_issue(words, "comment") or is_gh_issue(words, "create") or is_gh_issue(words, "edit")
        ):
            unreadable_body_rule(flag_values(words, "--body-file", "-F"))
        if carries_release_marker(words):
            deny(
                "a release marker is run-release.sh's record of a gate Don ran or a problem he waived; no agent writes one."
            )
        added = (
            flag_values(words, "--add-label")
            if is_gh_issue(words, "edit")
            else flag_values(words, "--label", "-l")
            if is_gh_issue(words, "create")
            else []
        )
        if "status:plan-approved" in added:
            deny(
                "status:plan-approved is Don's to add: approving a feature plan is a human decision, "
                "and no agent may approve a plan, its own or another's."
            )
        if {"release", "release-blocker"} & set(added):
            deny(
                "release and release-blocker are Don's to add: a freeze, and what may move during "
                "one, are his calls (R14)."
            )
        if is_gh_issue(words, "create") and {"status:verified", "status:fixed-pending-verify"} & set(added):
            deny(
                "an issue is never filed already verified or already handed off: create it without a "
                "status label and let the hand-off and the tester add them."
            )
        if is_gh_issue(words, "edit"):
            if role != "curator":
                owner_rule(words)
            removed = flag_values(words, "--remove-label")
            if "owner:don" in removed:
                deny("owner:don / status:needs-approval is a park with the human; only a human lifts it.")
            if "status:needs-approval" in removed and still_parked(words):
                deny("owner:don / status:needs-approval is a park with the human; only a human lifts it.")
        if "arch-approved" in added:
            deny(
                "arch-approved is Don's to add: it waives new surface during a freeze, a ratchet rise and an "
                "architecture review's blocking finding, each his call."
            )
        if "arch-review" in added:
            deny(
                "arch-review is the loop driver's: it queues the architecture review of a hand-off that "
                "changed dw/ or dw_mcp/."
            )
        if is_gh_issue(words, "edit") and "arch-review" in flag_values(words, "--remove-label") and role != "reviewer":
            deny(
                "only the reviewer removes arch-review, with its verdict: the architecture review comes "
                "before the tester's."
            )
        if role == "reviewer":
            if os.environ.get("HARNEST_SESSION_KIND") == "arch" and is_gh_issue(words, "close"):
                deny("an architecture review closes nothing: pass the fix on (remove arch-review) or bounce it.")
            if adds_verified(words):
                deny("status:verified claims an MCP check; a docs review adds status:reviewed instead.")
        if role in ("implementer", "lead", "reviewer"):
            if role != "reviewer" and closes_completed(words):
                deny(
                    "only the tester closes an issue as completed. gh closes as completed by default: "
                    'pass --reason "not planned" for wontfix/duplicate.'
                )
            if role != "reviewer" and adds_verified(words):
                deny("status:verified is the tester's to add, from a real MCP call.")
        if role == "implementer":
            problem = git_push_problem(words)
            if problem:
                deny(problem)
            if is_gh_issue(words, "edit") and "status:fixed-pending-verify" in flag_values(words, "--add-label"):
                arch_gate(cwd, "HEAD", lambda words=words: issue_has_label(words, "arch-approved"))
                handoff_gate(cwd)
            base = pr_merge_base(words)
            if base in ("", "develop") and merge_gated(cwd):
                deny(
                    "this merges a PR into develop%s on GitHub, where the hot zone, the architecture ratchet "
                    "and the freeze can't see what it adds. Merge it locally and push develop, which they "
                    "check." % ("" if base else " (or its base couldn't be read)")
                )
            issue = os.environ.get("HARNEST_ISSUE", "")
            push = pushed_develop(words, cwd)
            if push:  # the hot zone and ratchet need no issue; the waiver and new surface do
                arch_gate(
                    push[0],
                    push[1],
                    (
                        lambda issue=issue: (
                            label_on(issue, os.environ.get("HARNEST_TICKET_REPO", ""), "arch-approved") is True
                        )
                    )
                    if issue
                    else None,
                )
        elif role == "consumer":
            # A tester HANDOFF session applies a harness-side edit the
            # implementer asked for and closes the issue as done: nothing
            # to run over MCP, so its close is exempt. Adding
            # status:verified is not: that label claims an MCP check.
            handoff = os.environ.get("HARNEST_SESSION_KIND") == "handoff"
            if adds_verified(words) or (closes_completed(words) and not handoff):
                if not session_called_mcp(data.get("transcript_path", "")):
                    deny(
                        "verifying (closing as completed / status:verified) needs a real MCP call in this "
                        "session, and this session has made none. Re-run the repro over the dw tools first."
                    )


try:
    main()
except SystemExit:
    raise
except Exception as exc:  # a crash must refuse the call, never let it through
    print(f"Blocked by the harness guard (R3): guard error: {type(exc).__name__}: {exc}", file=sys.stderr)
    sys.exit(2)
