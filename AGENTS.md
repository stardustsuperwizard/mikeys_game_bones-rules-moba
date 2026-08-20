# Agent Instructions

## Project

Sword and Planet is a Godot game.

Human-authored design requirements and GitHub Issues are the source of truth
for intended behavior.

## Working Rules

- Read the complete Issue before making changes.
- Read relevant project documentation before implementation.
- Inspect existing code before introducing new abstractions.
- Make the smallest change necessary to satisfy the Issue.
- Do not implement functionality listed as out of scope.
- Do not refactor unrelated code.
- Do not add third-party dependencies unless explicitly requested.
- Do not modify third-party code unless explicitly requested.

## Architecture

- Game-specific behavior belongs in the game, not in reusable framework code.
- Prefer composition and existing extension points over new framework abstractions.
- Do not change public framework APIs unless the Issue explicitly requires it.
- If the requested feature conflicts with the documented architecture, explain
  the conflict rather than silently working around it.

## Agent Roles

Planning, implementation, and review run as separate sessions on different
models. See `docs/AGENT_WORKFLOW.md` for role definitions, model routing,
and the handoff contract.

## Testing

- Existing tests represent established behavior.
- Do not weaken, remove, or skip tests merely to make an implementation pass.
- Add tests for new behavior when practical.
- Report validation that could not be performed.

## Completion

Before declaring a task complete:

1. Verify the acceptance criteria in the Issue.
2. Run `.github/scripts/validate-godot.sh`.
3. Summarize what changed.
4. Call out assumptions, limitations, or unresolved design questions in the PR.