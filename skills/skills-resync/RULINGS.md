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
  carry no `superpowers:` prefixes and no `../<skill>/` paths. Upstream, 16 references pointed at
  sibling plugin skills; 5 resolved to skills vendored here and were reduced to bare names, and 11
  pointed at the 8 skills that were dropped and were rewritten into plain instructions. Left
  unpatched a re-vendor reintroduces all 16 as dangling references — several tagged
  `REQUIRED SUB-SKILL`, so they are executable, not prose.
- **L4** — `subagent-driven-development/code-reviewer.md` is a vendored copy of
  `requesting-code-review/code-reviewer.md`, and the 4 links to it were repointed from
  `../requesting-code-review/` to `./`. The skill dispatches its final reviewer with this file, so
  it is a functional dependency, not a citation — the patch carries the whole file, not just the
  links.
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

## The regime ledger (L6)

**L6 — the invocation regime is local state, never upstream state.** `disable-model-invocation:
true` is a **functional dependency, not a preference**: without it the skill pays its description
in every turn, and the trigger collisions come back — `idea-refine` and `brainstorming` both
firing on a formless idea, on top of `interview-me` and `grilling`, which are model-invoked by
design and already overlap on "stress-test my thinking".

**This list is the whole ruling. There is no global file behind it, and there must not be one.**
A `~/.claude/CLAUDE.md` or a new `rules/` file would load the ruling into every session and every
subagent to serve a decision only a resync ever makes. This file itself is not that global file:
it lives inside the skill's directory and loads only when skills-resync runs. The rule itself:
**demote a skill the moment a second skill claims the same opening move; a shared clause is not a
collision.** `domain-modeling` and `documentation-and-adrs` both handle ADRs and both stay
model-invoked — they overlap on one clause and diverge everywhere else, and neither tries to drive
the same conversation. `idea-refine` and `brainstorming` did.

**The script owns this one, and only this one path owns it.** `--apply` records the line before
the swap and re-inserts it inside the new frontmatter afterwards; `--snapshot` strips it from
every patch so the two mechanisms cannot both insert it and collide. Every diff ignores it, so a
skill whose only local change is L6 reads as `identical`. Nothing here is maintained by hand, and
a promotion or demotion needs no bookkeeping — the live file is the source of truth.

Because the diff ignores the line, `--check` reports it twice: as the per-row `REGIME` column,
and as the computed footer `REGIME: n/m mapped slash-only (x local, y upstream) (+ r unresolvable)
+ p/q unmapped slash-only`, where the unresolvable clause appears only while some slash-only
row's upstream cannot be resolved. The column is the only thing that catches an L6 lost out of
band; the footer is the
number source — reconcile it against the tables in this file, never against a memorised count.
*local* means the flag exists only in the live copy, so this ledger owns it through `--apply`'s
restore; *upstream* means upstream ships the line — `handoff`, `wayfinder`, `wait-what`,
`improve-codebase-architecture` and `to-spec` — so it is not a local edit there: neither re-add
it nor strip it. The denominator counts skill rows only — the `references` row has no frontmatter
and no regime. `code-simplification`, `incremental-implementation` and `interview-me` were
deliberately promoted back to model-invoked and are byte-identical to upstream — an absent
flag on those three is the intended state.

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

So the group adds **no L6 edit at all**: the four that must stay reachable are byte-identical to
upstream, and the one that should not be model-invoked was already flagged by its author. Nothing
here is maintained by hand. All five carry only bare-name cross-references (`grilling`,
`codebase-design`, `domain-modeling`), every one of which now resolves, so **no patches** either.

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
`debugging-and-error-recovery`, `test-driven-development`) remain in some bodies as prose "see also"
pointers. They are inert and accepted. Flag one only if it becomes an executable instruction.

## The RisorseArtificiali group

`plan-walkthrough`, `pr-walkthrough`, `slides` and `adversarial-code-review` arrived from
`github.com/RisorseArtificiali/skills` via the `skills` npm CLI, and were folded in as the first
four `git+` rows — the repo is not a marketplace plugin, so there is no catalog entry to resolve
through and the `main` tip is the upstream (see *Upstream resolution* in SKILL.md). Their entries
were removed from `~/.agents/.skill-lock.json` in the same pass: the directories are vendor state
now, and a later `npx skills update` must not be able to overwrite them. `microsoft-foundry` and
`find-skills` stay CLI-managed there, for other agents.

Upstream ships no `disable-model-invocation` lines, so the one regime edit is local — it counts
among the ledger's locally-added flags. Ruled 2026-09-15, recorded here so it is not reopened:

| skill | regime | ruling |
|---|---|---|
| `adversarial-code-review` | slash-only — local L6 | Claims the same opening move as `code-review-and-quality` and `ponytail-review` ("review this / before merging") and is the most expensive misfire in the fleet — reviewer subagents plus skeptic reproduction in isolated worktrees. The source repo's own cheatsheet frames it as "the gate, not the everyday tool", a deliberate human-invoked ritual; nothing dispatches to it, so demotion breaks no dispatch graph. |
| `plan-walkthrough`, `pr-walkthrough`, `slides` | model-invoked | Each is the sole claimant of its opening move — reviewing a plan-shaped document, walking through a PR above the code level, building a deck — so there is no collision to demote on. Their sibling cross-references are prose, not dispatches. |

No patches: apart from that one frontmatter line the four are byte-identical to upstream, and
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
  `consolidate-specs`, `model-config-sync`, `skills-resync`. The four RisorseArtificiali skills
  are mapped through `git+` rows (see *The RisorseArtificiali group*), so this line naming
  exactly those four originals is the reconciled state. Any *other* name is a skill vendored
  without an inventory row, and needs one.

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
