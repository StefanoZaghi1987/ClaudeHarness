# Prompt for Claude Code — Advanced Opusplan Configuration

You are a senior Claude Code platform engineer specializing in model routing, cost optimization, and long-term configuration maintainability.

## TASK

Audit and reconfigure my Claude Code setup (user settings, rules, subagents, advisor, fallback chains, and a maintenance command) to implement an **"advanced opusplan" model-routing strategy**: plan-default model and effort for standard work, highest-tier model for complex reasoning phases, tier-by-tier fallback, and a configuration that stays valid as model names, versions, and best practices evolve.

## CONTEXT

- This configuration must be project-agnostic: it will be applied across any language, framework, or repository.
- Goals, in priority order: (1) maximize code quality and architectural quality on complex tasks, (2) minimize token usage on everything else, (3) zero maintenance debt from hardcoded model names.
- "Complex tasks" means: planning/architecture design, design-spec review, implementation-plan review, and code review. Everything else is a "standard task."

## MANDATORY VERIFICATION STEP (do this FIRST, before changing anything)

Do not rely on your training data for any Claude Code configuration detail. Before proposing or writing any change:

1. Fetch the official documentation index at `https://code.claude.com/docs/llms.txt` and from it read, at minimum, the current pages on: **model configuration**, **settings**, **subagents**, **advisor**, **effort levels**, and **slash commands / skills**.
2. Determine my actual runtime context: provider (Anthropic API vs. subscription vs. Bedrock/Vertex/Foundry), plan type, Claude Code version, and which models/aliases are actually available to me (use `/status`-equivalent information, settings inspection, and the docs — ask me only for what you cannot detect).
3. For every settings key, alias, frontmatter field, and flag you use, confirm it exists in the current docs with the exact spelling and semantics. If the docs contradict anything in this prompt, the docs win — tell me about the discrepancy instead of guessing.
4. In your final report, cite the specific doc page that justifies each configuration choice.

## REQUIREMENTS

**R1 — Standard tasks run on my plan's default model.**
Ensure the effective session model is the **Default** for my plan/account type. Concretely: do not hardcode any versioned model ID; if my user/project settings currently pin a `model` value that overrides the plan default, surface it and (after my confirmation) remove or correct it so the plan default applies. The configuration must keep resolving to whatever my plan's default becomes in the future.

**R2 — Standard tasks run at my plan/model's default effort.**
Ensure no persistent effort override is in force (settings, environment variables, or saved session effort). The effective effort must be the model's documented default (the `/effort auto` behavior). Report the current effective effort and its source before and after.

**R3 — Latest releases only, via aliases.**
Use **model aliases exclusively** (`default`, `best`, `fable`, `opus`, `sonnet`, `haiku`, and their documented variants). Never write a versioned model ID (e.g., `claude-opus-4-8`) into any settings file, subagent, skill, or command. Aliases must be the mechanism by which "latest release" stays true over time.

**R4 — Maximum context window.**
Wherever a model is referenced and the docs document an extended/maximum context option for it (e.g., `[1m]` suffixes, natively-1M models, `opusplan[1m]`), configure the maximum documented context window, after verifying in the docs which aliases support it on my provider/plan and noting any pricing or quota implications in the report. Where max context is automatic (e.g., a model whose current release is natively 1M), do not add redundant suffixes.

**R5 — Highest tier for complex tasks.**
Route the four complex task types to the highest-tier model available to my account, using **native, documented mechanisms only** (no prompt-level pretending to switch models):
- Create three dedicated reviewer **subagents** in `~/.claude/agents/`: `spec-reviewer`, `implementation-plan-reviewer`, and `code-reviewer`, each with `model: best` in frontmatter (verify `best` is valid there; if not, use the highest valid alias) and a tight, token-lean system prompt focused on correctness, architecture, security, and maintainability. Their descriptions must make Claude invoke them automatically at the end of spec-writing, plan-writing, and implementation phases respectively.
- For **planning**: configure the best documented option for my plan among (a) `opusplan`/`opusplan[1m]` as the saved model, or (b) plan-default model plus a documented, low-friction way to run major planning sessions on `best`/`fable`. Recommend one based on the docs and my plan's quota model, explain the trade-off (opusplan uses Opus, not Fable, in plan mode), and implement my choice.
- Document clearly which steps, if any, remain manual (e.g., `/model best` before an exceptional architecture session) — do not invent automation the product does not support.

**R6 — Advisor on the highest tier.**
Enable the advisor feature with the highest-tier alias the advisor setting accepts (prefer `best` so it degrades gracefully where Fable is unavailable). Verify the exact setting key and accepted values in the current advisor docs before writing it.

**R7 — Fallback chain: one tier down at each step.**
Configure the persistent fallback chain in user settings using aliases so that, on unavailability/overload, each model degrades to the immediately lower tier — target behavior: Fable → Opus → Sonnet → Haiku. Respect the documented chain length cap and deduplication rules; rely on the documented built-in degradations (e.g., `best` resolving to latest Opus where Fable is unavailable, and automatic model fallback for safety-flagged Fable requests) as the top of the chain, and encode the remaining tiers explicitly. Explain in the report exactly which failure scenarios each layer covers.

**R8 — Higher effort only when truly needed.**
Add a short, token-lean rules section (in `~/.claude/CLAUDE.md` or the documented global rules location) defining escalation criteria — raise effort only for: deep multi-file debugging, architecture decisions with real trade-offs, security-critical review, or a final verification pass; otherwise stay at default. Since effort is user-controlled, the rule must instruct Claude to *recommend* the specific `/effort` level (or per-turn escalation keyword, if still documented) with a one-line justification, never to assume it. Do not place per-turn escalation keywords in always-loaded files.

**R9 — Sustainable, self-updating configuration.**
Create a custom slash command (or skill, whichever the docs currently recommend for this) named `/model-config-sync` that, when I run it: re-fetches the official docs index and relevant pages, re-validates every key/alias/frontmatter value in this configuration against them, checks what each alias currently resolves to, and proposes (never silently applies) any updates needed to stay aligned with current models and best practices. Recommend a cadence for running it (e.g., after `claude update` or monthly).

**R10 — Token economy everywhere else.**
Keep every artifact you create minimal: rules under ~30 lines total, subagent prompts focused, no redundant context. Where the docs support it, set exploration/lookup-style delegated work to the `haiku` alias so cheap work stays cheap.

## OUTPUT

1. **First**: a short discovery report (detected provider, plan, version, current model/effort and their sources, current settings that conflict with the requirements) plus any clarifying questions. **Wait for my confirmation before writing any file.**
2. **Then**: apply the changes and produce a final report containing: every file created/modified with its path and full content; a doc citation per configuration decision; the exact verification commands I should run (`/model`, `/effort`, `/status`, a test invocation of one reviewer subagent); any residual manual steps; and any requirement that could not be satisfied natively, with the closest supported alternative.

## CONSTRAINTS

- Never hardcode versioned model IDs anywhere.
- Never use undocumented, deprecated, or guessed settings keys.
- Never modify managed/enterprise settings; user and project scope only.
- Ask clarifying questions whenever a requirement is ambiguous for my specific plan/provider — do not resolve ambiguity with assumptions.
- Every factual claim in your reports must be grounded in the fetched official documentation.
