"""Prompt assembly: providers.sh's role_prompt, runtime_note and target_note."""
from . import REPO
from .providers import is_anthropic_model

AGENTS = REPO / "agents"

# role:kind -> the fragments concatenated, core first (R10).
FRAGMENTS = {
    "implementer:fix": ("core", "fix"),
    "implementer:triage": ("core", "triage"),
    "tester:verify": ("core", "verify", "cases"),
    "tester:handoff": ("core", "handoff", "cases"),
    "tester:answer": ("core", "answer"),
    "tester:closures": ("core", "closures"),
    "tester:task": ("core", "closures", "task", "cases", "standing-task"),
    "tester:spec": ("core", "spec", "cases"),
    "lead:design": ("core", "design"),
    "lead:decompose": ("core", "decompose"),
    "lead:build": ("core", "build"),
    "lead:closeout": ("core", "closeout"),
    "curator:audit": ("core", "audit"),
    "curator:review": ("core", "review"),
    "reviewer:docs": ("core", "docs"),
    "reviewer:arch": ("core", "arch"),
    "release:review": ("core", "review"),
    "release:notes": ("core", "notes"),
    "regression:whole": ("core", "run-cases", "sweep"),
    "regression:chunk": ("core", "run-cases", "chunk"),
    "regression:sweep": ("core", "sweep"),
}


class PromptError(Exception):
    pass


def role_prompt(role, kind, out, agents=AGENTS):
    """Writes <role>'s prompt for a <kind> session to <out>; returns <out>."""
    parts = FRAGMENTS.get(f"{role}:{kind}")
    if parts is None:
        raise PromptError(f"role_prompt: no prompt for {role}:{kind}")
    files = [agents / role / f"{p}.md" for p in parts]
    for f in files:
        if not f.is_file():
            raise PromptError(f"role_prompt: missing agents/{role}/{f.name}")
    with open(out, "wb") as o:
        for f in files:
            o.write(f.read_bytes())
    return out


_EXAMPLES = {
    "implementer": "a ticket hand-off comment, a wontfix or needs-info reason, a regression case you propose in a hand-off",
    "tester": "a verification comment, a bounce, a new issue, a regression-suite edit",
    "regression": "an issue body, a comment on an existing issue",
    "lead": "a feature plan and its verdict, an idea's disposition, a stage issue, a hand-off comment, a re-plan",
    "curator": "a curation proposal, a ruling on a suite request, an escalation to Don",
    "reviewer": "a docs review verdict, a bounce",
    "release": "a release review finding, a release-notes draft",
    "retro": "a harness proposal and its evidence",
}


def runtime_note(role, provider, model, secondary=False):
    """The "Runtime:" paragraph: which model and provider the agent is, so
    what it records durably can be told apart from another model's. A
    regression run on a secondary server may not edit a suite, so it is not
    told it does. No trailing newline (it is interpolated with $(...))."""
    if role not in _EXAMPLES:
        raise PromptError(f"run: runtime_note: unknown role '{role}' "
                          "(implementer|tester|regression|lead|curator|reviewer|release|retro)")
    examples = _EXAMPLES[role]
    if role == "regression" and not secondary:
        examples += ", a suite-file edit"
    id_hint = (" Use the exact model id your system prompt states (e.g. claude-opus-5), not the alias."
               if is_anthropic_model(model) else "")
    return "\n".join([
        f"Runtime: you are the {role} agent, running as model '{model}' via the '{provider}'",
        "provider. Whenever you record something durable that rests on your own",
        f"judgment — {examples} —",
        "name that model and provider in it, so a later reader can tell which model",
        f"produced it.{id_hint}",
    ])


def target_note(role, values, agents=AGENTS):
    """agents/<role>/target.md with its {{PLACEHOLDERS}} filled in: the rules
    a session on a server other than the primary follows."""
    f = agents / role / "target.md"
    if not f.is_file():
        raise PromptError(f"target_note: {f} is missing")
    text = f.read_text(encoding="utf-8")
    for key in ("TARGET", "SERVER", "URL", "DEPLOY", "HOST", "SERVER_DIR"):
        text = text.replace("{{" + key + "}}", values.get(key, ""))
    return text
