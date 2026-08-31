# GitHub Copilot Instructions

## Project Context

This repo (`mikeys_gamebones-rules-moba`) is a Godot 4 project whose exclusive purpose is developing a portable MOBA rules engine — the GDScript ruleset in `rules/` and the Python balance harness in `sim/`. The RPG game this project previously also contained has moved to a separate repository; do not add game-specific content here. Read and follow `AGENTS.md` before making repository changes.

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

## Executing an Implementation Task

This section applies whenever you are working an Issue titled `[impl]`, or
any Issue carrying the `implementation` label. It is the same contract as
`.github/agents/02-executor.agent.md`, restated here because almost no cloud
session loads that file: assigning Copilot from an Issue offers no agent
picker, and on GitHub Mobile choosing a custom agent gives up the model
picker. This file is read on every session regardless, which makes it — not
the profile — the contract of record. A short form also appears in the
**Implementation Agent Contract** section of the Issue itself.

### The contract

Treat the Issue's **Objective**, **Scope**, **Architecture Constraints**,
**Acceptance Criteria**, and **Out of Scope** sections as the authoritative
implementation contract.

The parent Feature provides context only. It does not expand your scope.
Neither do sibling tasks, and neither does anything you notice in passing.

### Procedure

1. Read the complete contract before changing anything.
2. Inspect the existing code and tests relevant to the task.
3. Implement the smallest change that satisfies the acceptance criteria.
4. Follow existing repository architecture and conventions.
5. Add or update tests when the acceptance criteria require it, or when they
   are needed to demonstrate the requested behavior.
6. Run `.github/scripts/validate-godot.sh`.
7. Fix defects that validation surfaces **within** the task's scope.
8. Stop and report anything you cannot resolve inside the contract.

### Guardrails

Do not:

- broaden the requested scope;
- redesign architecture;
- implement adjacent or sibling tasks;
- make speculative improvements;
- create GitHub Issues;
- modify unrelated systems because you spotted an opportunity;
- silently resolve architectural or product ambiguity;
- inherit additional work from the parent Feature;
- close the parent Feature.

If you find work outside the contract, do not implement it and do not file an
Issue for it. Report it under **Discovered out-of-scope work** and let the
planner decide.

If the task genuinely cannot be implemented without making an architectural
or product decision the contract does not already settle, stop and report the
ambiguity rather than deciding it. Minor choices that follow established
repository patterns do not need escalation.

### Completion report

The pull request title must start with `[<n>]`, where `<n>` is the
Implementation Task Issue number (for example `[94] Add moba cooldown
ledger`), and its description must close that Issue — `Closes #<n>` — and
must not close the parent Feature. Report:

1. **Files changed** — each file and why.
2. **Acceptance criteria** — each one, and whether it is satisfied.
3. **Validation** — the exact command run and its result.
4. **Discovered out-of-scope work** — or `None`.
5. **Unresolved issues** — anything that blocked complete implementation,
   or `None`.

Do not report the task complete if required validation failed. If validation
fails for a pre-existing or clearly out-of-scope reason, say so explicitly
rather than expanding the task to fix it.

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

The project is a MOBA in three layers: the self-contained combat ruleset in
`rules/`, the game that drives it in `scripts/` and `scenes/`, and the Python
balance harness in `sim/`. `rules/` has a one-way dependency arrow — the game
depends on the rules, never the reverse.

> **Revised 2026-08-30.** This previously read "the project uses reusable
> framework functionality provided under `addons/` and game-specific
> implementation outside reusable framework code." #276 deletes `addons/`
> entirely; there is no framework layer to sit outside of.

Before implementing a feature:

1. Inspect the existing shared types and extension points in `scripts/`.
2. Prefer using or extending those over duplicating their behavior.
3. Keep rules-engine behavior inside `rules/`, with its one-way dependency
   arrow intact, unless the Issue explicitly changes that boundary.

Do not modify third-party addon code unless explicitly requested.

## Actor Architecture

The 3D player implementation separates identity, presentation, and intent:

- `Actor` represents gameplay identity and the node anchor everything else
  hangs off — `MobaCombatant`, `Controller`, `Body`.
- `ActorBody3D` represents the Actor in the 3D world and owns the
  `is_multiplayer_authority()` movement gate.
- `Controller` supplies control intent.
- Game-specific controllers and bodies extend these rather than replacing them.

Preserve this separation unless an Issue explicitly changes the architecture.

> **Revised 2026-08-30.** These types previously lived in
> `addons/mikeys_game_bones/` and were described as "the framework's Actor
> model." #276 deletes `addons/` and absorbs the live parts into `scripts/`.
> The separation above is what survived a genre change and is worth keeping;
> the framework framing around it is not. `Actor`'s combat members
> (`take_damage`, `die`, `try_attack`, `attack_cooldown`) are superseded by
> `MobaCombatant` and are deleted by the same Issue — do not build on them.

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

Prefer signals or existing extension points when communication does
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
