# GitHub Copilot Instructions

## Project Context

Sword and Planet is a 3D role-playing game built with Godot 4.

Read and follow `AGENTS.md` before making repository changes.
Human-authored GitHub Issues and project documentation are the source of
truth for intended behavior.

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

When changing Godot scripts, scenes, or resources:

- Run the repository's available Godot headless validation.
- Ensure scripts parse successfully.
- Ensure referenced scenes and resources load.
- Report any validation that could not be performed.

Do not weaken validation to make a change pass.