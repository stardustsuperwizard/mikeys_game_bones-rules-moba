## In-progress channel ledger for a single combatant.
##
## Holds the channel a combatant is currently performing (an ability whose
## channel_duration > 0), advances it on an explicit tick(delta), and applies
## the effect on each declared tick interval. Tracks whether at least one tick
## has applied as an explicit boolean, not derived from elapsed time.
##
## Time advances only through tick(delta); there is no _process or
## _physics_process. MobaCombatant.tick() remains the sole per-frame entry
## point and drives this tracker from inside it, the same way it drives the
## MobaCastTracker and MobaCooldowns ledgers.
##
## Breaking a channel after at least one tick has applied - whether through
## MobaAbilityCaster.cancel() or a hard crowd control interrupt - has a fixed
## outcome: no refund (each tick independently spent its own resource), the
## cooldown stays running, and on_channel_break governs only buffs/debuffs.
class_name MobaChannelTracker
extends RefCounted


## Data for a channel that is currently in progress.
class _ChannelInProgress:
	var ability_id: StringName
	var ability: MobaAbility
	var resolved_targets: Array[Node]
	var elapsed_time: float
	var remaining_time: float
	## True once at least one tick has applied. Set when the first tick fires
	## (at t = 0), not derived from elapsed time.
	var has_applied_at_least_one_tick: bool = false
	## Accumulated time since the last tick was applied, for interval tracking
	var time_since_last_tick: float

	func _init(
		p_ability_id: StringName,
		p_ability: MobaAbility,
		p_targets: Array[Node],
		p_duration: float,
	) -> void:
		ability_id = p_ability_id
		ability = p_ability
		resolved_targets = p_targets
		elapsed_time = 0.0
		remaining_time = p_duration
		time_since_last_tick = 0.0


## The combatant this tracker belongs to.
var _combatant: MobaCombatant = null

## The channel currently in progress, or null when none is.
var _channel_in_progress: _ChannelInProgress = null


func _init(p_combatant: MobaCombatant) -> void:
	_combatant = p_combatant


## True while a channel is in progress.
func is_channeling() -> bool:
	return _channel_in_progress != null


## The ability being channeled, or null when no channel is in progress.
func current_ability() -> MobaAbility:
	if _channel_in_progress == null:
		return null
	return _channel_in_progress.ability


## True if the channel has applied at least one tick. False otherwise.
func has_applied_at_least_one_tick() -> bool:
	if _channel_in_progress == null:
		return false
	return _channel_in_progress.has_applied_at_least_one_tick


## Seconds remaining in the current channel, or 0.0 when not channeling.
func get_channel_time_remaining() -> float:
	if _channel_in_progress == null:
		return 0.0
	return _channel_in_progress.remaining_time


## Start a channel that will tick according to channel_tick_interval via tick().
## Called by MobaAbilityAction when an ability with channel_duration > 0 is activated.
##
## Applies the first tick immediately (t = 0), then subsequent ticks occur at
## the declared channel_tick_interval.
##
## Args:
##     ability_id: The ability being channeled
##     ability: The resolved MobaAbility resource
##     resolved_targets: The targets (may be empty; guarded in resolution)
##     channel_duration: Total duration of the channel, in seconds
func start(
	ability_id: StringName, ability: MobaAbility, resolved_targets: Array[Node], channel_duration: float
) -> void:
	_channel_in_progress = _ChannelInProgress.new(
		ability_id, ability, resolved_targets, channel_duration
	)

	# Apply the first tick immediately (t = 0)
	_apply_tick()


## Break an in-progress channel. A no-op if no channel is in progress.
## Applies the on_channel_break outcome (effects cleanup).
##
## This is called when a channel is explicitly cancelled via MobaAbilityCaster.cancel(),
## or when a hard CC interrupt lands during ABILITY_CHANNEL state. Unlike cast
## cancellation, channel breaking does NOT consult on_cancel or refund resource/cooldown.
## Each tick independently spent its own resource, and the cooldown started at commit
## keeps running.
func break_channel() -> void:
	if _channel_in_progress == null:
		return

	var ability := _channel_in_progress.ability
	var ability_id := _channel_in_progress.ability_id

	# Only apply on_channel_break effect cleanup if at least one tick has already applied.
	# Channels cannot be broken before the first tick because the first tick fires at t = 0,
	# so breaking a channel always means at least one tick already applied in practice.
	if _channel_in_progress.has_applied_at_least_one_tick:
		_apply_channel_break_outcome(ability_id, ability)

	# Clear the in-progress channel
	_channel_in_progress = null


## Advance the in-progress channel by delta seconds and apply ticks when they
## reach their interval. Channel completes when remaining_time reaches zero.
func tick(delta: float) -> void:
	if _channel_in_progress == null:
		return

	_channel_in_progress.remaining_time -= delta
	_channel_in_progress.time_since_last_tick += delta

	# Apply ticks at the declared interval. The first tick fires at t = 0 (immediately
	# when the channel starts), then every channel_tick_interval thereafter.
	var tick_interval := _channel_in_progress.ability.channel_tick_interval
	if tick_interval <= 0.0:
		# Continuous channel (tick every frame)
		if _channel_in_progress.remaining_time > 0.0:
			_apply_tick()
	else:
		# Discrete ticks at interval. _apply_tick() breaks the channel (nulling
		# _channel_in_progress) when the caster runs out of per-tick resource,
		# so both loop conditions and the post-tick update must re-check it.
		while (
			_channel_in_progress != null
			and _channel_in_progress.time_since_last_tick >= tick_interval
		):
			if _channel_in_progress.remaining_time <= 0.0:
				break
			_apply_tick()
			if _channel_in_progress == null:
				break
			_channel_in_progress.time_since_last_tick -= tick_interval

	# When the channel reaches its expiry point, clean it up
	if _channel_in_progress != null and _channel_in_progress.remaining_time <= 0.0:
		_channel_in_progress = null


## Apply a single tick of the channel: spend per-tick resource and apply damage/effects.
func _apply_tick() -> void:
	if _channel_in_progress == null:
		return

	var ability := _channel_in_progress.ability

	# Spend the per-tick resource cost
	if not _combatant.spend_resource(ability.resource_cost):
		# Out of resource: break the channel
		break_channel()
		return

	# Mark that at least one tick has applied
	_channel_in_progress.has_applied_at_least_one_tick = true

	# Apply the tick's damage and effects to each target via resolve() - same implementation
	# an instant ability uses. Targets may have been freed while the channel was in progress,
	# and resolve() guards null/freed targets, leaving the spent resource unreturned.
	for target in _channel_in_progress.resolved_targets:
		MobaAbilityAction.resolve(ability, target, _combatant)


## Apply the on_channel_break outcome for buffs/debuffs based on the ability's policy.
##
## Implements the on_channel_break mapping:
## - no_effect_remaining: remove any buffs/debuffs this ability applied
## - partial_effect_already_applied: leave them running their normal duration
##
## Note: resource, cooldown, and damage are never reversed either way.
func _apply_channel_break_outcome(ability_id: StringName, ability: MobaAbility) -> void:
	match ability.on_channel_break:
		MobaAbility.OnChannelBreak.NO_EFFECT_REMAINING:
			# Remove buffs/debuffs this ability applied from both caster and all targets
			var caster_container := _combatant.get_effect_container()
			if caster_container != null:
				caster_container.remove_modifiers_from(ability_id)

			# Also remove from all targets that have combatants
			if _channel_in_progress != null:
				for resolved_target in _channel_in_progress.resolved_targets:
					if resolved_target != null and is_instance_valid(resolved_target):
						var target_combatant := (
							resolved_target.get_node_or_null("MobaCombatant") as MobaCombatant
						)
						if target_combatant != null:
							var target_container := target_combatant.get_effect_container()
							if target_container != null:
								target_container.remove_modifiers_from(ability_id)

		MobaAbility.OnChannelBreak.PARTIAL_EFFECT_ALREADY_APPLIED:
			# Leave effects running their normal duration - nothing to do here
			pass
