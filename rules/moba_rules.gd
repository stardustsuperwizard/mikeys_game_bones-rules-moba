## MobaRules — module identity and shared path constants.
##
## Import this wherever a path into rules/data/ is needed so nothing
## downstream hard-codes "res://rules/data/".
class_name MobaRules
extends RefCounted

## Semantic version of the mikeys_game_rules_moba module.
const VERSION: String = "0.1.0"

## Root of all authored balance data (.tres files).
const DATA_ROOT: String = "res://rules/data/"

## Root of exported JSON for the Python balance harness.  Gitignored;
## nothing under rules/ reads from here.
const GENERATED_ROOT: String = "res://rules/data/generated/"
