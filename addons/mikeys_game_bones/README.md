# Mikey's Game Bones

A reusable, genre-agnostic gameplay framework for Godot 4 — the semantic layer between Godot's engine primitives (nodes, physics, rendering) and a specific game's rules and presentation.
 

## What's in it

```
actions/         Action, ActionResult, ActionRunner (the request -> legality -> resolve pipeline)
  verbs/          concrete actions: AttackAction, OpenAction
actors/          Actor (a presentation-neutral Node)
  bodies/          presentation shells: ActorBody3D, ActorBody2D
authority/       Authority (can this requester act as this actor?)
controllers/     Controller, PlayerController (decision-making, not execution --
                   AI decision-making is deliberately not here, see
                   addons/mikeys_basic_ai/)
things/          GameObject, ObjectDefinition (traits/capabilities/state -- the "noun" layer)
  props/           concrete non-actor things: Door
world/           WorldManager, SpawnPoint
```

## What it deliberately does not include

Combat resolution, ability scores, dice, character sheets, dialogue, inventory, or any UI. Those are game-specific — see `mikerpg`'s `game1_demo/` or `game2_misadventures/` for examples of a game built on top of this addon, each bringing its own rules engine.

## Design philosophy

`GameObject`s represent what exists. `Action`s represent what is attempted. `Rules` (defined by the consuming game, not this addon) determine what happens. Godot represents the result. See `docs/20260815T130000 - Game Objects and Rules.md` in the main `mikerpg` repo for the full design rationale.

The goals are as follows:
1. Build a single player game to start
2. Add a multiplayer option with an admin (or Dm/GM) client, like Neverwinter Nights.
3. Use as much of the godot editor as possible as the toolset for making stories.
4. Use components that already exist in the wild, example Inventory systems, and only code new when there is not a sufficient 3rd party addon or it no longer meets my needs.
5. Make the game as modular as possible and not have to hardcode as much as possible. Example, do I need to hardcode all NPCs or can I make a generic NPC class/object/whatever where the values are populated from a datastore?
6. Build the RPG layer, not another game engine. Godot should remain responsible for engine concerns such as scenes, nodes, physics, rendering, input, navigation, and networking. MikeRPG should focus on the RPG concepts Godot does not provide, such as actors, character sheets, rules, combat, creatures, quests, encounters, and GM functionality. Prefer Godot's native systems and existing addons where they solve the problem sufficiently; create abstractions primarily to express RPG concepts or to integrate reusable components, not to hide or replace Godot.


## Setup

Requires Godot 4.7+.

`addons/` is gitignored (third-party code, not part of the core game). No addons are currently required — the project opens and runs from a fresh clone with nothing to fetch.

## Verification

`tools/verify.sh` smoke-tests the project: rescans all scripts for parse errors, then boots the default scene headless and checks for runtime errors. It's not a behavior test — it doesn't assert in-game outcomes, just that everything loads and runs. Run it after moving/renaming files or before committing.
