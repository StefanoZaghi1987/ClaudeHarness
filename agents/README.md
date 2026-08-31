# Subagents

A **subagent** is a helper agent with its own context window, its own model, and its own
tools. You start it by name, it does one job, and it reports back. Its context is separate
from yours, so it does not inherit the assumptions your session has accumulated.

This directory holds four of them. Three implement the gates of
[`WORKFLOW.md`](../WORKFLOW.md); the fourth produces the design that the first gate then
checks.

> **They implement the gates. They are not the gates.** A gate is an agent review followed
> by a human approval. These four agents do the first half. You do the second half, and the
> second half is not optional.

## The four at a glance

| Agent | Model | Tools | Role in the workflow |
|---|---|---|---|
| [`architect`](architect.md) | `fable` | `Read, Grep, Glob` | Produces a design, in Phase 1 or Phase 2 |
| [`spec-reviewer`](spec-reviewer.md) | `opus` | `Read, Grep, Glob` | Runs **Gate 1**, after Specify |
| [`implementation-plan-reviewer`](implementation-plan-reviewer.md) | `opus` | `Read, Grep, Glob` | Runs **Gate 2**, after Plan |
| [`code-reviewer`](code-reviewer.md) | `opus` | `Read, Grep, Glob, Bash` | Runs **Gate 3**, after Implement |

Two details in that table are deliberate, and each one is explained below.

## Why `architect` is the odd one out

`architect` is the only **generative** agent here. The other three read something that
already exists and report on it. `architect` produces a design where none existed.

It is also the only one on `fable`, the highest tier. Design is the phase where a better
model changes the outcome most, because a weak architectural choice is not caught by tests
and is expensive to reverse. Review, by contrast, is a bounded reading task, and `opus`
handles it well.

What it must do, in order:

1. **Ground itself in the code.** Read the real modules, conventions, and existing patterns
   first. It is explicitly told not to invent structure that ignores what is already there.
2. **Propose an architecture.** Component boundaries and responsibilities, data flow, key
   interfaces, and where new code should land — preferring to extend existing patterns
   rather than introduce new ones.
3. **Name one or two rejected alternatives**, each with its concrete trade-off: latency,
   complexity, coupling, cost. This requirement exists because a design with no rejected
   alternatives is not a design — it is the first idea, written up.
4. **Cover security and failure modes.** Trust boundaries, authentication and authorisation,
   error handling, the rollback path, operational burden.
5. **Give a build order** that keeps the build and the tests green throughout.

It returns a design, not a step-by-step implementation plan. It also has an escape hatch:
if the task is too small to warrant architecture, it must say so in one line rather than
invent work.

## Why only `code-reviewer` has `Bash`

The other three are strictly read-only: `Read`, `Grep`, `Glob`. `code-reviewer` carries
`Bash` for exactly one reason — it runs `git diff` or `git diff --staged` and sources its
own diff, so you do not have to paste one in.

That is the whole justification. A reviewer that could also write would stop being a
reviewer.

## The three reviewers

Each reviews on four axes and returns a **ranked list, blocking findings first, each with a
concrete fix**. None of them restates the artifact back at you. If the artifact is sound,
each says so briefly and stops.

### `spec-reviewer` — Gate 1

| Axis | What it looks for |
|---|---|
| Correctness | Internal consistency, unstated assumptions, requirements that contradict each other or the existing codebase |
| Architecture | Component boundaries, data flow, failure modes, scalability limits, and **simpler alternatives that meet the same requirements** |
| Security | Trust boundaries, authentication and authorisation gaps, data exposure, injection surfaces |
| Maintainability | Coupling, migration and rollback paths, operational burden |

It reads only what it needs to verify the spec's claims against the codebase — a spec review
is not an excuse to read the whole repository.

### `implementation-plan-reviewer` — Gate 2

This one has a job the others do not: it **spot-checks the plan's claims by opening the
files the plan names**. A plan that acts on a function which does not exist is the most
common planning failure, and nothing else in the pipeline catches it before execution.

| Axis | What it looks for |
|---|---|
| Correctness | Do the files and APIs in each step exist? Is the order such that the build and tests stay green throughout? |
| Completeness | Missing migrations, configuration, tests, documentation, rollout and rollback steps |
| Architecture | Does the plan respect existing patterns and boundaries, or silently fork them? |
| Risk | Irreversible steps, security-sensitive changes, hidden coupling between steps |

### `code-reviewer` — Gate 3

| Axis | What it looks for |
|---|---|
| Correctness | Logic errors, unhandled edge cases, error handling, concurrency |
| Security | Input validation, injection, secrets in code, unsafe defaults |
| Architecture | Consistency with surrounding patterns, needless complexity or duplication |
| Maintainability | Naming, dead code, test coverage of the changed behaviour |

Two constraints keep its output usable: it reports **only issues it is confident about**,
each with a `file:line` and a concrete fix, and it **skips style points a formatter would
catch**. A review that lists forty things is a review nobody reads.

## The shared contract

- **A blocking finding sends work back one phase, never forward.** A spec with a blocking
  finding does not become a plan. A plan with a blocking finding does not become code.
- **Blocking findings come first, each with a fix.** A finding without a proposed fix is a
  complaint.
- **Silence on a clean artifact.** One line or one paragraph, then stop.
- **Models are named by alias, never by version ID.** `fable`, `opus`, `sonnet` and `haiku`
  are tiers, not releases, so these files keep working when the underlying models change.
  The [`model-config-sync`](../skills/model-config-sync/SKILL.md) skill exists to re-check
  that assumption against the official documentation after a Claude Code release.

## Installing them

Copy the `.md` files — not this README — into your agents directory:

```bash
find agents -name '*.md' ! -name README.md -exec cp {} ~/.claude/agents/ \;
```

Then restart Claude Code. The agents become available by name, both to you and to the
planner. Each works on its own; the pipeline in [`WORKFLOW.md`](../WORKFLOW.md) is how they
are designed to be used together.

The release zip already excludes this file, so unzipping it into `~/.claude/` will not drop
a stray README into a directory that Claude Code scans for agent definitions.
