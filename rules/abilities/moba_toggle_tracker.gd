## In-progress toggle ledger for a single combatant.
##
## Holds which ability, if any, is currently toggled on for this combatant,
## advances its drain accumulation on an explicit tick(delta), and deactivates
## it based on resource exhaustion, death, or crowd control (silence).
##
## Time advances only through tick(delta); there is no _process or
## _physics_process. MobaCombatant.tick() remains the sole per-frame entry
## point and drives this tracker from inside it, the same way it drives the
## MobaCastTracker and MobaChannelTracker ledgers.
##
## A toggle's resource_cost is the per-second drain rate while active. Drain
## accumulates at a fixed 1-second interval; if the combatant cannot afford a
## due drain, the toggle deactivates instead of going negative.
class_name MobaToggleTracker
extends RefCounted


## Data for a toggle that is currently active.
class _ToggleActive:
	var ability_id: StringName
	var ability: MobaAbility
	var resolved_targets: Array[Node]
	## Accumulated time since the last drain tick, for interval tracking
	var time_since_last_drain: float

	func _init(
		p_ability_id: StringName,
		p_ability: MobaAbility,
		p_targets: Array[Node],
	) -> void:
		ability_id = p_ability_id
		ability = p_ability
		resolved_targets = p_targets
		time_since_last_drain = 0.0


## The combatant this tracker belongs to.
var _combatant: MobaCombatant = null

## The toggle currently active, or null when none is.
var _toggle_active: _ToggleActive = null


func _init(p_combatant: MobaCombatant) -> void:
	_combatant = p_combatant


## True while a toggle is active.
func is_toggled_on(ability_id: StringName) -> bool:
	return _toggle_active != null and _toggle_active.ability_id == ability_id


## The ability currently toggled on, or null when no toggle is active.
func current_ability() -> MobaAbility:
	if _toggle_active == null:
		return null
	return _toggle_active.ability


## Start a toggle that will drain per-second resource via tick().
## Called by MobaAbilityAction when an ability with targeting_type == TOGGLE is activated.
##
## Args:
##     ability_id: The ability being toggled on
##     ability: The resolved MobaAbility resource
##     resolved_targets: The targets (may be empty; guarded in resolution)
func start(
	ability_id: StringName,
	ability: MobaAbility,
	resolved_targets: Array[Node],
) -> void:
	_toggle_active = _ToggleActive.new(ability_id, ability, resolved_targets)


## Deactivate the currently active toggle, if any. A no-op if no toggle is active.
##
## Clearing the ledger is the whole teardown: whatever the toggle already
## drained stays spent, the same way a channel tick's resource is never
## refunded. Unlike MobaChannelTracker.break_channel(), there is no
## on-deactivate outcome to apply, so no null guard is needed either -- the
## assignment is already a no-op when nothing is active.
func deactivate() -> void:
	_toggle_active = null


## Advance the active toggle by delta seconds and apply drains at 1-second
## intervals. Deactivates if resource is exhausted or silence is applied.
func tick(delta: float) -> void:
	if _toggle_active == null:
		return

	# Check if silence is applied; if so, deactivate the toggle
	if _combatant.has_crowd_control(MobaCrowdControlSpec.CCType.SILENCE):
		deactivate()
		return

	# Accumulate time for drain interval (fixed 1-second drain)
	_toggle_active.time_since_last_drain += delta

	# Drain per-second resource at 1-second intervals
	const DRAIN_INTERVAL := 1.0
	while _toggle_active != null and _toggle_active.time_since_last_drain >= DRAIN_INTERVAL:
		var ability := _toggle_active.ability
		# Try to spend the per-second drain cost
		if not _combatant.spend_resource(ability.resource_cost):
			# Out of resource: deactivate the toggle
			deactivate()
			return

		# Apply effects to each target via resolve() - same implementation
		# an instant ability uses. Targets may have been freed while the toggle was active,
		# and resolve() guards null/freed targets, leaving the spent resource unreturned.
		for target in _toggle_active.resolved_targets:
			MobaAbilityAction.resolve(ability, target, _combatant)

		# Consume the drain interval
		_toggle_active.time_since_last_drain -= DRAIN_INTERVAL
