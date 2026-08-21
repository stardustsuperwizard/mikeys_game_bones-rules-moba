## Health authority, stat access, and death handling for a MOBA actor.
##
## MobaCombatant is a child of an Actor and owns the actor's MOBA rules state:
## a duplicated runtime stat block, current health, the health mutation/read seam,
## and death signaling that fires exactly once. Signals health changes into the
## parent Actor's character_sheet.
class_name MobaCombatant
extends Node

signal health_changed(current: float, maximum: float)

@export var stat_block: MobaStatBlock = preload("res://rules/data/stat_blocks/baseline.tres")

var _runtime_stat_block: MobaStatBlock
var _current_health: float = 0.0
var _has_died: bool = false


func _ready() -> void:
	# Duplicate the stat block before any mutation
	_runtime_stat_block = stat_block.duplicate()
	_current_health = _runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	
	# Defer seeding the parent Actor's character_sheet because children ready before parents,
	# and the Actor's _ready() hasn't yet duplicated its character_sheet.
	# Writing it directly here would corrupt the shared resource.
	call_deferred("_seed_actor_character_sheet")


func _seed_actor_character_sheet() -> void:
	var parent_actor := get_parent() as Actor
	if parent_actor == null:
		return
	
	# Seed max_hp and current_hp from the stat block
	parent_actor.character_sheet.max_hp = int(_runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH))
	parent_actor.character_sheet.current_hp = int(_current_health)


## Get the current effective value of a stat (today equals the base value).
## Routes through an indirection that a modifier layer can later hook.
func get_stat(stat: StringName) -> float:
	return _get_modified_stat(stat)


## Get the unmodified base value of a stat.
func get_base_stat(stat: StringName) -> float:
	return _runtime_stat_block.get_stat_value(stat)


## Internal seam for stat modifications.
## Currently just returns the base value, but this is where the buff/debuff
## system will hook to apply modifiers.
func _get_modified_stat(stat: StringName) -> float:
	return _runtime_stat_block.get_stat_value(stat)


## Apply damage to the combatant.
## Reduces current health and triggers death handling if health reaches zero.
func apply_damage(amount: float) -> void:
	_current_health -= amount
	_update_health()


## Apply healing to the combatant.
## Increases current health but never exceeds maximum.
func apply_healing(amount: float) -> void:
	var max_health = _runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	_current_health = minf(_current_health + amount, max_health)
	_update_health()


## Check if the combatant is alive.
func is_alive() -> bool:
	return _current_health > 0.0


## Update health state and handle death.
func _update_health() -> void:
	# Mirror health into the parent Actor's character_sheet
	var parent_actor := get_parent() as Actor
	if parent_actor != null:
		parent_actor.character_sheet.current_hp = int(_current_health)
	
	# Emit the health changed signal
	var max_health = _runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	health_changed.emit(_current_health, max_health)
	
	# Handle death: call Actor.die() exactly once
	if _current_health <= 0.0 and not _has_died:
		_has_died = true
		if parent_actor != null:
			parent_actor.die()
