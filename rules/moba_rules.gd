## Root module for MOBA combat ruleset implementation.
## This module is designed to be extracted wholesale into addons/mikeys_game_rules_moba
## without editing a single file. All code here follows strict architectural constraints:
## - No outward references to res://scripts/, res://scenes/, or res://resources/
## - Dependencies only on Godot 4 and addons/mikeys_game_bones/
## - All global class_name identifiers prefixed with "Moba"
class_name MobaRules

## Semantic version of the MOBA rules module implementation.
const VERSION := "0.1.0"

## Root path for hand-authored rule data (.tres and .json files).
const DATA_ROOT := "res://rules/data/"

## Root path for Python-generated JSON exports (gitignored at runtime).
const GENERATED_ROOT := "res://rules/data/generated/"
