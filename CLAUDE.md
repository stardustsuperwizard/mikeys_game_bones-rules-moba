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
- `docs/AGENT_WORKFLOW.md` — how this repo's planner/executor/reviewer
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

## Before declaring anything complete

Run `.github/scripts/validate-godot.sh`. It's the same validation the
Copilot pipeline runs — the single source of truth for pass/fail, not a
duplicate check.

## Working an Implementation Task Issue

If you're picking up a `[impl]` Issue instead of the Copilot cloud agent or
the scripted `agent-02-execute.yml` executor: read the Issue body in full
(acceptance criteria, scope, expected files), open a PR with
`Closes #<issue>`, and add the `agent:review` label yourself once it's
ready. The automated reviewer (`agent-04-review.yml`) only auto-triggers on
`copilot/*` branches, so a Claude Code PR needs the manual label to enter
the same review gate everything else uses.
