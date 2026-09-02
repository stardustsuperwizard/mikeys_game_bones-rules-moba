## Authored configuration for stat point allocation during character build.
##
## Specifies how many total points are available for allocation, the maximum
## points any single stat can receive, and which stats are allocatable.
## Authored as .tres resources, following MobaRespawnPolicy pattern.
class_name MobaStatAllocationPolicy
extends Resource

## Total pool size: number of stat points available for allocation.
##
## Deliberately left without a GDScript default. The pool size and per-stat cap
## are tuning values that live in the authored .tres, never as literals here --
## a default in code is a second, silent source of truth for a number a human is
## expected to revisit.
@export var total_points: int

## Per-stat cap: maximum points that can be allocated to any single stat.
## Authored in .tres for the same reason as total_points.
@export var per_stat_cap: int

## Which stats are allocatable (subset of MobaStatBlock.get_valid_stats()).
## If empty, all valid stats are allocatable.
@export var allocatable_stats: Array[StringName] = []


## Get the allocatable stats for this policy.
## Returns all valid stats if allocatable_stats is empty, otherwise returns allocatable_stats.
func get_allocatable_stats() -> Array[StringName]:
	if allocatable_stats.is_empty():
		return MobaStatBlock.get_valid_stats()
	return allocatable_stats
