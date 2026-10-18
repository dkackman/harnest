"""Model/provider resolution: the one table mapping a (provider, model) pair
to the environment its claude process needs. A port of providers.sh's
resolve_model_env and friends; the comments there say why each variable is
set, and they hold here unchanged.

Every validator raises ProviderError with the message the bash prints on
stderr, so a driver that calls them at startup fails there, not three
minutes in.
"""

import os
import re
from dataclasses import dataclass, field

KNOWN_PROVIDERS = ("anthropic", "ollama", "gateway")
EFFORTS = ("low", "medium", "high", "xhigh", "max")

# The values CO_AUTHOR / CO_AUTHOR_EMAIL had at import, i.e. what the user
# set; co_author_for consults these, never a value it derived itself.
_USER_CO_AUTHOR = os.environ.get("CO_AUTHOR", "")
_USER_CO_AUTHOR_EMAIL = os.environ.get("CO_AUTHOR_EMAIL", "")


class ProviderError(Exception):
    pass


def is_anthropic_model(model):
    """Structural, not an allowlist: an alias (opus, opus[1m]), a full id, or
    a Bedrock/Vertex id. The bash `case` pattern, exactly."""
    return "claude" in model or model.startswith(("opus", "sonnet", "haiku", "fable")) or model in ("default", "best")


@dataclass
class ModelEnv:
    label: str  # "<provider>/<model>"
    set: dict = field(default_factory=dict)
    unset: list = field(default_factory=list)
    context_tokens: str = ""  # the declared window, or "" for the model's own

    def apply(self, env):
        """env with this pair's unsets and assignments applied (env -u ... V=...)."""
        out = dict(env)
        for k in self.unset:
            out.pop(k, None)
        out.update(self.set)
        return out


def resolve_model_env(provider, model, environ=None):
    e = os.environ if environ is None else environ
    me = ModelEnv(label=f"{provider}/{model}")
    if provider == "anthropic":
        if not is_anthropic_model(model):
            raise ProviderError(
                f"run: model '{model}' is not an Anthropic model name, but its provider is 'anthropic'.\n"
                "     Either set <ROLE>_MODEL to a Claude alias/id, or set PROVIDER\n"
                "     (or <ROLE>_PROVIDER) to ollama|gateway for that model."
            )
        me.unset = [
            "ANTHROPIC_BASE_URL",
            "ANTHROPIC_AUTH_TOKEN",
            "ANTHROPIC_DEFAULT_OPUS_MODEL",
            "ANTHROPIC_DEFAULT_SONNET_MODEL",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL",
        ]
    elif provider == "ollama":
        if is_anthropic_model(model):
            raise ProviderError(
                f"run: model '{model}' is an Anthropic model name, which Ollama does not serve.\n"
                "     Set <ROLE>_MODEL to the Ollama tag, e.g. gemma4:31b-it-q4_K_M."
            )
        ctx = e.get("OLLAMA_CONTEXT_TOKENS", "")
        if not ctx:
            raise ProviderError(
                "run: provider 'ollama' needs OLLAMA_CONTEXT_TOKENS — the model's context window in tokens.\n"
                "     It must not exceed the Ollama server's own window (OLLAMA_CONTEXT_LENGTH / num_ctx);\n"
                "     Ollama's Claude Code guidance uses 64k, e.g. OLLAMA_CONTEXT_TOKENS=65536."
            )
        if not re.fullmatch(r"[0-9]+", ctx):
            raise ProviderError(f"run: OLLAMA_CONTEXT_TOKENS must be a whole number of tokens, got '{ctx}'.")
        me.context_tokens = ctx
        token = e.get("OLLAMA_TOKEN") or "ollama"
        me.set = {
            "ANTHROPIC_BASE_URL": e.get("OLLAMA_BASE_URL") or "http://127.0.0.1:11434",
            "ANTHROPIC_AUTH_TOKEN": token,
            "ANTHROPIC_API_KEY": token,
            "ANTHROPIC_DEFAULT_OPUS_MODEL": model,
            "ANTHROPIC_DEFAULT_SONNET_MODEL": model,
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": model,
            "CLAUDE_CODE_SUBAGENT_MODEL": model,
            "CLAUDE_CODE_MAX_CONTEXT_TOKENS": ctx,
            "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
            "CLAUDE_CODE_TOTAL_TOKENS_REMINDER": "off",
            "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
            "ENABLE_TOOL_SEARCH": "true",
        }
        if e.get("OLLAMA_STRICT_SUPPRESS"):
            me.set.update(
                {
                    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
                    "MAX_THINKING_TOKENS": "0",
                    "DISABLE_PROMPT_CACHING": "1",
                }
            )
    elif provider == "gateway":
        base = e.get("GW_BASE_URL", "")
        if not base:
            raise ProviderError("run: provider 'gateway' needs GW_BASE_URL — the endpoint that speaks /v1/messages.")
        me.set = {"ANTHROPIC_BASE_URL": base}
        if e.get("GW_TOKEN"):
            me.set.update({"ANTHROPIC_AUTH_TOKEN": e["GW_TOKEN"], "ANTHROPIC_API_KEY": e["GW_TOKEN"]})
        me.set["ENABLE_TOOL_SEARCH"] = "true"
        if e.get("GW_CONTEXT_TOKENS"):
            me.context_tokens = e["GW_CONTEXT_TOKENS"]
            me.set["CLAUDE_CODE_MAX_CONTEXT_TOKENS"] = e["GW_CONTEXT_TOKENS"]
    else:
        raise ProviderError(f"run: unknown provider '{provider}' (known: {' '.join(KNOWN_PROVIDERS)})")
    return me


def validate_fallback_model(provider, fallback):
    if not fallback:
        return
    if provider == "anthropic" and not is_anthropic_model(fallback):
        raise ProviderError(
            f"run: FALLBACK_MODEL '{fallback}' is not an Anthropic model name, but the provider is 'anthropic'."
        )
    if provider == "ollama" and is_anthropic_model(fallback):
        raise ProviderError(
            f"run: FALLBACK_MODEL '{fallback}' is an Anthropic model name, which Ollama does not serve."
        )
    if provider not in KNOWN_PROVIDERS:
        raise ProviderError(f"run: unknown provider '{provider}' (known: {' '.join(KNOWN_PROVIDERS)})")


def effort_flags(provider, effort):
    """--effort for anthropic only: it is an Anthropic request parameter."""
    if effort not in EFFORTS:
        raise ProviderError(f"run: effort must be one of low|medium|high|xhigh|max, got '{effort}'")
    return ["--effort", effort] if provider == "anthropic" else []


def session_flags(provider, model, effort, budget, fallback="", autocompact="120000"):
    """--model, --fallback-model, --effort, --autocompact and --max-budget-usd
    (omitted at 0, which means none): providers.sh's session_flags."""
    flags = ["--model", model]
    validate_fallback_model(provider, fallback)
    if fallback:
        flags += ["--fallback-model", fallback]
    flags += effort_flags(provider, effort)
    flags += ["--autocompact", autocompact or "120000"]
    if str(budget) != "0":
        flags += ["--max-budget-usd", str(budget)]
    return flags


def co_author_for(provider, model):
    """(name, email) for the Co-Authored-By trailer: honest about which model
    edited the suite. A user-set CO_AUTHOR / CO_AUTHOR_EMAIL overrides each."""
    if is_anthropic_model(model):
        name = f"Claude ({model})"
        if provider != "anthropic":
            name += f" (via {provider})"
        email = "noreply@anthropic.com"
    else:
        name, email = f"{model} (via {provider})", "noreply@localhost"
    return (_USER_CO_AUTHOR or name, _USER_CO_AUTHOR_EMAIL or email)
