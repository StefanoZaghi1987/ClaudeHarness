# Tools: what can implement each phase, and what fits beside what

The **reference** half of the workflow. [`WORKFLOW.md`](../WORKFLOW.md) is normative and is meant
to be read once, top to bottom; this page is meant to be opened twenty times and never read in
order.

It owns two things, and they live nowhere else in the repository:

- **the catalogue** — every tool, once, under the phase it primarily serves;
- **the four rules** that decide whether two tools can sit next to each other.

Where each tool comes from and how to obtain it is [`skills/README.md`](../skills/README.md).
Where each artifact lands on disk is the
[artifact ledger](../WORKFLOW.md#the-artifact-ledger). The worked decision procedures — which
helper at which writing or reviewing moment — are
[`WRITE-AND-REVIEW.md`](WRITE-AND-REVIEW.md).

## Contents

- [How to read this page](#how-to-read-this-page)
- [Start here: what am I holding?](#start-here-what-am-i-holding)
- [The catalogue](#the-catalogue)
- [Composing tools: four rules](#composing-tools-four-rules)
- [The orderings still worth naming](#the-orderings-still-worth-naming)
- [Getting the tools](#getting-the-tools)

---

## How to read this page

Every catalogue row carries the same six columns.

| Column | What it tells you |
|---|---|
| **Tool** | The name you invoke. |
| **Kind** | `skill`, `subagent`, `rule`, or `mode`. Only a skill has a regime. |
| **Source** | The plugin or repo it comes from. **This column never affects whether two tools compose** — see [Not a rule](#not-a-rule-where-the-tool-comes-from). |
| **Regime** | `auto` — the model may start it on its own, **and another skill can dispatch it**. `manual` — it carries `disable-model-invocation: true`; you call it by name, and no skill can reach it. |
| **Writes** | The artifact key it leaves behind, or `—`. Keys are defined in the [artifact ledger](../WORKFLOW.md#the-artifact-ledger). |
| **What it does** | And when to reach for it. |

Two properties of this page are load-bearing:

> **Every tool has exactly one primary row**, in the phase it mainly serves. When a tool
> genuinely serves a second phase, it appears there only as a short pointer row that links
> back to its primary row — never as a second full row. If you find two full rows for the
> same tool, that is a bug in this page.

> **Regime is local state, not upstream.** `skills-resync` treats the invocation regime as a
> protected local edit, so a skill's regime here can differ from what its plugin ships. The
> governing rule is *demote a skill the moment a second skill claims the same opening move*.

## Start here: what am I holding?

The table to reopen at nine in the morning.

| When you are… | Reach for | Your part |
|---|---|---|
| holding a vague idea | `interview-me` | answer honestly, including "I don't know" |
| holding an idea that needs options | `idea-refine` | pick the direction |
| still uneasy after the interview | `grilling` | defend the idea, or change it |
| facing work too big for one session | `idea-refine`, then `wayfinder` | resolve the decision tickets, one per session |
| needing a fact a decision waits on | `research` | say where the note should live |
| needing something concrete to react to | `prototype` | react to it; do not keep it |
| unsure what the words in this project mean | `domain-modeling` | rule on the terms it challenges |
| holding a wayfinder map with every ticket closed | [the decision ledger](MAP-TO-SPEC.md) | approve the capability map before a single spec is written |
| holding a ledger and an approved capability map | `writing-prds` above, `to-spec` per capability | check the testing seams match what you expected |
| facing an open structural question | `architect` subagent | choose between the alternatives it names |
| ready to write down what "done" means | `spec-driven-development` | read the spec as if you had not written it |
| holding a finished spec or PRD you want walked | `plan-walkthrough` | answer the closed-menu questions, triage the findings |
| holding a finished spec | `spec-reviewer` subagent | **approve it, or send it back** |
| holding an approved spec | `writing-plans` | check the plan matches the scope of the spec |
| unable to say what the first step is | `planning-and-task-breakdown` | confirm the dependency order |
| holding a finished plan you want walked | `plan-walkthrough` | answer the closed-menu questions, triage the findings |
| reviewing a plan-shaped document that is not yours | `plan-walkthrough` (QUESTIONS mode) | turn the findings into author questions |
| holding a finished plan | `implementation-plan-reviewer` subagent | **approve it, or send it back** |
| about to write multi-file code | `incremental-implementation` | keep the steps small |
| about to write code that invites over-building | `/ponytail` | say "stop ponytail" the moment it gets in the way |
| executing a long plan | `executing-plans` | review at each checkpoint |
| about to make an irreversible decision | `doubt-driven-development` | read the disproof honestly |
| touching auth, storage, or untrusted input | `security-and-hardening` | do not defer it to review |
| holding a finished diff | `code-reviewer` subagent | **approve the merge, or send it back** |
| staring at a diff too big to judge by reading | `pr-walkthrough` | judge the impact map before the lines |
| merge-bound or risky, and it matters | `/adversarial-code-review` | read the verified verdict, then merge explicitly |
| holding a correct diff that looks inflated | `/ponytail-review` | decide which cuts you accept |
| holding correct but unclear code | `code-simplification` | confirm the behaviour did not change |
| looking at code that is correct and wrong-shaped | `/improve-codebase-architecture` | pick one opportunity from the report |
| finishing a feature or an epic | `consolidate-specs`, `consolidate-comments`, `documentation-and-adrs` | answer the "to be confirmed" questions |
| looking at a bug report | `diagnosing-bugs` or `systematic-debugging` | do not accept a symptom fix |
| lost in the agent's last message | `wait-what` | say what did not land |
| running out of session | `handoff` | check the handoff before closing |
| having to present the work | `slides` | rehearse from the speaker notes |
| suspecting the repo has grown heavier than the work | `/ponytail-audit` | read the ranked list, delete nothing on faith |
| a month since the last one | `skills-resync` | approve each re-vendor |

---

## The catalogue

### Phase 1 — Brainstorm

| Tool | Kind | Source | Regime | Writes | What it does, and when to reach for it |
|---|---|---|---|---|---|
| `interview-me` | skill | `agent-skills` | auto | intent | Asks you one question at a time until it is about 95% confident that it understands the *underlying* intent — not the feature you asked for, but the problem behind it. Reach for it whenever a request is underspecified, or when you catch yourself filling in requirements silently. Downstream hand-offs: `idea-refine` when the confirmed intent still needs options, `spec-driven-development` when it is already concrete. |
| `idea-refine` | skill | `agent-skills` | manual | idea | Structured divergent then convergent thinking: it first widens the set of options, then narrows it, and leaves a one-pager with a recommended direction and a *not doing* list. Reach for it when the idea is still shapeless, or when you want alternatives before committing to one. On Route D it runs **before** `wayfinder`: the one-pager names the destination the map is charted toward. |
| `grilling` | skill | `mattpocock-skills` | auto | — | Adversarial questioning of a plan, decision, or idea. It builds a design tree and works the frontier until it is empty, and it dispatches subagents for facts rather than asking you to look things up. Deliberately uncomfortable. Reach for it when the interview is finished but something still feels unresolved. |
| `brainstorming` | skill | `superpowers` | manual | design doc | The all-in-one path. It first classifies how much process the request needs, then works through dialogue to a design. Reach for it when you want one skill to carry you from idea to draft design in a single conversation. It reaches into Phase 2 — see the pointer row under [Phase 2](#phase-2--specify). |
| `wayfinder` | skill | `mattpocock-skills` | manual | map | For work too large for a single agent session. It charts the route as decision tickets on the issue tracker, then resolves them one at a time — **dispatching the three skills below itself**. Reach for it when the destination is clear but the way there is not. A closed map is not a spec: see [MAP-TO-SPEC.md](MAP-TO-SPEC.md). |
| `research` | skill | `mattpocock-skills` | auto | research note | Investigates a question against high-trust primary sources and captures the findings as Markdown, every claim cited. It mandates no path and must tell you where it saved the note. **A `wayfinder` research ticket dispatches it**; you rarely call it yourself. |
| `prototype` | skill | `mattpocock-skills` | auto | prototype | Builds a throwaway artifact — an outline, a stub, rough UI or logic code — so a design question has something concrete to react to. **A `wayfinder` prototype ticket dispatches it.** Reach for it directly only when "how should it look" or "how should it behave" is the blocking question. |
| `architect` | subagent | **this repo** (`fable`) | — | — | Catalogued under [Phase 2](#phase-2--specify), because what it produces is the design the spec is written from. In Phase 1 it goes **last, never first**: it designs well, but it designs whatever you point it at. |

### Phase 2 — Specify

| Tool | Kind | Source | Regime | Writes | What it does, and when to reach for it |
|---|---|---|---|---|---|
| `spec-driven-development` | skill | `agent-skills` | auto | capability map, spec, task list | Writes the specification before any code. When one requirement covers several independently testable capabilities, its gated Phase 0 decomposes them into a capability map of modules. Reach for it for any new feature or significant change. Its Plan and Tasks steps defer to `planning-and-task-breakdown` as the canonical source for the breakdown mechanics. |
| `architect` | subagent | **this repo** (`fable`) | — | — | Reads the real codebase, then proposes component boundaries, data flow, failure modes, where new code should live, and a build order that keeps the tests green. It must name one or two rejected alternatives with their trade-offs, and it has an escape hatch: it will tell you in one line if the task is too small to need architecture. Reach for it before the spec when the shape of the solution is genuinely open. |
| `writing-prds` | skill | `RisorseArtificiali/skills` | manual | PRD | Writes a phased PRD: problem, goal, non-goals, success criteria, decisions, phases with acceptance criteria, open questions. It refuses a raw idea — its gate is a validated understanding of the problem plus a set of `grilling` decisions. Reach for it when the work spans several phases and the decisions behind it are already settled. |
| `to-spec` | skill | `mattpocock-skills` | manual | spec | Synthesises a spec from what has already been settled, with no interview: problem, solution, a long numbered list of user stories, implementation decisions, testing seams, out of scope. Reach for it per capability, once that capability's decisions are closed. |
| `domain-modeling` | skill | `mattpocock-skills` | auto | domain model | Actively builds and sharpens the project's domain model: it challenges terms, invents edge cases, and writes the glossary and the decisions down as they crystallise. **Dispatched by `wayfinder` on every grilling ticket and by `improve-codebase-architecture`**; call it directly when the words in the project have stopped meaning one thing each. |
| `documentation-and-adrs` | skill | `agent-skills` | auto | ADR | Records a decision as an ADR. Reach for it when the spec contains a choice that future readers will question — the *why* belongs in an ADR, not in the spec. It serves [Closing out](#closing-out) too. |
| `brainstorming` | skill | `superpowers` | manual | design doc | Pointer row — catalogued under [Phase 1](#phase-1--brainstorm). Its later phases produce the design document directly, so one pass can cover Phase 1 and Phase 2 together. That is the cheapest option, and the weakest: intent and spec arrive together, and there is no separate stated intent to check the spec against. Its own last step then names `writing-plans` as the next skill — the successor is decided, not chosen. |

### Phase 3 — Plan

| Tool | Kind | Source | Regime | Writes | What it does, and when to reach for it |
|---|---|---|---|---|---|
| `writing-plans` | skill | `superpowers` | auto | plan | Turns a spec or clear requirements into a written plan, before any code is touched, assuming the engineer who executes it has zero context: which files each task touches, how to test it, what to read first. Reach for it for any multi-step task. Its plans name their own required executor: `subagent-driven-development` (recommended) or `executing-plans`. |
| `planning-and-task-breakdown` | skill | `agent-skills` | auto | task list | Breaks work into ordered tasks, estimates scope, and identifies which parts can run in parallel. It owns the task-list target. Reach for it when you cannot say what the first step is — that, not the size of the change, is the signal. |
| `plan-walkthrough` | skill | `RisorseArtificiali/skills` | auto | plan review | Logical review of a plan-shaped document — a spec, a PRD, an implementation plan, a design doc, a GitHub issue — with you in the loop. It builds a visual dossier (phase graph, `REQ-1…n` traceability matrix, assumption map, reality check against the codebase), then walks it step by step with closed-menu questions and finding triage. It is resumable. It has three moments — on a finished spec or PRD in Phase 2, on a plan in Phase 3, and as the ledger audit on Route D — see [Who reviews what](../WORKFLOW.md#who-reviews-what). Its graphs show the document's structure, not the system's architecture. Two modes, asked at setup: **EDIT** — the document is yours; accepted fixes are applied as before/after pairs you approve, and a *ready to commit* verdict hands off to `writing-prds` task decomposition. **QUESTIONS** — the document is someone else's; findings become author questions, optionally a drafted GitHub comment. |
| `dispatching-parallel-agents` | skill | `superpowers` | manual | — | Prepares two or more genuinely independent tasks for parallel agents, giving each exactly the context it needs and nothing else. Reach for it only when the tasks share no state and have no ordering between them — and only **after** a breakdown. |

### Phase 4 — Implement

| Tool | Kind | Source | Regime | Writes | What it does, and when to reach for it |
|---|---|---|---|---|---|
| `incremental-implementation` | skill | `agent-skills` | auto | — | Delivers the change in small, verifiable slices instead of one large edit. Reach for it whenever the change touches more than one file, or when a task feels too big to land in one go. |
| `executing-plans` | skill | `superpowers` | auto | — | Executes a written plan in a **separate session**, in an isolated worktree, with review checkpoints between steps and the full test suite before completion. Reach for it when the plan is long enough that carrying the planning conversation into the implementation would crowd the context window. When subagents are available, the skill itself points to `subagent-driven-development` instead. |
| `subagent-driven-development` | skill | `superpowers` | auto | progress | Executes independent plan tasks in the **current** session by dispatching subagents, keeping its own ledger so a fresh session can pick the work up. Reach for it when the plan has parallel branches and you want to stay in one conversation. |
| `doubt-driven-development` | skill | `agent-skills` | manual | — | Brings in a fresh-context reviewer that tries to **disprove** a non-trivial decision before it stands. Reach for it per decision — in unfamiliar code, in security-sensitive logic, before anything irreversible. Used everywhere, it doubles the cost of everything, including the parts that were never in doubt. |
| `security-and-hardening` | skill | `agent-skills` | auto | — | Hardens code that accepts untrusted input, manages sessions, stores data, or talks to third parties, and covers dependency and privacy risk. Reach for it **while writing that code**, and again in Phase 5 as a dedicated pass over the sensitive surfaces of the diff. |
| `effort-escalation` | rule | **this repo** | — | — | Keeps reasoning effort at the default level. The agent may only *recommend* raising it — for deep multi-file debugging, an architecture decision with real trade-offs, a security-critical review, or a final verification pass — and must then wait for you to set it. |
| `ponytail` | mode | `ponytail` | — | — | A lazy-senior-dev mode: question whether the code needs to exist at all, reach for the standard library before writing one, refuse an abstraction with a single implementation. Reach for it with `/ponytail` when the change is the kind that attracts speculative structure. It is **off by default on purpose** — as an always-on mode it contradicts Phases 1–3, where "shortest diff wins" is the wrong instinct. |

### Phase 5 — Review

| Tool | Kind | Source | Regime | Writes | What it does, and when to reach for it |
|---|---|---|---|---|---|
| `code-reviewer` | subagent | **this repo** (`opus`) | — | — | The default gate. It is the only agent in this repository with `Bash`, for exactly one reason: it runs `git diff` and collects the diff itself. It reports only findings it is confident about, most severe first, each with a `file:line` and a concrete fix, and it skips style points a formatter would catch. |
| `code-review-and-quality` | skill | `agent-skills` | auto | — | A multi-axis review pass before merging. Reach for it when you want a broader review than the diff-focused subagent gives — including for code written by another agent or another person. For the security verdict it defers to `security-and-hardening`. |
| `pr-walkthrough` | skill | `RisorseArtificiali/skills` | auto | PR review | The above-the-code pass: before-and-after architecture diagrams of the change, a Mermaid map of impacts, UX, operations, docs and tests, then an interactive walkthrough with finding triage. Reach for it when the diff is too large or unfamiliar to judge by reading, or when the PR is someone else's. It feeds your Gate 3 decision; it is not line-level review. |
| `adversarial-code-review` | skill | `RisorseArtificiali/skills` | manual | — | The heavy pre-merge treatment: fresh-context reviewers attack the change from distinct lenses, then skeptic subagents must reproduce every finding in an isolated worktree before it counts. Invoke `/adversarial-code-review` when the change is merge-bound and risky, or when a clean review surprised you. The heavy option for risky merges, not the everyday review. Complementary to `doubt-driven-development`: that cross-examines decisions while the work happens; this is the post-hoc pass on the finished change. |
| `code-simplification` | skill | `agent-skills` | auto | — | Refactors for clarity without changing behaviour. Reach for it **after** the code is correct, never instead of correctness. |
| `ponytail-review` | skill | `ponytail` | auto | — | A review pass that hunts **only** over-engineering: reinvented standard library, a dependency for what the platform already ships, an abstraction with one implementation, dead flexibility. Correctness, security and performance are explicitly out of scope. One line per finding, ending in `net: -N lines possible.` Reach for it when a correct diff still looks larger than the change it makes. |
| `codebase-design` | skill | `mattpocock-skills` | auto | — | The shared vocabulary for deep modules — depth, seam, adapter, leverage — plus the deletion test and the design-it-twice pattern. It is a reference that other skills call on for the terms, rather than a pass you run. Keep it `auto`: demoting it breaks every skill that dispatches it. |
| `improve-codebase-architecture` | skill | `mattpocock-skills` | manual | architecture report | Scans a codebase for deepening opportunities, presents them as a visual HTML report, then grills through whichever one you pick — **dispatching `codebase-design` and `domain-modeling` itself**. Invoke `/improve-codebase-architecture` when the code is correct and the wrong shape. This is the entry point of [Route F](../WORKFLOW.md#route-f--architecture-debt). |

### Closing out

Run these at the end of a feature or an epic — never in the middle of an implementation.

| Tool | Kind | Source | Regime | Writes | What it does |
|---|---|---|---|---|---|
| `consolidate-specs` | skill | [ClaudeSkills](https://github.com/StefanoZaghi1987/ClaudeSkills) | auto | — | Realigns the spec to the code it now describes, relocates historical rationale into an ADR, and hands anything it cannot resolve to a person through a `## To be confirmed` section. |
| `consolidate-comments` | skill | [ClaudeSkills](https://github.com/StefanoZaghi1987/ClaudeSkills) | auto | — | Deletes comments that only restate the code, and keeps what the code cannot say about itself. A comment is the one artifact that can lie without a test breaking. |
| `documentation-and-adrs` | skill | `agent-skills` | auto | ADR | Catalogued under [Phase 2](#phase-2--specify). Here it records the decision the work embodied, so the next reader does not have to reverse-engineer it from the diff. |
| `handoff` | skill | `mattpocock-skills` | manual | handoff | Catalogued under [Any moment](#any-moment-the-cross-cutting-tools). |

### The bug-fixing lane

| Tool | Kind | Source | Regime | Writes | What it does, and when to reach for it |
|---|---|---|---|---|---|
| `diagnosing-bugs` | skill | `mattpocock-skills` | auto | — | A diagnosis loop for hard bugs and performance regressions. Reach for it when something is broken, throwing, failing, or slow, and you do not yet know why. |
| `systematic-debugging` | skill | `superpowers` | manual | — | Enforces one rule above all others: find the root cause before proposing any fix. Reach for it on any bug, test failure, or unexpected behaviour. |

### Any moment: the cross-cutting tools

These belong to no phase. They apply whenever the situation appears.

| Tool | Kind | Source | Regime | Writes | When to reach for it |
|---|---|---|---|---|---|
| `wait-what` | skill | `mattpocock-skills` | manual | — | The agent's last message did not land. It forces a re-pitch in plain language. |
| `handoff` | skill | `mattpocock-skills` | manual | handoff | The work continues in another session, or with another agent. It writes outside the workspace on purpose, names a suggested next skill, and redacts secrets. |
| `context-engineering` | skill | `agent-skills` | manual | — | Output quality is degrading, or you have just switched to a different task. It curates what the agent sees. |
| `writing-for-agents` | skill | `mattpocock-skills` | manual | — | You are writing or editing a skill, a `CLAUDE.md`, an `AGENTS.md`, or any other document an agent will consume. |
| `slides` | skill | `RisorseArtificiali/skills` | auto | deck | The work must be presented or explained to an audience. It builds a slides markdown plus a fully-local reveal.js deck — no CDN, speaker notes included. |
| `ponytail-audit` | skill | `ponytail` | auto | — | The repository feels heavier than the work it does. A whole-tree over-engineering scan, ranked biggest cut first. One-shot, and it applies nothing. |
| `skills-resync` | skill | **this repo** | manual | — | Monthly, or when a skill behaves unexpectedly: re-sync your vendored skills against their upstream plugins or tracked repos. |
| `model-config-sync` | skill | **this repo** | manual | — | After a Claude Code release: re-check the model routing against the current official documentation. |
| `dispatching-parallel-agents` | skill | `superpowers` | manual | — | Catalogued under [Phase 3](#phase-3--plan), because deciding what is parallel is a planning act. |

### Building the tooling itself

Outside the feature workflow.

| Tool | Kind | Source | Regime | Writes | When to reach for it |
|---|---|---|---|---|---|
| `skill-creator` | skill | `skill-creator` | manual | — | You are building a new skill from scratch, or measuring an existing one. |
| `claude-automation-recommender` | skill | `claude-code-setup` | manual | — | You want to know which parts of your setup could be automated with hooks or commands. |
| `build-mcp-server`, `build-mcp-app`, `build-mcpb` | skills | `mcp-server-dev` | manual | — | You are building an MCP server, an MCP app, or an MCP bundle. The three are **one unit** — they cross-reference each other through sibling-relative paths. |

---

## Composing tools: four rules

A lookup table can only answer the questions somebody thought to write down. Per-phase pair
tables grow longer as the fleet grows, and they stay incomplete. These four rules are the
replacement: with them you can decide **any** pair, including pairs nobody has tried.

### Rule 1 — the invocation regime decides what can be reached

A skill marked `manual` in the catalogue carries `disable-model-invocation: true`. That flag does
two things, and the second one surprises people:

1. the model will never start it on its own — you call it by name;
2. **no other skill can dispatch it either.**

So the regime is not merely a context-cost setting. It is a reachability property.

> **Every skill that is a dispatch target must stay `auto`.**

Demote `grilling`, `domain-modeling`, `research`, `prototype` or `codebase-design` and you do not
make the harness quieter — you silently break `wayfinder` and `improve-codebase-architecture`.

### Rule 2 — a dispatcher already contains its targets

You do not *combine* a dispatcher with a skill it dispatches. The second is already inside the
first. Pairing them by hand runs the inner skill twice: once with the dispatcher's constructed
context, and once without.

There are exactly two dispatchers in the fleet.

| Dispatcher | Trigger | What it calls |
|---|---|---|
| `wayfinder` | a `research` ticket | `research` |
| | a `prototype` ticket | `prototype` |
| | a `grilling` ticket — **its default type** | `grilling` **and** `domain-modeling`, together |
| | a `task` ticket | nothing; the work is manual |
| | naming the destination, and mapping the frontier | `grilling` **and** `domain-modeling` |
| `improve-codebase-architecture` | throughout | `codebase-design`, `domain-modeling` |

Two consequences are worth stating:

- **`interview-me` is not a wayfinder ticket type.** There is no `wayfinder` → `interview-me`
  pairing. A ticket asks for a decision; an interview elicits an intent, and by the time a map
  exists the intent is settled.
- **`wayfinder` output is already grilled.** `grilling` is its default ticket type, so a closed
  map carries grilling decisions by construction. That is why `writing-prds` accepts it without
  waiving its own prerequisite — see [MAP-TO-SPEC.md](MAP-TO-SPEC.md).

### Rule 3 — overlapping triggers fire the wrong tool

Two `auto` skills whose descriptions claim the same opening move will collide, and you cannot
predict which one wins. The remedy is always the same: **leave one `auto`, and call the other by
name.**

| Pair | What they both claim |
|---|---|
| `idea-refine`, `brainstorming` | divergent exploration of a raw idea. Running both in one pass is worse than colliding: the second re-opens what the first closed. |
| `interview-me`, `grilling` | stress-testing your thinking. In *sequence* they are complementary; in parallel they compete, because one is trying to understand you while the other is trying to break you. |
| `writing-prds`, `spec-driven-development` | *drafting a PRD or requirements document*. |

The catalogue's `Regime` column already records how each collision was resolved here.

### Rule 4 — a sequence composes when the artifact types match

Tool A hands to tool B when what A **writes** is what B **accepts**.

- `writing-prds` accepts "a design doc, an evaluated issue, or an equivalent written source" — so
  `brainstorming` → `writing-prds` composes, and *a raw idea* → `writing-prds` does not.
- `writing-plans` accepts a spec — so `to-spec` → `writing-plans` composes.
- `executing-plans` accepts a plan file — so `writing-plans` → `executing-plans` composes, and
  nothing else does.
- `plan-walkthrough` accepts any plan-shaped document — a spec, a PRD, a plan, an issue.
- `consolidate-specs` accepts a spec **and the code it describes**, which is why it cannot run in
  Phase 2: half its input does not exist yet.

The `Writes` column and the [artifact ledger](../WORKFLOW.md#the-artifact-ledger) are what make
this checkable rather than remembered. If a sequence has a gap in the middle, the gap is a missing
artifact, not a missing skill.

### Not a rule: where the tool comes from

**Two tools from different plugins compose exactly as well as two from the same one.** A skill is
an instruction file; it has no runtime relationship with its siblings beyond the dispatches in
Rule 2, and those are by name, not by vendor.

The `Source` column exists so you can find a tool upstream, re-vendor it, or decide whether to
install its plugin. It is a supply-chain fact, not a compatibility fact. Reading it as one leads
you to avoid good combinations and to trust bad ones.

---

## The orderings still worth naming

Ten orderings are not derivable from the four rules, because they encode judgement rather than
mechanics. This is the whole list.

| Ordering | Why this way round |
|---|---|
| `idea-refine` → `interview-me` | Refining widens the option set; the interview converges on the one you chose. Reversing it interviews you about an idea you have not formed. |
| `interview-me` → `grilling` | The interview *extracts* what you mean; the grilling *attacks* what you meant. Running the attack second means it has something solid to attack. |
| anything → `architect`, never `architect` first | It designs well, but it designs whatever you point it at. Pointing it at an unclear intent produces a good design for the wrong thing. |
| `architect` → `spec-driven-development` | The spec is then written *from* a design that already names its rejected alternatives. `spec-reviewer` explicitly looks for "simpler alternatives that meet the same requirements", so handing it the ones you already considered removes a whole review round. |
| `planning-and-task-breakdown` → `dispatching-parallel-agents` | Parallelism is decided *after* the dependencies are known. Deciding what is parallel before you know the tasks is how you get two branches that both edit the same file. |
| `writing-plans` → `architect` — **backwards** | A plan that will not sequence cleanly usually means the design underneath it is wrong. This is a signal to return to Phase 2, not to try harder at Phase 3. |
| `code-reviewer` → `code-simplification` | Simplifying code that is still wrong produces elegant wrong code, and makes the next reviewer read a diff that no longer matches the plan. **Correctness first, clarity second, security wherever it applies.** |
| `code-reviewer` → `ponytail-review` → `code-simplification` | The same ordering, extended by one step: correctness, then what to cut, then the cut itself. `ponytail-review` names findings and applies nothing, so it turns an open-ended refactor into a checklist with a line count attached. Skip the middle step and `code-simplification` has to decide both what to change and whether to. |
| `code-review-and-quality` → `code-reviewer` | The broad multi-axis pass finds themes; the gate agent then confirms the specific defects with line references. Running the broad pass second wastes it, because the gate has already narrowed the field. |
| `pr-walkthrough` → the code-level pass | The logical pass parks code-level findings in its dossier instead of debating them; the code-level reviewers — and the gate — consume the parked list afterwards, before merge. |

Two anti-patterns are also judgement, not mechanics:

- **`executing-plans` and `subagent-driven-development` are two answers to the same question** —
  separate session, or subagents in this one. Running both means the plan is being executed in two
  places with no single view of progress. Choose one per plan.
- **No extra review pass substitutes for your approval.** None of these tools is a gate. They only
  feed one.

---

## Getting the tools

Only a few of the tools above ship in this repository: the four subagents in
[`agents/`](../agents/README.md), one rule in [`rules/`](../rules/), and two maintenance skills in
[`skills/`](../skills/README.md). Everything else comes from a plugin or a tracked repo.

[`skills/README.md`](../skills/README.md) is the supply-chain document: it groups the fleet by
source, explains the three ways to obtain a skill — install the plugin, vendor the skill, or install
the plugin and keep it idle — and records what was deliberately left out and why.
