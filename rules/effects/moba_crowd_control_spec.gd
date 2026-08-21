## Data-shape Resource for a crowd control effect block (§57 crowd_control block).
## This class is a pure data container; runtime application logic belongs in #30/#31.
class_name MobaCrowdControlSpec
extends Resource

enum CCType {
	STUN,
	ROOT,
	SLOW,
	SILENCE,
	DISARM,
	KNOCKBACK,
	PULL,
	KNOCK_UP,
	FEAR,
	TAUNT,
	BLIND,
}

## The kind of crowd control applied.
@export var type: CCType = CCType.STUN

## Magnitude of the effect (e.g. slow percentage as a fraction: 0.3 = 30 %).
@export var magnitude: float = 0.0

## Duration in seconds.
@export var duration: float = 0.0

## Whether the duration can be reduced by the target's Tenacity stat.
@export var affected_by_tenacity: bool = true
