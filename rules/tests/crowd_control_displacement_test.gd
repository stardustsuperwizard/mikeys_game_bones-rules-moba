## Test suite for displacement crowd control effects: KNOCKBACK, PULL, and KNOCK_UP.
##
## Covers:
## - Knockback moves target away from source via get_forced_move_direction()
## - Pull moves target toward source via get_forced_move_direction()
## - Displacement effects interrupt DASHING (displacement_only policy)
## - Non-displacement hard CC refuses against displacement_only policy
## - affected_by_tenacity flag controls whether Tenacity reduces displacement duration
## - Knock-up enters AIRBORNE with cause KNOCK_UP (not JUMP)
## - Queued effects are applied on knock-up landing, not at application
class_name CrowdControlDisplacementTest

const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")


## Positioned node for testing distance calculations.
class _TestPositionedNode:
	extends Node
	var global_position: Vector3 = Vector3.ZERO


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_knockback_moves_away_from_source())
	all_violations.append_array(_test_pull_moves_toward_source())
	all_violations.append_array(_test_knockback_honors_affected_by_tenacity_false())
	all_violations.append_array(_test_knockback_honors_affected_by_tenacity_true())
	all_violations.append_array(_test_displacement_interrupts_dashing())
	all_violations.append_array(_test_hard_cc_refused_while_dashing_displacement_only())
	all_violations.append_array(_test_knock_up_enters_airborne_with_knock_up_cause())
	all_violations.append_array(_test_queued_effect_applied_on_landing())

	if all_violations.is_empty():
		return true

	printerr("\n=== Crowd Control Displacement Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Create a combatant with positioned parent, MobaCombatant, and MobaStateMachine.
static func _create_positioned_combatant(position: Vector3 = Vector3.ZERO) -> Dictionary:
	var actor = _TestPositionedNode.new()
	actor.global_position = position

	var combatant = MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)
	actor.add_child(combatant)

	var state_machine = MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	return {"actor": actor, "combatant": combatant, "state_machine": state_machine}


## Test that knockback moves target away from source via get_forced_move_direction().
static func _test_knockback_moves_away_from_source() -> Array[String]:
	var violations: Array[String] = []

	var source_data = _create_positioned_combatant(Vector3.ZERO)
	var target_data = _create_positioned_combatant(Vector3(5.0, 0.0, 0.0))

	var source = source_data["combatant"]
	var target = target_data["combatant"]

	# Apply knockback with magnitude (0.0-1.0 fraction of ActorBody3D.SPEED)
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.KNOCKBACK
	spec.duration = 1.0
	spec.magnitude = 0.4
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Get forced move direction
	var forced_move = target.get_forced_move_direction()

	# Direction should be away from source (toward +X since target is at +5.0 X)
	if forced_move == Vector3.ZERO:
		violations.append("knockback_moves_away: forced_move should not be zero")
		return violations

	# X component should be positive (away from origin)
	if forced_move.x <= 0.0:
		violations.append(
			(
				"knockback_moves_away: X component should be positive (away from source), got %.2f"
				% forced_move.x
			)
		)

	# Magnitude should be non-zero
	if forced_move.length() == 0.0:
		violations.append("knockback_moves_away: magnitude should be non-zero")

	return violations


## Test that pull moves target toward source via get_forced_move_direction().
static func _test_pull_moves_toward_source() -> Array[String]:
	var violations: Array[String] = []

	var source_data = _create_positioned_combatant(Vector3(0.0, 0.0, 0.0))
	var target_data = _create_positioned_combatant(Vector3(5.0, 0.0, 0.0))

	var source = source_data["combatant"]
	var target = target_data["combatant"]

	# Apply pull with magnitude (0.0-1.0 fraction of ActorBody3D.SPEED)
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.PULL
	spec.duration = 1.0
	spec.magnitude = 0.4
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Get forced move direction
	var forced_move = target.get_forced_move_direction()

	# Direction should be toward source (toward -X since target is at +5.0 X and source at origin)
	if forced_move == Vector3.ZERO:
		violations.append("pull_moves_toward: forced_move should not be zero")
		return violations

	# X component should be negative (toward source at origin)
	if forced_move.x >= 0.0:
		violations.append(
			(
				"pull_moves_toward: X component should be negative (toward source), got %.2f"
				% forced_move.x
			)
		)

	# Magnitude should be non-zero
	if forced_move.length() == 0.0:
		violations.append("pull_moves_toward: magnitude should be non-zero")

	return violations


## Test that knockback with affected_by_tenacity=false ignores target's Tenacity.
static func _test_knockback_honors_affected_by_tenacity_false() -> Array[String]:
	var violations: Array[String] = []

	var source_data = _create_positioned_combatant(Vector3.ZERO)
	var target_data = _create_positioned_combatant(Vector3(5.0, 0.0, 0.0))

	var source = source_data["combatant"]
	var target = target_data["combatant"]

	# Give target high Tenacity
	var stat_block = target._runtime_stat_block.duplicate()
	stat_block.tenacity = 0.5  # 50% CC duration reduction
	target._runtime_stat_block = stat_block

	# Apply knockback with affected_by_tenacity=false
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.KNOCKBACK
	spec.duration = 1.0
	spec.magnitude = 0.4
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Displacement should have full 1.0 second duration, not reduced
	# We can verify this by checking that the displacement is still active after 0.99 seconds
	target.tick(0.99)

	if target._active_displacement == null:
		(
			violations
			. append(
				"knockback_honors_affected_by_tenacity_false: displacement should still be active at 0.99s"
			)
		)

	# After 1.01 seconds, it should expire
	target.tick(0.02)
	if target._active_displacement != null:
		violations.append(
			"knockback_honors_affected_by_tenacity_false: displacement should have expired at 1.01s"
		)

	return violations


## Test that knockback with affected_by_tenacity=true respects target's Tenacity.
static func _test_knockback_honors_affected_by_tenacity_true() -> Array[String]:
	var violations: Array[String] = []

	var source_data = _create_positioned_combatant(Vector3.ZERO)
	var target_data = _create_positioned_combatant(Vector3(5.0, 0.0, 0.0))

	var source = source_data["combatant"]
	var target = target_data["combatant"]

	# Give target 50% Tenacity (reduces 1.0s CC to 0.5s)
	var stat_block = target._runtime_stat_block.duplicate()
	stat_block.tenacity = 0.5
	target._runtime_stat_block = stat_block

	# Apply knockback with affected_by_tenacity=true
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.KNOCKBACK
	spec.duration = 1.0
	spec.magnitude = 0.4
	spec.affected_by_tenacity = true

	target.apply_crowd_control(spec, source)

	# Duration should be reduced to 0.5 seconds
	# Tick 0.49 seconds - should still be active
	target.tick(0.49)
	if target._active_displacement == null:
		(
			violations
			. append(
				"knockback_honors_affected_by_tenacity_true: displacement should still be active at 0.49s"
			)
		)

	# Tick 0.02 more seconds (0.51 total) - should expire
	target.tick(0.02)
	if target._active_displacement != null:
		violations.append(
			(
				"knockback_honors_affected_by_tenacity_true: displacement should have expired at "
				+ "0.51s with 50% Tenacity"
			)
		)

	return violations


## Test that displacement effects interrupt DASHING state.
static func _test_displacement_interrupts_dashing() -> Array[String]:
	var violations: Array[String] = []

	var source_data = _create_positioned_combatant(Vector3.ZERO)
	var target_data = _create_positioned_combatant(Vector3(5.0, 0.0, 0.0))

	var source = source_data["combatant"]
	var target = target_data["combatant"]
	var state_machine = target_data["state_machine"]

	# Enter DASHING state (which has displacement_only policy)
	state_machine.try_enter(MobaState.DASHING, 1.0)

	if state_machine.current_state != MobaState.DASHING:
		violations.append("displacement_interrupts_dashing: target should be in DASHING state")
		return violations

	# Apply knockback (displacement type)
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.KNOCKBACK
	spec.duration = 0.5
	spec.magnitude = 0.4
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Knockback should be applied (displacement is accepted against displacement_only policy)
	if target._active_displacement == null:
		violations.append("displacement_interrupts_dashing: knockback should be applied")

	# DASHING itself should be interrupted -- displacement is the one thing that
	# gets through a "displacement_only" policy, cutting the dash short into IDLE.
	if state_machine.current_state == MobaState.DASHING:
		violations.append("displacement_interrupts_dashing: DASHING should have been interrupted")

	return violations


## Test that non-displacement hard CC is refused while DASHING.
static func _test_hard_cc_refused_while_dashing_displacement_only() -> Array[String]:
	var violations: Array[String] = []

	var source_data = _create_positioned_combatant(Vector3.ZERO)
	var target_data = _create_positioned_combatant(Vector3(5.0, 0.0, 0.0))

	var source = source_data["combatant"]
	var target = target_data["combatant"]
	var state_machine = target_data["state_machine"]

	# Enter DASHING state (which has displacement_only policy)
	state_machine.try_enter(MobaState.DASHING, 1.0)

	if state_machine.current_state != MobaState.DASHING:
		violations.append("hard_cc_refused_while_dashing: target should be in DASHING state")
		return violations

	# Apply STUN (non-displacement hard-CC)
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.STUN
	spec.duration = 0.5
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# STUN should be refused
	if target.has_crowd_control(MobaCrowdControlSpec.CCType.STUN):
		violations.append("hard_cc_refused_while_dashing: STUN should not be applied")

	# State should still be DASHING
	if state_machine.current_state != MobaState.DASHING:
		violations.append("hard_cc_refused_while_dashing: state should still be DASHING")

	return violations


## Test that knock-up enters AIRBORNE with cause KNOCK_UP.
static func _test_knock_up_enters_airborne_with_knock_up_cause() -> Array[String]:
	var violations: Array[String] = []

	var source_data = _create_positioned_combatant(Vector3.ZERO)
	var target_data = _create_positioned_combatant(Vector3(5.0, 0.0, 0.0))

	var source = source_data["combatant"]
	var target = target_data["combatant"]
	var state_machine = target_data["state_machine"]

	# Apply knock-up
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.KNOCK_UP
	spec.duration = 0.5
	spec.magnitude = 0.4
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Should be in AIRBORNE state
	if state_machine.current_state != MobaState.AIRBORNE:
		violations.append(
			(
				"knock_up_enters_airborne_with_knock_up_cause: should be AIRBORNE, got %s"
				% MobaState.state_to_string(state_machine.current_state)
			)
		)

	# Cause should be KNOCK_UP
	var cause = state_machine.get_airborne_cause()
	if cause != MobaState.AirborneCause.KNOCK_UP:
		violations.append(
			"knock_up_enters_airborne_with_knock_up_cause: cause should be KNOCK_UP, got %d" % cause
		)

	return violations


## Test that a follow-up effect queued during knock-up is applied on landing,
## not at the moment the knock-up itself was applied.
static func _test_queued_effect_applied_on_landing() -> Array[String]:
	var violations: Array[String] = []

	var source_data = _create_positioned_combatant(Vector3.ZERO)
	var target_data = _create_positioned_combatant(Vector3(5.0, 0.0, 0.0))

	var source = source_data["combatant"]
	var target = target_data["combatant"]
	var state_machine = target_data["state_machine"]

	# Apply knock-up
	var knock_up_spec = MobaCrowdControlSpec.new()
	knock_up_spec.type = MobaCrowdControlSpec.CCType.KNOCK_UP
	knock_up_spec.duration = 0.5
	knock_up_spec.magnitude = 0.4
	knock_up_spec.affected_by_tenacity = false

	target.apply_crowd_control(knock_up_spec, source)

	if state_machine.current_state != MobaState.AIRBORNE:
		violations.append("queued_effect_applied_on_landing: should be AIRBORNE after knock-up")
		return violations

	# Queue a follow-up STUN to land with the knock-up (e.g. a knock-up-then-stun ability)
	var stun_spec = MobaCrowdControlSpec.new()
	stun_spec.type = MobaCrowdControlSpec.CCType.STUN
	stun_spec.duration = 1.0
	stun_spec.affected_by_tenacity = false
	target.queue_follow_up_effect_for_displacement(stun_spec, source)

	# The queued effect must not be applied yet, mid-air
	if target.has_crowd_control(MobaCrowdControlSpec.CCType.STUN):
		violations.append(
			"queued_effect_applied_on_landing: STUN should not be active before landing"
		)

	# Advance to landing (knock-up duration is 0.5)
	target.tick(0.6)

	if state_machine.current_state != MobaState.CROWD_CONTROLLED:
		violations.append(
			(
				"queued_effect_applied_on_landing: should be CROWD_CONTROLLED after landing, got %s"
				% MobaState.state_to_string(state_machine.current_state)
			)
		)

	# The queued STUN must be applied now, at landing
	if not target.has_crowd_control(MobaCrowdControlSpec.CCType.STUN):
		violations.append("queued_effect_applied_on_landing: STUN should be active after landing")

	return violations
