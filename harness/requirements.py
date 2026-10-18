"""What each regression case needs, and where it may run.

regression-requirements.json, keyed by case ID, records the models, assets
and load a case needs, and a hash of the case's text when that was
decided. The suites are never edited for it: it decides only where a case
runs, never whether or what it expects. An entry that is missing, or whose
hash no longer matches the case, sends the case to the primary only, which
holds every model and may download: incomplete data is slower, never wrong.

Cases that name each other (a `cleanup:` holding an output for a later
case, a `setup:` reusing an earlier one's) are one dependency group: one
lane, in file order. docs/superpowers/specs/2026-10-18-regression-fleet.md.
"""

import fnmatch
import hashlib
import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

from . import REPO
from .suite import CASE_HEADING

SIDECAR = REPO / "regression-requirements.json"  # HARNEST_REQUIREMENTS overrides it
LOADS = ("none", "light", "heavy", "exclusive")
_ID = re.compile(r"\b([A-Z]+-[A-Z][0-9]+)\b")


def case_blocks(suite_file):
    """{case id: its block}, from its heading to the next heading, in file order."""
    blocks, cur, lines = {}, None, []
    for line in Path(suite_file).read_text(encoding="utf-8").splitlines(keepends=True):
        if line.startswith("#"):
            if cur:
                blocks[cur] = "".join(lines)
            m = CASE_HEADING.match(line)
            cur, lines = (m.group(1), [line]) if m else (None, [])
        elif cur:
            lines.append(line)
    if cur:
        blocks[cur] = "".join(lines)
    return blocks


def block_hash(text):
    """Whitespace-insensitive, so reflowing a paragraph doesn't stale an entry."""
    return hashlib.sha256(" ".join(text.split()).encode()).hexdigest()[:16]


@dataclass
class Need:
    workflows: tuple = ()  # what the case runs by name; each server validates them
    models: tuple = ()  # every model it loads (inline workflows, and for deny/size rules)
    assets: tuple = ()
    load: str = "light"
    known: bool = False  # an entry exists and matches the case's text
    why_unknown: str = ""

    def union(self, other):
        return Need(
            workflows=tuple(sorted(set(self.workflows) | set(other.workflows))),
            models=tuple(sorted(set(self.models) | set(other.models))),
            assets=tuple(sorted(set(self.assets) | set(other.assets))),
            load=max(self.load, other.load, key=LOADS.index),
            known=self.known and other.known,
            why_unknown=self.why_unknown or other.why_unknown,
        )


def load_sidecar(path=None):
    path = path or os.environ.get("HARNEST_REQUIREMENTS") or SIDECAR
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except ValueError as e:
        raise ValueError(f"{path}: {e}") from e
    return data.get("cases", {}) if isinstance(data, dict) else {}


def need_for(case_id, block, sidecar):
    e = sidecar.get(case_id)
    if not isinstance(e, dict):
        return Need(why_unknown="no requirements entry")
    if e.get("hash") != block_hash(block):
        return Need(why_unknown="the case changed since its entry")
    load = e.get("load", "light")
    if load not in LOADS:
        return Need(why_unknown=f"unknown load '{load}'")
    return Need(
        workflows=tuple(e.get("workflows", ())),
        models=tuple(e.get("models", ())),
        assets=tuple(e.get("assets", ())),
        load=load,
        known=True,
    )


@dataclass
class Group:
    cases: list  # case ids, in file order
    need: Need = field(default_factory=Need)

    @property
    def weight(self):
        return len(self.cases)


def _link_text(block):
    """A case's `cleanup:` and `setup:` paragraphs (each runs to a blank line)."""
    out, on = [], False
    for line in block.splitlines():
        if re.match(r"(cleanup|setup):", line):
            on = True
        elif not line.strip():
            on = False
        if on:
            out.append(line)
    return "\n".join(out)


def groups(suite_file, sidecar, skip=()):
    """The suite's dependency groups, in order of their first case. A case
    naming another case of the same suite joins its group; <skip> (script
    cases, held-back cases) are left out, and so are their links."""
    blocks = case_blocks(suite_file)
    ids = [i for i in blocks if i not in skip]
    parent = {i: i for i in ids}

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in ids:
        # Only the lines that hand outputs between cases: a body's "same
        # probe as S-F005" is a cross-reference, not a dependency, and
        # linking on it chained a third of the complete suite together.
        for ref in _ID.findall(_link_text(blocks[i])):
            if ref != i and ref in parent:
                parent[find(ref)] = find(i)
    out = {}
    for i in ids:
        r = find(i)
        n = need_for(i, blocks[i], sidecar)
        if r in out:
            out[r].cases.append(i)
            out[r].need = out[r].need.union(n)
        else:
            out[r] = Group(cases=[i], need=n)
    return list(out.values())


def reference_sizes(all_facts):
    """A model's full size: the largest any server reports, from its cache
    or from validate_workflow's downloads_required (a partial cache
    understates it)."""
    sizes = {}
    for f in all_facts:
        for repo, gb in f.models.items():
            sizes[repo] = max(sizes.get(repo, 0), gb)
        for check in f.workflows.values():
            for m in check.get("missing", ()):
                sizes[m["repo"]] = max(sizes.get(m["repo"], 0), float(m.get("gb") or 0))
    return sizes


def workflow_names(sidecar):
    """Every workflow any entry names, for validating once per server."""
    return sorted({w for e in sidecar.values() if isinstance(e, dict) for w in e.get("workflows", ())})


def eligible(need, server, facts, ref_sizes):
    """(True, "") when a group with <need> may run on <server>, else (False, why)."""
    if not need.known:
        return (True, "") if server.primary else (False, f"primary only: {need.why_unknown}")
    if need.load in ("heavy", "exclusive") and not server.heavy:
        return False, f"{need.load} load"
    missing = {}
    for w in need.workflows:
        check = facts.workflows.get(w)
        if check is None or check.get("error"):
            return False, f"{w} doesn't validate here: {check.get('error') if check else 'not checked'}"
        for m in check["missing"]:
            missing[m["repo"]] = m
    for repo, m in missing.items():
        if m["blocked"]:
            return False, f"{repo} is licence-gated for this box's Hugging Face token"
        if not server.downloads:
            return False, f"{repo} is not cached ({float(m.get('gb') or 0):.0f} GB to download)"
    for m in sorted(set(need.models) | set(missing)):
        if any(fnmatch.fnmatch(m, pat) for pat in server.deny_models):
            return False, f"{m} is denied here"
        if m not in facts.models and not server.downloads:
            return False, f"{m} is not cached"
        if server.max_model_gb and ref_sizes.get(m, 0) > server.max_model_gb:
            return False, f"{m} is {ref_sizes[m]:.0f} GB, over {server.max_model_gb:g}"
    for a in need.assets:
        if a not in facts.assets:
            return False, f"asset {a} is not here"
    return True, ""
