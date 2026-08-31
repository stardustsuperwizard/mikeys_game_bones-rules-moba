# Mikey's Game Bones MOBA Rules

This repository is a MOBA built in Godot 4. Its combat ruleset lives as a
self-contained module in [`rules/`](rules/), with a Python balance harness in
[`sim/`](sim/) and the playable game in [`scenes/`](scenes/) and
[`scripts/`](scripts/).

`rules/` keeps a strictly one-way dependency arrow — the game depends on the
rules, never the reverse — enforced by `rules/tests/extraction_contract_test.gd`.
That isolation exists so client and server can run identical simulation, which
is what makes server-authoritative multiplayer tractable. Multiplayer is a
first-class feature of this game, not a later extension: #277 makes the
authority gate universal, #278 builds the session layer, and #47 resolves
combat on top of both.

Three modes share one ruleset and one character — arena brawler (base game),
PvE tower defense, and MOBA. See [`docs/GAME_MODES.md`](docs/GAME_MODES.md).

> **Revised 2026-08-30.** This was previously described as a portable rules
> engine "intended to be lifted wholesale into a Godot game project as a
> self-contained addon," depending on a `mikeys_game_bones` framework addon.
> #276 removes `addons/` entirely: what the game used is absorbed into its own
> source tree and the rest is deleted. This is a MOBA, not a framework host.
> See [`docs/rules/README.md`](docs/rules/README.md).

## Included Systems

- Combat statistics, damage resolution, cooldowns, resources, and effects.
- Ability and loadout data authored as Godot resources.
- Device-agnostic combat intents, targeting, and input constraints.
- AI, networking, state, UI, and data extension points needed by a MOBA combat
	ruleset.
- A Python harness for deterministic formula checks and statistical balance
	simulations.

## Repository Layout

| Path | Purpose |
| --- | --- |
| [`rules/`](rules/) | Portable Godot MOBA rules module. |
| [`sim/`](sim/) | Python balance harness and its tests. |
| [`docs/pulp_moba_rpg_ruleset.md`](docs/pulp_moba_rpg_ruleset.md) | Baseline combat design. |
| [`docs/rules/README.md`](docs/rules/README.md) | Implementation roadmap and issue batches. |
| [`AGENTS.md`](AGENTS.md) | Architecture and contribution constraints. |

## Development

Godot validation checks that resources and scripts load correctly:

```bash
.github/scripts/validate-godot.sh
```

Run the balance harness from the repository root:

```bash
pip install -e "./sim[dev]"
pytest sim/
```

The Python harness may invoke Godot to regenerate exported ability data. Set
`GODOT_BIN` when the Godot executable is not available on `PATH`. See
[`sim/README.md`](sim/README.md) for its full setup and test commands.

## Scope

This repository develops reusable combat rules and balance tooling only. A
consuming game owns its presentation, assets, scenes, progression, narrative,
and other game-specific systems. The former Mikey's Game Bones MOBA Rules RPG now lives in a
separate repository.
