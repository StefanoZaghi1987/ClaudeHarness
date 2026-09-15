---
name: skills-resync
description: Re-sync the vendored user skills in ~/.claude/skills against their upstream plugin or tracked-repo copies, and re-vendor the ones that moved after one confirmation. Manual maintenance task.
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
compatibility: Designed for Claude Code. Requires git, patch, diff, awk and python3 on PATH (Git Bash on Windows); manages skills under ~/.claude/skills.
---

These skills were copied out of their plugins so they survive the plugin being disabled, updated
or swept. They receive no marketplace updates. `scripts/resync.sh` owns every mechanical step —
refreshing upstream, resolving it, classifying drift, swapping the directory, replaying the
protected local edits, restoring the invocation regime, verifying the result, rebasing the
baseline, deleting its own leftovers.

This document owns the judgement, and there is now exactly one occasion for it: **a patch that
rejects**, meaning upstream rewrote a line a local edit owns. Everything else is decided by the
script.

Never write before the user confirms.

## Three sources of truth

`scripts/inventory.tsv` — which plugin each skill came from, its subpath, and the upstream **tree
hash** it was vendored at (a per-skill hash of the upstream skill directory, not a plugin commit
sha — see *Upstream resolution*). The script resolves the upstream from the marketplace clone, so
no version directory is recorded anywhere. The baseline column is rewritten by `--apply`;
hand-editing it makes `--check` lie in both directions — with one exception: **a new row is
authored with `-` as its baseline**. That is what marks it never-vendored, so `--check` reports it
`unvendored` and `--apply` performs the initial copy and writes the real hash. An optional 5th
column names a destination relative to `~/.claude/skills`, for the one row that vendors something
that is not a skill — see *The shared references* below.

`scripts/patches/<skill>.patch` — the protected local edits themselves, as a patch `--apply` replays
onto each fresh vendor. Generated only by `--snapshot`, never by hand. This is what makes a
re-vendor of an edited skill mechanical instead of a hand step nothing could confirm had happened.

This document — *why* each protected edit exists, and why a skill is or is not in the inventory.
`--check` output cannot be read without it.

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
- **L6 — the invocation regime is local state, never upstream state.** `disable-model-invocation:
  true` is a **functional dependency, not a preference**: without it the skill pays its description
  in every turn, and the trigger collisions come back — `idea-refine` and `brainstorming` both
  firing on a formless idea, on top of `interview-me` and `grilling`, which are model-invoked by
  design and already overlap on "stress-test my thinking".

  **This list is the whole ruling. There is no global file behind it, and there must not be one.**
  A `~/.claude/CLAUDE.md` or a new `rules/` file would load the ruling into every session and every
  subagent to serve a decision only a resync ever makes. The rule itself: **demote a skill the
  moment a second skill claims the same opening move; a shared clause is not a collision.**
  `domain-modeling` and `documentation-and-adrs` both handle ADRs and both stay model-invoked —
  they overlap on one clause and diverge everywhere else, and neither tries to drive the same
  conversation. `idea-refine` and `brainstorming` did.

  **The script owns this one, and only this one path owns it.** `--apply` records the line before
  the swap and re-inserts it inside the new frontmatter afterwards; `--snapshot` strips it from
  every patch so the two mechanisms cannot both insert it and collide. Every diff ignores it, so a
  skill whose only local change is L6 reads as `identical`. Nothing here is maintained by hand, and
  a promotion or demotion needs no bookkeeping — the live file is the source of truth.

  Because the diff ignores the line, `--check` reports it as its own `REGIME` column instead. That
  column is the only thing that catches an L6 lost out of band, so reconcile the count:
  **19 = 17 mapped + 2 of the 4 unmapped**, where the 17 is **13 locally added + 4 flagged
  upstream**. `handoff`, `wayfinder`, `wait-what` and `improve-codebase-architecture` ship the line
  upstream, so it is not a local edit there: neither re-add it nor strip it. The denominator counts
  skill rows only — the `references` row has no frontmatter and no regime. `code-simplification`,
  `incremental-implementation` and `interview-me` were deliberately promoted back to model-invoked
  and are byte-identical to upstream — an absent flag on those three is the intended state.

  Only 2 of the 4 unmapped originals are slash-only, and that is deliberate: `model-config-sync`
  and `skills-resync` declare themselves manual maintenance tasks, while `consolidate-comments` and
  `consolidate-specs` trigger on workflow moments ("at feature or epic completion") and must stay
  model-invoked to reach them. `--check` prints `+ 4 unmapped` because it counts the unmapped
  *names* and never reads their regime — so reconcile those 2 against this sentence, never against
  that line.

  The regime test is scoped to the **frontmatter** (`has_regime`), not a whole-file grep:
  `claude-automation-recommender` documents `disable-model-invocation: true` in its body as an
  example, and an unanchored grep matched that line — so `--apply` skipped the restore and silently
  promoted the skill to model-invoked. Scoping to the frontmatter makes the REGIME column the
  trustworthy signal its count relies on.

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
- **`interview-me` has two upstream candidates.** It is vendored from `agent-skills`, which is what
  the inventory records. A stale `sorbh/interview-me/1.6.0` clone also sits in the plugin cache
  although that plugin is no longer in `installed_plugins.json`; its copy is *not* the vendored one.
  Never diff against it.
- **`code-review` is a command, not a skill.** The plugin ships no skill; its
  `commands/code-review.md` was copied to `~/.claude/commands/code-review.md` with
  `disable-model-invocation` flipped to `true`. It is outside the inventory and `--check` will never
  see it — check it by hand, or leave it alone: the `code-reviewer` subagent covers the same ground
  for a working diff.
- **`ponytail` is deliberately not vendored and its plugin stays enabled.** Its value is almost
  entirely outside the skill files — the SessionStart mode hook, the `lite`/`full`/`ultra` tracker,
  the statusline, subagent propagation, six `/ponytail*` commands — none of which survives copying a
  `SKILL.md`. `ponytail-review` was vendored once and removed again. Never report ponytail as
  missing or drifted. If it is ever disabled, add rows for it to the inventory.
- **The four `UNMAPPED` skills are originals with no upstream** — `consolidate-comments`,
  `consolidate-specs`, `model-config-sync`, `skills-resync`. The four RisorseArtificiali skills
  are mapped through `git+` rows (see *The RisorseArtificiali group*), so this line naming
  exactly those four originals is the reconciled state. Any *other* name is a skill vendored
  without an inventory row, and needs one.

## The shared references

`agent-skills` keeps four checklists **outside** every skill, at the repo root, and five vendored
bodies cite them across eight sites: `security-checklist.md` (`code-review-and-quality`,
`security-and-hardening` ×4), `performance-checklist.md` (`code-review-and-quality`),
`orchestration-patterns.md` (`doubt-driven-development` ×2) and `definition-of-done.md`
(`incremental-implementation`, `planning-and-task-breakdown`). `orchestration-patterns.md` is cited
as the *authority* for a rule the skill enforces ("personas do not invoke other personas"), not as
a further-reading link, so these are load-bearing.

Every citation is written `../../references/<file>.md`. Upstream that resolves from
`<repo>/skills/<skill>/SKILL.md` to `<repo>/references/`; vendored, the identical relative path
resolves from `~/.claude/skills/<skill>/SKILL.md` to **`~/.claude/references/`**. So the directory
is vendored there and **every pointer resolves untouched** — no path rewrite, no patch, and nothing
to reconcile if upstream adds a fifth citation. That is why this is a `dest` column and not an L-flag.

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
one behind re-opens eight dangling pointers, and `--check` reports it in the same run.

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
through and the `main` tip is the upstream (see *Upstream resolution*). Their entries were removed
from `~/.agents/.skill-lock.json` in the same pass: the directories are vendor state now, and a
later `npx skills update` must not be able to overwrite them. `microsoft-foundry` and `find-skills`
stay CLI-managed there, for other agents.

Upstream ships no `disable-model-invocation` lines, so the one regime edit is local — the 13th of
L6's locally-added count. Ruled 2026-09-15, recorded here so it is not reopened:

| skill | regime | ruling |
|---|---|---|
| `adversarial-code-review` | slash-only — local L6 | Claims the same opening move as `code-review-and-quality` and `ponytail-review` ("review this / before merging") and is the most expensive misfire in the fleet — reviewer subagents plus skeptic reproduction in isolated worktrees. The source repo's own cheatsheet frames it as "the gate, not the everyday tool", a deliberate human-invoked ritual; nothing dispatches to it, so demotion breaks no dispatch graph. |
| `plan-walkthrough`, `pr-walkthrough`, `slides` | model-invoked | Each is the sole claimant of its opening move — reviewing a plan-shaped document, walking through a PR above the code level, building a deck — so there is no collision to demote on. Their sibling cross-references are prose, not dispatches. |

No patches: apart from that one frontmatter line the four are byte-identical to upstream, and
`slides`' `assets/` and `scripts/` travel inside its directory, so the tree hash covers them.

## Procedure

0. **`bash scripts/resync.sh --refresh`.** Pulls the marketplace clones, mirrors any plugin the
   catalog pins to a url+sha (superpowers, mattpocock-skills) whose current content is nowhere on
   disk, and fetches every `git+` row's mirror to its branch tip. This runs first and touches nothing under `~/.claude/skills`. It is mandatory before the
   first `--check` of a session: the install cache is frozen for disabled plugins (see *Upstream
   resolution* below), so without it `--check` compares against a stale tree and reports nothing.

1. **`bash scripts/resync.sh --check`.** Every row is decided by two inputs jointly — the upstream
   **tree hash** against the baseline says whether upstream moved, and the diff says what a
   re-vendor would change. The patch is the record of local edits, so its absence means there are
   none. It ends in five buckets:

   | Bucket | Meaning | Action |
   |---|---|---|
   | `identical` / `local-only` | no drift, or a local edit with a current patch | none |
   | `REVIEW` | a local edit that is `unsnapshotted` or `patch-stale` | step 2 |
   | `APPLIABLE` | upstream moved, or the row is `unvendored` (new, baseline `-`) | steps 3–4 |
   | `REFRESH` | upstream content is not on disk (a mirror missing or cache swept) | step 0 |
   | `BLOCKED` | not vendored, upstream gone, or a `dest` that escapes | by hand, one at a time |

   `local-only` with a current patch is silent and healthy — the edit is captured, so a later
   re-vendor replays it. Never infer a bucket from diff size: a large diff on an unchanged tree
   is still a local edit, and a small one on a changed tree is still an upstream change. The
   baseline is a per-skill tree hash, not a plugin commit sha, so a commit elsewhere in the
   plugin no longer reads as "this skill moved".
2. For each `REVIEW` row run `--diff <skill>` and check the diff against L1–L5 above. Confined to
   them, run **`--snapshot <skill>`** to capture it and the row goes quiet. Anything else is an
   **undocumented local edit**: report it inline and document it as a new L-flag in the same pass,
   then snapshot it. An unsnapshotted edit is the one thing a re-vendor destroys silently.
3. **Ask once, for the whole `APPLIABLE` set.** List the names and ask to re-vendor them all. Accept
   a subset if the user names one. `BLOCKED` skills are never included.
4. On confirmation, **`bash scripts/resync.sh --apply <skill> …`** runs the rest unattended. It
   stages from upstream, verifies the staged copy is byte-identical, backs the live directory up
   inside a `mktemp -d` (an `unvendored` row has none to back up, and a failure removes the new
   copy instead of restoring one), swaps wholesale — a merge would leave behind stale files that an upstream
   deletion should have removed, and that no later diff would catch — restores L6, replays the
   skill's patch, **verifies the live tree equals upstream+patch**, rebases the baseline, and sweeps
   every leftover. Nothing under `~/.claude/skills` is touched until a verified copy exists, and a
   skill whose patch rejects or fails verification is **rolled back whole** and keeps its old
   baseline, so a partial re-vendor is not a state this can reach.
5. Re-run `--check`. Expect `identical` or `local-only`. Do not report success from the fact that
   `--apply` exited 0.
6. For each rolled-back skill, reconcile by hand — this is the judgement the patches exist to
   isolate. Read the rejected hunk against the rewritten upstream, decide what the edit becomes
   (L5 may simply be obsolete), apply it to the live copy, then `--snapshot` it and `--apply` again.
7. Cleanup needs no step: `--apply` already ran `--clean`. It removes its own `mktemp -d` work and
   backup directories, any `SKILL.md.regime` staging file, any `.rej`/`.orig` a rejected patch left,
   `/skills-resync-backup` at the Git Bash mount root left by an older copy of this skill, **and**
   the marketplace clones the plugin installer orphans at `~/.claude/plugins/cache/temp_git_*`.
   It also prunes dead mirrors under `plugins/cache/skills-resync-mirror/`: the mirrors that are
   resolved upstream survive — a sha mirror while the catalog still pins its sha, a `git+` mirror
   while its inventory row exists (they *are* the upstream `--check`/`--diff` compare against);
   every other mirror is removed. Orphans younger than an hour are kept
   and reported instead — a concurrent plugin install works inside one, and nothing here can tell a
   live clone from a corpse by name. Override with `ORPHAN_MIN_AGE` on a machine known to be idle.
   Run `--clean --dry-run` on its own to size the leftovers without a re-vendor.
8. Report what was written, what was skipped, and what is still blocked.

`--self-test` exercises the replace, stale-file, missing-upstream, regime-restore, patch-replay,
reject-rollback, baseline-rebase, mainline-update, body-mention, initial-vendor/`dest` and
git-branch-tracking (clone, tip-update, malformed pid, prune-keep) paths in a
scratch directory, touching nothing real. Run it after editing the script.

Recommended cadence: monthly, or when a skill behaves unexpectedly.

## Upstream resolution

The install cache under `plugins/cache/` is **not** a usable upstream. These plugins are disabled,
and `claude plugin update` is version-gated: it answers "already at the latest version" and refuses
to re-fetch a moved sha while `plugin.json` still names the same version. A disabled plugin's cache
is therefore frozen at whatever it was installed with, and a diff against it sees no drift — the one
failure this whole skill exists to prevent. (Proven live: the cache reported `claude-automation-
recommender` as `identical` while the marketplace tree it was copied from had moved.)

So the script resolves upstream from the **marketplace clone** under `plugins/marketplaces/`, which
Claude Code refreshes, by the source kind the marketplace catalog records for the plugin:

- `./plugins/<name>` — the plugin tree lives inside the marketplace clone → use it in place
  (skill-creator, mcp-server-dev, claude-code-setup).
- `{source: github}` — the marketplace clone *is* the plugin → use it (agent-skills).
- `{source: url, sha}` — only a pinned sha is recorded, content not in the clone → mirror it
  (superpowers, mattpocock-skills). `--refresh` does the shallow fetch; the mirror lives under
  `plugins/cache/skills-resync-mirror/<plugin>/<sha12>/` and is kept (not swept) for as long as the
  catalog pins that sha.
- `git+<repo>@<branch>` — no marketplace at all, a plain repo tracked at a branch
  (RisorseArtificiali). The inventory row is the whole spec — there is no catalog entry to read —
  and the mirror sits at the same two-segment path with the repo munged flat. It is **mutable**:
  `--refresh` fetches and hard-resets it to the branch tip every run, where a pinned-sha mirror is
  skipped once fetched. A failed fetch keeps the mirror at the last known tip with a WARNING — the
  one bounded way a `--check` can compare against a stale upstream, and the WARNING is the signal
  that it did.

If the catalog entry is gone and the install cache is gone too, the row reads `upstream-missing`
(BLOCKED). `--hash <dir>` prints the tree hash a baseline holds, for reconciling by hand.
