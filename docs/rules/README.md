# Ruleset Implementation Roadmap

The MOBA combat ruleset in [`../pulp_moba_rpg_ruleset.md`](../pulp_moba_rpg_ruleset.md),
decomposed into 33 GitHub Issues (#20–#52) grouped into eight batches, plus three
Issues (#276–#278) added by the 2026-08-30 revision and five (#280–#284) by the
2026-08-31 revision.

Batches run from a minimum vertical slice to the complete ruleset. Each is a coherent,
mergeable increment: the game builds, runs, and is playable at the end of every batch.

Written 2026-08-20.

**Revised 2026-08-30** — execution order changed; four architectural decisions corrected.
**Revised again 2026-08-31** — three decisions added (no third-party addons; three modes, one
ruleset, one character; character creation as a design pillar), and the game-flow UI row
revised a second time. See `docs/GAME_MODES.md` for the mode architecture.

On the 2026-08-30 change:
Multiplayer is now a first-class feature of this game rather than a later extension, so
networking moves ahead of the remaining content, input-polish, and PvE batches. A
repository audit also invalidated the stated premise for scheduling networking last, and
disproved two of the architectural decisions recorded below. See **Execution order** and
the corrected rows in the table that follows.

---

## Architectural decisions taken across the whole backlog

These were settled before the Issues were written and are repeated as constraints inside
each one. They are not open for an implementation session to revisit.

| Decision | Rationale |
| --- | --- |
| All ruleset code lives in `rules/` at the repository root | ~~Lifted wholesale into `addons/mikeys_game_bones` as `mikeys_game_rules_moba` later, without editing a file inside it~~ **Superseded by #276.** `rules/` stays a coherent module with a one-way dependency arrow, and the extraction contract test still enforces that — but it is no longer destined for an addon. This repository is a MOBA, not a framework host |
| Nothing in `rules/` references `res://scripts/`, `res://scenes/`, or `res://resources/` | The dependency arrow points one way. Enforced by an automated contract test in #20 |
| `rules/` depends only on Godot 4 and the game's own source tree | **Revised by #276**, which deletes `addons/` entirely. What the MOBA used is absorbed into the game; the rest is deleted. There is no addon to depend on or to avoid modifying |
| Global `class_name` identifiers are prefixed `Moba` | ~~`Ability`, `Buff`, and `StatModifier` would collide with the third-party addons goal 4 commits to adopting, and this module ships into other projects~~ **Both rationales are now void** — #276 ends the ship-into-other-projects plan, and the project takes no third-party addons (row below). The prefix stays anyway, on a weaker but honest argument: it makes the `rules/` module boundary legible at every call site, and renaming ~100 classes is a large, risky, zero-value refactor. Keep by inertia, not by argument. `.tres` authoring requires a registered `class_name`, so `preload()` constants are not an available dodge |
| All rules state hangs off one `MobaCombatant` node, a child of `Actor` | Keeps the whole ruleset behind a single attachment point, and keeps game rules out of framework code per `AGENTS.md` |
| Combat math is pure and node-free, in `MobaFormulas` only | Unit-testable headless, and mirrorable by the Python harness |
| Game content is authored as `.tres` in the Godot inspector; a headless export produces JSON for Python only | §57 permits "JSON **or** converted Godot `Resource` files"; §65 requires shared *data*, not a shared format. Serves bones design goal 3, and typed `@export` fields make invalid enums unrepresentable rather than caught-by-test |
| Balance harness is Python in `sim/`, in this repository, with its own CI job | Settles the open question in `planned_features.md` §4.1. §65's second safeguard — a conformance suite — is #50 |
| `rules/data/generated/` is gitignored and regenerated on demand | Nothing stored means nothing can go stale. Godot is assumed present wherever the Python tests run — this is a Godot game, not a Python project |
| The balance pipeline is path-filtered to `rules/**` and `sim/**` | An asset or scene change cannot move a balance number, so it should not pay for a Godot download, an export, and a pytest run. Godot import/boot validation stays unfiltered and runs on everything. See #22 |
| Godot exports; Python never parses `.tres` | Godot serializes enums as integers. A Python-side int-to-name map mirroring five GDScript enums, with nothing verifying they agree, would be a silent wrong-numbers drift vector worse than the formula drift §65 is about |
| Combat kit is 4 action slots + 1 dedicated passive slot; passives never compete for an action slot | §62's open question, answered on #43. A dedicated slot makes `occupies_equipped_slot` a field with one legal value, so it is never added |
| Aim assist multipliers are anchored on **touch** at 1.0x, not gamepad — a deliberate deviation from §55 | Ratios are unchanged; it is a change of units. But with gamepad at 1.0x and touch at 1.5x, everything above 0.667 authored clamps on touch — including §55's own 0.7 for dashes — so distinct abilities collapse to full lock on the least precise device. Anchoring on touch means no multiplier exceeds 1.0 and the clamp can never fire. See #38 |
| Touch is the design target; keyboard + mouse stays the development scheme | §5 already says a mechanic that cannot be executed on all three is a rules problem, and §57 treats `touch_viable: false` as a design smell. Designing to the narrowest input and developing on the widest are not in conflict |
| **No third-party addons** | Decided 2026-08-31. The project builds what it needs. This reverses bones design goal 4 ("use components that already exist in the wild") for this repository: that goal served a reusable framework, and #276 ended the framework. Practical effect — game-flow UI, character creation, and the loadout editor are this project's work, not a plugin's |
| **Three modes, one ruleset, one character** | Decided 2026-08-31. Arena brawler (base game), PvE tower defense (expansion), MOBA (expansion). Combat, abilities, targeting, effects, identity, and the session layer are built once and shared; each mode adds only its own structure and content. Sequenced arena → tower defense → MOBA by marginal cost, and because TD builds the economy and stationary-attacker content MOBA also needs, on a smaller surface. **Consequence for #277: its authority gate must be a general command taxonomy, not three hardcoded verbs** — every mode adds commands (buy item, level ability, place tower) that need the same gate. See `docs/GAME_MODES.md` |
| **Character creation is a design pillar, not deferred UI** | Decided 2026-08-31. The player has a character that is *theirs* rather than one borrowed from a roster — named, dressed, statted, kept. Presets and starting templates are explicitly allowed as the front door (picking "Warrior" then making it yours is how D&D works); #44's loadouts are starting builds, not a competing roster. This is not a new direction: it is ruleset §2 (Classless Character Design) and §54 ("These are not classes. They are pools of abilities that can be combined freely"), and the data model already carries it — `MobaAbility.Discipline` enumerates all six §3 disciplines and every authored ability declares one. What is missing is the player-facing surface. With §54's "no character levels initially", creation is the *only* moment a player makes build choices, which makes it the build system rather than a pre-game formality |
| Ruleset UI lives in `rules/ui/` | A ruleset whose HUD lives elsewhere is not portable. Signals in, nothing out; no rules logic in UI |
| Game-flow UI is in scope, built in-house | **Revised twice.** Originally "out of scope for the entire backlog … a third-party addon is intended for these." Host/join, main menu, and pause came in scope with #278 — a first-class multiplayer feature cannot have its only entry point declared out of scope. Character creation and the loadout editor came in scope as the design pillar above. Nothing here is deferred to a plugin: the project takes no third-party addons. Settings remains unscheduled, but it is deferred, not excluded |
| Networking follows the request-and-resolve shape recorded by #276 | ~~Server-authoritative resolve with client request already exists in the framework~~ **The premise was false.** `Actor._resolve_attack()` is unreachable in the shipped game — both controllers return `null` from `get_attack_target()` when a `MobaCombatant` is present, and both production scenes have one. #276 deletes it, after recording the pattern in `docs/`. The shape is still right; it was never actually in service |

---

## Execution order

**Revised 2026-08-30.** Batches keep their names, membership, and internal coherence. What
changed is the order they run in.

Multiplayer is a first-class feature of this game, not an extension of the single-player
build. Single-player against bots remains fully supported and must not regress — it becomes
one session mode of a multiplayer game rather than the default that networking is bolted
onto later. The backlog as written encoded the opposite, scheduling networking second-to-last.

| Order | Batch | Issues | Status |
| --- | --- | --- | --- |
| 1 | 0 — Foundations | #20–#22 | done |
| 2 | 1 — Minimum vertical slice | #23–#29 | done |
| 3 | 2 — Effects and full resolution | #30–#35 | done |
| 4 | 3 — Targeting and input *(partial)* | #36–#38 | #36, #37 done; #38 in flight |
| 5 | **6a — Framework removal and the authority chokepoint** | **#276, #277** | **new** |
| 6 | **6b — Multiplayer session layer** | **#278** | **new** |
| 7 | **6c — Server-authoritative combat** | **#47, #48** | moved forward |
| 8 | **Arena completion — identity and match shape** | **#280, #281, #282, #283** | **new** |
| 9 | 3 — Targeting and input *(remainder)* | #39, #40, #41 | deferred |
| 10 | 4 — Content and remaining ability mechanics | #42, #43, #44 | deferred |
| 11 | 5 — PvE AI | #45, #46 | deferred |
| 12 | **6d — PvE tower defense (expansion)** | **#284** | **new** |
| 13 | 7 — Balance, conformance, and mobile | #49–#52 | unchanged |
| — | MOBA mode (expansion) | *not yet filed* | — |

**Order 8 is what turns multiplayer combat into a game.** #281 gives a match its shape
(best-of-N rounds), #280 gives the player a character that is theirs, and #282 and #283 make
that character visible to other people. Combat without them is a sandbox; with them the
arena is shippable.

**Order 12 sits after Batch 5** because tower defense wants #45's threat model — creeps
choosing between towers and the player is exactly the PvE target-selection problem — and
because `docs/GAME_MODES.md` gates it: **arena ships complete before tower defense starts.**

**MOBA mode has no Issue yet.** It is the third expansion in `docs/GAME_MODES.md` and is
deliberately unfiled: it is the most expensive of the three and its shape depends on what the
arena and tower defense modes teach. #47 and #48 are its *combat networking*, not the mode.

### Why networking moved

**The stated reason for deferring it was factually wrong.** Batch 6 was scheduled late
because "the existing code already has the right shape — `Actor._resolve_attack()` is
server-authoritative with client request, and every ruleset Issue routes activation through
`ActionRunner` and `Authority` for exactly this reason." A repository audit found neither
half holds:

- `Actor._resolve_attack()` is unreachable in the shipped game and is deleted by #276.
- Of the three player-originated commands, only ability activation passes through
  `ActionRunner` → `Authority`. Basic attack and cast-cancel call `MobaCombatant` mutators
  directly. `Authority.can_perform()` is itself inert — `Actor.owner_id` is `0` in both
  production scenes and never assigned outside test fixtures, so it returns `true`
  unconditionally.

So the argument that deferred networking was an argument that the work was *already mostly
done*. It is not started. #277 is what makes the latent structure real.

**§64 argues for doing it early anyway.** It calls the authority model "decision-critical
before any multiplayer combat code is written" and "worth locking in before §55–59 get
implemented in the engine layer, since retrofitting authority models is expensive."
Deferring to Batch 6 was in tension with the ruleset's own guidance from the start.

### What the reorder costs

`#47 Depends on: #44`, which depends on #42 and #43 — all deferred behind it now. That
dependency is **soft**: #44 is data authoring (two weapons, eight abilities, four loadouts,
four enemy profiles), and #47 needs *an* ability and *a* skillshot to test against, not the
full prototype set. Power Strike, Shield Bash, projectiles, aim assist, and the melee
bruiser loadout all already exist. Multiplayer combat can be built and tested on them.

Two genuine couplings remain, and they are costs rather than blockers:

- **#40 (jump and the Airborne state)** — movement prediction and reconciliation must cover
  every movement mode. Landing jump after prediction means extending it.
- **#42 (dash and displacement)** — #47's own notes flag that §64 makes server-side dash
  path validation a consequence of the authority decision.

Extending a correct authority model to cover a new movement mode is substantially cheaper
than retrofitting authority onto four movement modes that already shipped, which is exactly
what §64 warns about. Both #40 and #42 should carry an acceptance criterion for prediction
and server-side validation coverage when they land.

---

## Batch 0 — Foundations

Nothing else can start until these land. No gameplay.

| # | Title |
| --- | --- |
| [#20](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/20) | Establish the rules/ module layout and extraction contract for mikeys_game_rules_moba |
| [#21](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/21) | Ability and passive Resource definitions with JSON export tooling |
| [#22](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/22) | Python balance harness scaffold and split Fast/Deep CI suites |

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

**Confirmed 2026-08-20 on #20:** the `Moba` prefix is adopted. The repository now carries
two naming conventions deliberately — `rules/` carries the `Moba` prefix and `scripts/` keeps
bare names (`Actor`, `Rules`, `Door`, `CharacterSheet`) and are not renamed.

---

## Batch 1 — Minimum vertical slice

The smallest thing that is recognisably the ruleset: press `1`, watch a real number come
out of real statistics, see it on screen. **If you only run one batch, run this one.**

| # | Title |
| --- | --- |
| [#23](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/23) | Combat stat block and the MobaCombatant node |
| [#24](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/24) | Damage resolution: damage types, mitigation, penetration, and critical hits |
| [#25](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/25) | Character state machine with a data-driven interrupt table |
| [#26](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/26) | Resource pool, cooldowns, charges, and ability haste |
| [#27](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/27) | Ability resources, JSON loader, and the activation pipeline |
| [#28](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/28) | Combat loadout: basic attack plus four equipped ability slots |
| [#29](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/29) | Core combat HUD: health, resource, and ability slots |

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
| [#30](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/30) | Status effects, stat modifiers, and stacking policies |
| [#31](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/31) | Crowd control effects and Tenacity |
| [#32](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/32) | Sustain: lifesteal, omnivamp, healing, and shields |
| [#33](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/33) | Cast time, channeled abilities, cancellation, and resource refunds |
| [#34](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/34) | Death, the dead state, and respawn |
| [#35](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/35) | Combat feedback HUD: cast bar, status tray, damage numbers, and target frame |

Covers §14, §16, §17, §18, §58, §59, §60. §66 items 3 and 4.

#31 contains the anti-perma-stun regression test §60 asks for by name. #34 fixes the
latent bug in `planned_features.md` §0.3 — `Actor.die()` calling `queue_free()` on the
player and dangling the camera's `target_path`.

---

## Batch 3 — Targeting and input

The batch §66 warns gets expensive if deferred.

| # | Title |
| --- | --- |
| [#36](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/36) | Device-agnostic input intent layer |
| [#37](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/37) | Targeting modes: skillshot, ground, area, toggle, and projectiles |
| [#38](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/38) | Aim assist tiers and per-device magnetism scaling |
| [#39](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/39) | Lock-on targeting, target cycling, and the aim reticle |
| [#40](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/40) | Jump as a defined mechanic and the Airborne state |
| [#41](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/41) | Gamepad camera look and a scheme-independent aim direction |

Covers §5.1, §5.2, §5.4, §5.5, §11 (the remaining four types), §55. §66 items 6 and 7.

Projectiles exist for the first time in the project here. #41 closes the gap in
`planned_features.md` §1.6 — the right stick currently turns the body rather than the
camera, so a gamepad player cannot aim independently of where they are walking.

---

## Batch 4 — Content and remaining ability mechanics

| # | Title |
| --- | --- |
| [#42](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/42) | Dash and displacement abilities |
| [#43](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/43) | Passive abilities |
| [#44](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/44) | Prototype content: two weapons, eight abilities, four loadouts, four enemy profiles |

Covers §19, §42, §53, §62, and the `DASHING` row of §56. §66 item 8.

**§62's design question is answered** (2026-08-20, recorded on #43): a passive never
occupies an action slot, and the player **selects one** into a dedicated fifth slot. The
combat kit is *basic attack + 4 action abilities + 1 selected passive*, with temporary
passives rendering beside the selected one. This makes the §50 build space a product,
`(N choose 4) x (M choose 1)`, rather than a single combination — #51 reflects that.

**At the end of this batch:** the §53 first prototype exists and is playable. This is the
point at which the question "is this combat model any good" can be answered.

---

## Batch 5 — PvE AI

| # | Title |
| --- | --- |
| [#45](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/45) | PvE threat table and enemy target selection |
| [#46](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/46) | Data-driven enemy ability policy |

Covers §63. §66 item 10.

Taunt from #31 finally has something to override, which is what makes Guardian's §3 role
work at all.

---

## Batch 6 — Networking

| # | Title |
| --- | --- |
| [#47](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/47) | Server-authoritative combat resolution with client-side prediction |
| [#48](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/48) | Lag compensation and the rewind window for skillshots |

Covers §64. §66 item 9.

**Moved forward — see Execution order.** This batch now runs directly after the
targeting-and-input work that is already in flight, ahead of the remaining Batch 3, 4, and
5 issues.

It also gained two prerequisites the original plan assumed were already satisfied:

| # | What it delivers | Why #47 needs it |
| --- | --- | --- |
| #276 | Deletes `addons/`; absorbs what the MOBA uses into the game | #47 twice instructs the implementer to read and match `Actor._resolve_attack()`. That code is dead and is deleted here, after the request-and-resolve pattern is recorded in `docs/` |
| #277 | Routes every player-originated command through `ActionRunner` → `Authority`, and gives the gate a real `owner_id` to check | #47 assumes this chokepoint exists. Today one of three commands passes through it |
| #278 | Transport, peer lifecycle, state replication, host/join entry points | #47 resolves combat on top of a session layer that does not currently exist. There is no `MultiplayerSynchronizer` anywhere in the project, and nothing connects `peer_connected` |

**Scope correction.** #47 carries an acceptance criterion for per-peer spawn and despawn,
which #278 also claims. #278 owns peer lifecycle; #47 should drop that criterion, which
already sits oddly against its own Out of Scope list.

---

## Batch 7 — Balance, conformance, and mobile

| # | Title |
| --- | --- |
| [#49](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/49) | Python duel simulation and combat metrics |
| [#50](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/50) | GDScript-to-Python conformance suite |
| [#51](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/51) | Deep Balance Suite: build generation, matchup matrix, and balance reports |
| [#52](https://github.com/stardustsuperwizard/mikeys_gamebones-rules-moba/issues/52) | Touch control scheme and mobile combat HUD |

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
| **Batch 3** *(partial)* | Skillshot, ground, area and toggle targeting, projectiles, aim assist, and the device-agnostic input layer | 19 |
| **Batch 6** | Multiplayer: a host and clients in one session, with server-authoritative combat | 24 |
| **Arena complete** | A character that is yours, a match with a shape, and a lobby to stand in as them. **The point at which this is the game it claims to be** | 28 |
| **Batch 3 remainder** | Lock-on and the reticle, jump and Airborne, gamepad camera look | 31 |
| **Batch 4** | The §53 first prototype, complete and playable. **The natural place to stop and judge the design** | 34 |
| **Batch 5** | Meaningful PvE with threat and enemy ability policies | 36 |
| **Tower defense** | The second mode: waves, towers, and your champion, solo or co-op | 37 |
| **Batch 7** | The complete ruleset, the balance harness, drift protection, and touch | 41 |

Counts are cumulative over all 41 filed Issues — the original 33 (#20–#52), plus #276–#278
and #280–#284. The **Batch 3** row is now *partial* (#36–#38 only): the reorder moved #39–#41
after multiplayer, so stopping at Batch 6 means stopping with three of Batch 3's six Issues
done. **The previous edition of this table double-counted them, which put every row below it
one too high.**

Batch 6 now precedes the Batch 3 remainder, Batch 4, and Batch 5 — see **Execution order**.

---

## Deliberately not in this backlog

- **Settings UI.** Deferred, not excluded, and built in-house when it is scheduled —
  the project takes no third-party addons. Host/join, main menu, and pause moved in scope
  with #278; character creation and the loadout editor moved in scope as a design pillar.
  Loadouts stay authored as `.tres` until the creation surface lands.
- **Character progression.** No leveling, no ability learning, no discipline advancement.
  §54 says the initial ruleset has no character levels. **This is not the same as character
  creation**, which is in scope — §54's "no character levels" is precisely what makes
  creation-time choice the whole build system rather than an opening move.
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
