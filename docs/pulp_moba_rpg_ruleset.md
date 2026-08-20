# Pulp MOBA-Inspired RPG Ruleset — Baseline Design

## Purpose

This document defines a starting combat ruleset for a computer role-playing game that supports both single-player and multiplayer play.

The design goals are:

- Fast-paced real-time combat.
- MOBA-style movement, positioning, targeting, skillshots, cooldowns, and crowd control.
- Gamepad-first controls, with full parity on keyboard + mouse and touch.
- Classless character development.
- A small equipped combat kit rather than large MMO-style action bars.
- A pulp-adventure tone, with Barsoom as the primary inspiration while remaining flexible enough to support other public-domain adventure, fantasy, science-fiction, occult, lost-world, and weird-fiction settings.
- No character leveling in the initial ruleset.
- Enough numerical structure to allow automated balance testing.

This is intentionally a baseline. The objective is not to solve every RPG design problem before implementation. The rules should first produce enjoyable combat and then be iterated through playtesting and simulation.

Sections 1–54 are the original baseline design. Sections 55+ are implementation-readiness enhancements layered on top — closing gaps a coding agent will hit immediately when turning the baseline into an engine (gamepad targeting, ability data schema, state machine, stacking rules, PvE AI, and networking authority).

Section 5 has since been expanded from a gamepad-only mapping into the full three-scheme
control model (gamepad, keyboard + mouse, touch) that the implementation targets.

---

# 1. Core Design Philosophy

The combat engine uses a conventional MOBA model as its starting point.

The game does **not** initially use tabletop-style attack rolls, initiative, turns, saving throws, or Armor Class.

Instead:

- Characters move continuously.
- Basic attacks and abilities operate in real time.
- Position and range matter.
- Skillshots can miss because the player aimed poorly or the target moved.
- Targeted attacks generally hit if the target remains valid.
- Armor and resistance reduce incoming damage.
- Cooldowns regulate ability frequency.
- Resources regulate ability usage.
- Crowd control changes what characters can do.
- Death occurs when Health reaches zero.

The basic resolution loop is:

```text
Choose action
    ↓
Check legality
    ↓
Resolve targeting / collision
    ↓
Determine raw damage or effect
    ↓
Apply mitigation
    ↓
Apply damage / crowd control / buff / debuff
    ↓
Start cooldown
```

A central design principle is:

> The player's execution determines whether many actions connect; character statistics determine how effective those actions are.

This allows player skill to matter without requiring every interaction to become a reflex-heavy action-game mechanic.

---

# 2. Classless Character Design

The game does not require traditional character classes.

Instead, abilities are organized into **Disciplines**.

Disciplines are broad families of related combat capabilities. They are similar to "swim lanes" through which characters can acquire abilities.

A character is never required to declare:

> I am a Warrior.

Instead, a character may learn primarily Warrior abilities while also taking abilities from Slayer, Guardian, Mystic, Marksman, or other Disciplines.

The character's effective combat role emerges from the combination of:

- Equipped weapon
- Equipment
- Base statistics
- Learned abilities
- Equipped abilities
- Passive effects
- Player tactics

This means a character could effectively behave like:

- A pure swordsman
- A defensive sword-and-board fighter
- A mobile warrior/assassin
- A rifleman with traps
- A psychic duelist
- A heavily armored mystic
- A support-oriented explorer

without requiring any of those combinations to exist as formal classes.

---

# 3. Initial Disciplines

The first six Disciplines are derived from common MOBA combat roles.

## Warrior

Focus: melee offense, sustained combat, weapon techniques.

Example abilities:

- Power Strike
- Cleave
- Parry
- Riposte
- Charge
- Whirlwind

Typical play:

```text
Close distance → attack → pressure → survive retaliation → continue attacking
```

---

## Guardian

Focus: durability, battlefield control, protecting allies, disruption.

Example abilities:

- Shield Bash
- Brace
- Taunt
- Knockdown
- Intercept
- Fortify

Typical play:

```text
Engage → absorb pressure → disrupt enemy → protect ally → hold position
```

---

## Slayer

Focus: mobility, burst damage, pursuit, escape, opportunistic attacks.

Example abilities:

- Lunge
- Vanish
- Hamstring
- Execute
- Backstab
- Shadow Step

Typical play:

```text
Approach → burst → eliminate vulnerable target → escape
```

---

## Marksman

Focus: ranged basic attacks, positioning, sustained ranged pressure.

Example abilities:

- Aimed Shot
- Rapid Fire
- Evasive Roll
- Piercing Shot
- Suppressing Fire
- Deadeye

Typical play:

```text
Maintain range → attack → reposition → punish approach → continue firing
```

---

## Mystic

Focus: supernatural powers, psychic abilities, occult effects, weird science, energy weapons, and battlefield manipulation.

The name of the ability in the fiction does not have to determine its mechanical type.

For example, the same underlying mechanic could represent:

- A psychic blast
- A Martian energy projector
- An occult curse
- An Atlantean artifact
- A strange scientific weapon

Example abilities:

- Energy Bolt
- Mesmerize
- Force Barrier
- Teleport
- Area Blast
- Cataclysm

Typical play:

```text
Control space → spend resource → deliver burst or control → reposition
```

---

## Adventurer

Focus: utility, support, traps, medicine, scouting, improvisation, and pulp-hero versatility.

Example abilities:

- Field Dressing
- Trap
- Rally
- Trick Shot
- Smoke Bomb
- Grappling Line

Typical play:

```text
Adapt → support allies → manipulate battlefield → exploit opportunity
```

---

# 4. Combat Loadout

A character can learn many abilities but may equip only a small number at one time.

The initial rule is:

> **Basic Attack + 4 Equipped Active Abilities**

There is no separate mandatory Ultimate slot.

An unusually powerful ability may occupy one of the four slots.

This preserves the MOBA concept of a compact combat kit while allowing the player to construct that kit from multiple Disciplines.

Example:

```text
Basic Attack — Longsword

Slot 1 (A / key 1) — Power Strike      [Warrior]
Slot 2 (B / key 2) — Parry             [Warrior]
Slot 3 (X / key 3) — Lunge             [Slayer]
Slot 4 (Y / key 4) — Shield Bash       [Guardian]
```

Slots are positional and identical across control schemes (§5).

This character is not assigned a class.

The equipped loadout causes the character to behave like a mobile melee bruiser.

Another loadout using the same learned abilities might completely alter that combat role.

---

# 5. Control Schemes

The ruleset is designed around a controller rather than adapting controller input
after the combat system has already been built. Keyboard + mouse and touch are not
afterthoughts, however: all three schemes are first-class, and any combat mechanic
that cannot be executed comfortably on all three is a rules problem, not an input
problem.

Supported schemes:

```text
Gamepad          — console, computer, and mobile with a paired controller
Keyboard + Mouse — computer
Touch            — mobile
```

The exact mappings can change during implementation. The rules constraint that must
not change is that the primary combat kit (basic attack + four abilities + jump)
remains directly accessible on every scheme without modifier-button gymnastics.

## 5.1 Gamepad Mapping

| Input | Action |
|---|---|
| Left Stick | Movement |
| Right Stick | Camera / aiming |
| Left Stick Click (L3) | Jump |
| Right Trigger | Basic attack |
| A | Ability 1 |
| B | Ability 2 |
| X | Ability 3 |
| Y | Ability 4 |
| Left Bumper | Contextual defense / utility |
| Right Bumper | Targeting / lock-on |
| D-Pad | Items, weapon swap, or non-core utility |
| Right Stick Click (R3) | Camera recenter |

Jump is on L3 rather than A because the four face buttons are reserved for the
ability slots. If playtesting shows L3 is uncomfortable during sustained movement,
the fallback is D-Pad Up, not stealing a face button.

## 5.2 Keyboard + Mouse Mapping

Deliberately classic: WASD to move, Q/E to strafe, abilities on the number row,
jump on the space bar. This matches the bindings already present in
`project.godot`.

| Input | Action |
|---|---|
| W / S | Move forward / back |
| A / D | Turn left / right |
| Q / E | Strafe left / right |
| Space | Jump |
| Mouse Move / Right Mouse drag | Camera / aiming |
| Left Mouse | Basic attack / contextual primary action |
| Middle Mouse or Tab | Targeting / lock-on |
| 1 / 2 / 3 / 4 | Abilities 1–4 |
| Shift | Contextual defense / utility |
| C | Camera recenter |
| Mouse Wheel | Camera zoom |
| R / F | Items, weapon swap, non-core utility |

Three details worth stating explicitly because they are easy to get wrong later:

- **Ability slots are positional.** Key `1` is always loadout slot 1. Slots are
  never re-ordered by cooldown state, weapon, or context.
- **A/D turn, Q/E strafe.** The mouse drives the camera independently, so turn and
  strafe stay separate bindings rather than collapsing A/D into strafe.
- **Right mouse stays camera, not lock-on.** The current build uses right-drag to
  look around (see `README.md`), so lock-on takes Middle Mouse / Tab instead of
  overloading a button players already use for the camera.

## 5.3 Touch Mapping (Mobile)

The touch scheme follows established mobile-MOBA conventions rather than inventing
a new grammar.

| Input | Action |
|---|---|
| Left thumb — floating virtual stick | Movement (stick spawns where the thumb lands) |
| Right thumb — large primary button | Basic attack |
| Four buttons in an arc around primary | Abilities 1–4 |
| Small button above primary | Jump |
| Drag from an ability button | Aim that ability; release to cast |
| Drag back onto the button | Cancel the queued cast (no cost, no cooldown) |
| Drag on empty screen area | Camera |
| Pinch | Camera zoom |
| Double-tap empty area | Camera recenter |
| Tap an enemy | Lock-on / target select |

Rules-relevant constraints:

- **Drag-to-aim replaces the right stick.** A skillshot is pressed, aimed, and
  released as one gesture. Any ability that would require simultaneous independent
  movement *and* precision aiming for the full cast duration is not touch-viable and
  should be reworked or given a stronger assist tier (§55).
- **Touch defaults to the strongest assist tier.** See §55 for the per-device
  magnetism defaults.
- **Cast cancellation is a first-class gesture**, so §59 cancellation and refund
  rules must exist on every platform, not just as a mobile affordance.
- **Layout must be mirrorable** for left-handed play, respect device safe areas
  and notches, and keep every combat control at least 9 mm across.
- **A paired gamepad on mobile uses §5.1 unchanged** and hides the touch HUD.

## 5.4 Device-Agnostic Input Layer

The combat rules must never see a device. The input layer resolves a scheme into
intents, and only intents reach the state machine (§56) and the rules:

```text
MoveIntent(direction)          # stick vector | WASD/QE composite | virtual stick
AimIntent(direction | point)   # right stick | mouse ray | touch drag vector
JumpIntent()
BasicAttackIntent(held)
AbilityIntent(slot: 1–4, phase: press | aim | release | cancel)
LockOnIntent(press | release | cycle)
UtilityIntent(id)
```

This is what makes the Python balance harness (§21) meaningful: simulations consume
intents, so a duel simulation is device-independent, and device differences enter
the math only through assist tiers (§55) and player profiles (§40).

Requirements that follow from the intent layer:

- Every binding is remappable on every scheme.
- Schemes hot-swap. Receiving gamepad input while keyboard is active switches the
  prompts immediately, with no restart and no menu.
- No scheme may be given an action the others lack.

## 5.5 Jump

Jump exists on all three schemes and is a **traversal action, not a combat ability**.

```text
Jump Height:        1.2 m
Jump Duration:      ~0.7 sec
Air Control:        60% of Movement Speed
Resource Cost:      0
Cooldown:           0 (landing recovery only)
```

Baseline rules:

- Jump occupies no ability slot and has no entry in the cooldown system (§12).
- Jump grants **no** invulnerability frames, damage reduction, or CC immunity. It is
  not a dodge. Dodging is what mobility abilities are for, and they are budgeted as
  such (§32).
- Being airborne does **not** avoid ground-targeted AoE in the baseline. Allowing it
  would quietly make AoE damage a reflex check, which §55 exists to prevent.
- Jump is legal from Idle, Moving, and BasicAttackRecovery only (§56).
- Rooted, Stunned, Feared, and Taunted characters cannot jump, and jumping does not
  break an existing Root (§14).
- Basic attacks and abilities are disallowed while airborne unless the ability sets
  `usable_in_air` (§57).
- Knock-up (§14) is a separate forced-displacement effect and always overrides a
  player-initiated jump.

These are starting test values in the same sense as §6 — jump height and air control
are level-geometry decisions as much as combat ones.

---

# 6. Core Character Statistics

A baseline character begins with the following statistics.

These values are **starting test values**, not final balance values.

| Statistic | Baseline |
|---|---:|
| Health | 500 |
| Health Regeneration | 5 / second |
| Mana / Primary Resource | 250 |
| Resource Regeneration | 3 / second |
| Attack Damage | 50 |
| Attack Speed | 1.0 attacks / second |
| Attack Range | 2.0 meters melee |
| Armor | 30 |
| Magic Resistance | 25 |
| Movement Speed | 5.0 meters / second |
| Critical Chance | 5% |
| Critical Damage | 200% |
| Ability Haste | 0 |
| Armor Penetration | 0 |
| Magic Penetration | 0 |
| Lifesteal | 0% |
| Omnivamp | 0% |
| Tenacity | 0% |

Different character templates, species, equipment, or backgrounds may eventually alter these numbers.

For the first implementation, however, identical baseline characters are useful because they provide a clean control group for balance tests.

---

# 7. Damage Types

The baseline rules use three major damage types.

## Physical Damage

Reduced by Armor.

Typical sources:

- Swords
- Spears
- Claws
- Bullets
- Physical projectiles
- Many martial abilities

---

## Magical / Energy Damage

Reduced by Magic Resistance.

This category can represent more than literal magic.

Examples:

- Psychic attacks
- Energy weapons
- Weird science
- Occult attacks
- Elemental effects
- Strange artifacts

---

## True Damage

Ignores Armor and Magic Resistance.

True Damage should be uncommon because excessive access to it makes defensive statistics less valuable.

---

# 8. Damage Mitigation

For positive Armor or Magic Resistance, use:

```text
Damage Multiplier = 100 / (100 + Defense)
```

Then:

```text
Final Damage = Raw Damage × Damage Multiplier
```

Example:

```text
Raw Physical Damage = 50
Armor = 50

Multiplier = 100 / 150
Multiplier = 0.6667

Final Damage ≈ 33.33
```

This produces diminishing returns while ensuring that additional defense continues to provide value.

For the first implementation, negative defenses can be disallowed or clamped to zero. A negative-defense formula can be introduced later if needed.

---

# 9. Basic Attacks

A Basic Attack has:

- Damage
- Damage type
- Attack speed
- Attack range
- Wind-up
- Recovery
- Optional projectile speed
- Optional weapon-specific properties

Example melee attack:

```text
Longsword Basic Attack

Damage: 50 Physical
Attack Speed: 1.0 / sec
Range: 2.0 m
Wind-up: 0.30 sec
Recovery: 0.70 sec
```

The attack cycle is:

```text
Wind-up → Hit → Recovery → Ready
```

Movement or another action may cancel or interrupt part of this cycle depending on future animation and combat rules.

---

# 10. Ability Anatomy

Every active ability should be representable as data.

A generic ability may contain:

```text
Name
Discipline
Targeting Type
Damage Type
Base Damage
Scaling
Resource Cost
Cooldown
Cast Time
Range
Projectile Speed
Area Radius
Duration
Charges
Crowd Control
Buffs
Debuffs
Interrupt Rules
```

Not every ability needs every field.

---

# 11. Ability Targeting Types

## Self

Affects the caster.

Example:

```text
Brace
Gain +40 Armor for 4 seconds.
```

## Targeted

Selects a valid character or object.

Example:

```text
Shield Bash
Deal 40 Physical damage and stun target for 1 second.
```

## Skillshot

Travels or resolves along an aimed path.

Example:

```text
Spear Throw
Fire a projectile in the chosen direction.
```

Collision determines what is hit.

## Ground Targeted

The player selects a position.

Example:

```text
Bombardment
After 0.75 seconds, deal damage in a 3-meter radius.
```

## Area

Affects entities around the caster or another origin.

Example:

```text
Whirlwind
Damage nearby enemies.
```

## Toggle

Remains active until turned off or the resource is exhausted.

---

# 12. Cooldowns

Abilities follow:

```text
Ready → Activated → Cooldown → Ready
```

Example:

```text
Power Strike
Damage: 100 Physical
Mana Cost: 30
Cooldown: 6 sec
```

Cooldowns serve as a real-time action economy.

They prevent a player from simply repeating the strongest ability continuously.

---

# 13. Resources

The initial universal resource is Mana.

"Mana" may later be renamed or replaced for particular character concepts.

Examples could include:

- Mana
- Stamina
- Focus
- Psychic Power
- Energy
- Heat
- Ammunition
- Fury

For baseline testing, every character uses:

```text
Maximum Resource: 250
Regeneration: 3 / sec
```

Abilities consume resource.

Resource design adds a second limitation beyond cooldowns:

```text
Cooldown determines when an ability can be used again.
Resource determines how frequently abilities can be sustained over time.
```

---

# 14. Crowd Control

The baseline system supports the following effects.

| Effect | Result |
|---|---|
| Stun | Cannot move or act |
| Root | Cannot move |
| Slow | Movement Speed reduced |
| Silence | Cannot activate most abilities |
| Disarm | Cannot perform Basic Attacks |
| Knockback | Forced away from source |
| Pull | Forced toward source |
| Knock-up | Forced displacement plus temporary loss of control |
| Fear | Temporary forced movement or loss of directional control |
| Taunt | Forced to attack designated target |
| Blind | Basic attacks miss or become impaired |

Tenacity can reduce the duration of eligible crowd-control effects.

Example:

```text
Incoming Stun = 2.0 sec
Tenacity = 25%

Final Duration = 1.5 sec
```

Some effects such as knockback may ignore Tenacity.

---

# 15. Critical Hits

Baseline:

```text
Critical Chance = 5%
Critical Damage = 200%
```

A 50-damage attack that critically hits deals:

```text
50 × 2.0 = 100 raw damage
```

Critical hits are one of the first explicit random systems in the ruleset.

For automated tests, this means balance should be evaluated across many simulated attacks rather than judging critical-hit builds from a single result.

---

# 16. Sustain

The rules may support:

- Health Regeneration
- Resource Regeneration
- Lifesteal
- Omnivamp
- Healing
- Shields

## Lifesteal

Heals based on qualifying Basic Attack damage.

Example:

```text
Damage Dealt = 40
Lifesteal = 10%

Healing = 4
```

## Omnivamp

Heals from a broader set of damage sources.

## Shield

Temporary damage absorption.

Damage resolves:

```text
Incoming Damage
    ↓
Shield
    ↓
Remaining Damage
    ↓
Health
```

---

# 17. Buffs and Debuffs

Effects can temporarily modify statistics.

Examples:

```text
+30% Attack Speed for 5 sec
+20 Armor for 4 sec
-25 Armor for 6 sec
+20% Movement Speed for 3 sec
-30% Movement Speed for 2 sec
+15% Damage Taken for 4 sec
```

Effects should preferably be data-driven so that they can be simulated outside the game engine.

---

# 18. Death

Baseline:

```text
Health <= 0 → Dead
```

What happens after death is not part of the core combat rules.

Possible game modes may later use:

- Respawn
- Checkpoints
- Revive mechanics
- Permadeath
- Roguelike resets
- Multiplayer resurrection
- GM intervention

Combat only needs to define when death occurs.

---

# 19. Initial Example Ability Set

These values exist primarily to make simulation possible.

They are not final.

## Warrior

### Power Strike

```text
Damage: 100 Physical
Cost: 30 Mana
Cooldown: 6 sec
Range: Basic Attack Range
Targeting: Targeted
```

### Parry

```text
Duration: 1.0 sec
Effect: Reduce incoming Physical damage by 75%
Cost: 25 Mana
Cooldown: 8 sec
Targeting: Self
```

### Charge

```text
Range: 6 m
Damage: 40 Physical
Stun: 0.75 sec
Cost: 35 Mana
Cooldown: 10 sec
Targeting: Targeted
```

### Whirlwind

```text
Damage: 120 Physical
Radius: 3 m
Cost: 60 Mana
Cooldown: 15 sec
Targeting: Area
```

---

## Guardian

### Shield Bash

```text
Damage: 40 Physical
Stun: 1 sec
Cost: 30 Mana
Cooldown: 8 sec
```

### Brace

```text
Armor: +40
Magic Resistance: +30
Duration: 4 sec
Cost: 30 Mana
Cooldown: 12 sec
```

### Taunt

```text
Duration: 1.5 sec
Radius: 4 m
Cost: 40 Mana
Cooldown: 12 sec
```

### Ground Slam

```text
Damage: 80 Physical
Radius: 3 m
Knock-up: 0.75 sec
Cost: 60 Mana
Cooldown: 16 sec
```

---

## Slayer

### Lunge

```text
Dash: 4 m
Damage: 60 Physical
Cost: 25 Mana
Cooldown: 6 sec
```

### Vanish

```text
Stealth Duration: 3 sec
Cost: 40 Mana
Cooldown: 14 sec
```

### Hamstring

```text
Damage: 50 Physical
Slow: 40%
Duration: 2 sec
Cost: 25 Mana
Cooldown: 7 sec
```

### Execute

```text
Damage: 150 Physical
Bonus: +50% damage if target is below 30% Health
Cost: 60 Mana
Cooldown: 15 sec
```

---

## Marksman

### Aimed Shot

```text
Damage: 100 Physical
Range: 12 m
Cost: 30 Mana
Cooldown: 6 sec
Targeting: Skillshot
```

### Rapid Fire

```text
Attack Speed: +50%
Duration: 4 sec
Cost: 35 Mana
Cooldown: 12 sec
```

### Evasive Roll

```text
Dash: 4 m
Cost: 25 Mana
Cooldown: 7 sec
```

### Deadeye

```text
Damage: 180 Physical
Range: 18 m
Cost: 70 Mana
Cooldown: 18 sec
Targeting: Skillshot
```

---

## Mystic

### Energy Bolt

```text
Damage: 90 Magical
Range: 10 m
Cost: 30 Mana
Cooldown: 5 sec
Targeting: Skillshot
```

### Mesmerize

```text
Stun: 1.25 sec
Range: 8 m
Cost: 40 Mana
Cooldown: 10 sec
Targeting: Targeted
```

### Force Barrier

```text
Shield: 100
Duration: 4 sec
Cost: 40 Mana
Cooldown: 10 sec
```

### Cataclysm

```text
Damage: 160 Magical
Radius: 4 m
Cast Delay: 0.75 sec
Cost: 75 Mana
Cooldown: 18 sec
Targeting: Ground
```

---

## Adventurer

### Trick Shot

```text
Damage: 60 Physical
Debuff: Target deals -15% damage
Duration: 4 sec
Cost: 25 Mana
Cooldown: 7 sec
```

### Field Dressing

```text
Healing: 100
Cost: 40 Mana
Cooldown: 10 sec
```

### Snare

```text
Root: 1.5 sec
Trigger Radius: 1.5 m
Cost: 30 Mana
Cooldown: 10 sec
```

### Rally

```text
Attack Speed: +20%
Movement Speed: +15%
Duration: 5 sec
Radius: 6 m
Cost: 60 Mana
Cooldown: 18 sec
```

---

# 20. Why Automated Balance Tests Matter

Balance is difficult to reason about intuitively because multiple systems interact.

For example:

```text
+20% Attack Damage
```

does not necessarily produce the same combat benefit as:

```text
+20% Attack Speed
```

because:

- Crits interact with both differently.
- Armor affects damage.
- Attack animations may constrain effective Attack Speed.
- Lifesteal scales with damage output.
- Crowd control changes uptime.
- Movement affects whether attacks can connect.
- Cooldowns create burst windows.
- Resource exhaustion changes sustained damage.

A Python simulation provides a repeatable way to detect obvious balance problems before human playtesting.

Simulation does **not** replace playtesting.

It answers:

> Are the numbers mathematically plausible?

Human testing answers:

> Is the game actually fun?

Both are necessary.

---

# 21. Recommended Python Project Structure

Keep combat calculations independent from Godot whenever practical.

For example:

```text
balance/
├── models.py
├── formulas.py
├── abilities.py
├── simulation.py
├── scenarios.py
└── tests/
    ├── test_damage.py
    ├── test_defense.py
    ├── test_abilities.py
    ├── test_duels.py
    └── test_build_balance.py
```

The same formulas used by Godot can eventually be represented in shared data files or mirrored by deterministic tests.

The goal is to avoid burying balance logic inside scene scripts where it is difficult to test.

---

# 22. Basic Python Data Model

A simple starting model could be:

```python
from dataclasses import dataclass


@dataclass
class Character:
    health: float = 500
    max_health: float = 500

    resource: float = 250
    max_resource: float = 250

    attack_damage: float = 50
    attack_speed: float = 1.0

    armor: float = 30
    magic_resistance: float = 25

    crit_chance: float = 0.05
    crit_multiplier: float = 2.0

    movement_speed: float = 5.0
```

Keep this deliberately small initially.

---

# 23. Damage Formula Tests

Implementation:

```python
def mitigation_multiplier(defense: float) -> float:
    defense = max(0.0, defense)
    return 100.0 / (100.0 + defense)


def physical_damage(raw_damage: float, armor: float) -> float:
    return raw_damage * mitigation_multiplier(armor)


def magical_damage(raw_damage: float, resistance: float) -> float:
    return raw_damage * mitigation_multiplier(resistance)
```

Tests:

```python
import pytest


def test_zero_armor_does_not_reduce_damage():
    assert physical_damage(100, 0) == pytest.approx(100)


def test_100_armor_halves_physical_damage():
    assert physical_damage(100, 100) == pytest.approx(50)


def test_50_armor_reduces_100_damage_to_about_66():
    assert physical_damage(100, 50) == pytest.approx(66.6667, rel=1e-4)
```

These are **rules correctness tests**.

They ensure the implementation matches the design.

They are different from balance tests.

---

# 24. Time-to-Kill

One of the most useful balance metrics is **Time to Kill**, or TTK.

If Alice deals 50 raw Physical damage once per second against Bob with 30 Armor:

```python
def basic_attack_damage(attacker, defender):
    return physical_damage(
        attacker.attack_damage,
        defender.armor,
    )


def estimated_basic_attack_dps(attacker, defender):
    damage = basic_attack_damage(attacker, defender)
    return damage * attacker.attack_speed


def estimated_ttk(attacker, defender):
    dps = estimated_basic_attack_dps(attacker, defender)
    return defender.health / dps
```

Test:

```python
def test_baseline_ttk_is_reasonable():
    alice = Character()
    bob = Character()

    ttk = estimated_ttk(alice, bob)

    assert 10 <= ttk <= 20
```

The exact acceptable interval is a design decision.

The important idea is that the test expresses an intended gameplay envelope.

---

# 25. Use Balance Bands Rather Than Exact Numbers

A brittle balance test would say:

```python
assert ttk == 13.0
```

That makes ordinary tuning painful.

Prefer:

```python
assert 10 <= ttk <= 16
```

This says:

> A baseline duel should take roughly this long.

Similar target bands can be established for:

- Burst damage
- Sustained DPS
- Healing
- Shield strength
- Crowd-control duration
- Resource endurance
- Mobility
- Defensive uptime

---

# 26. Burst Damage Testing

Define a burst window.

For example:

> How much damage can a build deal in three seconds?

```python
def burst_ratio(damage, target_health):
    return damage / target_health
```

Then establish rules.

Example:

```python
def test_normal_build_cannot_delete_full_health_peer_instantly():
    target_health = 500
    burst_damage = 350

    assert burst_ratio(burst_damage, target_health) < 0.80
```

You may later intentionally allow Slayer builds to break that rule under specific conditions.

If so, encode the exception explicitly.

---

# 27. Cooldown Efficiency

A useful rough metric:

```text
Damage Per Cooldown Second =
Expected Damage / Cooldown
```

Example:

```python
def cooldown_efficiency(damage, cooldown):
    return damage / cooldown
```

Power Strike:

```text
100 damage / 6 sec = 16.67
```

Cataclysm:

```text
160 damage / 18 sec = 8.89
```

This does **not** mean Power Strike is necessarily stronger.

Cataclysm:

- Is AoE.
- May hit several characters.
- Deals a different damage type.
- Operates at range.

The metric is useful because it exposes abilities whose raw numbers are obviously unusual.

---

# 28. Resource Efficiency

Calculate:

```text
Damage Per Resource =
Damage / Resource Cost
```

Example:

```python
def resource_efficiency(damage, cost):
    return damage / cost
```

Power Strike:

```text
100 / 30 = 3.33 damage per Mana
```

Energy Bolt:

```text
90 / 30 = 3.0 damage per Mana
```

Again, this is a diagnostic metric rather than a complete measure of ability strength.

---

# 29. Effective Health

Defensive strength can be expressed as Effective Health.

For Physical damage:

```text
Physical Effective Health =
Health / Physical Damage Multiplier
```

At 500 HP and 50 Armor:

```text
Multiplier = 100 / 150
           = 0.6667

Effective Health ≈ 750
```

Python:

```python
def effective_health(health, defense):
    multiplier = mitigation_multiplier(defense)
    return health / multiplier
```

This makes it easy to compare:

```text
+100 Health
```

against:

```text
+20 Armor
```

---

# 30. Healing and Shield Equivalence

Healing and shields should be compared against damage expectations.

Example:

```python
def survivability_gain_from_heal(heal_amount):
    return heal_amount


def survivability_gain_from_shield(shield_amount):
    return shield_amount
```

This baseline is intentionally simple.

Later tests may account for:

- Healing reduction
- Shield expiration
- Armor interaction
- Overhealing
- Damage types

---

# 31. Crowd-Control Budget

Crowd control needs numerical testing too.

One useful metric is:

```text
CC Uptime =
CC Duration / Cooldown
```

Example:

Shield Bash:

```text
1 sec stun / 8 sec cooldown
= 12.5% theoretical uptime
```

Mesmerize:

```text
1.25 / 10
= 12.5%
```

This gives the two abilities comparable raw CC uptime even though their targeting, range, damage, and cost differ.

Test:

```python
def cc_uptime(duration, cooldown):
    return duration / cooldown


def test_baseline_hard_cc_uptime_is_not_excessive():
    assert cc_uptime(1.0, 8.0) <= 0.15
```

---

# 32. Mobility Budget

Mobility can be normalized approximately as:

```text
Dash Distance / Cooldown
```

Examples:

```text
Lunge:       4 m / 6 sec  = 0.67 m/sec
Evasive Roll: 4 m / 7 sec = 0.57 m/sec
```

This is not literally added to Movement Speed.

It is a comparison metric.

Mobility also carries qualitative value:

- Can it cross obstacles?
- Can it target enemies?
- Can it move in any direction?
- Is the character invulnerable during it?
- Can it be interrupted?

Those should be recorded separately.

Jump (§5.5) is deliberately excluded from this budget. It is universal, free, and
grants no invulnerability, so it differentiates no build and should never be traded
against a mobility ability during balance work.

---

# 33. Monte Carlo Simulation

Random systems such as critical hits should be tested across many trials.

Example:

```python
import random


def attack_once(attacker, defender):
    damage = attacker.attack_damage

    if random.random() < attacker.crit_chance:
        damage *= attacker.crit_multiplier

    return physical_damage(damage, defender.armor)


def simulate_attacks(attacker, defender, count=100_000):
    total = 0.0

    for _ in range(count):
        total += attack_once(attacker, defender)

    return total / count
```

Then:

```python
def test_average_crit_damage_is_close_to_expected():
    alice = Character()
    bob = Character()

    average = simulate_attacks(alice, bob)

    assert 38 <= average <= 42
```

Use a generous tolerance or seeded random generator so tests do not fail unpredictably.

---

# 34. Prefer Seeded Simulations

For reproducible tests:

```python
rng = random.Random(12345)
```

Then pass `rng` into simulation functions.

This ensures:

```text
Same code
+ Same seed
= Same simulation
```

That is important for CI.

---

# 35. Duel Simulation

The next stage is an event-driven duel simulator.

A simplified duel may track:

```text
Time
Health
Resource
Basic Attack timer
Ability cooldowns
Buff durations
Crowd control
Position
```

Pseudo-code:

```python
while alice.alive and bob.alive:
    advance_time(step)

    alice.update(step)
    bob.update(step)

    alice_ai.choose_action()
    bob_ai.choose_action()

    resolve_actions()

    if time > MAX_DUEL_TIME:
        break
```

Use a fixed simulation tick such as:

```text
0.05 sec
```

or use an event queue that jumps directly to the next action.

An event-driven model will eventually be more efficient.

---

# 36. Testing Builds Rather Than Classes

Because the game is classless, balance should focus on **loadouts**.

Example builds:

```text
Bruiser
- Power Strike
- Parry
- Lunge
- Shield Bash
```

```text
Burst Slayer
- Lunge
- Vanish
- Hamstring
- Execute
```

```text
Defensive Mystic
- Energy Bolt
- Force Barrier
- Mesmerize
- Brace
```

```text
Mobile Marksman
- Aimed Shot
- Rapid Fire
- Evasive Roll
- Snare
```

The simulator should compare these builds rather than assuming every Discipline is a sealed class.

---

# 37. Matchup Matrix

Run every test build against every other build.

Example:

| Build | Bruiser | Slayer | Mystic | Marksman |
|---|---:|---:|---:|---:|
| Bruiser | 50% | 57% | 48% | 44% |
| Slayer | 43% | 50% | 61% | 58% |
| Mystic | 52% | 39% | 50% | 55% |
| Marksman | 56% | 42% | 45% | 50% |

These numbers are examples only.

Do **not** require every matchup to equal 50%.

Some asymmetry is desirable.

The important questions are:

- Does one build dominate nearly everything?
- Does one ability appear in every winning build?
- Does one Discipline provide disproportionately valuable abilities?
- Are there builds with no meaningful counterplay?
- Does a particular combination produce extreme TTK?

---

# 38. Statistical Win-Rate Tests

For automated simulations, establish broad tolerances.

Example:

```python
def test_no_generalist_build_has_extreme_win_rate():
    win_rate = simulate_build_against_test_pool(my_build)

    assert 0.35 <= win_rate <= 0.65
```

This does not imply competitive esports-level balance.

It merely detects obvious outliers.

---

# 39. Skillshot Accuracy

Player execution should be represented as a parameter rather than assuming every skillshot hits.

Example simulation profiles:

```text
Novice:      35% skillshot accuracy
Average:     55%
Skilled:     70%
Expert:      85%
```

A test can then ask:

> Does a skillshot-heavy build become useless for average players but overwhelming for experts?

Example:

```python
def expected_skillshot_damage(raw_damage, hit_rate):
    return raw_damage * hit_rate
```

A 100-damage skillshot at 55% accuracy has:

```text
55 expected raw damage per cast
```

This becomes especially important when balancing targeted abilities against skillshots.

Skillshots should generally receive some benefit in exchange for their chance to miss, such as:

- Higher damage
- Longer range
- AoE
- Lower cooldown
- Crowd control
- Lower resource cost

---

# 40. Player Skill Profiles

Eventually, simulations should define player profiles.

Example:

```python
@dataclass
class PlayerProfile:
    skillshot_accuracy: float
    reaction_time: float
    cooldown_efficiency: float
    positioning_efficiency: float
```

Possible profiles:

```text
Casual
Average
Experienced
Expert
```

This prevents the game from being balanced only around mathematically perfect execution.

Note (see §55): once gamepad soft-lock targeting is defined, `skillshot_accuracy` alone
is no longer a sufficient proxy for execution. Profiles should separate raw aim
precision from the assist tier applied, since assist narrows the gap between skill
tiers by design.

Because §5 supports three control schemes, a profile should also carry the device it
represents:

```python
    input_device: str  # "gamepad" | "mouse" | "touch"
```

The device does not change the combat math directly. It selects the default assist
tier (§55) and sets a realistic ceiling on raw aim precision, which is why an
"Expert on touch" and an "Expert on mouse" are different profiles rather than the
same profile with a different number.

---

# 41. 1v1 Is Not Enough

MOBA-inspired abilities frequently become stronger or weaker depending on party size.

Therefore simulations should eventually include:

```text
1v1
2v2
3v3
4-player party vs encounter
Party vs boss
Party vs many weak enemies
```

An AoE ability that is mediocre in a duel may be exceptional against five enemies.

A Taunt that contributes little in 1v1 may be extremely valuable in multiplayer.

---

# 42. PvE Test Scenarios

Create standardized enemies.

Example:

## Weak Enemy

```text
HP: 150
Armor: 10
MR: 10
Damage: 20
Attack Speed: 0.8
```

## Standard Enemy

```text
HP: 500
Armor: 30
MR: 25
Damage: 50
Attack Speed: 1.0
```

## Elite Enemy

```text
HP: 1,200
Armor: 50
MR: 40
Damage: 80
Attack Speed: 0.9
```

## Boss

```text
HP: 5,000
Armor: 60
MR: 60
Damage: 100
Attack Speed: 0.8
```

Then define tests such as:

```python
def test_standard_enemy_fight_duration():
    duration = simulate_encounter(player_build, standard_enemy)

    assert 8 <= duration <= 25
```

See §63 for the enemy behavior/threat model these stat blocks assume.

---

# 43. Important Balance Metrics

At minimum, record:

- Time to Kill
- Damage per second
- Burst damage
- Damage taken
- Effective Health
- Healing per second
- Shield value
- Resource consumed
- Time until resource exhaustion
- Cooldown utilization
- Crowd-control uptime
- Basic-attack uptime
- Skillshot hit rate
- Distance traveled
- Time spent unable to act
- Ability usage counts
- Win rate
- Remaining Health at victory
- Fight duration

These metrics make it easier to diagnose **why** something wins.

---

# 44. Detecting Dominant Abilities

Because abilities can be mixed across Disciplines, one of the most important tests is ability selection frequency.

Suppose the strongest simulated builds are generated automatically.

If:

```text
Lunge appears in 93% of top-performing builds
```

that is a warning.

The problem may not be raw damage.

Lunge may simply provide too much value relative to one precious ability slot.

The restricted four-ability bar makes **slot efficiency** one of the game's most important balance concepts.

---

# 45. Ability Slot Value

Every equipped ability has an opportunity cost:

> Taking this ability means not taking another ability.

Therefore an ability should not be judged only by damage.

A rough evaluation model could record:

```text
Damage Contribution
Defensive Contribution
Mobility Contribution
CC Contribution
Support Contribution
Resource Efficiency
Cooldown Efficiency
```

Avoid collapsing these into a single universal "power score" too early.

The interactions are what make builds interesting.

---

# 46. Property-Based Tests

Python libraries such as Hypothesis can test broad mathematical properties.

Examples:

> Increasing Armor should never increase incoming Physical damage.

> Increasing Health should never reduce Effective Health.

> A 0% Critical Chance should never produce a critical hit.

> Resource should never fall below zero.

> Health should never exceed Maximum Health unless explicitly allowed.

Example:

```python
from hypothesis import given, strategies as st


@given(
    damage=st.floats(min_value=0, max_value=10_000),
    armor1=st.floats(min_value=0, max_value=500),
    armor2=st.floats(min_value=0, max_value=500),
)
def test_more_armor_never_increases_damage(damage, armor1, armor2):
    low = min(armor1, armor2)
    high = max(armor1, armor2)

    assert physical_damage(damage, high) <= physical_damage(damage, low)
```

This is extremely useful for combat engines because it finds edge cases humans may not think to test.

---

# 47. Regression Tests

Whenever playtesting identifies a broken build, save that scenario as a test.

Example:

```text
BUG:
Lunge + Shield Bash + Execute killed a baseline target
from full Health in 1.4 seconds with no counterplay.
```

After changing the numbers:

```python
def test_lunge_bash_execute_does_not_instantly_delete_peer():
    result = simulate_combo(...)

    assert result.time_to_kill >= 3.0
```

Balance testing therefore becomes cumulative.

Every major discovered exploit becomes a permanent regression test.

---

# 48. CI Integration

Run the balance tests in GitHub Actions along with normal unit tests.

Possible workflow:

```text
Pull Request
    ↓
Unit Tests
    ↓
Combat Formula Tests
    ↓
Fast Balance Simulations
    ↓
Regression Scenarios
    ↓
Pass / Fail
```

Do not run millions of simulations on every small commit.

Split tests into:

## Fast Suite

Runs on every pull request.

Examples:

- Formula tests
- Ability legality
- 100–1,000 duel simulations
- Known regression scenarios
- Ability data schema validation (§57)

## Deep Balance Suite

Runs manually or on a schedule.

Examples:

- Tens of thousands of matchups
- Build-generation experiments
- Multi-character encounters
- Statistical analysis

---

# 49. Balance Reports

The Python simulator should eventually output a machine-readable report.

Example:

```json
{
  "build": "warrior_slayer_guardian",
  "matches": 10000,
  "win_rate": 0.53,
  "average_ttk": 11.8,
  "average_damage": 612,
  "average_damage_taken": 481,
  "average_resource_remaining": 72,
  "cc_uptime": 0.11
}
```

The report can later be visualized as:

- Matchup matrices
- Histograms
- Scatter plots
- Damage distributions
- Ability pick rates
- TTK distributions

---

# 50. Build Generation

Once the number of abilities grows, automated testing can generate combinations.

With 24 learned abilities and four equipped slots:

```text
24 choose 4 = 10,626 possible unordered combinations
```

This is already large enough that manual testing will miss interactions.

Python can systematically search for:

- Highest burst build
- Highest sustained DPS build
- Highest Effective Health build
- Highest CC build
- Most universally successful loadout
- Abilities appearing disproportionately in winning builds

This is one of the strongest arguments for keeping the combat rules data-driven.

---

# 51. What Automated Tests Cannot Determine

A build can be mathematically balanced and still be miserable to play.

Python cannot reliably answer:

- Does movement feel responsive?
- Is landing this skillshot satisfying?
- Is an animation readable?
- Does a stun feel unfair?
- Is an ability understandable?
- Is combat exciting?
- Does the controller layout feel natural?
- Is a sound effect providing enough feedback?
- Is an encounter stressful in a good way?

Those require human playtesting.

The correct loop is:

```text
Design
  ↓
Unit Test
  ↓
Simulate
  ↓
Implement
  ↓
Playtest
  ↓
Record Problem
  ↓
Add Regression Test
  ↓
Tune
  ↓
Repeat
```

---

# 52. Recommended First Balance Targets

For the first playable prototype, avoid trying to achieve perfect balance.

Use broad target envelopes.

Suggested experimental targets:

| Metric | Initial Target |
|---|---|
| Baseline 1v1 TTK using basic attacks | 10–20 sec |
| Typical normal ability cooldown | 5–12 sec |
| Major ability cooldown | 12–20 sec |
| Hard CC duration | 0.5–1.5 sec |
| Normal mobility cooldown | 6–12 sec |
| Standard combat resource endurance | 20–40 sec |
| Normal burst against equal target | <80% max HP |
| Basic Skillshot accuracy assumption | 50–60% |
| Baseline fight starting HP | 500 |
| Baseline resource | 250 |
| Ability slots | 4 |
| Basic Attack slots | 1 fixed |

These are not promises.

They are initial hypotheses to test.

---

# 53. First Prototype Scope

A very small first implementation could include only:

## One baseline character model

```text
500 HP
250 Mana
50 AD
1.0 Attack Speed
30 Armor
25 MR
5 m/s Movement
5% Crit
```

## Two weapons

```text
Longsword
Rifle
```

## Eight abilities

```text
Power Strike
Parry
Charge
Shield Bash
Lunge
Aimed Shot
Energy Bolt
Field Dressing
```

## Four test loadouts

```text
Melee Bruiser
Mobile Slayer
Ranged Fighter
Mystic Hybrid
```

## Four enemy profiles

```text
Weak
Standard
Elite
Boss
```

## Control schemes

```text
Keyboard + Mouse  — the development scheme; already bound in project.godot
Gamepad           — must be playable in the first prototype, not deferred
Touch             — HUD can come later, but the intent layer (§5.4) ships now
```

Touch layout work does not have to happen in the first prototype, but nothing in
the first prototype may assume a keyboard, a mouse cursor, or a hover state.

That is enough to start discovering whether the fundamental combat model works.

---

# 54. Summary of Baseline Design

The baseline design is:

```text
MOBA-style real-time combat
+
Classless ability Disciplines
+
Basic Attack
+
Four equipped active abilities
+
Gamepad-first controls, with keyboard + mouse and touch parity
+
Equipment and statistics
+
No character levels initially
```

Characters learn abilities from broad Disciplines such as:

```text
Warrior
Guardian
Slayer
Marksman
Mystic
Adventurer
```

These are not classes.

They are pools of abilities that can be combined freely.

The player's currently equipped kit effectively creates their combat role.

The numerical system should be designed so that combat can be simulated independently from the game engine.

Python tests should operate at several levels:

```text
Formula correctness
        ↓
Ability correctness
        ↓
Combat metrics
        ↓
Duel simulation
        ↓
Build-vs-build simulation
        ↓
Party / PvE scenarios
        ↓
Statistical balance analysis
        ↓
Regression testing
```

The goal is not to allow Python to decide what is fun.

The goal is to make the rules measurable enough that human design decisions can be informed by repeatable evidence.

---

# 55. Targeting Model (Soft-Lock / Aim Assist)

The baseline design goal is explicit: engaging combat without requiring twitch-FPS
reflexes. The Skillshot definition in §11 ("travels or resolves along an aimed path")
is written for a mouse. On a stick, raw aim without assistance produces exactly the
reflex-dependent experience the design is trying to avoid.

Introduce three targeting assist tiers, selectable per-ability:

## Free Aim
No assistance. Reserved for high-power, high-skill-expression abilities (rare).

## Soft Lock (default for most Skillshots)
```text
Aim Cone: ±X degrees around cursor/reticle direction
Magnetism: nearest valid target within cone is used to bend trajectory toward it
Magnetism Strength: 0.0–1.0 (0 = cosmetic nudge, 1 = effectively targeted)
Acquisition Range: distance at which magnetism begins to apply
```

```python
def resolve_skillshot_direction(aim_direction, candidates, cone_degrees, magnetism):
    target = nearest_in_cone(candidates, aim_direction, cone_degrees)
    if target is None:
        return aim_direction
    return lerp_direction(aim_direction, direction_to(target), magnetism)
```

## Hard Lock (Targeted type abilities only)
Right Bumper cycles/holds a lock; ability auto-resolves to the locked unit if still valid
and in range at cast resolution.

Recommended defaults for the initial ability set:
```text
Skillshots (Aimed Shot, Energy Bolt, Deadeye): Soft Lock, 8° cone, 0.5 magnetism
Charge / Lunge (dash-to-target): Soft Lock, 12° cone, 0.7 magnetism
Cataclysm (ground-targeted AoE): Free Aim (no single target to assist toward)
```

## Per-Device Assist Scaling

An ability declares its assist *tier*; the input device (§5) scales the magnetism
applied within that tier. Same ability, same tier, different pointing precision:

| Device | Magnetism multiplier | Rationale |
|---|---:|---|
| Mouse | 0.35x | Fine pointing available; heavy assist feels like the game is playing for you |
| Gamepad | 1.0x | The baseline the tiers are tuned against |
| Touch | 1.5x | Drag-to-aim is the coarsest input; the thumb also occludes the target |

```text
effective_magnetism = clamp(ability.magnetism * device_multiplier, 0.0, 1.0)
```

Free Aim stays free aim on every device — a multiplier of anything times zero is
still zero. Abilities deliberately marked Free Aim are the ones where precision is
the point, so they should be rare and should not be load-bearing for any build.

Magnetism strength becomes a first-class tunable, and should be included in the
`PlayerProfile` skill simulation (§40) as a variable independent from raw accuracy —
it lets you simulate "gamepad + assist," "touch + assist," and "theoretical mouse
precision" as separate populations.

---

# 56. Character State Machine

Every character needs one authoritative state at any instant. This resolves the
"movement or another action may cancel or interrupt" ambiguity in §9.

```text
States:
  Idle
  Moving
  BasicAttackWindup
  BasicAttackRecovery
  AbilityCast        (has Cast Time > 0)
  AbilityChannel      (see §58)
  Dashing             (movement-locked mobility ability, e.g. Lunge, Charge)
  Airborne            (jump in progress or knock-up — see §5.5, §14)
  CrowdControlled     (Stunned / Rooted / Feared / Taunted — see §14)
  Dead
```

Legal interrupts per state (baseline — override per-ability via `Interrupt Rules`):

| State | Movement | New Basic Attack | New Ability | Interruptible by hard CC |
|---|---|---|---|---|
| Idle / Moving | ✅ | ✅ | ✅ | ✅ |
| BasicAttackWindup | ❌ (cancels attack) | ❌ | ❌ | ✅ |
| BasicAttackRecovery | ✅ | ❌ | ✅ | ✅ |
| AbilityCast | ❌ (cancels cast, resource refunded per §59) | ❌ | ❌ | ✅ |
| AbilityChannel | ❌ | ❌ | ❌ | ✅ (breaks channel) |
| Dashing | ❌ (locked to dash path) | ❌ | ❌ | only by displacement effects |
| Airborne | ✅ air control only (60%) | ❌ | ❌ (unless `usable_in_air`) | ✅ |
| CrowdControlled | per CC type (§14) | per CC type | per CC type | n/a |

Airborne is entered by a player jump (§5.5) or a knock-up (§14) and is the one state
with two distinct causes, so it should carry a flag for which. A player jump is exited
on landing; a knock-up is exited on landing *and* applies whatever CC follows it. A
character cannot jump out of an Airborne state — no double jump in the baseline.

This table is itself a good candidate for a data file (`state_transitions.json`) rather
than hardcoded logic, so balance/CC changes don't require touching state-machine code.

---

# 57. Formal Ability Data Schema

§10 lists fields in prose. Coding agents need a validated schema so every ability file
is structurally guaranteed correct before it reaches the simulator or the engine.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Ability",
  "type": "object",
  "required": ["id", "name", "discipline", "targeting_type", "damage_type",
               "resource_cost", "cooldown"],
  "properties": {
    "id": { "type": "string" },
    "name": { "type": "string" },
    "discipline": { "enum": ["warrior", "guardian", "slayer", "marksman", "mystic", "adventurer"] },
    "targeting_type": { "enum": ["self", "targeted", "skillshot", "ground", "area", "toggle"] },
    "aim_assist": { "enum": ["free", "soft_lock", "hard_lock", "none"] },
    "damage_type": { "enum": ["physical", "magical", "true", "none"] },
    "base_damage": { "type": "number", "default": 0 },
    "scaling": { "type": "object", "additionalProperties": { "type": "number" } },
    "resource_cost": { "type": "number" },
    "cooldown": { "type": "number" },
    "cast_time": { "type": "number", "default": 0 },
    "channel_duration": { "type": "number", "default": 0 },
    "range": { "type": "number", "default": 0 },
    "projectile_speed": { "type": "number" },
    "area_radius": { "type": "number" },
    "duration": { "type": "number" },
    "charges": { "type": "integer", "default": 1 },
    "usable_in_air": { "type": "boolean", "default": false },
    "touch_viable": { "type": "boolean", "default": true },
    "crowd_control": {
      "type": "object",
      "properties": {
        "type": { "enum": ["stun", "root", "slow", "silence", "disarm",
                            "knockback", "pull", "knock_up", "fear", "taunt", "blind"] },
        "magnitude": { "type": "number" },
        "duration": { "type": "number" },
        "affected_by_tenacity": { "type": "boolean", "default": true }
      }
    },
    "buffs": { "type": "array", "items": { "$ref": "#/definitions/statModifier" } },
    "debuffs": { "type": "array", "items": { "$ref": "#/definitions/statModifier" } },
    "interrupt_rules": {
      "type": "object",
      "properties": {
        "cancellable_by_movement": { "type": "boolean" },
        "cancellable_by_hard_cc": { "type": "boolean", "default": true },
        "refund_resource_on_cancel": { "type": "number", "default": 0 }
      }
    },
    "on_cancel": { "enum": ["full_refund", "partial_refund", "no_refund", "cooldown_still_applies"] }
  },
  "definitions": {
    "statModifier": {
      "type": "object",
      "properties": {
        "stat": { "type": "string" },
        "amount": { "type": "number" },
        "is_percentage": { "type": "boolean", "default": false },
        "duration": { "type": "number" },
        "stacking": { "enum": ["refresh", "stack", "ignore", "replace_if_stronger"] }
      }
    }
  }
}
```

Two fields exist purely to keep §5 honest:

- `usable_in_air` — whether the ability may be cast from the Airborne state (§5.5).
  Defaults to `false`, so jump stays a traversal tool rather than a free reposition
  mid-combo.
- `touch_viable` — set to `false` only when an ability genuinely cannot be executed
  with drag-to-aim (§5.3). This should be treated as a design smell rather than a
  supported configuration: assert in the Fast Suite that no *default* loadout (§53)
  contains an ability with `touch_viable: false`.

Validate every ability file against this schema in the **Fast Suite** (§48) before any
duel simulation runs — a malformed ability should fail CI in milliseconds, not surface
as a confusing simulation result.

This same schema is what both the Python balance harness and GDScript combat code
should load ability data from (as JSON or converted Godot `Resource` files), rather
than either side hardcoding numbers. See §66 for how this keeps the two
implementations in sync.

---

# 58. Channeled Abilities (missing Targeting/Casting type)

§11 covers Self/Targeted/Skillshot/Ground/Area/Toggle but not **Channeled** — abilities
that deal effect continuously while held and can be interrupted mid-effect (distinct
from Cast Time, which is a delay *before* the effect resolves).

```text
Channeled
Effect applies continuously (tick or continuous) while character remains in
AbilityChannel state. Broken by hard CC, by movement (if flagged), or by
completing full channel_duration.

Example:
  Suppressing Fire
  Channel Duration: 2.5 sec
  Tick Damage: 20 Physical / 0.25 sec
  Effect: Target Slowed 30% while channel active
  Broken by: Stun, Silence, Displacement
  Cost: 10 Mana / tick
```

Add `channel_duration` and `on_channel_break` (`no_effect_remaining` /
`partial_effect_already_applied`) to the schema in §57 (already included above).

---

# 59. Cast Cancellation & Resource Refund Rules

§9 mentions cancellation is possible but doesn't define the economic consequence. This
matters for balance testing (§28 Resource Efficiency assumes resource is *spent*, not
*attempted*).

```text
Default rule:
  Cancelled before cast completes → full resource refund, cooldown NOT applied
  Interrupted by hard CC during cast → resource refunded, cooldown NOT applied
  Interrupted after channel begins damage/effect application → no refund,
      cooldown applies (partial value was already delivered)
```

This default should be overridable per-ability via `on_cancel` (§57 schema) — some
kits may intentionally punish cancelled casts (e.g., a wind-up ability meant to bait CC).

---

# 60. Status Effect Stacking Rules

Neither §14 (Crowd Control) nor §17 (Buffs/Debuffs) defines what happens when the same
or related effects overlap. This is a frequent source of exploit-class bugs (§47).

```text
Per stat modifier, declare a stacking policy (see statModifier.stacking in §57):

  refresh            New application resets duration; magnitude unchanged.
  stack              Magnitude sums (or duration extends), up to max_stacks if defined.
  ignore             New application does nothing if one is already active.
  replace_if_stronger  Keep whichever instance has higher magnitude.

Hard CC (Stun/Root/Fear/Taunt) default policy: DO NOT stack durations.
  A second Stun applied during an active Stun sets duration to
  max(remaining, new_duration) — never sums. This prevents "perma-stun"
  combos from multiple characters chaining CC on one target (a known MOBA
  genre failure mode) and should be an explicit regression test (§47):

  def test_stacked_stuns_do_not_sum_duration():
      target = apply_stun(target, duration=1.0)
      advance_time(0.3)
      target = apply_stun(target, duration=1.0)
      assert target.cc_remaining("stun") == pytest.approx(1.0)
```

Consider a **diminishing-returns CC scaling** as an optional later system (used by
several live MOBAs): each subsequent hard-CC application on the same target within a
rolling window (e.g. 8 sec) has its duration multiplied by 0.5, then 0.25, floor at 0.

---

# 61. Armor/Magic Penetration and Ability Haste Formulas

These stats are listed in §6 but never defined mathematically.

```python
def effective_armor(target_armor, flat_pen, percent_pen):
    # Percent pen applies to remaining armor after flat pen, standard MOBA convention
    reduced = max(0.0, target_armor - flat_pen)
    return reduced * (1.0 - percent_pen)

def physical_damage(raw_damage, target_armor, attacker_flat_pen=0, attacker_percent_pen=0.0):
    eff_armor = effective_armor(target_armor, attacker_flat_pen, attacker_percent_pen)
    return raw_damage * mitigation_multiplier(eff_armor)
```

```python
def effective_cooldown(base_cooldown, ability_haste):
    # Standard MOBA-genre haste formula: haste is a percent-CDR-equivalent stat
    # that avoids the diminishing-returns awkwardness of stacking flat % CDR.
    return base_cooldown * (100.0 / (100.0 + ability_haste))
```

Add regression/property tests mirroring §46 (e.g., "increasing Ability Haste never
increases effective cooldown").

---

# 62. Passive Ability Type

§10/§57 define active ability anatomy only. Character Design (§2) references "Passive
effects" as a first-class concept but no schema exists for them.

```json
{
  "id": "passive_example",
  "name": "Battle Fury",
  "discipline": "warrior",
  "trigger": "on_basic_attack_hit",
  "effect": { "stat": "attack_speed", "amount": 0.02, "is_percentage": true,
              "duration": 3, "stacking": "stack", "max_stacks": 5 },
  "occupies_equipped_slot": false
}
```

Decide explicitly: are Passives always-on traits tied to *learned* (not equipped)
abilities, or do some occupy one of the four equipped slots? This changes the
"24 choose 4" combinatorics in §50 and should be pinned down before build-generation
tooling is built.

---

# 63. PvE AI / Threat Model

§42 defines enemy stat blocks but no behavior model, and §41 assumes party content
exists. A minimal data-driven AI spec:

```text
Threat Table (per enemy):
  threat[character_id] += damage_dealt_to_enemy
  threat[character_id] += flat_threat_from_ability (e.g., Taunt sets threat to max)
  threat decays: threat *= 0.95 per second out of combat

Target Selection (baseline):
  target = highest_threat_valid_target
  valid = alive, in aggro_range, not stealthed (unless enemy has true_sight)

Ability Usage (baseline enemy AI):
  Use highest-priority ability off cooldown whose precondition is met, else Basic Attack.
  Preconditions are simple data: {"if": "target_hp_pct < 0.3", "then": "execute_ability"}
```

This should be simulate-able the same way player builds are (§36-39) so PvE tuning
gets the same regression-test discipline as PvP.

---

# 64. Networking / Hit-Resolution Authority

Not addressed in the baseline, but decision-critical before any multiplayer combat
code is written, since it determines what "the player's execution" (§1 core
philosophy) actually means under latency.

```text
Recommended baseline: Server-authoritative hit resolution with client-side prediction.

  - Client predicts local movement + ability activation immediately (no input delay feel).
  - Client sends aim direction / target id + timestamp to server.
  - Server resolves collision/targeting using server-side entity positions,
    with a bounded rewind window (e.g. 100–150ms) for skillshot fairness
    ("favor the shooter" lag compensation).
  - Server is final authority on damage, CC application, and death.
  - Skillshot soft-lock/magnetism (§55) is computed client-side for feel,
    but hit confirmation is always server-side.

Cooldowns and resource are server-authoritative; client displays a predicted
local copy that reconciles on server correction.
```

This single decision affects animation cancel windows, whether Dash abilities need
server-side path validation, and how aim-assist interacts with rewind. Worth locking
in before §55–59 get implemented in the engine layer, since retrofitting authority
models is expensive.

---

# 65. Python vs. Godot/GDScript: Division of Testing Responsibility

The implementation language for the game itself is GDScript in Godot. This does not
change where balance testing should live.

```text
Python (balance/ project, §21) owns:
  - Exploratory and statistical balance work: Monte Carlo simulation (§33),
    build-vs-build matchup matrices (§37), 1v1/3v3/5v5 scenario testing (§41),
    automated build generation across thousands of loadout combinations (§50),
    property-based testing (§46).
  - This is a search/statistics problem. Fast headless iteration and a mature
    stats/testing ecosystem (pytest, Hypothesis, numpy) matter more here than
    engine fidelity. Running thousands of simulated fights through the actual
    engine — even headless — is far slower than a plain Python loop, and GDScript
    has no equivalent to Hypothesis-style property testing.

GDScript / Godot headless (GUT or similar) owns:
  - Correctness tests of the shipped combat code: does the actual implementation
    compute damage, cooldowns, and CC the way the formulas specify.
  - Integration-level behavior: animation timing, input handling, actual
    collision detection for skillshots, network sync (§64).
```

The risk this split introduces is not "wrong tool" — it's **two independent
implementations of the same formulas silently drifting apart** (GDScript hardcodes
`100.0 / (100.0 + armor)` in one place, Python in another, and someone tunes one
without the other). Two safeguards:

1. **Shared data, not shared code.** Ability stats and formula constants live in the
   JSON schema (§57), loaded by both Python and Godot `Resource` files — neither side
   hardcodes ability numbers.
2. **A conformance suite.** A fixed set of scenarios (specific characters, seeded RNG,
   expected outcomes) that both the Python harness and an in-Godot GUT test execute
   and must match within tolerance. Run this in CI whenever either side's combat math
   changes — it's the canary for formula drift between the two languages.

---

# 66. Suggested Priority Order for Implementation

Given the existing Python-first testing culture (§20-51), sequence new work so
schema/state-machine land before content:

```text
1. Ability JSON Schema (§57) + validation in Fast Suite
2. Character State Machine (§56) + interrupt table as data
3. Cast cancellation / refund rules (§59)
4. Stacking rules (§60) — write the anti-perma-stun regression test immediately
5. Armor/Magic Pen + Ability Haste formulas (§61)
6. Device-agnostic input layer (§5.4) — intents, not devices, reach the rules;
   cheap now, expensive after two schemes have been hardcoded
7. Soft-lock targeting + per-device assist scaling (§55) — prototype early, this is
   core to the stated design goal and hardest to bolt on later
8. Passive ability schema (§62)
9. Networking authority decision (§64) — decide before writing engine-side netcode
10. PvE AI/threat model (§63)
11. Conformance suite between Python and GDScript (§65) — set up as soon as both
    sides have any combat math implemented, not after
```

Items 1–5 are pure data-model/formula work and can be fully unit-tested in Python
before any Godot integration, consistent with the existing "keep combat calculations
independent from Godot" principle (§21).
