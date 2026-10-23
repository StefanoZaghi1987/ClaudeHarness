# Rulings

The full record of every judgement skills-resync runs on: each protected edit's rationale, the
regime ledger, the group provenance, and the skills that were evaluated and not vendored.
SKILL.md carries the procedure and the L-flag index; a patch that rejects or a `--lint` finding
is ruled here.

This file is the disclosed half of SKILL.md: it sits inside this skill's directory and loads
only when the skill runs. It is not, and must not become, an always-loaded global file — the
regime ledger below rules one out, and a sibling document that no session loads unless
skills-resync is invoked is exactly what that ruling permits.

## Protected local edits

The patches carry these across a re-vendor and `--apply` verifies the replay, so nothing below is a
checklist to work through by hand. It is the record of what each edit is *for* — needed when a patch
rejects and you have to decide what the edit should become against the rewritten upstream.

- **L1** — `idea-refine/SKILL.md`: the script path uses `${CLAUDE_SKILL_DIR}`, not a relative
  `skills/...` path, so it resolves at user scope.
- **L2** — `spec-driven-development/SKILL.md` Phase 4 names no other skill at all: it states the
  test-first behaviour and the load-only-what-the-task-needs behaviour directly. Upstream's three
  pointers all fail here — `skills/…` paths do not resolve at user scope, `test-driven-development`
  is not vendored, and `context-engineering` is user-invoked so no skill can reach it. Prose is the
  only form with nothing left to dangle, which is how L3 handles the same problem.
- **L3** — `executing-plans`, `subagent-driven-development`, `systematic-debugging`, `writing-plans`
  carry no `superpowers:` prefixes and no sibling path that fails to resolve. References that
  resolve to skills vendored here are reduced to bare names; references to the 8 dropped skills,
  and to a slash-only skill no dispatch can reach, are rewritten into plain instructions. Left
  unpatched a re-vendor reintroduces them as dangling references — several tagged
  `REQUIRED SUB-SKILL`, so they are executable, not prose.
- **L4** — `subagent-driven-development/code-reviewer.md` is a vendored copy of
  `requesting-code-review/code-reviewer.md`, and the 4 links to it were repointed from
  `../requesting-code-review/` to `./`. The skill dispatches its final reviewer with this file, so
  it is a functional dependency, not a citation — the patch carries the whole file, not just the
  links. `executing-plans` dispatches its reviewer with the same file and references the one copy
  at `../subagent-driven-development/code-reviewer.md` rather than carrying a second: one patch
  owns the file, and `--lint` verifies the sibling path.
- **L5** — `build-mcp-app/references/widget-templates.md` and `build-mcpb/references/local-security.md`:
  three pointers were changed from `../build-mcp-server/…` to `../../build-mcp-server/…`. **These
  were broken upstream**, not by vendoring — written as if resolving from the skill root while
  sitting inside `references/`. So this patch is a standing bug fix that upstream may land itself
  one day; if it rejects because the path is already correct there, drop the edit rather than
  restore it. The same string in `build-mcp-app/SKILL.md` is correct — leave it alone.
- **L7** — `writing-prds/SKILL.md`'s prerequisite gate read "invoke `brainstorming` and/or
  `grilling` first". `invoke` is an instruction, not prose, and `brainstorming` carries
  `disable-model-invocation: true`, so no skill can reach it — the half of that dispatch that
  named it always failed. The edit keeps `grilling` as the dispatch it can serve and turns the
  other half into what an agent can actually do: stop and tell the user to run `/brainstorming`.
  Same shape as L2 and L3, and the same trigger: a pointer that does not resolve at user scope.
- **L8** — `security-and-hardening/SKILL.md`'s privacy section ended "run the postmortem with
  the `debugging-and-error-recovery` skill" — a skill upstream ships but this fleet does not
  vendor, so the instruction could never run (it arrived with the 2026-09-22 re-vendor).
  Rewritten as the instruction itself: record what happened, the root cause, and the change
  that prevents recurrence. Naming no skill is the same nothing-left-to-dangle move L2 makes,
  and no dispatch could be reduced to a bare name — no vendored skill owns the postmortem move
  (`systematic-debugging` is slash-only, `diagnosing-bugs` is a live-bug loop). `--lint` now
  guards the class.
- **L9** — `build-mcp-server/SKILL.md` (Phases 2 and 5) and `build-mcp-app/SKILL.md` hand off to
  `build-mcp-app` and `build-mcpb` ("load the **`build-mcp-app`** skill", "defer to the
  **`build-mcpb`** skill"). Both targets are slash-only, so no skill can reach them (test 1 of the
  regime ledger). Each hand-off now tells the user to run `/build-mcp-app` or `/build-mcpb`, the L7
  shape: the three are one unit the user drives, and promoting the targets would put two rarely used
  descriptions in every turn. The `build-mcp-app` patch also carries its L5 lines.
- **L10** — `interview-me/SKILL.md`: "grill me" and "stress-test my thinking" are removed from its
  description and its *When to Use* list, because `grilling` claims the same words and must stay
  auto (test 3); and its hand-off to the slash-only `idea-refine` now tells the user to run
  `/idea-refine` (test 1). It stays auto for its own trigger — see the regime ledger.
- **L11** — `retro/SKILL.md` step 1 read "Call the Skill tool with `writing-for-agents` for the
  writing style guide". The target is vendored but slash-only, so no skill can reach it (test 1)
  — the dispatch always failed. The edit is the L7/L9 shape: tell the user to run
  `/writing-for-agents`. Promoting the target instead would put its description in every turn
  and re-open its collision with `skill-creator` (its ledger row below).

## The regime ledger (L6)

**L6 — the invocation regime is local state, never upstream state.** `disable-model-invocation:
true` is a **functional dependency, not a preference**: an auto skill pays its description in
every turn and in every subagent, can be reached by the model and by other skills, and fires
whenever its triggers match. The flag removes all three.

**This ledger is the whole ruling. There is no global file behind it, and there must not be one.**
A `~/.claude/CLAUDE.md` or a new `rules/` file would load the ruling into every session and every
subagent to serve a decision only a resync ever makes. This file itself is not that global file:
it lives inside the skill's directory and loads only when skills-resync runs.

**Every regime is decided by three tests, in order:**

1. **Reachability** — does another skill hand off to it? Then it stays auto, or the hand-off is
   rewritten into "tell the user to run `/<skill>`" as a protected edit (L7, L9, L10). Rule 1 in
   `workflow/TOOLS.md`.
2. **Need** — must the model reach it on its own: a step inside a workflow, or a moment a person
   cannot easily see? If not, it is slash-only: the user starts it and it costs no context.
3. **Collision** — if auto, does a second auto skill claim the same opening move? Then narrow one
   description as a protected edit, or demote one of the two. A shared clause is not a collision:
   `domain-modeling` and `documentation-and-adrs` both handle ADRs and both stay auto, because they
   diverge everywhere else and neither tries to drive the same conversation.

The cheapest fix wins: no change, then the regime flag, then a patch, which every re-vendor must
replay.

**The script owns the flag, and only this one path owns it.** `--apply` records the line before
the swap and re-inserts it inside the new frontmatter afterwards; `--snapshot` strips it from
every patch so the two mechanisms cannot both insert it and collide. Every diff ignores it, so a
skill whose only local change is L6 reads as `identical`. A promotion or demotion is one live-file
edit plus its row in the table below — the live file is the state, the table is the ruling.

Because the diff ignores the line, `--check` reports it twice: as the per-row `REGIME` column,
and as the computed footer `REGIME: n/m mapped slash-only (x local, y upstream) (+ r unresolvable)
+ p/q unmapped slash-only`, where the unresolvable clause appears only while some slash-only
row's upstream cannot be resolved. The column is the only thing that catches an L6 lost out of
band; the footer is the number source — reconcile it against the table below, never against a
memorised count. *local* means the flag exists only in the live copy, so this ledger owns it
through `--apply`'s restore; *upstream* means upstream ships the line — `handoff`, `wayfinder`,
`wait-what`, `improve-codebase-architecture`, `to-spec`, `to-tickets`, `retro`,
`drink-from-the-firehose`, `catch-me-up` and `show-me` — so it is not a local edit there:
neither re-add it nor strip it. The denominator counts skill rows only — the `references` row has
no frontmatter and no regime.

The local flags, one row each. `x local` plus `r unresolvable` in the footer is this table's row
count; a `-` in the REGIME column for any skill below is an L6 lost out of band.

| skill | 1 · handed off by | 2 · must the model reach it? | 3 · would collide with (auto) |
|---|---|---|---|
| `idea-refine` | `interview-me`, rewritten by L10 | no — entry point of Routes C and D | `grilling`, `interview-me` ("stress-test"), `spec-driven-development` ("vague idea") |
| `brainstorming` | `writing-prds`, rewritten by L7 | no — an entry point the user starts | `spec-driven-development`, `incremental-implementation`, `interview-me` — its "MUST use before any creative work" claims every feature request |
| `context-engineering` | — (L2 removed the pointer) | no — called when output degrades | its "starting a new session" trigger would fire in every session |
| `doubt-driven-development` | — | no — chosen per decision; its "any time a confident output" trigger would fire on nearly every turn and double the cost, and it cannot run inside a subagent | — |
| `dispatching-parallel-agents` | — | no — after a breakdown, by choice | `subagent-driven-development` ("independent tasks"), which forbids parallel implementation subagents |
| `systematic-debugging` | — | no | `diagnosing-bugs` — the same opening move: any bug, failure or unexpected behaviour |
| `writing-for-agents` | `retro`, rewritten by L11 | no — started when writing a document an agent consumes | `skill-creator`; the `claude-md-improver` plugin skill ("CLAUDE.md") |
| `skill-creator` | — | no — a heavy eval workflow the user starts | `writing-for-agents` ("create or edit skills") |
| `claude-automation-recommender` | — | no — an analysis the user starts | — |
| `build-mcp-server` | — | no — it opens a development workflow | — |
| `build-mcp-app`, `build-mcpb` | `build-mcp-server`, `build-mcp-app`, rewritten by L9 | no — the three are one unit the user drives | — |
| `adversarial-code-review` | — | no | `code-review-and-quality`, `ponytail-review` — *The RisorseArtificiali group* |
| `writing-prds` | — | no | `spec-driven-development` — *The map-to-spec pair* |

Two auto skills overlap and both stay auto, each by the tests. `grilling` is dispatched by
`wayfinder` (test 1). `interview-me` passes test 2: its unique trigger is the model catching
itself filling in requirements silently, a moment no person sees. Their shared "grill me" /
"stress-test my thinking" triggers are removed from `interview-me` by L10 (test 3). Its overlap with
`spec-driven-development` on a vague ask is a shared clause in sequence — the interview settles
the intent, the spec writes it down — not a collision. `code-simplification`,
`incremental-implementation` and `interview-me` were deliberately promoted back to model-invoked
and carry no flag.

Only 2 of the 4 unmapped originals are slash-only, and that is deliberate: `model-config-sync`
and `skills-resync` declare themselves manual maintenance tasks, while `consolidate-comments` and
`consolidate-specs` trigger on workflow moments ("at feature or epic completion") and must stay
model-invoked to reach them. The footer's `+ p/q unmapped slash-only` reads their regimes
directly, so it agrees with this ruling — an unmapped original in the slash-only half that this
paragraph does not name is a finding, not an arithmetic artefact.

The regime test is scoped to the **frontmatter** (`has_regime`), not a whole-file grep:
`claude-automation-recommender` documents `disable-model-invocation: true` in its body as an
example, and an unanchored grep matched that line — so `--apply` skipped the restore and silently
promoted the skill to model-invoked. Scoping to the frontmatter makes the REGIME column the
trustworthy signal its count relies on.

## The mattpocock engineering group

`codebase-design`, `domain-modeling`, `prototype`, `research` and `improve-codebase-architecture`
were vendored to close a hole that predates them: `wayfinder`, vendored since before, carries
**seven executable `Call the Skill tool with …` dispatches** to `research`, `prototype` and
`domain-modeling` — instructions, not prose, and every one of them dangled.

Their invocation regime is decided by that dispatch graph, not by taste. **A skill carrying
`disable-model-invocation: true` cannot be reached by another skill** — the same constraint L2
records for `context-engineering`. So every dispatch *target* stays model-invocable:

| skill | dispatched by | regime |
|---|---|---|
| `research`, `prototype` | `wayfinder` | model-invocable — required |
| `domain-modeling` | `wayfinder`, `improve-codebase-architecture` | model-invocable — required |
| `codebase-design` | `improve-codebase-architecture` | model-invocable — required |
| `improve-codebase-architecture` | nothing | slash-only, **and upstream already ships the line** |
| `to-tickets` | nothing | slash-only, **and upstream already ships the line** |
| `retro` | nothing | slash-only, **and upstream already ships the line** |

So the group adds **no L6 edit at all**: the four that must stay reachable are byte-identical to
upstream, and the one that should not be model-invoked was already flagged by its author. Nothing
here is maintained by hand. All five carry only bare-name cross-references (`grilling`,
`codebase-design`, `domain-modeling`), every one of which now resolves, so **no patches** either.

`to-tickets` and `retro` come from the same source and stand outside that graph: nothing
dispatches to either, and both ship `disable-model-invocation: true` at source, so the group
still adds no L6 edit. `to-tickets` would collide with `planning-and-task-breakdown` if it were
auto — the same "break work into tasks" opening move (test 3) — and the line its author ships
resolves that for free: one stays auto, the other is called by name. `retro` is a ritual the
user starts; its one patch is **L11** (the `writing-for-agents` dispatch), and its
`/setup-matt-pocock-skills` pointer in the no-tracker branch is the `to-spec` form — something
to tell the user, not something to invoke, so it does not dangle though that skill is not
vendored.

**`domain-modeling` and `documentation-and-adrs` overlap on ADRs, and both stay.** Ruled
2026-09-08, and recorded here so it is not reopened. They share one clause and nothing else:
`domain-modeling` owns terminology and `CONTEXT.md`, `documentation-and-adrs` owns public API
changes and shipped features, and `WORKFLOW.md` names the latter four times. Neither can be
dropped, and by L6's rule a shared clause is not a collision. Demoting `domain-modeling` is worse
than the overlap: it would silently break the 8 dispatch sites in `wayfinder` and
`improve-codebase-architecture`, and nothing in `--check` would show it. Editing its description is
worse still — ADR work is not incidental to it, the skill ships its own `ADR-FORMAT.md`, and the
edit would become a permanent patch that fights upstream at every re-vendor.

Bare-name cross-references to non-vendored skills (`source-driven-development`,
`api-and-interface-design`, `deprecation-and-migration`, `shipping-and-launch`,
`debugging-and-error-recovery`, `test-driven-development`, `observability-and-instrumentation`)
remain in some bodies as prose "see also"
pointers. They are inert and accepted. Flag one only if it becomes an executable instruction.
The same ruling covers `domain-modeling/GLOSSARY-FORMAT.md`: its `./src/*/GLOSSARY.md` links sit
inside the worked `GLOSSARY-MAP.md` example and name files in the reader's repo, not this fleet —
`--lint` reports them as candidates, and the ruling is example content, inert.

## The RisorseArtificiali group

`plan-walkthrough`, `pr-walkthrough`, `slides` and `adversarial-code-review` arrived from
`github.com/RisorseArtificiali/skills` via the `skills` npm CLI, and were folded in as the first
four `git+` rows; `drink-from-the-firehose` and `catch-me-up` joined them as new rows vendored by
the engine. The repo is not a marketplace plugin, so there is no catalog entry to resolve
through and the `main` tip is the upstream (see *Upstream resolution* in SKILL.md). The four
CLI-borne entries were removed from `~/.agents/.skill-lock.json`: the directories are vendor
state now, and a later `npx skills update` must not be able to overwrite them — the two
engine-vendored ones were never in it. `microsoft-foundry` and `find-skills` stay CLI-managed
there, for other agents.

Upstream ships no `disable-model-invocation` lines for the first four, so the group's one local
regime edit is `adversarial-code-review`'s; `drink-from-the-firehose` and `catch-me-up` ship the
line at source and count among the upstream-shipped flags. Ruled 2026-09-15 for the four,
2026-10-23 for the two, recorded here so it is not reopened:

| skill | regime | ruling |
|---|---|---|
| `adversarial-code-review` | slash-only — local L6 | Claims the same opening move as `code-review-and-quality` and `ponytail-review` ("review this / before merging") and is the most expensive misfire in the fleet — reviewer subagents plus skeptic reproduction in isolated worktrees. The source repo's own cheatsheet frames it as "the gate, not the everyday tool", a deliberate human-invoked ritual; nothing dispatches to it, so demotion breaks no dispatch graph. |
| `plan-walkthrough`, `pr-walkthrough`, `slides` | model-invoked | Each is the sole claimant of its opening move — reviewing a plan-shaped document, walking through a PR above the code level, building a deck — so there is no collision to demote on. Their sibling cross-references are prose, not dispatches. |
| `drink-from-the-firehose` | slash-only — **upstream already ships the line** | An onboarding ritual the user starts when entering a project: nothing dispatches to it, and no auto skill claims the move — `research` investigates a question, this teaches a codebase. |
| `catch-me-up` | slash-only — **upstream already ships the line** | The user knows they were away and types `/catch-me-up`; it needs an authenticated `gh` and stops rather than invent a report when it is missing. |

No patches: apart from that one frontmatter line the six are byte-identical to upstream, and
`slides`' `assets/` and `scripts/` travel inside its directory, so the tree hash covers them.

## The map-to-spec pair

`to-spec` (`mattpocock-skills`) and `writing-prds` (`git+github.com/RisorseArtificiali/skills`) are
one row each closing one hole, which is why they are recorded together rather than under their two
source groups. `wayfinder` was vendored to plan work too large for a single session; nothing
downstream of it could turn a map whose tickets are all closed into a specification. `WORKFLOW.md`
Phase 2 carries the method — the decision ledger, which resolves what each closed decision rules
today — and these two carry the documents: `writing-prds` writes the umbrella, `to-spec` writes one
spec per capability underneath it.

Regime. Ruled 2026-09-21, recorded here so it is not reopened:

| skill | regime | ruling |
|---|---|---|
| `to-spec` | slash-only — **upstream already ships the line** | Its author disabled model invocation at source, and nothing dispatches to it. Neither re-add the line nor strip it; it counts among the upstream-shipped flags in the ledger, not among the locally added. |
| `writing-prds` | slash-only — local L6 | It claims the same opening move as `spec-driven-development`: *"drafting a PRD or requirements document"* against *"write the PRD", "requirements doc", "spec this out in phases"*. By L6's rule that is a collision, not a shared clause — both try to drive the same conversation. `spec-driven-development` keeps the move, because `WORKFLOW.md` names it as the Phase 2 default for ordinary work and its Phase 0 is what the ledger method formalises its capability map with. `writing-prds` applies only when arriving from a closed map, which is a deliberate human move, and nothing dispatches to it. |

One patch, on `writing-prds`: **L7**, the unreachable `brainstorming` dispatch in its prerequisite
gate. Its remaining pointers — `interview-me`, `writing-plans`, `subagent-driven-development`,
`adversarial-code-review` — are prose "see also" lines and all four are vendored, so they resolve
either way.

`to-spec` needs none. Its one outward pointer, `/setup-matt-pocock-skills` for the triage label
vocabulary, is already phrased as something to tell the user rather than something to invoke, so
it does not dangle even though that skill is not vendored. Its step 3 publishes the finished spec
to the project issue tracker; a project that keeps its wayfinder map as local markdown has no
tracker to publish to, and that substitution belongs in a patch on the day it is made, not in a
pre-emptive edit here.

## The humanlayer skill

`show-me` is the fleet's one skill from `github.com/humanlayer/skills`, and it rides a `git+` row
like the RisorseArtificiali group even though that repo *is* a plugin marketplace: one skill out
of its six plugins is wanted, and a `git+` row vendors exactly that with no plugin installed and
no marketplace entry. The upstream is mutable by design, like every `git+` row.

| skill | regime | ruling |
|---|---|---|
| `show-me` | slash-only — **upstream already ships the line** | Nothing dispatches to it, and the moment it serves — not following the current topic — is one the user sees and can name with `/show-me`. No collision: the built-in `dataviz` skill owns data charts, this owns explaining a topic with the smallest visual that makes the point. |

No patches: byte-identical to upstream, and it names no sibling skill — its one tool call opens
the HTML artifact it writes.

## What the inventory cannot say

- **`superpowers`** — only 6 of the plugin's 14 skills are vendored. The other 8, including
  `using-git-worktrees`, `finishing-a-development-branch`, `test-driven-development`,
  `verification-before-completion`, `requesting-code-review` and `using-superpowers`, were
  deliberately dropped. Do not vendor them back in to "fix" L3.
- **`grill-me` and `grill-with-docs` were evaluated and deliberately not vendored.** Both are
  routers, not skills: `grill-me`'s whole body is `Call the Skill tool with "grilling"` — a pure
  alias of the already-vendored `grilling`, and `grill-with-docs` adds only a dispatch to
  `domain-modeling` alongside it. Both dispatch targets are now vendored, so neither router would
  dangle any more — they are still not worth a row, because invoking the two skills directly is the
  whole of what they do. Do not vendor them back in for symmetry.
- **`setup-matt-pocock-skills` is not vendored.** `to-tickets` points the user at it only in its
  no-tracker branch, phrased as something to tell the user — the `to-spec` form, which does not
  dangle. The local-file mode needs no tracker, and tracker configuration is a one-time human
  decision, not a recurring skill.
- **The other five `humanlayer/skills` plugins are not vendored.** The repo is a marketplace of
  six plugins; one skill from one of them is wanted, so the row is `git+` on the repo with a
  subpath rather than a plugin install. Do not vendor the rest for symmetry.
- **The three `build-mcp-*` skills are one unit — never re-vendor a subset.** They cross-reference
  each other with sibling-relative paths (`../build-mcp-server/references/elicitation.md` in
  `build-mcp-app/SKILL.md`). That path resolves only while all three sit as siblings under
  `~/.claude/skills/`. Re-vendoring one alone breaks it silently.
- **`claude-automation-recommender`, `skill-creator` and the three `build-mcp-*`** carry their own
  per-skill `references/` directories and were vendored with them. Those are *inside* the skill and
  need no special handling; the `agent-skills` group's references are shared and sit outside it —
  the row below.
- **`code-review` is a command, not a skill — and it is no longer vendored.** The plugin ships no
  skill; its `commands/code-review.md` was copied to `~/.claude/commands/` once, and that copy is
  gone — Claude Code now ships its own `/code-review`, covering the same ground. Nothing to
  maintain: outside the inventory, invisible to `--check` and `--lint`, and nothing dangles.
- **`ponytail` is deliberately not vendored, and its plugin stays enabled but idle.** The mode
  cannot be vendored: the SessionStart hook, the `lite`/`full`/`ultra` tracker, the statusline,
  subagent propagation and six `/ponytail*` commands are wiring, and none of it survives copying a
  `SKILL.md`. `ponytail-review` and `ponytail-audit` are the opposite case — self-contained bodies
  with no sibling references, extractable in full — and they are still not vendored, because the
  plugin is installed and keeps them current for free. `ponytail-review` was vendored once and
  removed again for that reason. What was removed instead is the always-on cost: `defaultMode` is
  set to `off` in the plugin's own config file (`%APPDATA%\ponytail\config.json` on Windows,
  `~/.config/ponytail/config.json` elsewhere), so the hooks emit nothing until a
  `/ponytail*` command is invoked. Never report ponytail as missing or drifted. If the plugin is
  ever disabled, add rows for it to the inventory.
- **The four `UNMAPPED` skills are originals with no upstream** — `consolidate-comments`,
  `consolidate-specs`, `model-config-sync`, `skills-resync`. All seven RisorseArtificiali skills
  and `show-me` are mapped through `git+` rows (see *The RisorseArtificiali group*, *The
  map-to-spec pair* and *The humanlayer skill*), so this line naming exactly those four originals
  is the reconciled state. Any *other* name is a skill vendored without an inventory row, and
  needs one.

## The shared references

`agent-skills` keeps four checklists **outside** every skill, at the repo root, and the vendored
bodies cite them: `security-checklist.md` (`code-review-and-quality`, `security-and-hardening`),
`performance-checklist.md` (`code-review-and-quality`), `orchestration-patterns.md`
(`doubt-driven-development`) and `definition-of-done.md` (`incremental-implementation`,
`planning-and-task-breakdown`). `orchestration-patterns.md` is cited as the *authority* for a
rule the skill enforces ("personas do not invoke other personas"), not as a further-reading
link, so these are load-bearing.

A citation sits at whatever depth its file has upstream — `../../references/<file>.md` from a
`SKILL.md`, `../../../references/<file>.md` from inside a per-skill `references/` directory — and
**every one resolves untouched**, because the vendored layout mirrors upstream's depth relative to
the skill directory: the shared tree is vendored to **`~/.claude/references/`**, the one hop
outside the skills root that the relative path lands on. No path rewrite, no patch, and nothing
to reconcile when upstream adds a citation at a new depth. That is why this is a `dest` column
and not an L-flag — and `--lint` verifies the resolution on demand.

The **whole** upstream directory is vendored, not the four cited files. A per-file subset would need
tracking machinery the tree hash already provides for free, and the three uncited files
(`accessibility-checklist.md`, `observability-checklist.md`, `testing-patterns.md`) cost nothing:
nothing loads them unless a body points at them.

The row is `references … ../references`. It is the only row with a `dest`, it has no `SKILL.md`,
carries no invocation regime, and is excluded from the `REGIME` denominator. **One level up is the
limit.** `dest` becomes the argument to `mv` and, on rollback, to `rm -rf`, so a dest that
normalises outside the skills root's parent — `../../x`, `..`, anything absolute — is refused as
`bad-dest` and the row goes to BLOCKED. It is a typo guard, not a threat model: the file is
hand-edited, and a home directory sits one hop past the legal destination. Treat it as a
dependency of the five skills above it, not as a peer: re-vendoring those five while leaving this
one behind re-opens every citation they carry, and `--check` reports it in the same run.
