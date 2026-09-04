# CLAUDE.md

This file exists so Claude Code reads the same contract GitHub Copilot does.
There is one source of truth; this is a pointer to it, not a copy.

## Read first

- `AGENTS.md` — project context, working rules, architecture constraints,
  testing and completion requirements. Tool-agnostic; read it in full before
  any change.
- `.github/copilot-instructions.md` — despite the name, this is the fuller
  execution contract: how to work an Implementation Task Issue, guardrails,
  scope boundaries, the Godot/actor/scene/signal architecture, and
  validation steps. `AGENTS.md` defers to it for the details.
- `docs/AGENT_WORKFLOW.md` — how this repo's planner/implementor/reviewer
  pipeline works, and how model routing and PR contracts fit together. Read
  before touching `.github/workflows/`, `.github/agents/`, or
  `.github/actions/`.

## Path-scoped instructions

Copilot picks these up automatically via `applyTo:` frontmatter; Claude Code
does not, so check manually before editing:

| Directory | Also read |
| --- | --- |
| `rules/**` | `.github/instructions/rules.instructions.md` |
| `sim/**` | `.github/instructions/sim.instructions.md` |

## Declaring that one Issue blocks another

Write the edge in the Issue's `## Dependencies` table and add the `blocker`
label to the Issue doing the blocking. That label is what
`.github/workflows/issue-dependencies.yml` fires on to create GitHub's native
dependency relationship — the table is the declaration, the relationship is
derived from it, and nothing else in this repository creates it.

The contract is *Declaring Issue dependencies* in
`.github/copilot-instructions.md`; the grammar is
`.github/scripts/issue_dependencies.py`. Do not use `gh issue edit
--add-blocked-by`: it needs a `gh` newer than the runner may have, and
failing silently there is the bug this replaced.

## Before declaring anything complete

Run `.github/scripts/validate-godot.sh`. It's the same validation the
Copilot pipeline runs — the single source of truth for pass/fail, not a
duplicate check.

It covers the Godot project, and nothing else. If you touched the dependency
tooling — `issue_dependencies.py`, `sync-issue-dependencies.py`,
`issue-dependencies.yml`, or the `## Dependencies` block in a template — also
run `.github/scripts/test-issue-dependencies.sh`. It needs no Godot, no
credentials and no network, and it pins the one contract that fails silently:
a parser that stops recognizing the table produces a clean, green, empty sync.

## Working an Implementation Task Issue

If you're picking up a `[impl]` Issue instead of the Copilot cloud agent or
the scripted `agent-02-implement.yml` implementor: read the Issue body in full
(acceptance criteria, scope, expected files), open a PR with
`Closes #<issue>`, and add the `agent:review` label yourself once it's
ready. The automated reviewer (`agent-04-review.yml`) only auto-triggers on
`copilot/*` branches, so a Claude Code PR needs the manual label to enter
the same review gate everything else uses.

## Working without an Issue

A review, audit, or exploratory session is not an implementor session, and the
scope rules written for implementors do not all transfer. The clearest case is
the PR template telling the implementation session not to file the
out-of-scope work it discovers: that exists to stop an implementor widening its
own Issue, and it inverts when deciding what should become work is the point
of the session. File discovered work when asked, and link it from the PR.

Such a PR has no originating Issue and so no `Closes #<issue>` line. Say that
explicitly at the top instead of leaving the template's placeholder in, and
still add `agent:review` — the gate is the same one everything else uses.

Put this marker on the **first non-blank line** of the body:

```text
<!-- no-originating-issue -->
```

`issue-linking.yml` gates on the branch prefix, and these sessions get
`claude/*` branch names, so without the marker the PR lands in a job whose
only success path is a closing reference it is not supposed to have — and
whose repair step would otherwise scan the body and silently link the PR to
any open Implementation Task it merely mentions. Prose saying there is no
Issue is for the reader; the marker is what the workflow reads. It is inert
on a PR that does close a task.

The first line specifically, matched exactly rather than searched for. A
search anywhere in the body would find the marker in boilerplate that merely
contains it — including the PR template's own header comment, which becomes
the body of every new PR — and would then wave through the unlinked PRs the
check exists to catch. If you keep the template's comment, the marker goes
above it.
