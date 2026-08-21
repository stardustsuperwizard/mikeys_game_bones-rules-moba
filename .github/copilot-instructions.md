# GitHub Copilot Instructions

## Project Context

Sword and Planet is a 3D role-playing game built with Godot 4. Read and follow `AGENTS.md` before making repository changes.

## Path-Scoped Instructions

Some directories carry additional instructions that apply automatically when you touch
files inside them. On github.com these are honored by the Copilot cloud agent and by
Copilot code review.

| File | Applies to |
| --- | --- |
| `.github/instructions/rules.instructions.md` | `rules/**` — the MOBA combat ruleset |
| `.github/instructions/sim.instructions.md` | `sim/**` — the Python balance harness |

They are additive, not replacements. This file and `AGENTS.md` still apply.

## Work Delegation

Human-authored GitHub Issues and project documentation remain the
source of truth for intended behavior.

Roles, model routing, and the session flow are defined in
`docs/AGENT_WORKFLOW.md`. Execution sessions start cold: the task Issue
is the only context carried across the handoff. If a constraint is not
written in the Issue, it does not exist.

When work is delegated by a planning agent:

- Treat the delegated task as a bounded subset of the parent Issue.
- Do not expand the delegated task beyond its stated acceptance criteria.
- If the delegated task conflicts with the parent Issue, AGENTS.md,
  or these instructions, stop and report the conflict rather than
  resolving it by changing scope.

## Godot

- This project targets Godot 4.
- Use Godot 4 APIs and conventions.
- Do not introduce Godot 3 APIs or deprecated Godot 3 patterns.
- Use GDScript unless an Issue explicitly requires another language.
- Prefer typed GDScript where practical.
- Preserve Godot scene and resource serialization conventions.
- Do not manually rewrite `.tscn`, `.tres`, or `project.godot` more broadly
  than required by the Issue.

## Project Architecture

The project uses reusable framework functionality provided under `addons/`
and game-specific implementation outside reusable framework code.

Before implementing a feature:

1. Inspect the existing framework APIs and extension points.
2. Prefer using or extending those APIs over duplicating framework behavior.
3. Keep Sword and Planet-specific behavior outside reusable addons unless
   the Issue explicitly changes the framework.

Do not modify third-party addon code unless explicitly requested.

## Actor Architecture

The existing 3D player implementation follows the framework's Actor model:

- `Actor` represents gameplay identity/state.
- `ActorBody3D` represents the Actor in the 3D world.
- `Controller` supplies control intent.
- Game-specific controllers and bodies extend the appropriate framework
  classes rather than replacing them.

Preserve this separation unless an Issue explicitly changes the architecture.

## Scenes and Nodes

Use Godot node types according to their intended responsibility.

For example:

- `CharacterBody3D` for character movement and collision.
- `StaticBody3D` for immovable physical geometry.
- `Area3D` for triggers and detection volumes.
- `Camera3D` for 3D cameras.

Prefer composition of nodes and components over deep inheritance hierarchies.

## Input

Use named Input Map actions rather than hard-coding keyboard keys in gameplay
logic.

Preserve existing input actions unless an Issue explicitly changes them.

Current player controls and their semantics should be inspected in
`project.godot` and the existing player controller before modification.

## Physics

Perform character physics and movement through Godot's physics lifecycle.

- Use `_physics_process()` for physics-driven movement.
- Respect `CharacterBody3D.velocity`.
- Use `move_and_slide()` appropriately.
- Do not implement custom collision or gravity systems when Godot's built-in
  physics behavior satisfies the requirement.

## Signals and Coupling

Prefer signals or existing framework extension points when communication does
not require direct ownership.

Avoid creating global dependencies or new autoload singletons merely to
connect unrelated systems.

## Scope

Follow `AGENTS.md`.

In particular:

- Implement only what the Issue requires.
- Treat acceptance criteria as requirements.
- Treat explicitly out-of-scope behavior as prohibited for that change.
- Do not opportunistically redesign neighboring systems.
- Do not introduce abstractions solely for hypothetical future features.

## Validation

When changing Godot scripts, scenes, or resources, run:

```
.github/scripts/validate-godot.sh
```

This is the same validation CI runs. It performs an import pass (scenes and
resources resolve) and a headless boot (scripts parse, autoloads initialize).

- Report the exact command and its result.
- Report any validation that could not be performed, rather than omitting it.
- Exit code 127 means Godot was not on PATH — that is "could not validate",
  not "validated successfully".

Do not weaken validation to make a change pass.
