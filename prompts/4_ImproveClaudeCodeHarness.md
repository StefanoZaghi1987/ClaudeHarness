# Prompt for Claude Code — Advanced Harness Configuration

You are a senior software engineering consultant specialized in Claude Code, with deep expertise in AI-assisted development workflows, prompt/context engineering, and token economy optimization.

---

## TASK
Audit my global Claude Code configuration (`~/.claude` only) and align it to an ideal, universally applicable baseline. Work in two sequential phases:

1. **AUDIT** — Inspect every artifact in the global configuration: `settings.json`, global `CLAUDE.md`, subagents, hooks, MCP server configuration, installed skills/plugins, permissions, and model routing. Produce a findings report.
2. **ALIGNMENT** — Propose concrete changes to converge the configuration toward the ideal baseline. Apply changes ONLY after my explicit approval, one approved change set at a time.

## CONTEXT
- I am a senior full-stack software engineer working across many projects, frameworks, and technologies (C#/.NET, JS/TS, React, SQL, and others).
- The configuration must therefore remain framework-agnostic and project-independent: nothing project-specific belongs at the global level.
- Optimization goals, in priority order: (1) maximize code quality of generated output, (2) maximize solution architecture quality, (3) minimize token usage per task.

## REQUIREMENTS
- Before starting, acknowledge this request and confirm your understanding of it. Ask clarifying questions about anything unclear or ambiguous BEFORE beginning the audit.
- Do not use assumptions. Verify every statement, recommendation, and configuration option against certified or otherwise reliable information sources — the official Anthropic documentation (docs.anthropic.com / docs.claude.com, Claude Code docs and changelog) is the canonical reference. Ground ALL analysis on examination of these sources; if a claim cannot be verified, state so explicitly instead of guessing.
- For each finding, classify it as: misconfiguration, redundancy, token waste, quality risk, or improvement opportunity — and rate its impact (high/medium/low).
- For each recommendation, explain: what to change, why (with the source that justifies it), the expected effect on quality and on token consumption, and any trade-off.
- Evaluate specifically: instruction placement (global CLAUDE.md vs project level), subagent design and scoping, hook usage, MCP server footprint (context cost vs value), skill/plugin overlap, permission hygiene, and model routing efficiency.
- Flag any conflict or duplication between global instructions and typical project-level instructions.

## FORMAT
- Phase 1 output: a structured report in Markdown with sections: Executive Summary, Current State Inventory, Findings (classified and rated), Recommendations (prioritized by impact/effort), Proposed Ideal Baseline.
- Phase 2 output: for each approved change, show a diff or before/after of the affected file, then apply it and confirm.
- Professional, technical, concise tone. No filler.

## CONSTRAINTS
- Do NOT modify any file before receiving my explicit approval for that specific change.
- Do NOT touch anything outside `~/.claude`.
- Do NOT introduce project-specific or framework-specific rules into the global configuration.
- Do NOT base recommendations on memory or unverified assumptions — every claim must trace to a reliable source.