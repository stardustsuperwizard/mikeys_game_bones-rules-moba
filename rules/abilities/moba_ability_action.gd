## Action that activates a MOBA ability.
##
## MobaAbilityAction executes the full ability activation pipeline:
## 1. Legality: state machine can(&"ability")
## 2. Legality: cooldown/charges/resource via MobaCombatant.can_activate()
## 3. Legality: silenced seam (Batch 2, empty for now)
## 4. Target resolution (self, targeted, or unimplemented)
## 5. Resource and cooldown commitment
## 6. State machine transition into ABILITY_CAST if cast_time > 0
## 7. Damage application (if not cast_time-delayed to Batch 2)
## 8. Effects seam (crowd control/buffs/debuffs, Batch 2, empty for now)
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
	var combatant := _get_combatant(actor)
	if combatant == null:
		return ActionResult.new(false, FAILURE_ILLEGAL_STATE)

	# Steps 1-4: state machine, cooldown/charges/resource legality, then silenced
	var state_machine := _get_state_machine(actor)
	var early_failure := _check_early_legality(combatant, state_machine)
	if early_failure != &"":
		return ActionResult.new(false, early_failure)

	# Step 5: Resolve target based on targeting type
	var target_resolution := _resolve_target(ability)
	if target_resolution.failure != &"":
		return ActionResult.new(false, target_resolution.failure)
	var resolved_target: Node = target_resolution.target

	# Step 6: Commit activation (spend resource and start cooldown)
	var commit_failure := _commit_activation(combatant)
	if commit_failure != &"":
		return ActionResult.new(false, commit_failure)

	# Step 7: Enter ABILITY_CAST state if cast_time > 0
	if state_machine != null and ability.cast_time > 0.0:
		state_machine.try_enter(MobaState.ABILITY_CAST, ability.cast_time)

	# Steps 8-9: Apply damage and effects, guarded against the target having
	# evaporated between commit (step 6) and this resolution step. The
	# resource spend and cooldown start committed above are never refunded
	# if that happens -- resolution just safely no-ops.
	if resolved_target != null and is_instance_valid(resolved_target):
		# Step 8: Apply damage (Batch 2 will defer this if cast_time > 0)
		# For now, apply immediately
		_apply_damage(ability, resolved_target)

		# Step 9: Apply effects (crowd control, buffs, debuffs) - Batch 2 seam
		_apply_effects_seam(ability, resolved_target)

	return ActionResult.new(true)


## Find a combatant's MobaCombatant child node.
func _get_combatant(node: Node) -> MobaCombatant:
	return node.get_node_or_null("MobaCombatant") as MobaCombatant


## Find a node's MobaStateMachine child node.
func _get_state_machine(node: Node) -> MobaStateMachine:
	return node.get_node_or_null("MobaStateMachine") as MobaStateMachine


## Check state machine, cooldown/charges/resource legality, then the silenced seam.
## Order pinned by the Scope: step 1 (state), steps 2-3 (cooldown/charges/resource
## via MobaCombatant.can_activate), step 4 (silenced).
## Returns an empty StringName if legal, otherwise a FAILURE_* constant.
func _check_early_legality(combatant: MobaCombatant, state_machine: MobaStateMachine) -> StringName:
	if state_machine != null and not state_machine.can(&"ability"):
		return FAILURE_ILLEGAL_STATE

	var legality_result: int = combatant.can_activate(ability_id)
	var failure := &""
	match legality_result:
		MobaCombatant.ActivationFailure.ON_COOLDOWN:
			failure = FAILURE_ON_COOLDOWN
		MobaCombatant.ActivationFailure.NO_CHARGES:
			failure = FAILURE_NO_CHARGES
		MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE:
			failure = FAILURE_INSUFFICIENT_RESOURCE
		MobaCombatant.ActivationFailure.UNKNOWN_ABILITY:
			failure = FAILURE_UNKNOWN_ABILITY
		MobaCombatant.ActivationFailure.OK:
			failure = &""
		_:
			failure = FAILURE_ILLEGAL_STATE
	if failure != &"":
		return failure

	if _check_silenced_seam(combatant):
		return FAILURE_ILLEGAL_STATE

	return &""


## Resolve the ability's target based on its targeting type.
## Returns {"target": Node, "failure": StringName}; failure is empty on success.
func _resolve_target(ability: MobaAbility) -> Dictionary:
	match ability.targeting_type:
		MobaAbility.TargetingType.SELF:
			return {"target": actor, "failure": &""}
		MobaAbility.TargetingType.TARGETED:
			# Targeted abilities require explicit_target
			if context.explicit_target == null:
				return {"target": null, "failure": FAILURE_INVALID_TARGET}
			# Guard against freed/invalid targets
			if not is_instance_valid(context.explicit_target):
				return {"target": null, "failure": FAILURE_INVALID_TARGET}
			# Check range
			var caster_pos: Vector3 = _get_position(actor)
			var target_pos: Vector3 = _get_position(context.explicit_target)
			var distance: float = caster_pos.distance_to(target_pos)
			if distance > ability.range:
				return {"target": null, "failure": FAILURE_OUT_OF_RANGE}
			return {"target": context.explicit_target, "failure": &""}
		_:
			# All other targeting types not implemented in Batch 1
			return {"target": null, "failure": FAILURE_TARGETING_NOT_IMPLEMENTED}


## Commit activation (spend resource and start cooldown).
## Returns an empty StringName on success, otherwise a FAILURE_* constant.
func _commit_activation(combatant: MobaCombatant) -> StringName:
	var commit_result: int = combatant.commit_activate(ability_id)
	var failure := &""
	match commit_result:
		MobaCombatant.ActivationFailure.ON_COOLDOWN:
			failure = FAILURE_ON_COOLDOWN
		MobaCombatant.ActivationFailure.NO_CHARGES:
			failure = FAILURE_NO_CHARGES
		MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE:
			failure = FAILURE_INSUFFICIENT_RESOURCE
		MobaCombatant.ActivationFailure.OK:
			failure = &""
		_:
			# Should not reach here if can_activate passed, but guard it
			failure = FAILURE_ILLEGAL_STATE
	return failure


## Apply the ability's damage to the resolved target, if any.
## Safe to call with an invalid/freed target (guards with is_instance_valid()) --
## already-committed resource/cooldown cost is never refunded in that case.
func _apply_damage(ability: MobaAbility, target: Node) -> void:
	if target == null or not is_instance_valid(target) or ability.base_damage <= 0.0:
		return

	var target_combatant := _get_combatant(target)
	if target_combatant == null:
		return

	var damage := MobaDamage.new(
		ability.base_damage, _damage_type_to_moba(ability.damage_type), actor  # source is the caster
	)
	target_combatant.apply_damage(damage)


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
func _check_silenced_seam(_combatant: MobaCombatant) -> bool:
	# TODO Batch 2: Check if caster has silenced crowd control
	return false


## Seam for applying effects (Batch 2 feature).
## Applies crowd control, buffs, and debuffs from the ability to the target.
## Empty implementation for Batch 1.
func _apply_effects_seam(_ability: MobaAbility, _target: Node) -> void:
	# TODO Batch 2: Apply crowd control from ability.crowd_control
	# TODO Batch 2: Apply buffs from ability.buffs
	# TODO Batch 2: Apply debuffs from ability.debuffs
	pass
