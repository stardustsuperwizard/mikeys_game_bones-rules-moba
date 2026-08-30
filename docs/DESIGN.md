# Mikey's Game Bones MOBA Rules - Design

## Concept

Mikey's Game Bones MOBA Rules is a portable, mechanics-first combat rules
engine for Godot 4. The GDScript module in `rules/` and Python harness in
`sim/` are designed to be reused by consuming games without coupling to a
specific setting, world, asset set, or narrative.

The baseline combat specification is maintained in
[`pulp_moba_rpg_ruleset.md`](pulp_moba_rpg_ruleset.md). Its setting-specific
examples are illustrative only; they do not define content for this repository.

## Design Authority

Combat mechanics, data schemas, and balance targets are human-directed.

AI agents may implement specifications but should not invent major mechanics,
game-specific content, or architectural direction unless explicitly asked to
propose options.

## Current Development Principle

Build the smallest portable rules systems needed to test the combat model.

Avoid abstractions until real rules-engine behavior demonstrates that they are
needed. A consuming game owns presentation, scenes, progression, and narrative.