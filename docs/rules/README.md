# Ruleset Implementation Roadmap

The MOBA combat ruleset in [`../pulp_moba_rpg_ruleset.md`](../pulp_moba_rpg_ruleset.md),
decomposed into 33 GitHub Issues (#20–#52) grouped into eight batches.

Batches run from a minimum vertical slice to the complete ruleset. Each is a coherent,
mergeable increment: the game builds, runs, and is playable at the end of every batch.

Written 2026-08-20. Issues are unassigned; nothing has been delegated to an agent yet.

---

## Architectural decisions taken across the whole backlog

These were settled before the Issues were written and are repeated as constraints inside
each one. They are not open for an implementation session to revisit.

| Decision | Rationale |
| --- | --- |
| All ruleset code lives in `rules/` at the repository root | Lifted wholesale into `addons/mikeys_game_bones` as `mikeys_game_rules_moba` later, without editing a file inside it |
| Nothing in `rules/` references `res://scripts/`, `res://scenes/`, or `res://resources/` | The dependency arrow points one way. Enforced by an automated contract test in #20 |
| `rules/` depends only on Godot 4 and the public `mikeys_game_bones` API | `addons/` is never modified by a ruleset Issue |
| Global `class_name` identifiers are prefixed `Moba` | Godot's class registry is flat and global; `Ability`, `Buff`, and `StatusEffect` would collide with the third-party addons this project intends to adopt |
| All rules state hangs off one `MobaCombatant` node, a child of `Actor` | Keeps the whole ruleset behind a single attachment point, and keeps game rules out of framework code per `AGENTS.md` |
| Combat math is pure and node-free, in `MobaFormulas` only | Unit-testable headless, and mirrorable by the Python harness |
| Game content is authored as `.tres` in the Godot inspector; a headless export produces JSON for Python only | §57 permits "JSON **or** converted Godot `Resource` files"; §65 requires shared *data*, not a shared format. Serves bones design goal 3, and typed `@export` fields make invalid enums unrepresentable rather than caught-by-test |
| Balance harness is Python in `sim/`, in this repository, with its own CI job | Settles the open question in `planned_features.md` §4.1. §65's second safeguard — a conformance suite — is #50 |
| `rules/data/generated/` is gitignored and regenerated on demand | Nothing stored means nothing can go stale. Godot is assumed present wherever the Python tests run — this is a Godot game, not a Python project |
| The balance pipeline is path-filtered to `rules/**` and `sim/**` | An asset or scene change cannot move a balance number, so it should not pay for a Godot download, an export, and a pytest run. Godot import/boot validation stays unfiltered and runs on everything. See #22 |
| Godot exports; Python never parses `.tres` | Godot serializes enums as integers. A Python-side int-to-name map mirroring five GDScript enums, with nothing verifying they agree, would be a silent wrong-numbers drift vector worse than the formula drift §65 is about |
| Ruleset UI lives in `rules/ui/` | A ruleset whose HUD lives elsewhere is not portable. Signals in, nothing out; no rules logic in UI |
| Game-flow UI is out of scope for the entire backlog | Main menu, pause, settings, host/join, character creation, loadout editor — a third-party addon is intended for these |
| Networking follows the existing `Actor.try_attack` / `_resolve_attack` shape | Server-authoritative resolve with client request already exists in the framework; #47 makes it real rather than retrofitting |

---

## Batch 0 — Foundations

Nothing else can start until these land. No gameplay.

| # | Title |
| --- | --- |
| [#20](https://github.com/stardustsuperwizard/sword-and-planet/issues/20) | Establish the rules/ module layout and extraction contract for mikeys_game_rules_moba |
| [#21](https://github.com/stardustsuperwizard/sword-and-planet/issues/21) | Ability and passive Resource definitions with JSON export tooling |
| [#22](https://github.com/stardustsuperwizard/sword-and-planet/issues/22) | Python balance harness scaffold and split Fast/Deep CI suites |

Covers §57, §62, §21, §48, §65. §66 implementation item 1.

**Data format.** Three kinds of file, defined in #21 and worth knowing before reading any
other Issue:

| Kind | Where | Committed |
| --- | --- | --- |
| Authored `.tres` — abilities, passives, weapons, loadouts, enemies, stat blocks | `rules/data/<kind>/` | yes |
| Authored `.json` — the §56 interrupt table, §55 device multipliers, §65 conformance fixtures | `rules/data/` | yes |
| Generated `.json` — the export Python reads | `rules/data/generated/` | **no, gitignored** |

Godot loads `.tres` directly and never reads the generated JSON. The export exists solely
so the Python harness needs no `.tres` parser.

**Human decision needed in #20:** confirm the `Moba` class name prefix before 33 Issues
adopt it.

---

## Batch 1 — Minimum vertical slice

The smallest thing that is recognisably the ruleset: press `1`, watch a real number come
out of real statistics, see it on screen. **If you only run one batch, run this one.**

| # | Title |
| --- | --- |
| [#23](https://github.com/stardustsuperwizard/sword-and-planet/issues/23) | Combat stat block and the MobaCombatant node |
| [#24](https://github.com/stardustsuperwizard/sword-and-planet/issues/24) | Damage resolution: damage types, mitigation, penetration, and critical hits |
| [#25](https://github.com/stardustsuperwizard/sword-and-planet/issues/25) | Character state machine with a data-driven interrupt table |
| [#26](https://github.com/stardustsuperwizard/sword-and-planet/issues/26) | Resource pool, cooldowns, charges, and ability haste |
| [#27](https://github.com/stardustsuperwizard/sword-and-planet/issues/27) | Ability resources, JSON loader, and the activation pipeline |
| [#28](https://github.com/stardustsuperwizard/sword-and-planet/issues/28) | Combat loadout: basic attack plus four equipped ability slots |
| [#29](https://github.com/stardustsuperwizard/sword-and-planet/issues/29) | Core combat HUD: health, resource, and ability slots |

Covers §4, §6, §7, §8, §9, §10, §11 (self and targeted only), §12, §13, §15, §56, §61.
§66 items 2 and 5.

Also closes `planned_features.md` §0.1 — #28 puts a hostile actor in `main.tscn`, which
makes `AttackAction`, `Rules.attack`, and `SimpleAIController` reachable at runtime for
the first time.

**At the end of this batch:** Power Strike works on a real enemy with a real damage
number, a real cooldown sweep, and a real resource cost.

---

## Batch 2 — Effects and full resolution

Everything the damage pipeline left as a documented seam.

| # | Title |
| --- | --- |
| [#30](https://github.com/stardustsuperwizard/sword-and-planet/issues/30) | Status effects, stat modifiers, and stacking policies |
| [#31](https://github.com/stardustsuperwizard/sword-and-planet/issues/31) | Crowd control effects and Tenacity |
| [#32](https://github.com/stardustsuperwizard/sword-and-planet/issues/32) | Sustain: lifesteal, omnivamp, healing, and shields |
| [#33](https://github.com/stardustsuperwizard/sword-and-planet/issues/33) | Cast time, channeled abilities, cancellation, and resource refunds |
| [#34](https://github.com/stardustsuperwizard/sword-and-planet/issues/34) | Death, the dead state, and respawn |
| [#35](https://github.com/stardustsuperwizard/sword-and-planet/issues/35) | Combat feedback HUD: cast bar, status tray, damage numbers, and target frame |

Covers §14, §16, §17, §18, §58, §59, §60. §66 items 3 and 4.

#31 contains the anti-perma-stun regression test §60 asks for by name. #34 fixes the
latent bug in `planned_features.md` §0.3 — `Actor.die()` calling `queue_free()` on the
player and dangling the camera's `target_path`.

---

## Batch 3 — Targeting and input

The batch §66 warns gets expensive if deferred.

| # | Title |
| --- | --- |
| [#36](https://github.com/stardustsuperwizard/sword-and-planet/issues/36) | Device-agnostic input intent layer |
| [#37](https://github.com/stardustsuperwizard/sword-and-planet/issues/37) | Targeting modes: skillshot, ground, area, toggle, and projectiles |
| [#38](https://github.com/stardustsuperwizard/sword-and-planet/issues/38) | Aim assist tiers and per-device magnetism scaling |
| [#39](https://github.com/stardustsuperwizard/sword-and-planet/issues/39) | Lock-on targeting, target cycling, and the aim reticle |
| [#40](https://github.com/stardustsuperwizard/sword-and-planet/issues/40) | Jump as a defined mechanic and the Airborne state |
| [#41](https://github.com/stardustsuperwizard/sword-and-planet/issues/41) | Gamepad camera look and a scheme-independent aim direction |

Covers §5.1, §5.2, §5.4, §5.5, §11 (the remaining four types), §55. §66 items 6 and 7.

Projectiles exist for the first time in the project here. #41 closes the gap in
`planned_features.md` §1.6 — the right stick currently turns the body rather than the
camera, so a gamepad player cannot aim independently of where they are walking.

---

## Batch 4 — Content and remaining ability mechanics

| # | Title |
| --- | --- |
| [#42](https://github.com/stardustsuperwizard/sword-and-planet/issues/42) | Dash and displacement abilities |
| [#43](https://github.com/stardustsuperwizard/sword-and-planet/issues/43) | Passive abilities |
| [#44](https://github.com/stardustsuperwizard/sword-and-planet/issues/44) | Prototype content: two weapons, eight abilities, four loadouts, four enemy profiles |

Covers §19, §42, §53, §62, and the `DASHING` row of §56. §66 item 8.

**Human decision needed in #43, before implementation starts:** §62 asks explicitly
whether passives are always-on traits tied to *learned* abilities, or whether some occupy
one of the four equipped slots. This changes the §50 build-generation combinatorics. The
Issue proposes an answer and says not to guess.

**At the end of this batch:** the §53 first prototype exists and is playable. This is the
point at which the question "is this combat model any good" can be answered.

---

## Batch 5 — PvE AI

| # | Title |
| --- | --- |
| [#45](https://github.com/stardustsuperwizard/sword-and-planet/issues/45) | PvE threat table and enemy target selection |
| [#46](https://github.com/stardustsuperwizard/sword-and-planet/issues/46) | Data-driven enemy ability policy |

Covers §63. §66 item 10.

Taunt from #31 finally has something to override, which is what makes Guardian's §3 role
work at all.

---

## Batch 6 — Networking

| # | Title |
| --- | --- |
| [#47](https://github.com/stardustsuperwizard/sword-and-planet/issues/47) | Server-authoritative combat resolution with client-side prediction |
| [#48](https://github.com/stardustsuperwizard/sword-and-planet/issues/48) | Lag compensation and the rewind window for skillshots |

Covers §64. §66 item 9.

Scheduled here rather than earlier because the existing code already has the right shape —
`Actor._resolve_attack()` is server-authoritative with client request, and every ruleset
Issue routes activation through `ActionRunner` and `Authority` for exactly this reason.
#47 also closes the per-peer spawn and despawn gap in `planned_features.md` §3.2.

---

## Batch 7 — Balance, conformance, and mobile

| # | Title |
| --- | --- |
| [#49](https://github.com/stardustsuperwizard/sword-and-planet/issues/49) | Python duel simulation and combat metrics |
| [#50](https://github.com/stardustsuperwizard/sword-and-planet/issues/50) | GDScript-to-Python conformance suite |
| [#51](https://github.com/stardustsuperwizard/sword-and-planet/issues/51) | Deep Balance Suite: build generation, matchup matrix, and balance reports |
| [#52](https://github.com/stardustsuperwizard/sword-and-planet/issues/52) | Touch control scheme and mobile combat HUD |

Covers §5.3, §20–§52 (the balance methodology), §65. §66 item 11.

**#50 can be pulled forward.** §66 lists the conformance suite last but adds a caveat that
overrides the ordering: "set up as soon as both sides have any combat math implemented,
not after." It technically becomes possible once #24 and #22 are both merged. Every
constraint in the earlier Issues — pure static formulas, seedable RNG, fixed-step
simulation, shared numeric expectations asserted in both languages — exists to make it
cheap when it lands.

---

## Reading the batches as escalating scope

If the whole backlog is more than you want to commit to, these are the natural stopping
points, each of which leaves the repository in a coherent state:

| Stop after | You get | Issues |
| --- | --- | --- |
| **Batch 1** | A minimum vertical slice: one ability, end to end, visible on screen, with real statistics behind it | 10 |
| **Batch 2** | Full combat resolution — effects, crowd control, sustain, casting, death — but targeted abilities only | 16 |
| **Batch 3** | All six targeting types, projectiles, aim assist, and all three control schemes' input model | 22 |
| **Batch 4** | The §53 first prototype, complete and playable. **The natural place to stop and judge the design** | 25 |
| **Batch 5** | Meaningful PvE with threat and enemy ability policies | 27 |
| **Batch 6** | Multiplayer combat | 29 |
| **Batch 7** | The complete ruleset, the balance harness, drift protection, and touch | 33 |

---

## Deliberately not in this backlog

- **Game-flow UI.** Main menu, pause, settings, host/join, character creation, and a
  loadout editor. A third-party addon is intended for these; loadouts are authored as data
  files until then.
- **Character progression.** No leveling, no ability learning, no discipline advancement.
  §54 says the initial ruleset has no character levels.
- **Equipment and inventory.** `planned_features.md` §1.5 tracks it separately.
- **Navigation and pathfinding.** `planned_features.md` §2.1. Dashes and AI chase are
  straight lines.
- **Art, animation, and audio.** Primitive meshes and placeholder shapes throughout.
- **Game Master mode.** `planned_features.md` §3.1. `Authority.can_perform()` remains its
  natural extension point and no Issue closes that off.
- **Mobile platform work beyond playability.** Renderer selection and performance budget
  are `planned_features.md` §1.8; #52 only covers running and playing.
- **The remaining §19 abilities** beyond the eight §53 names — Whirlwind, Taunt, Vanish,
  Execute, Deadeye, Rapid Fire, Mesmerize, Ground Slam, Hamstring, Trick Shot, Snare,
  Rally, Brace. Several land incidentally as test fixtures; a full content pass is future
  work.

---

## Notes on how these Issues are written

Each Issue follows `.github/ISSUE_TEMPLATE/01-feature.md` and adds sections aimed at a cold
implementation session, per `docs/AGENT_WORKFLOW.md`:

- **Depends on** — a header line, so dependency order is visible without opening the plan.
- **Notes for the Implementing Agent** — specific traps. Integer division in
  `100 / (100 + defense)`; Godot readying children before parents when seeding
  `character_sheet`; `max(remaining, new)` versus summing stun durations; slerp rather than
  lerp for aim magnetism; pooling floating combat text before an area ability hits five
  targets at once.
- **Ruleset References** — the exact sections each Issue implements.
- **Scenarios** — happy path, normal, boundary case, and invalid, per the template.

Where the ruleset leaves something genuinely undecided, the Issue names it as a decision to
be made and recorded rather than letting it be resolved by whichever implementation ran
first. Where `AGENTS.md` would call it a major game mechanic, the Issue escalates to a
human instead — #43 is the clearest case.
