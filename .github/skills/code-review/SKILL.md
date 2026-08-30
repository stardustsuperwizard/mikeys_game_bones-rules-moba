---
name: code-review
description: >-
  Repository conventions and architecture constraints for Mikey's Game Bones
  MOBA Rules, a portable Godot 4 rules engine. Use whenever reviewing a pull
  request's diff in this repository — GDScript, scenes (.tscn), resources (.tres), or
  project.godot — for architecture fit, scope discipline, and Godot
  convention adherence.
---

# Mikey's Game Bones MOBA Rules code review

Mikey's Game Bones MOBA Rules is a portable Godot 4 MOBA combat rules engine.
This skill carries the review-relevant subset of `AGENTS.md` and
`.github/copilot-instructions.md` so pull request review can check a diff
against them without those files being open in context.

Path-scoped rules for `rules/**` (the MOBA combat ruleset) and `sim/**` (the
Python balance harness) live in
`.github/instructions/rules.instructions.md` and
`.github/instructions/sim.instructions.md` and apply automatically when a
diff touches those directories — do not restate them here.

## Scope discipline

Flag, don't just note in passing:

- Changes outside what the linked Issue's Scope / Acceptance Criteria /
  Out of Scope sections describe, if the PR body links one.
- Opportunistic refactors of code the diff didn't need to touch.
- New third-party dependencies, or edits to third-party/addon code, without
  the Issue explicitly requesting it.
- New abstractions justified only by hypothetical future use, rather than
  the change at hand.
- `.tscn`, `.tres`, or `project.godot` edits broader than the change
  requires (e.g. reformatted or reordered nodes/properties unrelated to the
  diff).

## Architecture

- Rules-engine behavior belongs under `rules/`; reusable framework behavior
  belongs under `addons/`. A diff that adds game-specific logic to either
  location, or duplicates framework behavior instead of using an extension
  point, is a fit issue worth flagging.
- Public framework APIs under `addons/` should not change unless the linked
  Issue explicitly calls for it.
- The player/Actor stack follows: `Actor` (gameplay identity/state),
  `ActorBody3D` (the Actor in the 3D world), `Controller` (control intent).
  Game-specific controllers/bodies should extend these, not replace or
  bypass the separation.
- Prefer composition and existing extension points over new inheritance
  hierarchies or new framework abstractions.

## Godot conventions

- Godot 4 APIs and idioms only — flag Godot 3 patterns or deprecated APIs.
- GDScript, typed where practical, unless the Issue explicitly calls for
  another language.
- Node types should match responsibility: `CharacterBody3D` for character
  movement/collision, `StaticBody3D` for immovable geometry, `Area3D` for
  triggers/detection, `Camera3D` for cameras, etc. — flag a mismatch (e.g.
  movement logic hung off the wrong body type).
- Physics-driven movement belongs in `_physics_process()`, using
  `CharacterBody3D.velocity` and `move_and_slide()` — flag hand-rolled
  collision or gravity where Godot's physics already covers the case.
- Gameplay input should go through named Input Map actions
  (`project.godot`), not hard-coded keys. Existing input actions and their
  semantics should be preserved unless the Issue changes them.
- Prefer signals or existing framework extension points for loose coupling.
  Flag a new autoload/global singleton introduced just to wire two unrelated
  systems together.

## Validation

Changes touching GDScript, scenes, or resources should have been checked
with `.github/scripts/validate-godot.sh` (import pass + headless boot). If
the PR description doesn't report running it, or reports a failure that
wasn't addressed, call that out.

## What this skill is not

This repository also runs a separate, Issue-aware review pipeline
(`.github/agents/03-reviewer.agent.md`, dispatched by
`.github/workflows/agent-04-review.yml` via the `agent:review` label). It
checks a PR's diff against its linked Implementation Task Issue's
acceptance criteria and publishes a `PASS` / `FIX` / `PLANNING FAILURE` /
`DESIGN AMBIGUITY` verdict with a `review:*` label. This skill is
complementary to that pipeline, not a replacement for it — use it for code
quality, architecture fit, and convention adherence, not as a source of
acceptance-criteria verdicts.
