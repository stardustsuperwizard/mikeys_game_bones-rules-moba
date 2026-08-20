# Planned Features

A high-level backlog of what the game still needs, derived from a review of the
repository as of 2026-08-19.

This is a **feature inventory, not a design document**. Items are described at
the level of "what is missing and roughly where it would go." Detailed design
belongs in the relevant design doc or in the GitHub Issue that implements it.

Implementation notes are suggestions only. Per `DESIGN.md`, design authority is
human-directed; nothing here is approved architecture.

---

## Current State

Stated plainly, because there is a gap between what the code supports and what
the running game does:

`scenes/main.tscn` contains a 20x20 walled box, one directional light, one
player capsule, and a camera. `WorldManager.spawn_points` has exactly one entry:
the player. There is **no enemy and no door in the scene**.

As a result `AttackAction`, `OpenAction`, `Rules.attack`, `Rules.open`, `Door`,
and `SimpleAIController` are all unreachable at runtime. The framework is
further along than the game is.

What works today:

- Movement — keyboard (W/S/Q/E/A/D/Space) and left-click contextual action.
- Third-person camera — free-look, zoom, wall collision, recenter.
- The Action -> Authority -> Rules pipeline, in principle.
- Headless CI validation (import pass + boot pass).
- One integration test covering the mouse contextual action.

---

## Tier 0 — Make the current build a playable loop

These are small and unlock a disproportionate amount of existing code.

### 0.1 Put content in the test room

Add a hostile actor scene and a `Door` instance to the main scene.

The actor scene can mirror `scenes/player/player.tscn` with `PlayerController3D`
swapped for `SimpleAIController` and `hostile = true`. Both get added to
`WorldManager.spawn_points` as new `SpawnPoint` resources.

**Why first:** this turns a large share of the existing codebase from dead code
into playable, testable behavior. Highest value per unit of effort in the repo.

### 0.2 Minimum viable UI

There is currently no UI of any kind. Health exists only as `print()` output in
`../addons/mikeys_game_bones/actors/actor.gd`.

Minimum useful set:

- Player health bar.
- Target health bar (or floating bars over actors).
- Interaction prompt — note that `PlayerController.get_nearby_interactable()`
  was written specifically as a non-consuming hook for this and currently has
  no consumer.
- Damage feedback (floating numbers or a combat log).

### 0.3 Death and respawn

`Actor.die()` calls `queue_free()`. When the player dies the player node is
deleted, the camera's `target_path` dangles, and the session is unrecoverable.

Needs a dead state (disable the controller, keep the node) followed by respawn
at a `SpawnPoint`. This is closer to a latent bug than a missing feature.

### 0.4 Game state and entry points

No main menu, no pause, no quit, no host/join UI. Multiplayer is currently
reachable only through the `--server` and `--connect=<address>` command-line
flags handled by the networking addon.

---

## Tier 1 — Core RPG systems

`pulp_moba_rpg_ruleset.md` specifies a substantial system. Almost none of it is
implemented.

### 1.1 Real combat resolution

`Rules.attack` is a flat `BASE_ATTACK_DAMAGE := 1`. `CharacterSheet` has
`character_name` and `max_hp` and nothing else.

Needs:

- The ruleset's stat block on `CharacterSheet`.
- Damage types (physical / magical-energy / true).
- The armor and resistance mitigation formula.
- Critical hits.

Expanding `CharacterSheet` is the natural first step; most of Tier 1 depends
on it.

### 1.2 Abilities, cooldowns, and resources

Ruleset sections 10-13. Nothing exists. This is the single largest system in
the backlog.

Needs an `Ability` resource, the four-slot combat loadout, per-ability cooldown
timers, and a resource pool.

**Implementation note:** modeling abilities as `Action` subclasses lets them
reuse `ActionRunner` and `Authority`, and inherit the server-authoritative
request/resolve split that `Actor._resolve_attack()` already establishes.

### 1.3 Targeting modes

Self, targeted, skillshot, ground-targeted, area, and toggle.

Today targeting is either "nearest hostile within range" or "whatever was
clicked." Skillshots additionally require projectiles, which do not exist.

### 1.4 Status effects, buffs, debuffs, and crowd control

Nothing exists. Needs a timed-effect container on `Actor`.

**Implementation note:** crowd control has to gate `Controller` intent, not just
apply modifiers — a stunned actor's `get_move_direction()` must return zero
regardless of what the player is pressing.

### 1.5 Equipment and inventory

The ruleset's "small equipped combat kit" rather than an MMO-style action bar.
Also the prerequisite for loot and any sense of reward.

### 1.6 Character creation

The classless discipline system. The initial ruleset has no leveling, but
players still need a way to choose and configure a build.

---

## Tier 2 — World and content

### 2.1 Navigation and pathfinding

Already noted as missing in the README. Click-to-move works only along a clear
straight line, and AI chase is straight-line as well.

**Implementation note:** `NavigationRegion3D` plus `NavigationAgent3D` slots in
behind `get_move_direction()` without changing the `Controller` contract, and
would allow deleting the stall-timeout guard currently in
`../scripts/player_controller_3d.gd`.

### 2.2 More than one area

No zone manager, level loading, or transitions. Doors currently open onto
nothing.

### 2.3 Art assets and animation

Everything in the game is a primitive mesh. The README already scopes Quaternius
as a candidate asset source.

Note that `ActorAnimator` is fully written and completely unused. Wiring a
single character model into it would validate that entire path cheaply.

### 2.4 Save, load, and persistence

Nothing exists. Single-player needs saves; the "persistent world" goal in the
README implies server-side persistence, which is a materially larger
commitment. Worth deciding which is actually being targeted before building.

### 2.5 Audio

No sound of any kind — no music, effects, ambience, or mixer setup.

---

## Tier 3 — The differentiating features

### 3.1 Game Master mode

This is the headline feature in the README and **none of it exists**.

Needs, at minimum:

- A GM free-camera / detached view mode.
- Runtime spawn and despawn of actors and props.
- Possessing a creature.
- Live editing of stats and health.
- Speaking as an NPC.

**Implementation note:** the architecture already has usable seams for this.
`Authority.can_perform()` is the correct place for "a GM bypasses ownership,"
and `WorldManager.spawn()` already routes through `MultiplayerSpawner` with a
plain data dictionary, which is most of what runtime GM spawning needs.

### 3.2 Multiplayer session layer

The networking addon provides transport only. Its own comments state that the
consuming game must own per-peer spawning and despawning; that file does not
exist in this repository.

Missing:

- Per-peer player spawn and despawn on connect and disconnect.
- State replication for actors — health in particular is not replicated.
- Disconnect and reconnect handling.
- A lobby or session browser.

Combat is already server-authoritative in shape, which is a good foundation.

### 3.3 Dialogue and narrative tools

A stated project goal is fostering creative storytelling, but there is no
dialogue system, NPC conversation, or quest structure.

Given the Game Master ambition, GM-driven improvised dialogue may be a better
fit for this project than an authored quest system.

---

## Cross-Cutting Concerns

### 4.1 Balance simulation harness

Ruleset sections 20-53 — roughly half the document — specify a Python test suite
with its own project layout, inside what is otherwise a Godot repository.

Needs a decision:

- A `sim/` subdirectory with its own CI job.
- A separate repository.
- Reimplementation as headless GDScript.

The risk in keeping it Python is duplicating the damage formula in two languages
that can silently drift apart.

### 4.2 Test coverage

Currently one integration test (`../tests/mouse_action_test.gd`), which is good
but narrow. `Rules`, `Authority`, and damage resolution have no coverage.

Since agents write most of the code in this project, cheap unit tests on the
rules layer are likely to pay for themselves quickly.

---

## Suggested Sequencing

An order that keeps the game playable and evaluable at every step, consistent
with the "smallest playable systems" principle in `DESIGN.md`:

1. Enemy and door in the test room (0.1)
2. Death and respawn (0.3)
3. Minimum viable UI (0.2)
4. Expanded `CharacterSheet` and real damage resolution (1.1)
5. Abilities, cooldowns, and resources (1.2)

Everything after that depends on how the combat prototype actually feels in
play.
