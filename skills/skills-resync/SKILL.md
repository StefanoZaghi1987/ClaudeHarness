---
name: skills-resync
description: Re-sync the vendored user skills in ~/.claude/skills against their upstream plugin or tracked-repo copies, re-vendor the ones that moved after one confirmation, and report dangling cross-references between them (--lint). Manual maintenance task.
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
compatibility: Designed for Claude Code. Requires git, patch, diff, awk and python3 on PATH (Git Bash on Windows); manages skills under ~/.claude/skills.
---

These skills were copied out of their plugins so they survive the plugin being disabled, updated
or swept. They receive no marketplace updates. `scripts/resync.sh` owns every mechanical step —
refreshing upstream, resolving it, classifying drift, swapping the directory, replaying the
protected local edits, restoring the invocation regime, verifying the result, sweeping the
fleet's cross-references, rebasing the baseline, deleting its own leftovers.

This document owns the judgement, and there are exactly two occasions for it: **a patch that
rejects**, meaning upstream rewrote a line a local edit owns, and **a `--lint` finding**, where
whether a named skill or path is prose or a broken instruction is ruled. Everything else is
decided by the script. The full record of both rulings — each protected edit's rationale, the
regime ledger, what was evaluated and not vendored — lives in [`RULINGS.md`](RULINGS.md), which
sits beside this document and loads only when this skill runs.

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
that is not a skill — see *The shared references* in RULINGS.md.

`scripts/patches/<skill>.patch` — the protected local edits themselves, as a patch `--apply` replays
onto each fresh vendor. Generated only by `--snapshot`, never by hand. This is what makes a
re-vendor of an edited skill mechanical instead of a hand step nothing could confirm had happened.

This directory's two documents — *why* each protected edit exists, and why a skill is or is not in
the inventory. `--check` output cannot be read without them.

## Procedure

0. **`bash scripts/resync.sh --refresh`.** Pulls the marketplace clones, mirrors any plugin the
   catalog pins to a url+sha (superpowers, mattpocock-skills) whose current content is nowhere on
   disk, and fetches every `git+` row's mirror to its branch tip. This runs first and touches
   nothing under `~/.claude/skills`. It is mandatory before the first `--check` of a session: the
   install cache is frozen for disabled plugins (see *Upstream resolution* below), so without it
   `--check` compares against a stale tree and reports nothing. `--refresh` reports *N of M
   mirrors failed* and exits nonzero only when every mirror failed — a partial failure leaves the
   run comparable, and the WARNINGs are the signal of which mirrors sat still.

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
2. For each `REVIEW` row run `--diff <skill>` and check the diff against the L-flag index below,
   and RULINGS.md's full entries. Confined to them, run **`--snapshot <skill>`** to capture it and
   the row goes quiet. Anything else is an **undocumented local edit**: report it inline and
   document it as a new L-flag in the same pass, then snapshot it. An unsnapshotted edit is the
   one thing a re-vendor destroys silently.
3. **Ask once, for the whole `APPLIABLE` set.** List the names and ask to re-vendor them all. Accept
   a subset if the user names one. `BLOCKED` skills are never included.
4. On confirmation, **`bash scripts/resync.sh --apply <skill> …`** runs the rest unattended. It
   stages from upstream, verifies the staged copy is byte-identical, backs the live directory up
   inside a `mktemp -d` (an `unvendored` row has none to back up, and a failure removes the new
   copy instead of restoring one), swaps wholesale — a merge would leave behind stale files that an
   upstream deletion should have removed, and that no later diff would catch — restores L6, replays
   the skill's patch, **verifies the live tree equals upstream+patch**, rebases the baseline, and
   sweeps every leftover. Nothing under `~/.claude/skills` is touched until a verified copy exists,
   and a skill whose patch rejects or fails verification is **rolled back whole** and keeps its old
   baseline, so a partial re-vendor is not a state this can reach.
5. Re-run `--check`. Expect `identical` or `local-only`. Do not report success from the fact that
   `--apply` exited 0. The `REGIME:` footer computes its own arithmetic — mapped slash-only split
   into local and upstream, plus unmapped slash-only — so reconcile it against the regime ledger in
   RULINGS.md, never against a memorised count. Then run **`--lint`**: it reports paths that do not
   resolve and instructions naming a missing or slash-only skill, guarded ones listed apart with
   their verdict — candidates only, because prose-vs-instruction is a ruling recorded in RULINGS.md
   (L8 is the worked case; the accepted pointers under *The mattpocock engineering group* are the
   other side of it).
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
   every other mirror is removed. Orphans younger than an hour are kept and reported instead — a
   concurrent plugin install works inside one, and nothing here can tell a live clone from a corpse
   by name. Override with `ORPHAN_MIN_AGE` on a machine known to be idle. Run `--clean --dry-run`
   on its own to size the leftovers without a re-vendor.
8. Report what was written, what was skipped, and what is still blocked.
9. If this run changed `SKILL.md`, `RULINGS.md`, `inventory.tsv` or `patches/`, copy them into the
   tracked copy of this skill and commit it. The release and the CI test that copy, and nothing
   else keeps the two in step — an `--apply` here rebases baselines the tracked copy never sees,
   and a patch the copy lacks is a patch its own documentation references but cannot ship.

## Protected local edits — index

`--apply` replays the patches and verifies the replay, so nothing below is a checklist to work
through by hand. It is the index of what each edit is *for* — needed when a patch rejects and you
must decide what the edit becomes against the rewritten upstream. Full entries with rationale:
[`RULINGS.md`](RULINGS.md).

- **L1** — `idea-refine`: the script path uses `${CLAUDE_SKILL_DIR}`, so it resolves at user scope.
- **L2** — `spec-driven-development`: Phase 4 names no other skill — prose with nothing left to
  dangle.
- **L3** — `executing-plans`, `subagent-driven-development`, `systematic-debugging`,
  `writing-plans`: no `superpowers:` prefixes, no `../<skill>/` paths; 16 upstream references
  reduced or rewritten.
- **L4** — `subagent-driven-development` carries `code-reviewer.md` itself; its 4 links repointed
  to `./`.
- **L5** — `build-mcp-app`, `build-mcpb`: three `../../build-mcp-server/` fixes for links broken
  *upstream* — drop the edit if upstream lands it.
- **L6** — the invocation regime is local state, never upstream state: `--apply` records and
  restores the flag, every diff ignores it, `--check` reports it as the REGIME column and footer.
  The rule and the ledger: RULINGS.md.
- **L7** — `writing-prds`: the unreachable `brainstorming` dispatch became "stop and tell the user
  to run `/brainstorming`".
- **L8** — `security-and-hardening`: the postmortem dispatch to a non-vendored skill became the
  instruction itself.

## What the inventory cannot say

One line each; the full rulings and their reasons are in RULINGS.md.

- Only 6 of superpowers' 14 skills are vendored — the other 8 were deliberately dropped. Do not
  vendor them back in to "fix" L3.
- `grill-me` and `grill-with-docs` were evaluated and deliberately not vendored: routers, not
  skills. Do not vendor them back in for symmetry.
- The three `build-mcp-*` skills are one unit — never re-vendor a subset.
- `claude-automation-recommender`, `skill-creator` and the three `build-mcp-*` carry their own
  per-skill `references/`; the `agent-skills` group's are shared and sit outside it (the
  `references` row).
- `code-review` is a command, not a skill, and is no longer vendored — Claude Code ships its own
  `/code-review`. Nothing to maintain.
- `ponytail` is deliberately not vendored and its plugin stays enabled but idle (`defaultMode:
  off`). Never report ponytail as missing or drifted. If the plugin is ever disabled, add rows for
  it to the inventory.
- The four `UNMAPPED` skills are originals with no upstream — `consolidate-comments`,
  `consolidate-specs`, `model-config-sync`, `skills-resync`. Any *other* name is a skill vendored
  without an inventory row, and needs one.

## Upstream resolution

The install cache under `plugins/cache/` is **not** a usable upstream. These plugins are disabled,
and `claude plugin update` is version-gated: it answers "already at the latest version" and refuses
to re-fetch a moved sha while `plugin.json` still names the same version. A disabled plugin's cache
is therefore frozen at whatever it was installed with, and a diff against it sees no drift — the one
failure this whole skill exists to prevent.

The script resolves upstream from the **marketplace clone** under `plugins/marketplaces/`, which
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

`--self-test` runs in a scratch directory, touching nothing real. Every behavior change to the
script ships with a new fixture world in it, and both CI workflows run it on every push and
release — a green run is the proof the mechanics still hold. Run it after editing the script.

Recommended cadence: monthly, or when a skill behaves unexpectedly.
