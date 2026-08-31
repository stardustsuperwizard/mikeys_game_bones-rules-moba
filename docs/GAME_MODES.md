# Game Modes

One character, one ruleset, three modes. This document records what is shared, what
each mode adds, and the seams that must stay general so a mode can be added without
reopening the core.

Written 2026-08-31. Companion to `docs/rules/README.md` (implementation roadmap) and
`docs/pulp_moba_rpg_ruleset.md` (combat rules).

---

## The through-line

**A character that is yours, not one you borrow.**

In League you pick Ahri; she is not yours, every Ahri is identical, and you give her
back at the end. In World of Warcraft, Dungeons & Dragons, or Guild Wars you have *your*
character — named, dressed, statted by you, persistent, and you show up as them.

That is the product. Every mode below exists to give that character somewhere to go, and
the reason to stand in the lobby is that the character standing there is yours.

**Presets and templates are not in tension with this.** Picking "Warrior" as a starting
template and then naming, dressing, and tuning it is exactly how D&D character creation
works. Templates are the front door, not a competing model — they give a new player the
onboarding ramp a champion roster would, without taking ownership away.

**Stat optimisation is a feature, not a complexity cost.** Working out which combination
is best — or best *for you* — is half the fun of D&D, Warhammer 40,000, and Guild Wars
build theorycrafting. It is the retention loop, and it is why a player opens the game when
they do not have time for a match.

### Guild Wars 1 is the closest reference

The ability-picking model comes from it, and it solved several problems this design hits:

| GW1 | Here |
| --- | --- |
| **Primary and secondary profession; skills drawn from both** | **Primary and secondary Discipline; four action abilities drawn from both (#280 D1)** |
| 8 skill slots from a pool of hundreds | 4 action slots + 1 passive, from six Disciplines (§4, §3) |
| Build theorycrafting *was* the metagame | The intended retention loop |
| Attributes freely re-set outside combat | Stats freely respecable between matches (#280 D2) |
| PvP characters created instantly at max power | Everything available from the start; no grind to be competitive (#280 D6) |
| Skills unlocked account-wide, not per character | **Deferred** — the model if a progression hook is ever wanted, and it adds progression without character levels, keeping §54 intact |

**The character system is decided** (#280, 2026-08-31): one primary and one secondary
Discipline, abilities from those two only, a modest respecable stat pool on top of the §6
baseline, free weapon choice, fully editable between matches, and templates shipped as data
rather than as a class concept. Six Disciplines gives 30 ordered pairs — a roster-sized
identity space nobody had to author.

The accepted cost is that a three-Discipline build is illegal. Taken deliberately: an
unconstrained pick offers no *decision*, only "find the best four", and converges on one
build. Constraint is what makes optimisation fun.

---

## The shared core — built once, used by every mode

Everything below already exists and is mode-agnostic. No mode may fork it.

| System | Where |
| --- | --- |
| Damage resolution, types, mitigation, penetration, crits | `MobaDamage`, `MobaFormulas` (§7, §8, §15) |
| Cooldowns, charges, resources, ability haste | `MobaCooldowns`, `MobaCombatant` (§12, §13) |
| Ability activation pipeline and typed failures | `MobaAbilityAction`, `MobaAbilityCaster` |
| Targeting: self, targeted, skillshot, ground, area, toggle | `MobaTargeting`, `MobaProjectile` (§11) |
| Status effects, stat modifiers, stacking policies | `MobaEffectContainer` (§16) |
| Crowd control and Tenacity | `MobaCrowdControlTracker` (§14) |
| Sustain: lifesteal, omnivamp, healing, shields | `MobaCombatant` (§16) |
| State machine and interrupt table | `MobaStateMachine` (§56) |
| Death and respawn | `MobaDeathHandler` |
| Device-agnostic input, aim assist | `MobaInputRouter`, `MobaAimAssist` (§5) |
| Combat HUD | `rules/ui/` |
| Character creation, identity, cosmetics | #280 |
| Authority gate, transport, session layer, lobby | #277, #278 |

**The character is shared too.** The same built character enters every mode. A build that
is fun in the arena should be recognisably the same character defending a lane.

---

## Mode 1 — Arena (the base game)

Team arena brawler. Best-of-N rounds, full reset between rounds. Both sides at full power
from the first second: no in-match progression, no economy, no map objectives.

The match arc comes from the **series**, not from power growth inside a fight — the
answer ruleset §54's "no character levels" points at, and the one that costs least.

**Adds over the shared core:** round lifecycle (start, win condition, reset, series
score), an arena map, and the lobby that leads into it.

**Status:** the closest to done. Combat is built; rounds and the lobby are not.

---

## Mode 2 — PvE Tower Defense (expansion)

Kingdom Rush-shaped. Waves follow a fixed route; the player places towers at build slots
and spends earned gold. Single-player on a phone, or started as a team from the lobby.

**Your champion fights alongside the towers.** This is a deliberate design constraint, not
a detail: a pure commander's-eye tower defense would make the character — the entire point
of the product — irrelevant in one of its three modes. Towers plus your own built character
keeps the through-line intact, and is *cheaper*, because the character already works.

**Why this is inexpensive here:** a tower is a `MobaCombatant` with a weapon and no
`Controller`. Combat in this codebase is a **component**, not a base class, so a stationary
attacker needs no new entity type — `MobaBasicAttackCycle.start(target)` already drives an
attack with no controller, no body movement, and no `Actor` beyond a null-guarded sheet
mirror. (Compare Heroes of Newerth, which needed `IBuildingEntity : IUnitEntity` as its own
class in a deep inheritance chain.)

Damage types against armoured creeps, slows and stuns, area abilities, projectiles, and
effect stacking are all the shared core, unchanged.

**Adds over the shared core:**

- **Waypoint pathing.** The cheap kind — Godot's `Path3D` / `PathFollow3D` along an
  authored route, not A\*. Note the repository has *no* navigation of any kind today
  (`planned_features.md` §2.1: click-to-move and AI chase are straight lines), so this is
  the first pathing in the project.
- Wave scheduling as authored data, spawning through the existing `WorldManager` /
  `SpawnPoint` path.
- Build slots and tower placement UI.
- A gold economy.
- A leak / lose condition.
- Tower content and creep profiles.

**Mobile is a first-class target for this mode.** Touch is already the design target
(§5.3, and the aim-assist multipliers are anchored on touch), and tower defense is the most
touch-native of the three.

---

## Mode 3 — MOBA (expansion)

Lanes, creeps, towers, items, a win condition. The mode the ruleset is named for and the
most expensive of the three.

**Adds over the shared core:** in-match progression — abilities change during the match and
the player carries a temporary inventory — plus the map, creeps, structures, and an economy.

**The in-match progression seams already exist:**

| What the mode needs | State today |
| --- | --- |
| Swap the loadout mid-match | `MobaCombatant.loadout` setter duplicates and re-registers — works |
| Add or upgrade an ability mid-match | `register_ability()` is a keyed dict write — idempotent, works |
| Temporary item stats | `apply_stat_modifier()` → `MobaEffectContainer`, with stacking and durations — items are one more modifier source with a different lifetime |

So "abilities change and you get a temporary inventory" is content and UI on top of seams
#28 and #30 already built, not a new system.

---

## Sequencing, and why

**Arena → Tower Defense → MOBA.**

Marginal cost over what exists today, cheapest first:

1. **Arena** — combat is built. Needs rounds and a lobby.
2. **Tower Defense** — reuses combat wholesale. Adds waypoint pathing, waves, placement,
   and an economy.
3. **MOBA** — everything TD adds, plus lanes, creeps, structures, items, and a win
   condition, and it is the mode most sensitive to balance.

Tower Defense before MOBA is deliberate: **TD builds the economy and the stationary-attacker
content that MOBA mode also needs**, on a smaller and more forgiving surface. Doing MOBA
second would build both under harder constraints.

### The seam that keeps expansions cheap

**#277's authority gate must be a general command taxonomy, not three hardcoded verbs.**

Every mode adds player-originated commands — *buy item*, *level ability*, *place tower*,
*sell tower* — and each must pass the same gate as *attack* and *cast*. If #277 lands with
a command abstraction, each expansion registers its verbs and inherits server authority for
free. If it hardcodes today's three, every expansion reopens it.

This is the single highest-leverage decision in this document.

---

## The honest risk

Three modes is three games' worth of **content, balance, and UI**, even when the engine is
shared. The engine genuinely is shared — that part of this plan is sound and the seams are
real. What does not amortise is authored content, a balance pass per mode, and the
mode-specific interface.

The failure this invites is three modes at 60% and nothing shipped.

**Mitigation:** arena is finished and playable — rounds, lobby, and a content set a player
would actually spend an evening with — before tower defense starts. Each mode ships before
the next begins. The modes are expansions in build order, not parallel tracks.

Two costs that are easy to underestimate, and neither has a ticket today:

- **The lobby is a persistent networked social space**, not a menu. Continuous presence,
  join/leave churn, more concurrent players than a match, and it is up while nothing else
  is happening. Plausibly harder than an arena match.
- **The entire appearance system today is `Actor.color`** — one `Color` on a primitive
  capsule. "Armor, clothing, colours, name" needs an art pipeline and a customisation
  system that does not exist in any form, and it is what makes the lobby worth standing in.
