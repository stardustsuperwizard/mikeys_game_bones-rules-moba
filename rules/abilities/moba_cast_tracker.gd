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
	var resolved_targets: Array[Node]
	var remaining_time: float
	var context: MobaCastContext  # Needed to re-resolve GROUND abilities at resolution time

	func _init(
		p_ability_id: StringName,
		p_ability: MobaAbility,
		p_targets: Array[Node],
		p_time: float,
		p_context: MobaCastContext = null
	) -> void:
		ability_id = p_ability_id
		ability = p_ability
		resolved_targets = p_targets
		remaining_time = p_time
		context = p_context


## The combatant this tracker belongs to.
var _combatant: MobaCombatant = null

## The cast currently in progress, or null when none is.
var _cast_in_progress: _CastInProgress = null


func _init(p_combatant: MobaCombatant) -> void:
	_combatant = p_combatant


## True while a cast is in progress.
func is_casting() -> bool:
	return _cast_in_progress != null


## The ability being cast, or null when no cast is in progress.
func current_ability() -> MobaAbility:
	if _cast_in_progress == null:
		return null
	return _cast_in_progress.ability


## Seconds remaining in the current cast, or 0.0 when not casting.
func get_cast_time_remaining() -> float:
	if _cast_in_progress == null:
		return 0.0
	return _cast_in_progress.remaining_time


## Start a cast that will resolve after its cast_time elapses via tick().
## Called by MobaAbilityAction when an ability with cast_time > 0 is activated.
##
## Args:
##     ability_id: The ability being cast
##     ability: The resolved MobaAbility resource
##     resolved_targets: The targets (may be empty; guarded in resolution)
##     cast_time: Remaining time until resolution, in seconds
##     context: The MobaCastContext (needed for GROUND re-resolution)
func start(
	ability_id: StringName,
	ability: MobaAbility,
	resolved_targets: Array[Node],
	cast_time: float,
	context: MobaCastContext = null
) -> void:
	_cast_in_progress = _CastInProgress.new(ability_id, ability, resolved_targets, cast_time, context)


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


## Resolve a cast that has expired: apply damage and effects to all targets.
##
## For GROUND abilities, targets are re-resolved at resolution time (after the
## cast delay) so targets that moved out of radius during the delay are not hit.
## For all other targeting types, pre-resolved targets from activation time are used.
##
## Resolution runs through MobaAbilityAction.resolve() -- the same implementation
## an instant ability uses -- so a cast_time ability and an instant one cannot
## resolve differently. It guards null/freed targets itself, leaving the
## already-committed resource and cooldown spent.
##
## The in-progress cast is cleared BEFORE applying effects, so a cancel() call
## made within effect application finds nothing in progress (per Scope's
## "resolution wins ties" guarantee).
func _resolve() -> void:
	if _cast_in_progress == null:
		return

	var ability := _cast_in_progress.ability
	var targets_to_resolve: Array[Node]

	# For GROUND abilities, re-resolve targets at resolution time to capture
	# the aimed point after the cast delay. For all other types, use pre-resolved
	# targets from activation time.
	if ability.targeting_type == MobaAbility.TargetingType.GROUND and _cast_in_progress.context != null:
		# Re-resolve GROUND targets at this moment (after cast_time has elapsed)
		var caster := _cast_in_progress.context.caster
		var ground_point := _cast_in_progress.context.ground_point
		targets_to_resolve = MobaTargeting.resolve_ground(caster, ground_point, ability)
	else:
		# Use pre-resolved targets from activation time
		targets_to_resolve = _cast_in_progress.resolved_targets

	# Clear the in-progress cast BEFORE resolving effects, so a cancel() call
	# made within any effect application finds nothing in progress (per Scope's
	# "resolution wins ties" guarantee).
	_cast_in_progress = null

	# Apply resolution to each target through the shared resolve() implementation
	for target in targets_to_resolve:
		MobaAbilityAction.resolve(ability, target, _combatant)
