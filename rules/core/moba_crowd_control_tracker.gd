## Crowd control ledger for a single combatant: the active hard-CC entries
## and their max(remaining, new) stacking, the single active displacement,
## per-tick duration expiry, and the CROWD_CONTROLLED / AIRBORNE transitions
## those drive.
##
## Split out of MobaCombatant to keep that file under the project's
## max-file-lines gate (see .gdlintrc). A private implementation detail of
## MobaCombatant, the same way MobaShieldTracker, MobaCastTracker,
## MobaChannelTracker, and MobaDeathHandler are -- MobaCombatant's
## apply_crowd_control(), has_crowd_control(), and can_perform_action()
## remain the sole public seam; callers never reach this class directly.
class_name MobaCrowdControlTracker
extends RefCounted

## The seven hard-CC types that enter/hold CROWD_CONTROLLED. SLOW (a stat-modifier
## debuff per #219) is deliberately excluded: apply_crowd_control() refuses it.
const _HARD_CC_TYPES := [
	MobaCrowdControlSpec.CCType.STUN,
	MobaCrowdControlSpec.CCType.ROOT,
	MobaCrowdControlSpec.CCType.SILENCE,
	MobaCrowdControlSpec.CCType.DISARM,
	MobaCrowdControlSpec.CCType.FEAR,
	MobaCrowdControlSpec.CCType.TAUNT,
	MobaCrowdControlSpec.CCType.BLIND,
]

## The three displacement types: one-shot forced moves via _apply_displacement(),
## never subject to the hard-CC max(remaining, new) stacking rule (#221).
const _DISPLACEMENT_TYPES := [
	MobaCrowdControlSpec.CCType.KNOCKBACK,
	MobaCrowdControlSpec.CCType.PULL,
	MobaCrowdControlSpec.CCType.KNOCK_UP,
]

## Actions gated by active hard-CC entries in can_perform_action().
const _CC_GATED_ACTIONS := [&"move", &"basic_attack", &"ability"]


## Internal entry for an active crowd control effect.
class _CCEntry:
	var type: int  # CCType enum value
	var remaining: float  # Time left in seconds
	var source: MobaCombatant  # The combatant who applied this CC
	var spec: MobaCrowdControlSpec  # The effect spec (carries magnitude for BLIND/SLOW)

	func _init(
		p_type: int, p_remaining: float, p_source: MobaCombatant, p_spec: MobaCrowdControlSpec
	) -> void:
		type = p_type
		remaining = p_remaining
		source = p_source
		spec = p_spec


## Internal entry for an active displacement effect (KNOCKBACK, PULL, KNOCK_UP).
class _DisplacementEntry:
	var type: int  # CCType enum value (KNOCKBACK, PULL, or KNOCK_UP)
	var remaining: float  # Time left in seconds
	var source: MobaCombatant  # The combatant who applied this displacement
	var spec: MobaCrowdControlSpec  # The effect spec
	var direction: Vector3  # The direction to move (normalized)
	var speed: float  # The speed in units per second
	var queued_effect: MobaCrowdControlSpec  # Optional follow-up effect (for KNOCK_UP)
	var queued_effect_source: MobaCombatant  # Source for the queued effect

	func _init(
		p_type: int,
		p_remaining: float,
		p_source: MobaCombatant,
		p_spec: MobaCrowdControlSpec,
		p_direction: Vector3,
		p_speed: float,
		p_queued_effect: MobaCrowdControlSpec = null,
		p_queued_effect_source: MobaCombatant = null,
	) -> void:
		type = p_type
		remaining = p_remaining
		source = p_source
		spec = p_spec
		direction = p_direction
		speed = p_speed
		queued_effect = p_queued_effect
		queued_effect_source = p_queued_effect_source


## The combatant this tracker belongs to. Every state transition below goes
## through its sibling MobaStateMachine, and the cast/channel interrupt goes
## through its own public seam, so this class owns the ledger and nothing else.
var _combatant: MobaCombatant = null

## Active crowd control entries keyed by CCType. Maps int (CCType) to _CCEntry.
## Multiple entries of different types can exist simultaneously; only one per type.
var _active_cc_entries: Dictionary = {}

## Active displacement entry (KNOCKBACK, PULL, or KNOCK_UP). Only one displacement
## can be active at a time. null when no displacement is active.
var _active_displacement: _DisplacementEntry = null


func _init(p_combatant: MobaCombatant) -> void:
	_combatant = p_combatant


## Apply a crowd control effect. Routes to displacement or hard CC by type;
## SLOW and any unrecognized type are refused.
func apply(spec: MobaCrowdControlSpec, source: MobaCombatant) -> void:
	var state_machine := _combatant.get_state_machine()

	if spec.type in _DISPLACEMENT_TYPES:
		_apply_displacement(spec, source, state_machine)
	elif spec.type in _HARD_CC_TYPES:
		_apply_hard_cc(spec, source, state_machine)
	# SLOW and any unrecognized type are refused.


## Whether an entry of the given CCType is currently active.
func has(cc_type: int) -> bool:
	return cc_type in _active_cc_entries


## Whether no hard-CC entry is active at all.
func is_empty() -> bool:
	return _active_cc_entries.is_empty()


## The source combatant of an active entry, or null if the type is not active.
func get_source(cc_type: int) -> MobaCombatant:
	if cc_type not in _active_cc_entries:
		return null
	var entry = _active_cc_entries[cc_type]
	return entry.source


## Seconds remaining on an active entry, or 0.0 if the type is not active.
func get_remaining(cc_type: int) -> float:
	if cc_type not in _active_cc_entries:
		return 0.0
	var entry = _active_cc_entries[cc_type]
	return entry.remaining


## The spec of an active entry, or null if the type is not active.
func get_spec(cc_type: int) -> MobaCrowdControlSpec:
	if cc_type not in _active_cc_entries:
		return null
	var entry = _active_cc_entries[cc_type]
	return entry.spec


## Whether `action` is one of the actions hard CC can gate at all. Actions
## outside this set are the state machine's business alone.
func gates_action(action: StringName) -> bool:
	return action in _CC_GATED_ACTIONS


## Whether any active hard-CC entry blocks `action`. Only meaningful for the
## CC-gated actions (move/basic_attack/ability) with at least one active entry.
func blocks_action(action: StringName) -> bool:
	var blocked := false
	match action:
		&"move":
			for cc_entry in _active_cc_entries.values():
				blocked = blocked or MobaCrowdControl.blocks_move(cc_entry.type)
		&"basic_attack":
			for cc_entry in _active_cc_entries.values():
				blocked = blocked or MobaCrowdControl.blocks_basic_attack(cc_entry.type)
		&"ability":
			for cc_entry in _active_cc_entries.values():
				blocked = blocked or MobaCrowdControl.blocks_ability(cc_entry.type)
	return blocked


## Whether a displacement (KNOCKBACK, PULL, or KNOCK_UP) is currently active.
func has_displacement() -> bool:
	return _active_displacement != null


## Forced movement direction/magnitude while a displacement is active, scaled by
## speed / ActorBody3D.SPEED so ActorBody3D._physics_process()'s unmodified
## velocity.x = move_direction.x * SPEED formula covers the authored distance
## over the authored duration, not always base walking speed. Vector3.ZERO
## when no displacement is active.
func forced_move_direction() -> Vector3:
	if _active_displacement == null:
		return Vector3.ZERO

	return _active_displacement.direction * (_active_displacement.speed / ActorBody3D.SPEED)


## Queue a follow-up crowd control effect applied when a knock-up lands (e.g.
## knock-up then stun). No-op unless the active displacement is KNOCK_UP.
func queue_follow_up_effect(effect_spec: MobaCrowdControlSpec, source: MobaCombatant) -> void:
	if (
		_active_displacement == null
		or _active_displacement.type != MobaCrowdControlSpec.CCType.KNOCK_UP
	):
		return

	_active_displacement.queued_effect = effect_spec
	_active_displacement.queued_effect_source = source


## Drop every entry and any active displacement without touching the state
## machine -- matches MobaCombatant.clear_all_active_effects()'s contract of
## leaving signals and state transitions to the caller, who may be changing
## other state in the same operation.
func clear() -> void:
	_active_cc_entries.clear()
	_active_displacement = null


## Advance crowd control durations and expire entries.
## For hard CC: Returns to IDLE once the last active entry expires.
## For displacement: Expires displacement when duration is reached, and for KNOCK_UP,
## applies any queued follow-up effect when transitioning from AIRBORNE to IDLE.
func tick(delta: float) -> void:
	var state_machine := _combatant.get_state_machine()

	# Advance all hard CC entries
	for cc_type in _active_cc_entries.keys():
		var entry = _active_cc_entries[cc_type]
		entry.remaining -= delta
		if entry.remaining <= 0.0:
			_active_cc_entries.erase(cc_type)

	# If no hard CC entries remain, return to IDLE (if we're in CROWD_CONTROLLED)
	if _active_cc_entries.is_empty() and state_machine != null:
		if state_machine.current_state == MobaState.CROWD_CONTROLLED:
			state_machine.try_enter(MobaState.IDLE)

	# Advance displacement entry
	if _active_displacement != null:
		_active_displacement.remaining -= delta
		if _active_displacement.remaining <= 0.0:
			# Displacement is expiring
			var was_knock_up := _active_displacement.type == MobaCrowdControlSpec.CCType.KNOCK_UP
			var queued_effect := _active_displacement.queued_effect
			var queued_effect_source := _active_displacement.queued_effect_source
			_active_displacement = null

			# For KNOCK_UP, handle landing logic
			if was_knock_up and state_machine != null:
				if state_machine.current_state == MobaState.AIRBORNE:
					# Transition to IDLE (the state machine handles this)
					state_machine.try_enter(MobaState.IDLE)

					# Apply any queued follow-up effect on landing
					if queued_effect != null:
						_combatant.apply_crowd_control(queued_effect, queued_effect_source)


## Apply a displacement crowd control effect (KNOCKBACK, PULL, KNOCK_UP).
##
## Replaces any existing displacement outright (last write wins; unlike hard CC,
## displacement is never subject to the max(remaining, new) stacking rule since
## it resolves as a one-shot forced move, not a held duration).
##
## spec.magnitude is a validated 0.0-1.0 fraction (rules/tools/validate_ability_data.gd),
## the same "fraction of full effect" semantics SLOW already applies to movement_speed.
## Here it is a fraction of the body's own ActorBody3D.SPEED, so a 0.0 magnitude
## means no forced movement rather than an unexplained default speed.
##
## KNOCK_UP additionally enters AIRBORNE with cause KNOCK_UP. KNOCKBACK/PULL
## instead interrupt a "displacement_only" state (currently only DASHING) by
## cutting it short into IDLE -- that state leaving is the interrupt itself,
## since only displacement is ever accepted against that policy (#220).
func _apply_displacement(
	spec: MobaCrowdControlSpec, source: MobaCombatant, state_machine: MobaStateMachine
) -> void:
	var final_duration := spec.duration
	if spec.affected_by_tenacity:
		var tenacity := _combatant.get_stat(MobaStatBlock.TENACITY)
		final_duration = MobaFormulas.crowd_control_duration(spec.duration, tenacity)

	var away := spec.type != MobaCrowdControlSpec.CCType.PULL
	var direction := _compute_displacement_direction(source, away)
	var speed := spec.magnitude * ActorBody3D.SPEED

	_active_displacement = _DisplacementEntry.new(
		spec.type, final_duration, source, spec, direction, speed
	)

	if state_machine == null:
		return

	if spec.type == MobaCrowdControlSpec.CCType.KNOCK_UP:
		state_machine.try_enter(
			MobaState.AIRBORNE, final_duration, MobaState.AirborneCause.KNOCK_UP
		)
	elif state_machine.hard_cc_policy() == &"displacement_only":
		state_machine.try_enter(MobaState.IDLE)


## Apply a hard crowd control effect (STUN, ROOT, SILENCE, DISARM, FEAR, TAUNT, BLIND).
func _apply_hard_cc(
	spec: MobaCrowdControlSpec, source: MobaCombatant, state_machine: MobaStateMachine
) -> void:
	# Cancel an in-progress cast or channel first, if the ability in progress
	# declares itself cancellable_by_hard_cc.
	_combatant.interrupt_for_hard_crowd_control()

	# Consult state machine policy for hard-CC types
	var policy := state_machine.hard_cc_policy() if state_machine != null else &"no"
	if policy == &"no" or policy == &"displacement_only":
		return

	# Enter CROWD_CONTROLLED (durationless state) if not already there
	# "yes" and "breaks_channel" both permit entry
	if state_machine != null:
		if state_machine.current_state != MobaState.CROWD_CONTROLLED:
			state_machine.try_enter(MobaState.CROWD_CONTROLLED)

	# Compute final duration
	var final_duration := spec.duration
	if spec.affected_by_tenacity:
		var tenacity := _combatant.get_stat(MobaStatBlock.TENACITY)
		final_duration = MobaFormulas.crowd_control_duration(spec.duration, tenacity)

	# Track the entry (max(remaining, new_duration) rule for same CCType)
	var cc_type := spec.type
	if cc_type in _active_cc_entries:
		var existing_entry = _active_cc_entries[cc_type]
		existing_entry.remaining = maxf(existing_entry.remaining, final_duration)
		existing_entry.source = source
		existing_entry.spec = spec
	else:
		var new_entry = _CCEntry.new(cc_type, final_duration, source, spec)
		_active_cc_entries[cc_type] = new_entry


## Compute a normalized displacement direction between this combatant and source:
## away=true points from source to this (KNOCKBACK/KNOCK_UP), away=false points
## from this to source (PULL). Falls back to Vector3.BACK/FORWARD respectively
## when either position cannot be determined or the two positions coincide.
func _compute_displacement_direction(source: MobaCombatant, away: bool) -> Vector3:
	var default := Vector3.BACK if away else Vector3.FORWARD
	var this_pos = _get_parent_position(_combatant)
	var source_pos = _get_parent_position(source)

	if this_pos == null or source_pos == null:
		return default

	var delta: Vector3 = (
		(this_pos as Vector3) - (source_pos as Vector3)
		if away
		else (source_pos as Vector3) - (this_pos as Vector3)
	)
	return delta.normalized() if delta.length() > 0.0 else default


## The parent node's global_position, or null when there is no parent or the
## parent does not carry one (MobaCombatant is often tested bare, outside any
## body). Returns Variant precisely so "no position" stays distinguishable
## from Vector3.ZERO.
func _get_parent_position(combatant: MobaCombatant) -> Variant:
	var parent := combatant.get_parent()
	if parent == null:
		return null
	return parent.get("global_position")
