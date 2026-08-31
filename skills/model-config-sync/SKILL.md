---
name: model-config-sync
description: Re-validate the model-routing configuration (settings.json aliases, fallback chain, advisor, reviewer subagents, effort rules) against the current official Claude Code docs and propose updates. Manual maintenance task.
disable-model-invocation: true
allowed-tools: WebFetch, Read, Glob, Grep
compatibility: Designed for Claude Code. Reads and validates the Claude Code model-configuration files in ~/.claude against the official docs.
---

Re-validate this machine's model-routing configuration against the current official docs.
Propose changes only — never apply an edit without explicit user confirmation.

1. Fetch `https://code.claude.com/docs/llms.txt`, then the current pages on model
   configuration, settings, subagents, advisor, and skills.
2. Read `~/.claude/settings.json`, `~/.claude/agents/*.md`,
   `~/.claude/rules/effort-escalation.md`, and this skill file.
3. Verify against the docs just fetched (not memory):
   - every settings key still exists with the same semantics: `model` absent ⇒ plan
     Default applies; `fallbackModel` array; `advisorModel`; no persistent `effortLevel`
   - what `default`, `best`, `fable`, `opus`, `sonnet`, `haiku` currently resolve to for
     this account, and that the fallback chain still steps one tier down per entry
     within the documented chain-length cap
   - subagent frontmatter is still valid (`model: fable`, `tools`), and whether a
     higher-tier alias now exists or `best` became valid in frontmatter
   - advisor pairing rules still accept the configured advisor for the models in use,
     and whether an advisor fallback chain has become a documented feature
   - no versioned model ID has crept into any of these files
   - extended-context defaults: whether any `[1m]` suffix became necessary or redundant
4. Report a table — item, current value, docs say, action needed — then show proposed
   file diffs and wait for approval before editing anything.

Recommended cadence: after every `claude update` that changes the minor version, or monthly.
