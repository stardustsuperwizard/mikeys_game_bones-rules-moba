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
	var resolved_targets: Array[Node] = []
	resolved_targets.assign(target_resolution.targets)

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
		# start_cast() receives a target list that will be re-resolved for GROUND at
		# cast resolution time (after delay) to capture targets at the aimed point.
		#
		# start_cast() -> MobaCastTracker.start() -> _CastInProgress._init() all take
		# a typed Array[Node] parameter, so a target freed between commit (step 6) and
		# here would fault at that boundary rather than no-opping. Filter freed entries
		# out first: resolve()/MobaCastTracker._resolve() already guard a null/freed
		# target, and the cast still gets registered so tick()/cancel() have something
		# to act on for whatever targets remain valid.
		combatant.start_cast(
			ability_id, ability, _filter_live_targets(resolved_targets), ability.cast_time, context
		)
	elif ability.channel_duration > 0.0:
		# Enter ABILITY_CHANNEL state
		if state_machine != null:
			state_machine.try_enter(MobaState.ABILITY_CHANNEL, ability.channel_duration)

		# Start the channel: ticks (including the first tick at t = 0) will be applied
		# via tick(). Same freed-target hazard as start_cast() above, and the same fix:
		# filter freed entries out of the typed Array[Node] before it crosses that
		# boundary; MobaChannelTracker's per-tick resolve() already guards null/freed.
		combatant.start_channel(
			ability_id, ability, _filter_live_targets(resolved_targets), ability.channel_duration
		)
	else:
		# Instant ability: steps 8-9 run now, through the same resolve() the
		# deferred cast path uses. A target that evaporated between commit
		# (step 6) and here makes resolution a safe no-op; the resource spend
		# and cooldown start committed above are never refunded.
		#
		# GROUND has no pre-resolved list (see _resolve_target() above) -- it
		# queries through _ground_target_producer(), the same callable
		# MobaCastTracker.start() uses for a deferred GROUND cast, so an
		# instant and a delayed GROUND ability share one query implementation
		# instead of two call sites that could diverge.
		var instant_targets: Array[Node] = resolved_targets
		if ability.targeting_type == MobaAbility.TargetingType.GROUND:
			instant_targets = _ground_target_producer(context, ability).call()
		for target in instant_targets:
			resolve(ability, target, combatant)

	return ActionResult.new(true)


## Build the callable that (re-)queries the physics world for candidates
## within the ability's area_radius around cast_context.ground_point.
##
## The one GROUND query implementation: execute()'s instant branch calls it
## immediately, and MobaCastTracker.start() stores it unchanged as the
## target-list producer for a deferred cast, calling it lazily at resolution
## time. Sharing the callable is what keeps an instant and a delayed GROUND
## ability from silently resolving targets two different ways.
static func _ground_target_producer(
	cast_context: MobaCastContext, ability: MobaAbility
) -> Callable:
	return func() -> Array[Node]:
		return MobaTargeting.resolve_ground(cast_context.caster, cast_context.ground_point, ability)


## Filter out freed/invalid entries before a target list crosses a typed
## Array[Node] parameter boundary (start_cast()/start_channel()). Binding an
## already-freed object to a typed parameter is a hard engine error, not
## something is_instance_valid() inside the callee can rescue -- see the
## comments at both call sites in execute().
static func _filter_live_targets(targets: Array[Node]) -> Array[Node]:
	var live: Array[Node] = []
	for target in targets:
		if is_instance_valid(target):
			live.append(target)
	return live


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


## Resolve the ability's target(s) based on its targeting type.
## Returns {"targets": Array[Node], "failure": StringName}; failure is empty on success.
##
## Every targeting type routes through MobaTargeting -- the sole place that reads
## Actor.hostile -- for its base candidate(s). SELF and AREA use its result directly;
## TARGETED/CHANNELED additionally need the range check and failure-reason mapping
## MobaTargeting has no ability-activation context to make (it only ever returns a
## plain list), so _resolve_targeted_or_channeled_target() layers that on top.
func _resolve_target(ability: MobaAbility) -> Dictionary:
	var targets: Array[Node] = []
	var failure: StringName = &""

	match ability.targeting_type:
		MobaAbility.TargetingType.SELF:
			targets = MobaTargeting.resolve_self(actor, ability)

		MobaAbility.TargetingType.TARGETED:
			var resolution := _resolve_targeted_or_channeled_target(ability, false)
			if resolution.failure != &"":
				failure = resolution.failure
			else:
				targets = [resolution.target]

		MobaAbility.TargetingType.CHANNELED:
			var resolution := _resolve_targeted_or_channeled_target(ability, true)
			if resolution.failure != &"":
				failure = resolution.failure
			else:
				targets = [resolution.target]

		MobaAbility.TargetingType.AREA:
			targets = MobaTargeting.resolve_area(actor, ability)

		MobaAbility.TargetingType.GROUND:
			# Do not query here. A GROUND target list is only ever produced by
			# _ground_target_producer(): execute()'s instant branch calls it
			# immediately, and MobaCastTracker.start() calls it lazily at
			# resolution time for a deferred cast. Querying here too would be a
			# second, wasted physics query for the deferred case, since the
			# cast tracker discards whatever list it is handed for GROUND and
			# re-queries anyway so targets that moved out of radius during the
			# delay are not hit.
			targets = []

		_:
			# All other targeting types not implemented (SKILLSHOT, TOGGLE)
			failure = FAILURE_TARGETING_NOT_IMPLEMENTED

	return {"targets": targets, "failure": failure}


## Resolve a targeted or channeled ability's target, checking validity and range.
##
## The null/freed guard MUST run and return before MobaTargeting.resolve_targeted()/
## resolve_channeled() are ever called: both take a typed `target: Node` parameter, and
## context.explicit_target can already be a freed object here (see
## _test_target_freed_before_activation in ability_activation_test.gd) -- binding an
## already-freed object to a *fresh* typed parameter is a hard engine error ("Invalid type
## in function"), the same hazard the resolve()/_apply_damage() comments describe, and it
## aborts the calling function rather than raising something is_instance_valid() could
## catch. is_instance_valid() itself takes Variant, so it is safe to call first and gate on.
##
## resolve_targeted()/resolve_channeled() are otherwise identical null/is_instance_valid()
## checks wrapping the single explicit_target, kept as two named functions per the Issue's
## Scope rather than merged into one; `channeled` picks which one this call site exercises.
## Range is not something MobaTargeting can check -- it has no ability-activation context,
## only a plain candidate list -- so it stays here.
func _resolve_targeted_or_channeled_target(ability: MobaAbility, channeled: bool) -> Dictionary:
	if context.explicit_target == null or not is_instance_valid(context.explicit_target):
		return {"target": null, "failure": FAILURE_INVALID_TARGET}

	var candidates: Array[Node] = (
		MobaTargeting.resolve_channeled(actor, context.explicit_target, ability)
		if channeled
		else MobaTargeting.resolve_targeted(actor, context.explicit_target, ability)
	)
	if candidates.is_empty():
		return {"target": null, "failure": FAILURE_INVALID_TARGET}

	var target: Node = candidates[0]
	# Check range
	var caster_pos: Vector3 = _get_position(actor)
	var target_pos: Vector3 = _get_position(target)
	var distance: float = caster_pos.distance_to(target_pos)
	if distance > ability.range:
		return {"target": null, "failure": FAILURE_OUT_OF_RANGE}
	return {"target": target, "failure": &""}


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
		for buff in ability.buffs:
			caster_combatant.apply_stat_modifier(buff, StringName(ability.id), false)

	# Apply debuffs to the resolved target's combatant
	if target_combatant != null:
		for debuff in ability.debuffs:
			target_combatant.apply_stat_modifier(debuff, StringName(ability.id), true)

	# Apply healing to the caster's combatant
	if caster_combatant != null and ability.heal_amount > 0.0:
		caster_combatant.apply_healing(ability.heal_amount)

	# Apply shield to the caster's combatant
	if caster_combatant != null and ability.shield_amount > 0.0:
		caster_combatant.apply_shield(
			ability.shield_amount, StringName(ability.id), ability.duration
		)
