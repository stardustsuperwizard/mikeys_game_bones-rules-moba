## Root module for MOBA combat ruleset implementation.
## This module is a self-contained package with a one-way dependency arrow:
## the game depends on the rules, never the reverse. All code here follows strict architectural constraints:
## - No outward references to res://scripts/, res://scenes/, or res://resources/
## - Dependencies only on Godot 4 and the game's shared types
## - All global class_name identifiers prefixed with "Moba"
class_name MobaRules

## Semantic version of the MOBA rules module implementation.
const VERSION := "0.1.0"

## Root path for hand-authored rule data (.tres and .json files).
const DATA_ROOT := "res://rules/data/"

## Root path for Python-generated JSON exports (gitignored at runtime).
const GENERATED_ROOT := "res://rules/data/generated/"

## Static instance of a seedable RandomNumberGenerator used for all crit rolls.
## Deterministic replay (§34) and conformance suite testing require that crit rolls
## go through this seeded instance, never the global randf().
static var _crit_rng := RandomNumberGenerator.new()

## Static instance of a seedable RandomNumberGenerator used for blind miss rolls.
## Mirrors the crit_rng pattern for deterministic testing and replay.
static var _blind_rng := RandomNumberGenerator.new()


## Seed the crit RNG for deterministic replay.
static func seed_crit_rng(seed: int) -> void:
	_crit_rng.seed = seed


## Draw a random roll from the crit RNG.
## Returns a value in [0.0, 1.0).
static func roll_crit() -> float:
	return _crit_rng.randf()


## Seed the blind miss RNG for deterministic replay.
static func seed_blind_rng(seed: int) -> void:
	_blind_rng.seed = seed


## Draw a random roll from the blind miss RNG.
## Returns a value in [0.0, 1.0).
static func roll_blind() -> float:
	return _blind_rng.randf()
