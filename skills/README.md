# Skills

A **skill** is a folder with a `SKILL.md` file that teaches Claude Code one specific job.

This directory ships **two** skills. The thirty-nine that do the rest of the work are
vendored from plugins into `~/.claude/skills/` and ship nowhere in this repository. That gap
is the whole point of this page, so it is worth stating plainly:

> The two skills here are the ones that **maintain the setup**. The skills that **do the
> work** come from plugins, and are copied — *vendored* — into `~/.claude/skills/`. This
> repository ships the machinery that keeps those copies current, plus the manifest that
> records where every one of them came from.

**This page is the supply chain.** It answers *where does this skill come from, and how do I
get it*. What each skill does, which phase it serves, and whether two of them compose is
[`workflow/TOOLS.md`](../workflow/TOOLS.md) — the one place in this repository that maps a
skill to a phase.

## Contents

- [Shipped here: the two maintenance skills](#shipped-here-the-two-maintenance-skills)
- [The vendored fleet, by source](#the-vendored-fleet-by-source)
- [How to get them: plugin, vendored, or idle](#how-to-get-them-plugin-vendored-or-idle)
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

The flag has a second effect that matters when you set it yourself: **a manual skill cannot
be reached by another skill's dispatch either.** That is Rule 1 in
[`workflow/TOOLS.md`](../workflow/TOOLS.md#rule-1--the-invocation-regime-decides-what-can-be-reached),
and it is why some skills below must stay model-invocable however rarely you call them.

### `skills-resync` in one paragraph

Vendoring a skill costs you updates. `skills-resync` gives them back. It records where each
vendored skill came from and the exact upstream state it was copied at, detects when that
upstream has moved, captures your local edits as replayable patches, and then performs a
verify-then-swap re-vendor that rolls back cleanly if a patch does not apply. It resolves
upstream from the marketplace clone rather than from the plugin install cache, because the
install cache is frozen for a disabled plugin — so comparing against it would never show
drift at all. Skills from a plain git repo (no marketplace) ride the same machinery through a
`git+<repo>@<branch>` inventory row whose mirror is fetched to the branch tip.

```bash
RESYNC=~/.claude/skills/skills-resync/scripts/resync.sh

bash $RESYNC --self-test           # run this first, on a new machine
bash $RESYNC --refresh             # pull marketplaces, sync mirrors (pinned sha, git branch)
bash $RESYNC --check               # classify every vendored skill's drift
bash $RESYNC --diff <skill>        # show local against upstream
bash $RESYNC --snapshot <skill>    # capture local edits as a patch
bash $RESYNC --apply <skill>       # re-vendor, then replay the patch
```

The full mechanics — the drift buckets, the protected-edit classes, the rollback guarantees
— are in [`skills-resync/SKILL.md`](skills-resync/SKILL.md); the rulings behind each protected
edit and each rejection are in [`skills-resync/RULINGS.md`](skills-resync/RULINGS.md).

### `model-config-sync` in one paragraph

Model names change. Documented settings change. This skill fetches the current official
Claude Code documentation, reads your `~/.claude/settings.json`, your `~/.claude/agents/*.md`
and your effort rule, and reports a table of *item / what you have now / what the docs say /
what to do*. It then stops and waits. It never applies an edit without your approval.

---

## The vendored fleet, by source

**None of the skills below ship in this repository.** They are listed because
[`WORKFLOW.md`](../WORKFLOW.md) and [`workflow/TOOLS.md`](../workflow/TOOLS.md) name them, and
a workflow you cannot reproduce cannot be followed.

The full machine-readable record — plugin, marketplace, path inside the plugin, and the
upstream state each copy was taken at — is
[`skills-resync/scripts/inventory.tsv`](skills-resync/scripts/inventory.tsv). That file
ships as a **worked example of the format, not as configuration to reproduce**: point the
`INVENTORY` environment variable at your own file to manage a different set.

Thirty-nine skills, from six plugins and one tracked repo, grouped here by where they come
from — because *plugin, vendored, or idle* is a decision you make per source, not per skill.
The `Catalogued under` column points at the section of
[`workflow/TOOLS.md`](../workflow/TOOLS.md) that says what the skill does.

### `agent-skills`

A GitHub-source marketplace entry: the clone *is* the plugin, so upstream is the repo itself.
Vendored, because a minority of the plugin is in use and several skills carry protected local
edits. One row in the inventory is **not a skill**: `agent-skills` keeps four checklists at its
repo root and five of the skills below cite them as `../../references/<file>.md`. Vendored,
that same relative path resolves to `~/.claude/references/`, so the directory is kept in sync
there and every pointer resolves untouched.

| Skill | Catalogued under |
|---|---|
| `interview-me` | [Phase 1](../workflow/TOOLS.md#phase-1--brainstorm) |
| `idea-refine` | [Phase 1](../workflow/TOOLS.md#phase-1--brainstorm) |
| `spec-driven-development` | [Phase 2](../workflow/TOOLS.md#phase-2--specify) |
| `documentation-and-adrs` | [Phase 2](../workflow/TOOLS.md#phase-2--specify) |
| `planning-and-task-breakdown` | [Phase 3](../workflow/TOOLS.md#phase-3--plan) |
| `incremental-implementation` | [Phase 4](../workflow/TOOLS.md#phase-4--implement) |
| `doubt-driven-development` | [Phase 4](../workflow/TOOLS.md#phase-4--implement) |
| `security-and-hardening` | [Phase 4](../workflow/TOOLS.md#phase-4--implement) |
| `code-review-and-quality` | [Phase 5](../workflow/TOOLS.md#phase-5--review) |
| `code-simplification` | [Phase 5](../workflow/TOOLS.md#phase-5--review) |
| `context-engineering` | [Any moment](../workflow/TOOLS.md#any-moment-the-cross-cutting-tools) |
| `references` | *not a skill* — the shared checklist tree |

### `mattpocock-skills`

A url-pinned marketplace entry, mirrored per sha. The largest single group, and the most
interconnected: `wayfinder` and `improve-codebase-architecture` dispatch four of their
siblings by name, which is why those four must stay model-invocable however rarely you call
them directly.

| Skill | Catalogued under |
|---|---|
| `wayfinder` | [Phase 1](../workflow/TOOLS.md#phase-1--brainstorm) |
| `grilling` | [Phase 1](../workflow/TOOLS.md#phase-1--brainstorm) |
| `research` | [Phase 1](../workflow/TOOLS.md#phase-1--brainstorm) — dispatched by `wayfinder` |
| `prototype` | [Phase 1](../workflow/TOOLS.md#phase-1--brainstorm) — dispatched by `wayfinder` |
| `to-spec` | [Phase 2](../workflow/TOOLS.md#phase-2--specify) |
| `domain-modeling` | [Phase 2](../workflow/TOOLS.md#phase-2--specify) — dispatched by both |
| `codebase-design` | [Phase 5](../workflow/TOOLS.md#phase-5--review) — dispatched by `improve-codebase-architecture` |
| `improve-codebase-architecture` | [Phase 5](../workflow/TOOLS.md#phase-5--review) |
| `diagnosing-bugs` | [The bug-fixing lane](../workflow/TOOLS.md#the-bug-fixing-lane) |
| `handoff` | [Any moment](../workflow/TOOLS.md#any-moment-the-cross-cutting-tools) |
| `wait-what` | [Any moment](../workflow/TOOLS.md#any-moment-the-cross-cutting-tools) |
| `writing-for-agents` | [Any moment](../workflow/TOOLS.md#any-moment-the-cross-cutting-tools) |

### `superpowers`

A url-pinned marketplace entry, mirrored per sha. **Six of fourteen were kept** — the clearest
case in the fleet for vendoring rather than installing, because most of the plugin was
declined. See [what was left out](#what-was-deliberately-left-out-and-why).

| Skill | Catalogued under |
|---|---|
| `brainstorming` | [Phase 1](../workflow/TOOLS.md#phase-1--brainstorm) |
| `writing-plans` | [Phase 3](../workflow/TOOLS.md#phase-3--plan) |
| `dispatching-parallel-agents` | [Phase 3](../workflow/TOOLS.md#phase-3--plan) |
| `executing-plans` | [Phase 4](../workflow/TOOLS.md#phase-4--implement) |
| `subagent-driven-development` | [Phase 4](../workflow/TOOLS.md#phase-4--implement) |
| `systematic-debugging` | [The bug-fixing lane](../workflow/TOOLS.md#the-bug-fixing-lane) |

### `RisorseArtificiali/skills`

The one tracked repo: no marketplace, so it rides a `git+<repo>@<branch>` inventory row whose
mirror is hard-reset to the branch tip on every `--refresh`. Upstream is therefore **mutable**
— the branch tip, not a pinned sha — so this group drifts more often than the others by design.

| Skill | Catalogued under |
|---|---|
| `writing-prds` | [Phase 2](../workflow/TOOLS.md#phase-2--specify) |
| `plan-walkthrough` | [Phase 3](../workflow/TOOLS.md#phase-3--plan) |
| `pr-walkthrough` | [Phase 5](../workflow/TOOLS.md#phase-5--review) |
| `adversarial-code-review` | [Phase 5](../workflow/TOOLS.md#phase-5--review) |
| `slides` | [Any moment](../workflow/TOOLS.md#any-moment-the-cross-cutting-tools) |

### `mcp-server-dev`, `skill-creator`, `claude-code-setup`

Three small local-path marketplace entries, resolved in place. All manual, all outside the
feature workflow.

| Skill | From | Catalogued under |
|---|---|---|
| `build-mcp-server` | `mcp-server-dev` | [Building the tooling itself](../workflow/TOOLS.md#building-the-tooling-itself) |
| `build-mcp-app` | `mcp-server-dev` | [Building the tooling itself](../workflow/TOOLS.md#building-the-tooling-itself) |
| `build-mcpb` | `mcp-server-dev` | [Building the tooling itself](../workflow/TOOLS.md#building-the-tooling-itself) |
| `skill-creator` | `skill-creator` | [Building the tooling itself](../workflow/TOOLS.md#building-the-tooling-itself) |
| `claude-automation-recommender` | `claude-code-setup` | [Building the tooling itself](../workflow/TOOLS.md#building-the-tooling-itself) |

> The three `build-mcp-*` skills are **one unit**. They cross-reference each other through
> sibling-relative paths that only resolve while all three sit next to each other under
> `~/.claude/skills/`. Never vendor or re-vendor a subset of them.

### `ponytail` — installed, not vendored

The one source with **no inventory rows on purpose**. Its skills come from the live plugin and
stay upstream-current for free; what was removed is its wiring, by configuration rather than by
copying. See [what was left out](#what-was-deliberately-left-out-and-why) for the reasoning,
and [Phase 4](../workflow/TOOLS.md#phase-4--implement) and
[Phase 5](../workflow/TOOLS.md#phase-5--review) for `ponytail` and `ponytail-review`.

### Written from scratch — no upstream at all

Four skills in `~/.claude/skills/` have no upstream, because nobody vendored them. Two ship in
this repository; two live in
[ClaudeSkills](https://github.com/StefanoZaghi1987/ClaudeSkills).

| Skill | Home | Catalogued under |
|---|---|---|
| `skills-resync` | **this repository** | [Any moment](../workflow/TOOLS.md#any-moment-the-cross-cutting-tools) |
| `model-config-sync` | **this repository** | [Any moment](../workflow/TOOLS.md#any-moment-the-cross-cutting-tools) |
| `consolidate-specs` | ClaudeSkills | [Closing out](../workflow/TOOLS.md#closing-out) |
| `consolidate-comments` | ClaudeSkills | [Closing out](../workflow/TOOLS.md#closing-out) |

---

## How to get them: plugin, vendored, or idle

**Install the plugin.** The simple path. The marketplace keeps the skills updated for you.
The cost is that you install every skill in that plugin, and **every installed skill occupies
the context window in every turn** — including the ones you never use, and including inside
every subagent, which inherits the same weight.

That cost is the reason this repository exists. The six plugins hold far more than
thirty-nine skills. Taking thirty-nine of them and leaving the rest is a deliberate
reduction, not an accident.

**Vendor the skill.** Copy the one skill you want into `~/.claude/skills/` and disable the
plugin. You pay context only for what you chose, and your copy survives the plugin being
disabled, updated, or removed. The cost is that your copy stops receiving updates —
which is what `skills-resync` fixes.

**Install the plugin, and keep it idle.** For a plugin whose weight is not in its skills but
in its wiring — hooks that fire on every session, every subagent, every prompt. `ponytail` is
the one here: six skills worth having on demand, behind a `SessionStart` hook that injects a
behavioural ruleset whether the turn is about code or not. Its config file takes
`defaultMode: off`, which silences the hooks and leaves every skill invocable. You pay the
skill descriptions and nothing else, and the copies stay upstream-current without an inventory
row.

No path is universally right. The rule of thumb: **install the plugin when you use most of it;
vendor when you use a few skills out of many, or when you need local edits to survive; keep
the plugin idle when what you want is its skills and what you are paying for is its hooks.**

---

## What was deliberately left out, and why

A list of what was selected proves nothing — every setup has one. A list of what was
**rejected** is the evidence that a choice was actually made. These decisions are recorded in
[`skills-resync/RULINGS.md`](skills-resync/RULINGS.md) so they are not quietly reversed later.

**`ponytail` is not vendored, and its plugin stays enabled but idle.** It is the one tool
here that splits in two. The mode is wiring — a SessionStart hook, an intensity tracker, a
statusline, propagation into subagents, six slash commands — and none of that survives copying
a `SKILL.md`: when a plugin's value is in its wiring rather than its text, vendoring produces a
hollow copy. `ponytail-review` and `ponytail-audit` are the reverse — self-contained bodies
that could be extracted in an afternoon. They are still not vendored, because extraction was
never the real question. The only cost worth removing was the ruleset the hooks injected into
every session and every subagent — including Phases 1 to 3, where "shortest diff wins"
contradicts `spec-driven-development` — and setting `defaultMode` to `off` removes it by
configuration. Vendoring on top of that would buy drift tracking for two skills the plugin
already keeps current, at the price of two inventory rows and a second copy of each.

**Eight of the fourteen `superpowers` skills were dropped**, among them
`using-git-worktrees`, `test-driven-development`, `verification-before-completion` and
`requesting-code-review`. Six were kept. This is what "designed, not accumulated" means in
practice: the plugin was read, and most of it was declined.

**`grill-me` and `grill-with-docs` were evaluated and rejected as routers, not skills.** The
entire body of `grill-me` is an instruction to call `grilling`, which is already vendored —
so it would add context weight and no capability. `grill-with-docs` adds only a dispatch to
`domain-modeling` alongside it; both targets are vendored now, so there is no missing link
for them to fix — and neither earns a row, because invoking the two skills directly is all
they do.

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

It runs in a throwaway directory and touches nothing in your real setup. Every behavior change
to the script ships with a new fixture world in its self-test, and both CI workflows run it —
a green run is the proof the mechanics still hold.
