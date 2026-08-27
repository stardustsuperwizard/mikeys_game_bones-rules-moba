## In-progress cast ledger for a single combatant.
##
## Holds the cast a combatant is currently performing (an ability whose
## cast_time > 0), advances it on an explicit tick(delta), and resolves it -
## applying damage and effects - once the remaining time reaches zero.
##
## Time advances only through tick(delta); there is no _process or
## _physics_process. MobaCombatant.tick() remains the sole per-frame entry
## point and drives this tracker from inside it, the same way it drives the
## MobaCooldowns ledger.
##
## Cancelling a cast before it resolves - whether through
## MobaAbilityCaster.cancel() or a hard crowd control interrupt - routes
## through cancel() here, so both produce identical resource and cooldown
## outcomes for a given ability.
class_name MobaCastTracker
extends RefCounted


## Data for a cast that is currently resolving.
class _CastInProgress:
	var ability_id: StringName
	var ability: MobaAbility
	var resolved_target: Node
	var remaining_time: float

	func _init(
		p_ability_id: StringName, p_ability: MobaAbility, p_target: Node, p_time: float
	) -> void:
		ability_id = p_ability_id
		ability = p_ability
		resolved_target = p_target
		remaining_time = p_time


## The owning combatant. Typed as Node rather than MobaCombatant so this file
## carries no cyclic class dependency back to the combatant that owns it.
var _combatant: Node = null

## The cast currently in progress, or null when none is.
var _cast_in_progress: _CastInProgress = null


func _init(p_combatant: Node) -> void:
	_combatant = p_combatant


## True while a cast is in progress.
func is_casting() -> bool:
	return _cast_in_progress != null


## The ability being cast, or null when no cast is in progress.
func current_ability() -> MobaAbility:
	if _cast_in_progress == null:
		return null
	return _cast_in_progress.ability


## Start a cast that will resolve after its cast_time elapses via tick().
## Called by MobaAbilityAction when an ability with cast_time > 0 is activated.
##
## Args:
##     ability_id: The ability being cast
##     ability: The resolved MobaAbility resource
##     resolved_target: The target (may be null; guarded in resolution)
##     cast_time: Remaining time until resolution, in seconds
func start(
	ability_id: StringName, ability: MobaAbility, resolved_target: Node, cast_time: float
) -> void:
	_cast_in_progress = _CastInProgress.new(ability_id, ability, resolved_target, cast_time)


## Cancel an in-progress cast and apply the on_cancel outcome (resource
## refund, cooldown change). A no-op if no cast is in progress - it returns
## without error, since a speculative cancel is a supported call.
func cancel() -> void:
	if _cast_in_progress == null:
		return

	var ability := _cast_in_progress.ability
	var ability_id := _cast_in_progress.ability_id

	# Apply the on_cancel outcome
	_apply_cancel_outcome(ability_id, ability)

	# Clear the in-progress cast
	_cast_in_progress = null


## Advance the in-progress cast by delta seconds and resolve it when it
## reaches time 0. Resolution completes synchronously inside this call.
func tick(delta: float) -> void:
	if _cast_in_progress == null:
		return

	_cast_in_progress.remaining_time -= delta
	if _cast_in_progress.remaining_time <= 0.0:
		_resolve()


## Apply the resource and cooldown outcome of cancelling a cast.
## Implements the on_cancel mapping table from the Scope:
## - full_refund: refund 100% of resource_cost, undo cooldown
## - partial_refund: refund refund_resource_on_cancel fraction, undo cooldown
## - no_refund: no refund, undo cooldown
## - cooldown_still_applies: no refund, leave cooldown running
func _apply_cancel_outcome(ability_id: StringName, ability: MobaAbility) -> void:
	match ability.on_cancel:
		MobaAbility.OnCancel.FULL_REFUND:
			_refund_and_undo_cooldown(ability_id, ability.resource_cost)
		MobaAbility.OnCancel.PARTIAL_REFUND:
			var refund_amount := ability.resource_cost * ability.refund_resource_on_cancel
			_refund_and_undo_cooldown(ability_id, refund_amount)
		MobaAbility.OnCancel.NO_REFUND:
			_undo_cooldown_only(ability_id)
		MobaAbility.OnCancel.COOLDOWN_STILL_APPLIES:
			# No-op: cooldown stays running, no resource refund
			pass


## Refund resource and undo the cooldown for a cancelled ability.
func _refund_and_undo_cooldown(ability_id: StringName, refund_amount: float) -> void:
	_combatant.restore_resource(refund_amount)
	_combatant.cancel_cooldown(ability_id)


## Undo the cooldown for a cancelled ability without refunding resource.
func _undo_cooldown_only(ability_id: StringName) -> void:
	_combatant.cancel_cooldown(ability_id)


## Resolve a cast that has expired: apply damage and effects to the target.
## Guards against freed/invalid targets with is_instance_valid().
func _resolve() -> void:
	if _cast_in_progress == null:
		return

	var ability := _cast_in_progress.ability
	var resolved_target := _cast_in_progress.resolved_target

	# Clear the in-progress cast BEFORE resolving effects, so a cancel() call
	# made within any effect application finds nothing in progress (per Scope's
	# "resolution wins ties" guarantee).
	_cast_in_progress = null

	# Guard against freed/invalid targets
	if resolved_target == null or not is_instance_valid(resolved_target):
		return

	# Apply damage and effects
	_apply_damage_and_effects(ability, resolved_target)


## Apply damage and effects from a resolved cast.
## This is the deferred resolution step for cast_time > 0 abilities.
func _apply_damage_and_effects(ability: MobaAbility, target: Node) -> void:
	# Step 1: Apply damage
	_apply_damage(ability, target)

	# Step 2: Apply effects (crowd control, buffs, debuffs)
	_apply_effects(ability, target)


## Apply damage from a resolved cast.
func _apply_damage(ability: MobaAbility, target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return

	var raw_amount := _compute_scaled_damage(ability)
	if raw_amount <= 0.0:
		return

	var target_combatant := target.get_node_or_null("MobaCombatant")
	if target_combatant == null:
		return

	var damage := MobaDamage.new(raw_amount, _damage_type_to_moba(ability.damage_type), _combatant)
	target_combatant.apply_damage(damage)


## Compute the raw damage amount for a cast: base_damage plus ability.scaling ratios.
func _compute_scaled_damage(ability: MobaAbility) -> float:
	var amount := ability.base_damage
	for stat_name in ability.scaling:
		var ratio: float = ability.scaling[stat_name]
		amount += ratio * _combatant.get_stat(StringName(stat_name))
	return amount


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


## Apply effects from a resolved cast.
func _apply_effects(ability: MobaAbility, target: Node) -> void:
	var target_combatant := target.get_node_or_null("MobaCombatant")

	# Apply crowd control from ability.crowd_control to the target
	if ability.crowd_control != null and target_combatant != null:
		target_combatant.apply_crowd_control(ability.crowd_control, _combatant)

	# Apply buffs to the caster's combatant (self)
	var caster_effects: MobaEffectContainer = _combatant.get_effect_container()
	for buff in ability.buffs:
		caster_effects.apply_modifier(buff, StringName(ability.id))

	# Apply debuffs to the resolved target's combatant
	if target_combatant != null:
		var target_effects: MobaEffectContainer = target_combatant.get_effect_container()
		for debuff in ability.debuffs:
			target_effects.apply_modifier(debuff, StringName(ability.id))

	# Apply healing to the caster
	if ability.heal_amount > 0.0:
		_combatant.apply_healing(ability.heal_amount)

	# Apply shield to the caster
	if ability.shield_amount > 0.0:
		_combatant.apply_shield(ability.shield_amount, StringName(ability.id), ability.duration)
