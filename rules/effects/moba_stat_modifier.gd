## Data-shape Resource for a single stat modifier entry (§57 statModifier block).
## This class is a pure data container; runtime application logic belongs in #30/#31.
class_name MobaStatModifier
extends Resource

enum Stacking {
	REFRESH,
	STACK,
	IGNORE,
	REPLACE_IF_STRONGER,
}

## The stat key this modifier applies to (e.g. "attack_speed", "armor").
@export var stat: String = ""

## Flat or percentage amount to apply.
@export var amount: float = 0.0

## When true, `amount` is treated as a fraction (0.05 = 5 %).
@export var is_percentage: bool = false

## Duration in seconds. 0 means permanent until explicitly removed.
@export var duration: float = 0.0

## How multiple applications of this modifier interact.
@export var stacking: Stacking = Stacking.REFRESH

## Maximum number of stacks allowed when stacking == STACK.
@export_range(1, 100) var max_stacks: int = 1
