## Per-ability cooldown and charge ledger.
##
## Tracks per-ability cooldown remaining and available charges, advancing on an
## explicit tick(delta).
## Each ability maintains one timer that counts down the remaining cooldown. When the timer
## expires and charges are below max_charges, one charge is granted and the timer restarts.
##
## Haste is applied at cooldown start time and a running timer is never retroactively recomputed.
## This means haste changes do not affect timers already in progress—the effective cooldown
## duration is locked in when start() is called.
##
## Time advances only through tick(delta); there is no _process or _physics_process.
class_name MobaCooldowns
extends RefCounted


# Internal state for each ability's cooldown
class _AbilityState:
	var max_charges: int
	var available_charges: int
	var timer_duration: float  # Effective cooldown (after haste applied at start time)
	var timer_remaining: float  # Current time left on the active timer

	# True when the most recent start() is the call that began the running
	# timer, rather than consuming a charge while an earlier recharge timer
	# was already in flight. cancel() undoes a timer only in that case.
	var timer_started_by_last_start: bool = false


# Dictionary mapping ability_id to _AbilityState
var _ability_states: Dictionary = {}


## Start or use a cooldown for the given ability.
##
## If the ability has not been started before, initializes it with max_charges available.
## Decrements one available charge and starts a timer only if no timer is already running.
## The effective cooldown duration is computed from base_cooldown and haste at this moment
## and is stored; a running timer's duration is never retroactively changed.
##
## Args:
##     ability_id: Unique identifier for the ability
##     base_cooldown: Base cooldown duration in seconds
##     haste: Ability Haste value (affects cooldown duration only at start time)
##     max_charges: Maximum number of charges this ability can have
func start(ability_id: StringName, base_cooldown: float, haste: float, max_charges: int) -> void:
	# Initialize if we've never seen this ability before
	if not ability_id in _ability_states:
		var state: _AbilityState = _AbilityState.new()
		state.max_charges = max_charges
		state.available_charges = max_charges
		state.timer_duration = 0.0
		state.timer_remaining = 0.0
		_ability_states[ability_id] = state

	var state: _AbilityState = _ability_states[ability_id]

	# Decrement a charge
	state.available_charges = maxi(0, state.available_charges - 1)

	# Start the timer only if none is currently running
	if state.timer_remaining <= 0.0:
		state.timer_duration = MobaFormulas.effective_cooldown(base_cooldown, haste)
		state.timer_remaining = state.timer_duration
		state.timer_started_by_last_start = true
	else:
		# A recharge timer for an earlier activation is still running; this
		# start() only spent a charge, so there is no timer of its own to undo.
		state.timer_started_by_last_start = false


## Get the remaining cooldown time for the given ability.
##
## Returns the time remaining on the active timer, or 0.0 if no timer is running or
## if the ability has not been started.
##
## Args:
##     ability_id: Unique identifier for the ability
##
## Returns:
##     Remaining cooldown time in seconds (0.0 if not started or timer not active)
func remaining(ability_id: StringName) -> float:
	if not ability_id in _ability_states:
		return 0.0

	var state: _AbilityState = _ability_states[ability_id]
	return maxf(0.0, state.timer_remaining)


## Get the number of available charges for the given ability.
##
## Returns the current charge count. If the ability has never been started, returns 0
## (the unknown/default state, since max_charges is not known).
##
## Args:
##     ability_id: Unique identifier for the ability
##
## Returns:
##     Number of available charges (0 if not started)
func charges(ability_id: StringName) -> int:
	if not ability_id in _ability_states:
		return 0

	var state: _AbilityState = _ability_states[ability_id]
	return state.available_charges


## Check if the ability is ready to use.
##
## An ability is ready if it has at least one charge and no active timer (remaining <= 0).
## If the ability has never been started, returns true (unknown abilities are ready).
##
## Args:
##     ability_id: Unique identifier for the ability
##
## Returns:
##     true if the ability can be activated, false otherwise
func is_ready(ability_id: StringName) -> bool:
	if not ability_id in _ability_states:
		return true

	var state: _AbilityState = _ability_states[ability_id]
	return state.available_charges > 0 and state.timer_remaining <= 0.0


## Advance all active timers by the given delta time.
##
## Decrements each running timer. When a timer expires and charges are still below max_charges,
## grants one charge and restarts the timer from its stored duration, correctly carrying any
## overshoot so that large deltas do not lose time. When max_charges is reached, the timer
## stops at 0.0.
##
## Args:
##     delta: Time elapsed in seconds
func tick(delta: float) -> void:
	for state: _AbilityState in _ability_states.values():
		if state.timer_remaining > 0.0:
			state.timer_remaining -= delta

			# Handle timer expiry and charge regeneration with overshoot
			while state.timer_remaining <= 0.0 and state.available_charges < state.max_charges:
				state.available_charges += 1
				state.timer_remaining += state.timer_duration

			# Stop the timer when max charges is reached
			if state.available_charges >= state.max_charges:
				state.timer_remaining = 0.0


## Get the effective (haste-adjusted) duration locked in when the active timer started.
##
## Args:
##     ability_id: Unique identifier for the ability
##
## Returns:
##     Effective cooldown duration in seconds (0.0 if not started)
func duration(ability_id: StringName) -> float:
	if not ability_id in _ability_states:
		return 0.0

	var state: _AbilityState = _ability_states[ability_id]
	return maxf(0.0, state.timer_duration)


## Get the maximum number of charges recorded for the given ability.
##
## Named maximum_charges() rather than max_charges() because start() already
## takes a max_charges parameter, which GDScript treats as a name collision.
##
## Args:
##     ability_id: Unique identifier for the ability
##
## Returns:
##     Maximum charge count (0 if not started)
func maximum_charges(ability_id: StringName) -> int:
	if not ability_id in _ability_states:
		return 0

	var state: _AbilityState = _ability_states[ability_id]
	return state.max_charges


## Undo the cooldown and charge state that the most recent start() established.
## Restores the consumed charge, and clears the timer only if that start() is
## what began it (as if start was never called).
##
## On a multi-charge ability a second activation spends a charge while the
## first activation's recharge timer is still running. Cancelling that second
## activation must leave the in-flight timer alone: clearing it would strand
## the ability below max charges forever, since tick() only advances a timer
## that is still above zero.
##
## A no-op if the ability has never been started.
##
## Args:
##     ability_id: Unique identifier for the ability
func cancel(ability_id: StringName) -> void:
	if not ability_id in _ability_states:
		return

	var state: _AbilityState = _ability_states[ability_id]

	# Restore the consumed charge
	state.available_charges = mini(state.available_charges + 1, state.max_charges)

	# Clear the timer only when this start() is the call that began it.
	if state.timer_started_by_last_start:
		state.timer_remaining = 0.0
		state.timer_duration = 0.0

	state.timer_started_by_last_start = false


## Clear all active cooldowns and restore all abilities to maximum charges.
## Called on respawn to reset ability availability.
func clear_all_cooldowns() -> void:
	for state: _AbilityState in _ability_states.values():
		state.available_charges = state.max_charges
		state.timer_remaining = 0.0
		state.timer_duration = 0.0
		state.timer_started_by_last_start = false


## Serialize per-ability cooldown state as an Array of plain Dictionaries, for
## replication. Each entry carries ability_id, timer_remaining and
## available_charges.
##
## Plain data only, so the value survives a MultiplayerSynchronizer round trip
## without carrying an _AbilityState object reference across the wire.
func get_snapshot() -> Array:
	var result: Array = []
	for ability_id in _ability_states:
		var state: _AbilityState = _ability_states[ability_id]
		var serialized := {
			"ability_id": ability_id,
			"timer_remaining": state.timer_remaining,
			"available_charges": state.available_charges,
		}
		result.append(serialized)
	return result


## Rebuild cooldown state from a snapshot produced by get_snapshot().
##
## `abilities` supplies max_charges, which the snapshot deliberately omits: it
## comes from the identically-loaded ability definition on every peer, so
## replicating it would create a second source of truth for a static value.
## An entry naming an ability this peer does not know is skipped rather than
## guessed at.
func set_snapshot(snapshot: Array, abilities: Dictionary) -> void:
	_ability_states.clear()
	for entry in snapshot:
		if not (entry is Dictionary):
			continue

		var ability_id = entry.get("ability_id", &"")
		if not (ability_id in abilities):
			continue

		var ability = abilities[ability_id]
		var timer_remaining := float(entry.get("timer_remaining", 0.0))
		var state: _AbilityState = _AbilityState.new()
		state.max_charges = ability.charges if ability else 1
		state.available_charges = int(entry.get("available_charges", 0))
		state.timer_remaining = timer_remaining
		# The snapshot carries elapsed time, not the ability's full cooldown.
		# timer_duration is only used for progress display, so seeding it from
		# the remaining time keeps a restored cooldown self-consistent.
		state.timer_duration = timer_remaining
		state.timer_started_by_last_start = timer_remaining > 0.0
		_ability_states[ability_id] = state
