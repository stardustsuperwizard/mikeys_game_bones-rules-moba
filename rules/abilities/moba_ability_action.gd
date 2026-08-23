## Action that activates a MOBA ability.
##
## MobaAbilityAction executes the full ability activation pipeline:
## 1. Legality checks (state, cooldown, charges, resource)
## 2. Target resolution (self, targeted, or unimplemented)
## 3. Resource and cooldown commitment
## 4. Damage application (if not cast_time-delayed to Batch 2)
## 5. State machine transitions for cast/channel states
##
## Failure reasons returned as StringName:
## - unknown_ability: ability_id not found in library
## - illegal_state: state machine does not allow ability activation
## - on_cooldown: ability is on cooldown (MobaCombatant.can_activate)
## - no_charges: no charges remaining (MobaCombatant.can_activate)
## - insufficient_resource: not enough resource (MobaCombatant.can_activate)
## - invalid_target: explicit_target is freed/invalid (for targeted abilities)
## - out_of_range: target out of ability range (for targeted abilities)
## - targeting_not_implemented: unimplemented targeting type
class_name MobaAbilityAction
extends Action

const FAILURE_UNKNOWN_ABILITY = &"unknown_ability"
const FAILURE_ILLEGAL_STATE = &"illegal_state"
const FAILURE_ON_COOLDOWN = &"on_cooldown"
const FAILURE_NO_CHARGES = &"no_charges"
const FAILURE_INSUFFICIENT_RESOURCE = &"insufficient_resource"
const FAILURE_INVALID_TARGET = &"invalid_target"
const FAILURE_OUT_OF_RANGE = &"out_of_range"
const FAILURE_TARGETING_NOT_IMPLEMENTED = &"targeting_not_implemented"

var ability_id: StringName
var context: MobaCastContext


func _init(p_actor: Actor, p_ability_id: StringName, p_context: MobaCastContext) -> void:
	super(p_actor)
	ability_id = p_ability_id
	context = p_context


func execute() -> ActionResult:
	# Step 1: Load ability
	var ability := MobaAbilityLibrary.get_ability(ability_id)
	if ability == null:
		return ActionResult.new(false, FAILURE_UNKNOWN_ABILITY)

	# Step 2: Get combatant
	var combatant: MobaCombatant = null

	# Try to find combatant as a child node (normal scene tree)
	combatant = actor.get_node_or_null("MobaCombatant") as MobaCombatant

	# Fall back to checking for a direct property (for testing)
	if combatant == null and actor.has_meta("_test_combatant"):
		combatant = actor.get_meta("_test_combatant") as MobaCombatant

	if combatant == null:
		return ActionResult.new(false, FAILURE_ILLEGAL_STATE)

	# Step 3: Check state machine can("ability")
	var state_machine: MobaStateMachine = null

	# Try to find state machine as a child node (normal scene tree)
	state_machine = actor.get_node_or_null("MobaStateMachine") as MobaStateMachine

	# Fall back to checking for a direct property (for testing)
	if state_machine == null and actor.has_meta("_test_state_machine"):
		state_machine = actor.get_meta("_test_state_machine") as MobaStateMachine

	if state_machine != null and not state_machine.can(&"ability"):
		return ActionResult.new(false, FAILURE_ILLEGAL_STATE)

	# Step 4: Check legality silenced (seam for Batch 2)
	if _check_silenced_seam(combatant):
		return ActionResult.new(false, FAILURE_ILLEGAL_STATE)

	# Step 4.5: Check legality (cooldown, charges, resource)
	var legality_result: int = combatant.can_activate(ability_id)
	if legality_result != MobaCombatant.ActivationFailure.OK:
		# Map the combatant's failure enum to our StringName constants
		match legality_result:
			MobaCombatant.ActivationFailure.ON_COOLDOWN:
				return ActionResult.new(false, FAILURE_ON_COOLDOWN)
			MobaCombatant.ActivationFailure.NO_CHARGES:
				return ActionResult.new(false, FAILURE_NO_CHARGES)
			MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE:
				return ActionResult.new(false, FAILURE_INSUFFICIENT_RESOURCE)
			MobaCombatant.ActivationFailure.UNKNOWN_ABILITY:
				return ActionResult.new(false, FAILURE_UNKNOWN_ABILITY)
			_:
				return ActionResult.new(false, FAILURE_ILLEGAL_STATE)

	# Step 5: Resolve target based on targeting type
	var resolved_target: Node = null
	match ability.targeting_type:
		MobaAbility.TargetingType.SELF:
			resolved_target = actor
		MobaAbility.TargetingType.TARGETED:
			# Targeted abilities require explicit_target
			if context.explicit_target == null:
				return ActionResult.new(false, FAILURE_INVALID_TARGET)
			# Guard against freed/invalid targets
			if not is_instance_valid(context.explicit_target):
				return ActionResult.new(false, FAILURE_INVALID_TARGET)
			# Check range
			var caster_pos: Vector3 = _get_position(actor)
			var target_pos: Vector3 = _get_position(context.explicit_target)
			var distance: float = caster_pos.distance_to(target_pos)
			if distance > ability.range:
				return ActionResult.new(false, FAILURE_OUT_OF_RANGE)
			resolved_target = context.explicit_target
		_:
			# All other targeting types not implemented in Batch 1
			return ActionResult.new(false, FAILURE_TARGETING_NOT_IMPLEMENTED)

	# Step 6: Commit activation (spend resource and start cooldown)
	var commit_result: int = combatant.commit_activate(ability_id)
	if commit_result != MobaCombatant.ActivationFailure.OK:
		# Should not reach here if can_activate passed, but guard it
		match commit_result:
			MobaCombatant.ActivationFailure.ON_COOLDOWN:
				return ActionResult.new(false, FAILURE_ON_COOLDOWN)
			MobaCombatant.ActivationFailure.NO_CHARGES:
				return ActionResult.new(false, FAILURE_NO_CHARGES)
			MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE:
				return ActionResult.new(false, FAILURE_INSUFFICIENT_RESOURCE)
			_:
				return ActionResult.new(false, FAILURE_ILLEGAL_STATE)

	# Step 7: Enter ABILITY_CAST state if cast_time > 0
	if state_machine != null and ability.cast_time > 0.0:
		state_machine.try_enter(MobaState.ABILITY_CAST, ability.cast_time)

	# Step 8: Apply damage (Batch 2 will defer this if cast_time > 0)
	# For now, apply immediately
	if resolved_target != null and ability.base_damage > 0.0:
		var target_combatant: MobaCombatant = null

		# Try to find combatant as a child node (normal scene tree)
		target_combatant = resolved_target.get_node_or_null("MobaCombatant") as MobaCombatant

		# Fall back to checking for a direct property (for testing)
		if target_combatant == null and resolved_target.has_meta("_test_combatant"):
			target_combatant = resolved_target.get_meta("_test_combatant") as MobaCombatant

		if target_combatant != null:
			var damage := MobaDamage.new(
				ability.base_damage, _damage_type_to_moba(ability.damage_type), actor  # source is the caster
			)
			target_combatant.apply_damage(damage)

	# Step 9: Apply effects (crowd control, buffs, debuffs) - Batch 2 seam
	if resolved_target != null:
		_apply_effects_seam(ability, resolved_target)

	return ActionResult.new(true)


## Map MobaAbility.DamageType to MobaDamage.DamageType
func _damage_type_to_moba(damage_type: int) -> int:
	match damage_type:
		MobaAbility.DamageType.PHYSICAL:
			return MobaDamage.DamageType.PHYSICAL
		MobaAbility.DamageType.MAGICAL:
			return MobaDamage.DamageType.MAGICAL
		MobaAbility.DamageType.TRUE:
			return MobaDamage.DamageType.TRUE
		_:
			return MobaDamage.DamageType.PHYSICAL


## Get world position of a node, with a default fallback.
func _get_position(node: Node) -> Vector3:
	if node == null:
		return Vector3.ZERO

	# Try to access global_position (works for Actor and Node3D)
	if node.get("global_position") != null:
		return node.global_position as Vector3

	# Fallback to zero
	return Vector3.ZERO


## Seam for silenced check (Batch 2 feature).
## Returns true if caster is silenced and cannot activate abilities.
## Empty implementation for Batch 1.
func _check_silenced_seam(combatant: MobaCombatant) -> bool:
	# TODO Batch 2: Check if caster has silenced crowd control
	return false


## Seam for applying effects (Batch 2 feature).
## Applies crowd control, buffs, and debuffs from the ability to the target.
## Empty implementation for Batch 1.
func _apply_effects_seam(ability: MobaAbility, target: Node) -> void:
	# TODO Batch 2: Apply crowd control from ability.crowd_control
	# TODO Batch 2: Apply buffs from ability.buffs
	# TODO Batch 2: Apply debuffs from ability.debuffs
	pass
