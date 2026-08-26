## Transient per-shield pool entry carrying absorption capacity and expiry time.
##
## MobaShield is a RefCounted value object that encapsulates an active shield:
## the remaining absorption capacity, the source that applied it, and the time
## remaining until it expires. Shields are consumed in order of shortest remaining
## duration first during damage resolution.
class_name MobaShield
extends RefCounted

## Remaining absorption capacity (float).
var amount: float

## The source (StringName) that applied this shield.
var source: StringName

## Time left in seconds until this shield expires and is removed.
var remaining: float


## Construct a new shield with the given absorption amount, source, and duration.
func _init(p_amount: float, p_source: StringName, p_duration: float) -> void:
	amount = p_amount
	source = p_source
	remaining = p_duration
