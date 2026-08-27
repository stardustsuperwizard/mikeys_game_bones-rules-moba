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
##
## Resolution runs through MobaAbilityAction.resolve() -- the same
## implementation an instant ability uses -- so a cast_time ability and an
## instant one cannot resolve differently. It guards a null/freed target
## itself, leaving the already-committed resource and cooldown spent.
func _resolve() -> void:
	if _cast_in_progress == null:
		return

	var ability := _cast_in_progress.ability

	# Left untyped on purpose: the target may have been freed while the cast
	# was in flight, and narrowing a freed object into a Node-typed local
	# would fault here rather than no-opping inside resolve().
	var resolved_target = _cast_in_progress.resolved_target

	# Clear the in-progress cast BEFORE resolving effects, so a cancel() call
	# made within any effect application finds nothing in progress (per Scope's
	# "resolution wins ties" guarantee).
	_cast_in_progress = null

	MobaAbilityAction.resolve(ability, resolved_target, _combatant)
