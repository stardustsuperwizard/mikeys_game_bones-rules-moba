## Health authority, stat access, and death handling for a MOBA actor.
##
## MobaCombatant is a child of an Actor and owns the actor's MOBA rules state:
## a duplicated runtime stat block, current health, the health mutation/read seam,
## and death signaling that fires exactly once. Signals health changes into the
## parent Actor's character_sheet.
class_name MobaCombatant
extends Node

signal health_changed(current: float, maximum: float)
## Emitted when damage is resolved. Carries both raw (pre-crit, pre-mitigation)
## and final (post-mitigation) amounts, plus metadata about the damage event.
signal damage_resolved(raw: float, final: float, damage_type: int, was_crit: bool, source)
## Emitted when current or maximum resource changes.
signal resource_changed(current: float, maximum: float)

@export var stat_block: MobaStatBlock = preload("res://rules/data/stat_blocks/baseline.tres")

var _runtime_stat_block: MobaStatBlock
var _current_health: float = 0.0
var _has_died: bool = false
var _current_resource: float = 0.0


func _ready() -> void:
	# Duplicate the stat block before any mutation
	_runtime_stat_block = stat_block.duplicate()
	_current_health = _runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	_current_resource = _runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)
	
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


## Apply damage to the combatant via a MobaDamage packet.
##
## Resolution order (pinned per Architecture Constraints):
## 1. Raw amount
## 2. Crit roll and multiplier (if can_crit)
## 3. Damage-type routing (PHYSICAL/MAGICAL/TRUE)
## 4. Penetration against target's defense
## 5. Mitigation multiplier
## 6. Final amount
## 7. Shield seam (documented empty hook)
##
## Emits damage_resolved once per packet.
func apply_damage(damage: MobaDamage) -> void:
	var raw: float = damage.amount
	var final: float = raw
	var was_crit: bool = false
	
	# Step 2: Crit roll and multiplier
	if damage.can_crit:
		var crit_chance: float = get_stat(MobaStatBlock.CRIT_CHANCE)
		var crit_damage: float = get_stat(MobaStatBlock.CRIT_DAMAGE)
		var crit_roll: float = MobaRules.roll_crit()
		
		if MobaFormulas.is_critical(crit_roll, crit_chance):
			was_crit = true
			final = MobaFormulas.apply_crit(raw, crit_damage)
		else:
			final = raw
	else:
		final = raw
	
	# Step 3-6: Damage-type routing and mitigation
	match damage.damage_type:
		MobaDamage.DamageType.PHYSICAL:
			var armor: float = get_stat(MobaStatBlock.ARMOR)
			final = MobaFormulas.physical_damage(final, armor, damage.flat_pen, damage.percent_pen)
		
		MobaDamage.DamageType.MAGICAL:
			var resistance: float = get_stat(MobaStatBlock.MAGIC_RESISTANCE)
			final = MobaFormulas.magical_damage(final, resistance, damage.flat_pen, damage.percent_pen)
		
		MobaDamage.DamageType.TRUE:
			# TRUE damage ignores all defenses and penetration
			final = MobaFormulas.true_damage(final)
	
	# Step 7: Shield seam (documented empty hook per §16, Batch 2 sustain issue)
	# This private hook receives the final amount and returns it unchanged.
	# It exists as a placeholder for future shield implementations.
	final = _apply_shield_seam(final)
	
	# Reduce health
	_current_health -= final
	_update_health()
	
	# Emit damage_resolved
	damage_resolved.emit(raw, final, damage.damage_type, was_crit, damage.source)


## Private shield seam: documented empty hook per §16.
## This exists as a placeholder for Batch 2 sustain systems (shields, lifesteal).
## Returns the input unchanged.
func _apply_shield_seam(amount: float) -> float:
	# TODO §16: Shield mitigation hook for Batch 2
	# return amount adjusted by any active shields
	return amount


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


## Get current resource value.
func get_current_resource() -> float:
	return _current_resource


## Get maximum resource value from the stat block.
func get_maximum_resource() -> float:
	return get_stat(MobaStatBlock.RESOURCE)


# Property accessors for current_resource and maximum_resource
var current_resource: float:
	get:
		return _current_resource

var maximum_resource: float:
	get:
		return get_stat(MobaStatBlock.RESOURCE)


## Spend resource from the pool.
## Returns false and mutates nothing if amount exceeds current_resource.
## Otherwise deducts amount, emits resource_changed, and returns true.
## spend_resource(0.0) returns true even at zero current resource.
func spend_resource(amount: float) -> bool:
	if amount > _current_resource:
		return false
	
	_current_resource -= amount
	resource_changed.emit(_current_resource, get_stat(MobaStatBlock.RESOURCE))
	return true


## Restore resource to the pool.
## Clamps the result at maximum and emits resource_changed.
func restore_resource(amount: float) -> void:
	var max_resource = get_stat(MobaStatBlock.RESOURCE)
	_current_resource = minf(_current_resource + amount, max_resource)
	resource_changed.emit(_current_resource, max_resource)


## Advance time by delta seconds.
## Accumulates resource and health regeneration continuously (not gated by one-second intervals).
## Health regeneration clamps at maximum and emits health_changed.
## A dead combatant does not regenerate health.
## Resource regeneration always occurs (dead or alive).
func tick(delta: float) -> void:
	# Accumulate resource regeneration
	var resource_regen = get_stat(MobaStatBlock.RESOURCE_REGEN)
	var max_resource = get_stat(MobaStatBlock.RESOURCE)
	_current_resource = minf(_current_resource + resource_regen * delta, max_resource)
	resource_changed.emit(_current_resource, max_resource)
	
	# Accumulate health regeneration (only if alive)
	if is_alive():
		var health_regen = get_stat(MobaStatBlock.HEALTH_REGEN)
		var max_health = get_stat(MobaStatBlock.HEALTH)
		_current_health = minf(_current_health + health_regen * delta, max_health)
		_update_health()
