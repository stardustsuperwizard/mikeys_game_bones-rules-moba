# Historical Game Backlog

This document is retained as a record of the former Mikey's Game Bones MOBA Rules RPG
backlog, reviewed on 2026-08-19. It is not the roadmap for
`mikeys_gamebones-rules-moba` and does not authorize work in this repository.

The active MOBA rules-engine roadmap is
[`rules/README.md`](rules/README.md). Design authority and the repository scope
are described in [`DESIGN.md`](DESIGN.md) and [`../AGENTS.md`](../AGENTS.md).

The historical notes below may help explain older files that remain during the
repository transition, but game-specific features, scenes, and presentation are
out of scope for this project.

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
- Gamepad movement, jump, and camera recenter — bound in `../project.godot`,
  driven through the same `Controller` contract as the keyboard. Touch has no
  bindings. This covers two of the three schemes the ruleset requires (§5).
- Third-person camera — free-look, zoom, wall collision, recenter.
- The Action -> Authority -> Rules pipeline, in principle.
- Headless CI validation (import pass + boot pass).
- One integration test covering the mouse contextual action.

---

## Tier 0 — Make the current build a playable loop

These are small and unlock a disproportionate amount of existing code.

### 0.1 Put content in the test room

**Hostile actor done (T4); `Door` instance still outstanding.** A hostile
actor scene (`scenes/enemy/enemy.tscn`) now exists with `SimpleAIController`,
`hostile = true`, and a `MobaCombatant` carrying the melee-bruiser loadout.
It is registered as the second entry in `WorldManager.spawn_points` in
`scenes/main.tscn` and spawns at runtime at position (-2, 0, -3). The player
scene also carries a `MobaCombatant`, `MobaStateMachine`, and
`MobaAbilityCaster`; ability slots 1-4 are wired to the `ability_1`–`ability_4`
input actions. A `Door` instance in the main scene is still needed.

### 0.2 Minimum viable UI

~~There is currently no UI of any kind. Health exists only as `print()` output
in `../addons/mikeys_game_bones/actors/actor.gd`.~~

> **Resolved.** The combat HUD landed in #29 and #35 — health and resource bars,
> ability slots, cast bar, status tray, floating combat text, and target frame,
> all under `rules/ui/`. The `print()` in `Actor.take_damage()` is on a dead path
> deleted by #276.

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

~~No main menu, no pause, no quit, no host/join UI.~~

> **Resolved.** #314 shipped the entry points, on the transport from #312 and
> the replication substrate from #313. `scenes/ui/main_menu.tscn` is the boot
> scene (`run/main_scene`) and offers Play Offline, Host (port field) and Join
> (address and port fields); none of the three needs a command-line flag. Host
> starts a listen-server session in which the host plays, and a second instance
> joining through Join sees the same world. Play Offline keeps today's
> single-player-vs-bots boot with no network peer.
>
> `scenes/ui/pause_menu.tscn` rides inside `scenes/main.tscn`, so it is present
> whenever the world scene runs — including when that scene is launched directly
> from the editor. The `pause` action (Escape) opens it over the combat HUD with
> Resume and Quit. **Quit returns to the main menu** rather than exiting the
> application: it drops the session through `SessionManager.go_offline()` and
> loads the menu, so a player can start or join another session without
> relaunching.
>
> The note previously here recorded that the `--server` and `--connect=<address>`
> flags handled by the networking addon did nothing, and that nothing in the
> project could actually start a session. #276 deleted that addon.
> `--dedicated-server` (#312) is the one command-line path that remains, and it
> exists precisely because a dedicated server has no local operator to click a
> menu.

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
reuse `ActionRunner` and `Authority`. ~~and inherit the server-authoritative
request/resolve split that `Actor._resolve_attack()` already establishes.~~

> **Corrected 2026-08-30.** The first half happened — `MobaAbilityAction`
> extends `Action` and runs through `ActionRunner`. The second half did not.
> `Actor._resolve_attack()` is unreachable in the shipped game and is deleted by
> #276, which records the request/resolve pattern in `docs/` first. And the
> chokepoint is not universal: of the three player-originated commands, only
> ability activation passes the gate — basic attack and cast-cancel call
> `MobaCombatant` mutators directly, and `Authority.can_perform()` returns
> `true` unconditionally because `owner_id` is never assigned outside tests.
> #277 makes it real.

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

### 1.6 Control schemes and the input layer

Ruleset section 5. The `InputMap` in `../project.godot` now carries both
keyboard + mouse and gamepad bindings, including `basic_attack`,
`ability_1`–`ability_4`, `lock_on`, and `defend`.

**Status as of T4:** `ability_1`–`ability_4` now have consumers in
`../scripts/player_controller_3d.gd` (activate the corresponding slot on the
player's `MobaAbilityCaster`). The basic-attack path fires automatically when
the click-order system delivers the player into melee range of an attack target,
so `basic_attack` is driven by proximity rather than read directly from input
(this avoids the dual left-click conflict between `action_primary` and
`basic_attack`). `lock_on` and `defend` remain unbound.

Needs, in order:
- Gamepad camera look. `ThirdPersonCamera3D` orbits on mouse motion only, so
  the right stick is bound to `turn_left`/`turn_right` — it turns the body
  rather than the camera. §5.1 wants the right stick on the camera, which
  needs a stick-driven orbit and a matching aim direction first.
- A device-agnostic intent layer (§5.4) sitting between Godot `InputEvent` and
  the controllers, so `Controller.get_move_direction()` and ability activation
  never branch on device.
- Touch HUD — floating virtual stick, ability arc, drag-to-aim, and cast
  cancellation (§5.3).
- Remapping UI and scheme hot-swap for prompt glyphs.

**Implementation note:** the intent layer is the cheap part and the part that
gets expensive if deferred. Two schemes hardcoded into `PlayerController3D` is
already enough branching to make the third painful.

### 1.7 Jump as a defined mechanic

Ruleset section 5.5. `jump` is bound and handled in
`../scripts/player_controller_3d.gd:75`, but the ruleset now gives it actual
rules: an `Airborne` state (§56), no i-frames, 60% air control, no casting
while airborne unless the ability sets `usable_in_air`.

Depends on the state machine landing (part of 1.2/1.4).

### 1.8 Mobile platform support

Distinct from 1.6 — the touch HUD is input, this is everything else: Android
and iOS export presets, renderer and performance budget, HUD scaling for safe
areas and notches, and touch-appropriate defaults for aim assist (§55).

A paired gamepad on mobile is nearly free once 1.6 exists, since it reuses the
gamepad scheme unchanged.

**Not a Tier 1 blocker.** It is listed here because the ruleset now treats touch
as a first-class scheme, so the cost of ignoring it grows with every UI screen
built mouse-first.

### 1.9 Character creation

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

**Tracked by #278.** The `SessionManager` autoload (#312) provides ENet
transport in three session modes -- offline, listen-server and
dedicated-server -- and `WorldManager` spawns and despawns a player actor per
peer on connect and disconnect.

Actor state replicates (#313), and authority is split per subtree rather
than per actor. The Actor and its `Body` stay owned by the connecting peer,
so movement keeps today's client-authoritative model; `MobaCombatant` and
its sibling `MobaStateMachine` are re-set to the server (peer `1`) on every
spawn, so a client can never broadcast its own claimed combat state. Two
`MultiplayerSynchronizer` nodes carry it: the Body's transform continuously
from the owning peer, and current health/resource, active shields, active
effects, cooldown state and the current state on-change from the server.

Each replicated property is genuinely settable and emits the same signal a
local mutation would, so the HUD binders -- which observe signals, never
polled properties -- needed no changes to see remote state.

Missing:

- A lobby or session browser.

Combat is server-authoritative in *shape* — one gated command out of three
(see §1.2's correction) — which is a partial foundation. #277 completes it.
Replication is the substrate only: it carries steady state, not one-shot
events like damage numbers, and it does not validate what a client submits.

One gap is worth naming, because the replication authority and the tick gate
currently disagree. `PlayerController3D._physics_process()` gates on the
**Body's** authority, and the Body belongs to the connecting peer — so for a
client-owned actor it is the *client*, not the server, that calls
`MobaCombatant.tick()`, advancing regen, cooldowns and effect expiry on a
node the server is authoritative for. The server's values overwrite the
client's whenever the server changes them, so the two drift between server-side
changes rather than diverging permanently. Closing it means either ticking
combat on the authority or reconciling the two, which is #47's
(prediction/reconciliation) and #277's (command routing) territory, not the
substrate's.

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
6. Device-agnostic input layer and gamepad camera look (1.6) — before a second
   scheme's worth of input branching accumulates

Everything after that depends on how the combat prototype actually feels in
play.
