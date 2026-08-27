## Action that activates a MOBA ability.
##
## MobaAbilityAction executes the full ability activation pipeline:
## 1. Legality: state machine can(&"ability")
## 2. Legality: cooldown/charges/resource via MobaCombatant.can_activate()
## 3. Legality: silenced seam
## 4. Target resolution (self, targeted, or unimplemented)
## 5. Resource and cooldown commitment
## 6. State machine transition into ABILITY_CAST if cast_time > 0
## 7. Resolution -- damage, then effects (crowd control/buffs/debuffs/heal/shield)
##    via resolve(). Immediate when cast_time == 0; deferred to
##    MobaCastTracker when cast_time > 0, which calls the same resolve().
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
## - invalid_context: MobaCastContext has no caster (MobaAbilityCaster.activate)
##
## This is the canonical place these reasons are defined; both this file and
## its test reference these constants rather than duplicating the literals.
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
const FAILURE_EMPTY_SLOT = &"empty_slot"
## Not produced by MobaAbilityAction itself -- MobaCastContext.caster is non-nullable
## by the time an Action reaches execute(). Returned by MobaAbilityCaster.activate()
## when its context has no caster, before an Action is even constructed. Lives here
## so it shares the one canonical failure-reason block the Scope requires.
const FAILURE_INVALID_CONTEXT = &"invalid_context"

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
	var early_failure := _check_early_legality(combatant)
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

	# Step 7: Route based on ability timing type.
	# - cast_time > 0: deferred to ABILITY_CAST, resolve when cast completes
	# - channel_duration > 0: deferred to ABILITY_CHANNEL, ticks applied repeatedly
	# - cast_time == 0 and channel_duration == 0: instant, apply immediately
	if ability.cast_time > 0.0:
		# Enter ABILITY_CAST state
		if state_machine != null:
			state_machine.try_enter(MobaState.ABILITY_CAST, ability.cast_time)

		# Start the cast: damage and effects will be applied when it resolves via tick().
		# start_cast() -> MobaCastTracker.start() -> _CastInProgress._init() all take
		# a typed Node parameter, so a target freed between commit (step 6) and here
		# would fault at that boundary rather than no-opping. Substitute null in that
		# case: MobaCastTracker._resolve() and resolve() already guard a null target,
		# and the cast still gets registered so tick()/cancel() have something to act on.
		var cast_target: Node = resolved_target if is_instance_valid(resolved_target) else null
		combatant.start_cast(ability_id, ability, cast_target, ability.cast_time)
	elif ability.channel_duration > 0.0:
		# Enter ABILITY_CHANNEL state
		if state_machine != null:
			state_machine.try_enter(MobaState.ABILITY_CHANNEL, ability.channel_duration)

		# Start the channel: ticks (including the first tick at t = 0) will be applied
		# via tick(). Like the cast path, guard against a freed target.
		var channel_target: Node = resolved_target if is_instance_valid(resolved_target) else null
		combatant.start_channel(ability_id, ability, channel_target, ability.channel_duration)
	else:
		# Instant ability: steps 8-9 run now, through the same resolve() the
		# deferred cast path uses. A target that evaporated between commit
		# (step 6) and here makes resolution a safe no-op; the resource spend
		# and cooldown start committed above are never refunded.
		resolve(ability, resolved_target, combatant)

	return ActionResult.new(true)


## Find a combatant's MobaCombatant child node.
static func _get_combatant(node: Node) -> MobaCombatant:
	return node.get_node_or_null("MobaCombatant") as MobaCombatant


## Find a node's MobaStateMachine child node.
func _get_state_machine(node: Node) -> MobaStateMachine:
	return node.get_node_or_null("MobaStateMachine") as MobaStateMachine


## Check state machine, cooldown/charges/resource legality, then the silenced seam.
## Order pinned by the Scope: step 1 (state), steps 2-3 (cooldown/charges/resource
## via MobaCombatant.can_activate), step 4 (silenced).
## Returns an empty StringName if legal, otherwise a FAILURE_* constant.
func _check_early_legality(combatant: MobaCombatant) -> StringName:
	if not combatant.can_perform_action(&"ability"):
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
		MobaAbility.TargetingType.TARGETED, MobaAbility.TargetingType.CHANNELED:
			# Targeted and channeled abilities resolve targeting identically: both
			# require explicit_target and check ability.range.
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


## Apply an ability's damage and then its effects to a resolved target.
##
## This is the one resolution implementation, shared by both activation paths:
## MobaAbilityAction.execute() calls it directly for an instant ability
## (cast_time == 0), and MobaCastTracker._resolve() calls it when a deferred
## cast (cast_time > 0) reaches its resolution point. Keeping it in one place
## is what stops the instant and cast-time paths silently diverging.
##
## Safe to call with a null/freed target: resolution no-ops rather than
## refunding the resource and cooldown already committed.
##
## `target` is deliberately untyped. A Node freed between commit and this call
## fails GDScript's typed-argument check *before* any guard in the body could
## run, which would abort execute() instead of no-opping -- so the parameter
## stays Variant and narrows to Node only after is_instance_valid() passes.
static func resolve(ability: MobaAbility, target, caster_combatant: MobaCombatant) -> void:
	if target == null or not is_instance_valid(target):
		return

	var target_node := target as Node
	if target_node == null:
		return

	_apply_damage(ability, target_node, caster_combatant)
	_apply_effects_seam(ability, target_node, caster_combatant)


## Apply the ability's damage to the resolved target, if any.
##
## `target` is typed Node here, unlike resolve()'s untyped parameter: this is
## only reachable through resolve(), which already narrows to Node via
## is_instance_valid() before calling in. Do not call this directly with a
## target that might be freed -- the typed argument faults at the call
## boundary before the body's own is_instance_valid() guard ever runs.
static func _apply_damage(
	ability: MobaAbility, target: Node, caster_combatant: MobaCombatant
) -> void:
	if target == null or not is_instance_valid(target):
		return

	var raw_amount := _compute_scaled_damage(ability, caster_combatant)
	if raw_amount <= 0.0:
		return

	var target_combatant := _get_combatant(target)
	if target_combatant == null:
		return

	# source is the caster's MobaCombatant, not the caster Actor: apply_damage()
	# reads the attacker's crit statistics off it, and MobaDamage.source is a
	# MobaCombatant at every construction site.
	var damage := MobaDamage.new(
		raw_amount, _damage_type_to_moba(ability.damage_type), caster_combatant
	)
	target_combatant.apply_damage(damage)


## Compute the raw damage amount: base_damage plus ability.scaling ratios against
## the caster's live stats (e.g. {"attack_damage": 0.6} adds 0.6 * caster attack_damage).
## This is only the "base + scaling*stat" summation, not a mitigation/crit/cooldown
## formula, so it is not a MobaFormulas concern per that file's own docstring --
## MobaFormulas.physical_damage()/magical_damage()/etc. are still the only place
## mitigation math happens, inside MobaCombatant.apply_damage().
static func _compute_scaled_damage(ability: MobaAbility, caster_combatant: MobaCombatant) -> float:
	var amount := ability.base_damage
	if caster_combatant == null:
		return amount
	for stat_name in ability.scaling:
		var ratio: float = ability.scaling[stat_name]
		amount += ratio * caster_combatant.get_stat(StringName(stat_name))
	return amount


## Map MobaAbility.DamageType to MobaDamage.DamageType
static func _damage_type_to_moba(damage_type: int) -> int:
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


## Seam for silenced check.
## Returns true if caster is silenced and cannot activate abilities.
func _check_silenced_seam(combatant: MobaCombatant) -> bool:
	var silence_type = MobaCrowdControlSpec.CCType.SILENCE
	return combatant.has_crowd_control(silence_type)


## Seam for applying effects.
## Applies crowd control, buffs, debuffs, healing, and shielding from the ability.
static func _apply_effects_seam(
	ability: MobaAbility, target: Node, caster_combatant: MobaCombatant
) -> void:
	var target_combatant := _get_combatant(target)

	# Apply crowd control from ability.crowd_control to the target
	if ability.crowd_control != null and target_combatant != null and caster_combatant != null:
		target_combatant.apply_crowd_control(ability.crowd_control, caster_combatant)

	# Apply buffs to the caster's combatant
	if caster_combatant != null:
		var caster_effects := caster_combatant.get_effect_container()
		for buff in ability.buffs:
			caster_effects.apply_modifier(buff, StringName(ability.id))

	# Apply debuffs to the resolved target's combatant
	if target_combatant != null:
		var target_effects := target_combatant.get_effect_container()
		for debuff in ability.debuffs:
			target_effects.apply_modifier(debuff, StringName(ability.id))

	# Apply healing to the caster's combatant
	if caster_combatant != null and ability.heal_amount > 0.0:
		caster_combatant.apply_healing(ability.heal_amount)

	# Apply shield to the caster's combatant
	if caster_combatant != null and ability.shield_amount > 0.0:
		caster_combatant.apply_shield(
			ability.shield_amount, StringName(ability.id), ability.duration
		)
