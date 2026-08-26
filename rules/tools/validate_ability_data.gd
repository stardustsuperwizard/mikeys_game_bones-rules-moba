## Semantic validator for MobaAbility and MobaPassive resources.
##
## Checks cross-field authoring errors that aren't caught by Godot's
## structural @export type/range system. Accumulates and reports ALL
## violations found rather than stopping at the first.

class_name ValidateAbilityData
extends RefCounted

# Preload resource classes
const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaPassive = preload("res://rules/abilities/moba_passive.gd")
const MobaStatModifier = preload("res://rules/effects/moba_stat_modifier.gd")
const MobaCrowdControlSpec = preload("res://rules/effects/moba_crowd_control_spec.gd")
const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")


## Validates a MobaAbility resource.
## Returns an array of violation strings (each with file path and field name).
static func validate_ability(resource_path: String, ability: MobaAbility) -> Array[String]:
	var violations: Array[String] = []

	# Check cooldown >= 0
	if ability.cooldown < 0.0:
		violations.append("%s: cooldown (negative: %s)" % [resource_path, ability.cooldown])

	# Check resource_cost >= 0
	if ability.resource_cost < 0.0:
		violations.append(
			"%s: resource_cost (negative: %s)" % [resource_path, ability.resource_cost]
		)

	# Check heal_amount >= 0
	if ability.heal_amount < 0.0:
		violations.append("%s: heal_amount (negative: %s)" % [resource_path, ability.heal_amount])

	# Check shield_amount >= 0
	if ability.shield_amount < 0.0:
		violations.append(
			"%s: shield_amount (negative: %s)" % [resource_path, ability.shield_amount]
		)

	# Check magnitude-style fields are in range 0.0-1.0
	if ability.magnetism < 0.0 or ability.magnetism > 1.0:
		violations.append(
			"%s: magnetism (out of range 0.0-1.0: %s)" % [resource_path, ability.magnetism]
		)

	if ability.refund_resource_on_cancel < 0.0 or ability.refund_resource_on_cancel > 1.0:
		violations.append(
			(
				"%s: refund_resource_on_cancel (out of range 0.0-1.0: %s)"
				% [resource_path, ability.refund_resource_on_cancel]
			)
		)

	# Check SOFT_LOCK aim_assist requirement
	if ability.aim_assist == MobaAbility.AimAssist.SOFT_LOCK:
		if ability.aim_cone_degrees <= 0.0 and ability.magnetism <= 0.0:
			violations.append(
				"%s: SOFT_LOCK aim_assist missing aim_cone_degrees or magnetism" % [resource_path]
			)

	# Check stack modifier (if max_stacks > 1, it's a stack modifier)
	# Stack modifiers with buffs/debuffs bearing max_stacks must have max_stacks set
	if not ability.buffs.is_empty() or not ability.debuffs.is_empty():
		# If ability has any modifiers and max_stacks is set, check it's valid
		if ability.max_stacks < 1:
			violations.append(
				"%s: max_stacks is invalid (< 1: %s)" % [resource_path, ability.max_stacks]
			)

	# Check CHANNELED targeting_type requirement
	if ability.targeting_type == MobaAbility.TargetingType.CHANNELED:
		if ability.channel_duration <= 0.0:
			violations.append(
				"%s: CHANNELED targeting_type missing/zero channel_duration" % [resource_path]
			)

	# Check crowd_control magnitude if present
	if ability.crowd_control != null:
		var cc_violations = _validate_crowd_control(resource_path, ability.crowd_control)
		violations.append_array(cc_violations)

	# Check stat modifiers
	for buff in ability.buffs:
		var buff_violations = _validate_stat_modifier(resource_path, buff, "buff")
		violations.append_array(buff_violations)

	for debuff in ability.debuffs:
		var debuff_violations = _validate_stat_modifier(resource_path, debuff, "debuff")
		violations.append_array(debuff_violations)

	return violations


## Validates a MobaPassive resource.
## Returns an array of violation strings (each with file path and field name).
static func validate_passive(resource_path: String, passive: MobaPassive) -> Array[String]:
	var violations: Array[String] = []

	# Passives don't have cooldown or resource_cost

	# Check effect if present
	if passive.effect != null:
		var effect_violations = _validate_stat_modifier(resource_path, passive.effect, "effect")
		violations.append_array(effect_violations)

	return violations


## Validates a crowd control spec's magnitude field.
static func _validate_crowd_control(
	resource_path: String, cc: MobaCrowdControlSpec
) -> Array[String]:
	var violations: Array[String] = []

	if cc.magnitude < 0.0 or cc.magnitude > 1.0:
		violations.append(
			"%s: crowd_control.magnitude (out of range 0.0-1.0: %s)" % [resource_path, cc.magnitude]
		)

	return violations


## Validates a stat modifier's fields.
static func _validate_stat_modifier(
	resource_path: String, modifier: MobaStatModifier, context: String
) -> Array[String]:
	var violations: Array[String] = []

	# Check that stat names a real MobaStatBlock stat
	if modifier.stat.is_empty():
		violations.append("%s: %s stat is empty" % [resource_path, context])
	elif not StringName(modifier.stat) in MobaStatBlock.get_valid_stats():
		violations.append("%s: %s stat is unknown (%s)" % [resource_path, context, modifier.stat])

	# Check that if stacking is STACK, max_stacks is set
	if modifier.stacking == MobaStatModifier.Stacking.STACK:
		if modifier.max_stacks < 1:
			violations.append(
				(
					"%s: %s max_stacks is invalid when stacking=STACK (< 1: %s)"
					% [resource_path, context, modifier.max_stacks]
				)
			)

	return violations
