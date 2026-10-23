---
name: skills-resync
description: Re-sync the vendored user skills against their upstream plugin or tracked-repo copies, re-vendor the ones that moved after one confirmation, and report dangling cross-references between them (--lint). Manual maintenance task.
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
compatibility: Designed for Claude Code. Requires bash 3.2+, git 2.30+, awk and Python 3.7+ (python3 or python) on PATH (Git Bash on Windows); manages the skills directory ($SKILLS_DIR).
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

`scripts/inventory.tsv` — the source each skill was vendored from (a plugin, or a tracked repo),
its subpath under it, and the upstream **tree hash** it was vendored at (a per-skill hash of the
upstream skill directory, not a plugin commit sha — see *Upstream resolution*). The script resolves
the upstream from the marketplace clone, so no version directory is recorded anywhere. The baseline column is rewritten by `--apply`;
hand-editing it makes `--check` lie in both directions — with one exception: **a new row is
authored with `-` as its baseline**. That is what marks it never-vendored, so `--check` reports it
`unvendored` and `--apply` performs the initial copy and writes the real hash. An optional 5th
column names a destination relative to the skills directory (`$SKILLS_DIR`), for the one row
that vendors something that is not a skill — see *The shared references* in RULINGS.md.

`scripts/patches/<skill>.patch` — the protected local edits themselves, as a patch `--apply` replays
onto each fresh vendor. Generated only by `--snapshot`, never by hand. This is what makes a
re-vendor of an edited skill mechanical instead of a hand step nothing could confirm had happened.

`$INVENTORY` and `$PATCHES`, when set, replace both paths, and they are the files every step below
means. A missing inventory stops every flag that reads it with `resync: no inventory at <path>`:
report the path and stop.

This directory's two documents — *why* each protected edit exists, and why a skill is or is not in
the inventory. `--check` output cannot be read without them.

## Procedure

Every step names a flag of one command, `bash "${CLAUDE_SKILL_DIR}/scripts/resync.sh" <flag>`.
The absolute path matters: the working directory is the user's project, not this skill, so a
relative `scripts/resync.sh` does not resolve (the L1 problem). Run it with the Bash tool — Git
Bash on Windows. In PowerShell, `bash` resolves to the WSL launcher
(`C:\Windows\system32\bash.exe`), which sees a different `~/.claude`. Give `--refresh`, `--apply`
and `--self-test` the maximum timeout the Bash tool accepts (600000 ms by default): on Windows the
2-minute default can stop them, and an `--apply` stopped mid-swap ends on a `KEPT:` copy (step 4).

0. **`--refresh`.** Pulls the marketplace clones, mirrors any plugin the
   catalog pins to a url+sha (superpowers, mattpocock-skills) whose current content is nowhere on
   disk, and fetches every `git+` row's mirror to its branch tip. This runs first and touches
   nothing under `~/.claude/skills`. It is mandatory before the first `--check` of a session: the
   install cache is frozen for disabled plugins (see *Upstream resolution* below), so without it
   `--check` compares against a stale tree and reports nothing. `--refresh` reports *N of M
   mirrors failed* and exits nonzero only when every mirror failed — a partial failure leaves the
   run comparable, and the WARNINGs are the signal of which mirrors sat still.

1. **`--check`.** Every row is decided by two inputs jointly — the upstream
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

   Rows `not-vendored` across the fleet — with `upstream-missing` where a marketplace is not added
   yet — are a new computer, not a loss: the engine maintains a fleet that exists and does not
   build one. Tell the user to copy `~/.claude/skills/` and `~/.claude/references/` from the old
   computer or a backup and to add its plugin marketplaces, then run step 0 again. Leave the
   baselines as they are — a `-` baseline vendors with no live copy to read the L6 regime from,
   so a locally slash-only skill comes back model-invoked.

   `local-only` with a current patch is silent and healthy — the edit is captured, so a later
   re-vendor replays it. Never infer a bucket from diff size: a large diff on an unchanged tree
   is still a local edit, and a small one on a changed tree is still an upstream change. The
   baseline is a per-skill tree hash, not a plugin commit sha, so a commit elsewhere in the
   plugin no longer reads as "this skill moved".
2. For each `REVIEW` row run `--diff <skill>` and check the diff against the L-flag index below,
   and RULINGS.md's full entries. Confined to them, run **`--snapshot <skill>`** to capture it and
   the row goes quiet. Anything else is an **undocumented local edit**: report it inline and
   document it as a new L-flag in the same pass, then snapshot it. An unsnapshotted edit is the
   one thing a re-vendor destroys silently. A diff of only `old mode`/`new mode` lines is no edit:
   an executable bit lost in a copy between computers. Tell the user to `chmod +x` the file named.
3. **Ask once, for the whole `APPLIABLE` set.** List the names and ask to re-vendor them all. Accept
   a subset if the user names one. `BLOCKED` skills are never included.
4. On confirmation, **`--apply <skill> …`** runs the rest unattended: it stages upstream, swaps
   the directory wholesale, restores L6, replays the patch, **verifies the live tree equals
   upstream+patch**, rebases the baseline and cleans up. A skill whose patch rejects or fails
   verification is **rolled back whole** and keeps its old baseline (step 6). Four kinds of output
   need the user, and each goes to them as it is, with the line under it:
   - `<skill>: could not move the live copy aside (in use?), nothing changed` — the rename was
     refused, and the line above gives the OS reason (on Windows, usually a directory held open by
     Explorer, an editor or a shell). Once the user frees it, `--apply` that skill again.
   - `KEPT: <dir>` — the run stops. The line under it names the skill and says whether the backup
     in that directory, or neither copy, is known to be whole. No run deletes the directory; the
     user restores the skill by hand.
   - a held `~/.claude/.skills-resync.lock` — another `--apply` or `--clean` is running, or one was
     killed. `--apply`'s message says which and what to check; the lock is the user's to remove.
   - any other line with `refusing` or `ROLLBACK FAILED`. For an `unvendored` row, the directory a
     `ROLLBACK FAILED` line names is a partial new copy the user deletes by hand.
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
7. Cleanup needs no step: `--apply` ends with `--clean`, unless it stopped on a `KEPT:` copy.
   `--clean` removes the engine's own leftovers, the orphaned `temp_git_*` plugin clones older
   than `ORPHAN_MIN_AGE` minutes (60), and the mirrors no row resolves to. It keeps and reports
   younger clones, because a concurrent plugin install may be working inside one. Every
   `.skills-resync-kept-*` directory, and every work directory whose `backup/` is not empty (a
   killed `--apply`), is listed as `clean: KEPT <dir>` and never removed; each such line goes to
   the user like a `KEPT:` in step 4. Run `--clean --dry-run` on its own to size the leftovers
   without a re-vendor.
8. Report what was written, what was skipped, and what is still blocked.
9. If this run changed `SKILL.md`, `RULINGS.md`, or the inventory and patches the engine used
   (`$INVENTORY`, `$PATCHES`), copy them into the tracked copy of this skill and commit it. The release and the CI test that copy, and nothing
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
  `writing-plans`: no `superpowers:` prefixes and no sibling path that fails to resolve;
  vendored targets become bare names, dropped or slash-only targets become plain instructions.
- **L4** — `subagent-driven-development` carries `code-reviewer.md` itself; its 4 links repointed
  to `./`, and `executing-plans` reaches the same copy at `../subagent-driven-development/`.
- **L5** — `build-mcp-app`, `build-mcpb`: three `../../build-mcp-server/` fixes for links broken
  *upstream* — drop the edit if upstream lands it.
- **L6** — the invocation regime is local state, never upstream state: `--apply` records and
  restores the flag, every diff ignores it, `--check` reports it as the REGIME column and footer.
  The rule and the ledger: RULINGS.md.
- **L7** — `writing-prds`: the unreachable `brainstorming` dispatch became "stop and tell the user
  to run `/brainstorming`".
- **L8** — `security-and-hardening`: the postmortem dispatch to a non-vendored skill became the
  instruction itself.
- **L9** — `build-mcp-server`, `build-mcp-app`: the hand-offs to the slash-only `build-mcp-app` and
  `build-mcpb` became "tell the user to run `/build-mcp-app`" / "`/build-mcpb`".
- **L10** — `interview-me`: "grill me" and "stress-test my thinking" left its triggers to
  `grilling`; its `idea-refine` hand-off became "tell the user to run `/idea-refine`".
- **L11** — `retro`: the `writing-for-agents` dispatch became "tell the user to run
  `/writing-for-agents`" — the target is vendored but slash-only, so no skill can reach it.

## What the inventory cannot say

One line each; the full rulings and their reasons are in RULINGS.md.

- Only 6 of superpowers' 14 skills are vendored — the other 8 were deliberately dropped. Do not
  vendor them back in to "fix" L3.
- `grill-me` and `grill-with-docs` were evaluated and deliberately not vendored: routers, not
  skills. Do not vendor them back in for symmetry.
- `setup-matt-pocock-skills` is not vendored — `to-tickets` points the user at it only in its
  no-tracker branch, in the `to-spec` form that does not dangle.
- The other five `humanlayer/skills` plugins are not vendored — one `git+` row for `show-me`, not
  a plugin install. Do not vendor the rest for symmetry.
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
- `git+<repo>@<branch>` — a repo tracked at a branch tip: a plain repo with no marketplace
  (RisorseArtificiali), or a marketplace repo when only one skill of it is wanted
  (`humanlayer/skills`). The row never reads the catalog and is the whole spec either way, and
  the mirror sits at the same two-segment path with the repo munged flat. It is **mutable**:
  `--refresh` fetches and hard-resets it to the branch tip every run, where a pinned-sha mirror is
  skipped once fetched. A failed fetch keeps the mirror at the last known tip with a WARNING — the
  one bounded way a `--check` can compare against a stale upstream, and the WARNING is the signal
  that it did.

If the catalog entry is gone and the install cache is gone too, the row reads `upstream-missing`
(BLOCKED). `--hash <dir>` prints the tree hash a baseline holds, for reconciling by hand.

`--self-test` runs in a scratch directory, touching nothing real. Every behavior change to the
script ships with a new fixture world in it, and both CI workflows run it on every push, pull
request and release — a green run is the proof the mechanics still hold. Run it after editing
the script.

Recommended cadence: monthly, or when a skill behaves unexpectedly.
