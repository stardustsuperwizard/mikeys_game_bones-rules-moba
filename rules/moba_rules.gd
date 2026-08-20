## class_name MobaRules
## Module identity and path constants for the MOBA combat ruleset.
##
## Import this script with preload() or rely on the global class_name. Downstream
## code must use DATA_ROOT rather than hard-coding "res://rules/data/" so the
## path survives extraction into an addon.
class_name MobaRules
extends RefCounted

## Semantic version of the rules module.
const VERSION: String = "0.1.0"

## Canonical root path for all authored balance data.
const DATA_ROOT: String = "res://rules/data/"

## Root path for generated JSON exported for the Python balance harness.
## This directory is gitignored and regenerated on demand.
const GENERATED_ROOT: String = "res://rules/data/generated/"
