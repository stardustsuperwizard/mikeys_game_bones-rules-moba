# Agent Instructions

## Project

`mikeys_gamebones-rules-moba` is a Godot 4 project whose exclusive purpose is
developing a portable MOBA rules engine: the GDScript ruleset in `rules/` and
the Python balance harness in `sim/`. It is not a game — `rules/` is built to
be lifted wholesale into a game project as a self-contained addon (see
`.github/instructions/rules.instructions.md`). The broader RPG game this
project previously also contained has moved to a separate repository; do not
add game-specific content here.

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

- Rules-engine behavior stays generic and portable — do not couple `rules/`
  or `sim/` to any specific game's assets, scenes, or content.
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