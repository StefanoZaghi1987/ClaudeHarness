# Skills

A **skill** is a folder with a `SKILL.md` file that teaches Claude Code one specific job.

This directory ships **two** skills. The workflow in [`WORKFLOW.md`](../WORKFLOW.md) uses
about thirty. That gap is the whole point of this page, so it is worth stating plainly:

> The two skills here are the ones that **maintain the setup**. The skills that **do the
> work** come from plugins, and are copied — *vendored* — into `~/.claude/skills/`. This
> repository ships the machinery that keeps those copies current, plus the manifest that
> records where every one of them came from.

## Contents

- [Shipped here: the two maintenance skills](#shipped-here-the-two-maintenance-skills)
- [The vendored fleet](#the-vendored-fleet)
- [How to get them: plugin or vendored](#how-to-get-them-plugin-or-vendored)
- [What was deliberately left out, and why](#what-was-deliberately-left-out-and-why)

---

## Shipped here: the two maintenance skills

| Skill | What it does |
|---|---|
| [`skills-resync`](skills-resync/SKILL.md) | Re-syncs your vendored skills against their upstream plugins, and replays your protected local edits onto every fresh copy. |
| [`model-config-sync`](model-config-sync/SKILL.md) | Re-checks your model routing — aliases, fallback chain, advisor, subagent frontmatter — against the current official Claude Code documentation, then proposes changes. |

Both are **manual only**. Their frontmatter carries `disable-model-invocation: true`, which
means the model can never decide to run them on its own. You call them by name when you
want them.

That flag is not decoration. A skill the model can invoke must keep its description in the
context window in every turn, so it can decide whether to fire. A manual skill does not. For
maintenance tasks that run once a month, paying that cost on every turn makes no sense — and
worse, two skills with overlapping trigger descriptions will collide and fire each other.

### `skills-resync` in one paragraph

Vendoring a skill costs you updates. `skills-resync` gives them back. It records where each
vendored skill came from and the exact upstream state it was copied at, detects when that
upstream has moved, captures your local edits as replayable patches, and then performs a
verify-then-swap re-vendor that rolls back cleanly if a patch does not apply. It resolves
upstream from the marketplace clone rather than from the plugin install cache, because the
install cache is frozen for a disabled plugin — so comparing against it would never show
drift at all.

```bash
RESYNC=~/.claude/skills/skills-resync/scripts/resync.sh

bash $RESYNC --self-test           # run this first, on a new machine
bash $RESYNC --refresh             # pull marketplaces, mirror pinned plugins
bash $RESYNC --check               # classify every vendored skill's drift
bash $RESYNC --diff <skill>        # show local against upstream
bash $RESYNC --snapshot <skill>    # capture local edits as a patch
bash $RESYNC --apply <skill>       # re-vendor, then replay the patch
```

The full mechanics — the drift buckets, the protected-edit classes, the rollback guarantees
— are in [`skills-resync/SKILL.md`](skills-resync/SKILL.md).

### `model-config-sync` in one paragraph

Model names change. Documented settings change. This skill fetches the current official
Claude Code documentation, reads your `~/.claude/settings.json`, your `~/.claude/agents/*.md`
and your effort rule, and reports a table of *item / what you have now / what the docs say /
what to do*. It then stops and waits. It never applies an edit without your approval.

---

## The vendored fleet

**None of the skills below ship in this repository.** They are listed because
[`WORKFLOW.md`](../WORKFLOW.md) names them, and a workflow you cannot reproduce is a story
rather than a method.

The `From` column gives the source plugin. The full machine-readable record — plugin,
marketplace, path inside the plugin, and the upstream state each copy was taken at — is
[`skills-resync/scripts/inventory.tsv`](skills-resync/scripts/inventory.tsv). That file
ships as a **worked example of the format, not as configuration to reproduce**: point the
`INVENTORY` environment variable at your own file to manage a different set.

Twenty-eight skills, from six plugins, grouped here by the workflow phase they serve.

### Phase 1 — Brainstorm

| Skill | From | What it does |
|---|---|---|
| `interview-me` | `agent-skills` | Extracts what you actually want instead of what you think you should want, through a one-question-at-a-time interview, until it reaches about 95% confidence about the underlying intent. |
| `idea-refine` | `agent-skills` | Refines a raw idea into a sharp, actionable concept through structured divergent then convergent thinking. Triggers on "ideate", "refine this idea", "stress-test my plan". |
| `grilling` | `mattpocock-skills` | Grills you relentlessly about a plan, decision, or idea. For when you want your own thinking stress-tested. |
| `brainstorming` | `superpowers` | Turns ideas into fully formed designs and specs through collaborative dialogue. It first classifies how much process the request needs, then follows that path. |
| `wayfinder` | `mattpocock-skills` | Plans a chunk of work larger than one agent session as a shared map of decision tickets on the issue tracker, then resolves them one at a time. |

### Phase 2 — Specify

| Skill | From | What it does |
|---|---|---|
| `spec-driven-development` | `agent-skills` | Creates specs before coding. When a single requirement spans several independently testable capabilities, it decomposes them into a capability map of modules. |
| `documentation-and-adrs` | `agent-skills` | Records decisions and documentation — architectural decisions, public API changes, shipped features, and context future engineers will need. |

### Phase 3 — Plan

| Skill | From | What it does |
|---|---|---|
| `writing-plans` | `superpowers` | Turns a spec or clear requirements for a multi-step task into a written plan, before any code is touched. |
| `planning-and-task-breakdown` | `agent-skills` | Breaks work into ordered, implementable tasks. Also for estimating scope, and for finding what can run in parallel. |
| `dispatching-parallel-agents` | `superpowers` | For two or more independent tasks with no shared state and no ordering. It constructs exactly the context each agent needs, rather than letting them inherit the session. |

### Phase 4 — Implement

| Skill | From | What it does |
|---|---|---|
| `incremental-implementation` | `agent-skills` | Delivers changes incrementally. For any change touching more than one file, or any task too big to land in one step. |
| `executing-plans` | `superpowers` | Executes a written implementation plan in a separate session, with review checkpoints. |
| `subagent-driven-development` | `superpowers` | Executes implementation plans with independent tasks in the current session, through subagents. |
| `doubt-driven-development` | `agent-skills` | Subjects every non-trivial decision to a fresh-context adversarial review — biased to **disprove**, not to approve — before it stands. |
| `security-and-hardening` | `agent-skills` | Hardens code against vulnerabilities: untrusted input, authentication, data storage, external integrations, and privacy compliance. |

### Phase 5 — Review

| Skill | From | What it does |
|---|---|---|
| `code-review-and-quality` | `agent-skills` | Conducts a multi-axis code review before merging any change — code written by you, by another agent, or by a person. |
| `code-simplification` | `agent-skills` | Simplifies code for clarity without changing behaviour, for code that works but is harder to read than it should be. |

The phase also closes out with `documentation-and-adrs` (listed under Phase 2, since it
serves both) and `handoff` (listed under *Any moment*), plus `consolidate-specs` and
`consolidate-comments` from [ClaudeSkills](https://github.com/StefanoZaghi1987/ClaudeSkills).
See [Closing out](../WORKFLOW.md#phase-5--review) in the workflow.

### The bug-fixing lane

| Skill | From | What it does |
|---|---|---|
| `diagnosing-bugs` | `mattpocock-skills` | A diagnosis loop for hard bugs and performance regressions. Triggers on "diagnose", "debug this", or a report of something broken, throwing, failing, or slow. |
| `systematic-debugging` | `superpowers` | Enforces one rule on any bug, test failure, or unexpected behaviour: always find the root cause before attempting a fix. A symptom fix is a failure. |

### Any moment

| Skill | From | What it does |
|---|---|---|
| `wait-what` | `mattpocock-skills` | "Stop. That last message did not land: re-pitch it." Forces an explanation in simplified technical English. |
| `handoff` | `mattpocock-skills` | Compacts the current conversation into a handoff document, including which skills the next agent should call, so a fresh session can continue the work. |
| `context-engineering` | `agent-skills` | Optimises what the agent sees and when. For a new session, for degrading output quality, for switching tasks, or for configuring a project's rules files. |
| `writing-for-agents` | `mattpocock-skills` | The reference for writing any document an agent consumes: a skill, an `AGENTS.md`, a `CLAUDE.md`, or a document reached by a pointer. |

### Building the tooling itself

| Skill | From | What it does |
|---|---|---|
| `skill-creator` | `skill-creator` | Creates new skills, modifies and improves existing ones, and measures skill performance. |
| `claude-automation-recommender` | `claude-code-setup` | Analyses a codebase and recommends Claude Code automations: hooks, subagents, skills, plugins, MCP servers. |
| `build-mcp-server` | `mcp-server-dev` | Builds an MCP server: wrapping an API for Claude, exposing tools to Claude. |
| `build-mcp-app` | `mcp-server-dev` | Adds interactive UI and widgets to an MCP server, rendering components in the chat. |
| `build-mcpb` | `mcp-server-dev` | Packages and distributes a local MCP server as a `.mcpb` bundle. |

> The three `build-mcp-*` skills are **one unit**. They cross-reference each other through
> sibling-relative paths that only resolve while all three sit next to each other under
> `~/.claude/skills/`. Never vendor or re-vendor a subset of them.

---

## How to get them: plugin or vendored

**Install the plugin.** The simple path. The marketplace keeps the skills updated for you.
The cost is that you install every skill in that plugin, and **every installed skill occupies
the context window in every turn** — including the ones you never use, and including inside
every subagent, which inherits the same weight.

That cost is the reason this repository exists. Six plugins hold far more than 28 skills.
Taking 28 of them and leaving the rest is a deliberate reduction, not an accident.

**Vendor the skill.** Copy the one skill you want into `~/.claude/skills/` and disable the
plugin. You pay context only for what you chose, and your copy survives the plugin being
disabled, updated, or removed. The cost is that your copy stops receiving updates —
which is what `skills-resync` fixes.

Neither path is universally right. The rule of thumb: **install the plugin when you use most
of it; vendor when you use a few skills out of many, or when you need local edits to
survive.**

---

## What was deliberately left out, and why

A list of what was selected proves nothing — every setup has one. A list of what was
**rejected** is the evidence that a choice was actually made. These decisions are recorded in
[`skills-resync/SKILL.md`](skills-resync/SKILL.md) so they are not quietly reversed later.

**`ponytail` is not vendored, and its plugin stays enabled.** Almost all of its value sits
outside the skill files: a SessionStart hook, an intensity tracker, a statusline, propagation
into subagents, and six slash commands. None of that survives copying a `SKILL.md`. When a
plugin's value is in its wiring rather than its text, vendoring it produces a hollow copy.

**Eight of the fourteen `superpowers` skills were dropped**, among them
`using-git-worktrees`, `test-driven-development`, `verification-before-completion` and
`requesting-code-review`. Six were kept. This is what "designed, not accumulated" means in
practice: the plugin was read, and most of it was declined.

**`grill-me` and `grill-with-docs` were evaluated and rejected as routers, not skills.** The
entire body of `grill-me` is an instruction to call `grilling`, which is already vendored —
so it would add context weight and no capability. `grill-with-docs` dispatches to `grilling`
and to `domain-modeling`, and `domain-modeling` is not vendored, so half of its dispatch
would dangle.

**`code-review` is a command, not a skill.** Its plugin ships no skill at all, so it lives in
`~/.claude/commands/` instead, outside the inventory. The `code-reviewer` subagent covers the
same ground for a working diff.

**Four skills in `~/.claude/skills/` have no upstream at all**, because they were written
from scratch: `skills-resync` and `model-config-sync` (both in this repository), plus
`consolidate-comments` and `consolidate-specs`, which live in
[ClaudeSkills](https://github.com/StefanoZaghi1987/ClaudeSkills).

---

## Installing the two skills from here

```bash
cp -r skills/model-config-sync skills/skills-resync ~/.claude/skills/
```

Then run the self-test once, before anything else:

```bash
bash ~/.claude/skills/skills-resync/scripts/resync.sh --self-test
```

It exercises the replace, patch-replay, reject-rollback and baseline-rebase paths in a
throwaway directory, and touches nothing in your real setup.
