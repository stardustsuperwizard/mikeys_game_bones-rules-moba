# Pulp MOBA-Inspired RPG Ruleset — Baseline Design

## Purpose

This document defines a starting combat ruleset for a computer role-playing game that supports both single-player and multiplayer play.

The design goals are:

- Fast-paced real-time combat.
- MOBA-style movement, positioning, targeting, skillshots, cooldowns, and crowd control.
- Gamepad-friendly controls.
- Classless character development.
- A small equipped combat kit rather than large MMO-style action bars.
- A pulp-adventure tone, with Barsoom as the primary inspiration while remaining flexible enough to support other public-domain adventure, fantasy, science-fiction, occult, lost-world, and weird-fiction settings.
- No character leveling in the initial ruleset.
- Enough numerical structure to allow automated balance testing.

This is intentionally a baseline. The objective is not to solve every RPG design problem before implementation. The rules should first produce enjoyable combat and then be iterated through playtesting and simulation.

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

A — Power Strike      [Warrior]
B — Parry             [Warrior]
X — Lunge             [Slayer]
Y — Shield Bash       [Guardian]
```

This character is not assigned a class.

The equipped loadout causes the character to behave like a mobile melee bruiser.

Another loadout using the same learned abilities might completely alter that combat role.

---

# 5. Gamepad-Oriented Combat

The ruleset should be designed around a controller rather than adapting controller input after the combat system has already been built.

A possible baseline mapping:

| Input | Action |
|---|---|
| Left Stick | Movement |
| Right Stick | Camera / aiming |
| Right Trigger | Basic attack |
| A | Ability 1 |
| B | Ability 2 |
| X | Ability 3 |
| Y | Ability 4 |
| Left Bumper | Contextual defense / utility |
| Right Bumper | Targeting / lock-on |
| D-Pad | Items, weapon swap, or non-core utility |

The exact mapping can change during implementation.

The important rules constraint is that the primary combat kit remains easily accessible without modifier-button gymnastics.

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

That is enough to start discovering whether the fundamental combat model works.

---

# 54. Summary

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
Gamepad-first controls
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
