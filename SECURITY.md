# Security

This repository ships configuration, not a service. The security surface is narrow and
specific, and this page states it plainly rather than reciting a template.

## Supported versions

The latest [release](https://github.com/StefanoZaghi1987/ClaudeHarness/releases) only. There
are no maintenance branches.

## The trust model

### A skill is a prompt, and a prompt is the thing the model obeys

`skills-resync` copies `SKILL.md` files from third-party plugins into `~/.claude/skills/`,
where Claude Code loads them as instructions. It never executes upstream code — it copies
files and applies patches — but that distinction buys less than it sounds like it does: the
files it copies are instructions the model will follow, in your sessions, with your tools and
your credentials.

> **Vendoring a skill means trusting whoever controls its upstream, to the same degree you
> trust anything else that can tell the model what to do.**

Every source is named in
[`skills/skills-resync/scripts/inventory.tsv`](skills/skills-resync/scripts/inventory.tsv).
Read that file as a list of parties you have decided to trust.

### Some sources are pinned and some are not

| Source kind | Upstream is | What that means for you |
|---|---|---|
| local-path and GitHub-source marketplace entries | the marketplace clone | Moves when the marketplace moves. |
| url-pinned marketplace entries (`{source: url, sha}`) | a mirror of one **immutable** sha | Cannot change under you. A new sha is a visible inventory change. |
| `git+<repo>@<branch>` rows | the **branch tip**, hard-reset on every `--refresh` | **Mutable by design.** Whoever can push to that branch can change what you vendor next. |

The `git+…@branch` kind is the one to think about before adopting it. It exists because the
source has no marketplace, and it trades pinning for freshness knowingly.

### The review step is `--check` and `--diff`, and it is not optional

`--apply` performs a **wholesale swap**: it stages the upstream copy, verifies it byte for
byte, backs the live directory up in a temporary directory, replaces it, restores the local
invocation regime, replays your protected-edit patch, verifies the result equals
upstream-plus-patch, and rebases the baseline. If a patch rejects, it rolls back **whole** —
a partially re-vendored skill is unreachable by construction.

None of that tells you whether the new upstream text is something you want the model reading.
That is what `--check` and `--diff <skill>` are for, and `--apply` deliberately asks for one
confirmation covering the whole appliable set rather than proceeding on its own.

### `inventory.tsv` is an example, not a configuration to adopt

It ships as a worked example of the format. Copying it wholesale copies the author's trust
decisions along with it. Point the `INVENTORY` environment variable at your own file instead.

### What the rest of the repository does

- The four subagents in `agents/` are `Read`, `Grep`, `Glob` only, except `code-reviewer`,
  which also carries `Bash` for one purpose: running `git diff` to source its own diff.
- `rules/effort-escalation.md` changes reasoning effort policy and nothing else.
- `model-config-sync` fetches the official Claude Code documentation over the network and
  **never applies an edit without your approval**.
- `build_release.py` validates and zips. It has no dependencies and makes no network calls.
- The GitHub Actions workflows pin every action to a full commit SHA, not a floating tag.

### Run the self-test first

```bash
bash ~/.claude/skills/skills-resync/scripts/resync.sh --self-test
```

It exercises replace, patch replay, reject-rollback and baseline rebase in a throwaway
directory and touches nothing in your real setup. Run it before the first `--apply` on any new
machine.

## Reporting a vulnerability

Use GitHub's **private vulnerability reporting** on this repository (Security → Report a
vulnerability). If that is unavailable to you, open a normal issue that describes the *class*
of the problem without a working exploit, and say that you have details to share privately.

Please report anything that lets a third party change what lands in `~/.claude` without the
confirmation step, anything that makes `--apply` leave a skill directory in a partially
replaced state, and anything in the shipped subagents or rule that widens their tool access
beyond what is documented above.

This is a personal project with no service-level commitment. Expect a best-effort reply, not
a guaranteed window.
