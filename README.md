# Mikey's Game Bones MOBA Rules

`mikeys_gamebones-rules-moba` is a portable MOBA combat rules engine for Godot
4. It contains a reusable GDScript rules module in [`rules/`](rules/) and a
Python balance harness in [`sim/`](sim/). It is not a complete game, and it does
not include game-specific scenes, content, assets, or world design.

The rules module is intended to be lifted wholesale into a Godot game project
as a self-contained addon. It depends only on Godot 4 and the public
`mikeys_game_bones` API.

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
