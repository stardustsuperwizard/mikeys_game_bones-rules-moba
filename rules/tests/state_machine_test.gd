## Comprehensive tests for MobaStateMachine.
##
## Exercises every row of the state transition table, verifies data-driven behavior,
## tests state transitions, duration handling, terminal state semantics, signal
## emission, and detectable state-table load failures.
class_name StateMachineTest


static func run() -> bool:
	var all_passed = true

	# Test 1: State machine initializes correctly
	if not _test_initialization():
		all_passed = false

	# Test 2: Table-covering test for all state legalities (incl. hard-CC policy)
	if not _test_all_states_legality():
		all_passed = false

	# Test 3: Movement policies for all states
	if not _test_movement_policies():
		all_passed = false

	# Test 4: State transitions and signal emission
	if not _test_state_transitions():
		all_passed = false

	# Test 5: Duration tracking, expiration, and signal emission
	if not _test_duration_tracking():
		all_passed = false

	# Test 6: DEAD is terminal, reached through the public API
	if not _test_dead_terminal():
		all_passed = false

	# Test 7: Zero-duration handling: rejected for duration-requiring states,
	# allowed (and silent) for durationless states
	if not _test_zero_duration_not_entered():
		all_passed = false

	# Test 8: Data-driven behavior - mutation test
	if not _test_data_driven_mutation():
		all_passed = false

	# Test 9: AIRBORNE cause flag storage
	if not _test_airborne_cause():
		all_passed = false

	# Test 10: Unknown action detection
	if not _test_unknown_action_error():
		all_passed = false

	# Test 11: Malformed state table detection
	if not _test_malformed_table_detection():
		all_passed = false

	# Test 12: DEAD must not expire via tick(), even when entered with a
	# positive duration - DEAD is durationless and terminal.
	if not _test_dead_does_not_expire():
		all_passed = false

	if all_passed:
		return true
	return false


static func _test_initialization() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	if machine.current_state != MobaState.IDLE:
		printerr("FAIL: Initial state should be IDLE")
		ok = false

	if machine.time_in_state != 0.0:
		printerr("FAIL: Initial time_in_state should be 0.0")
		ok = false

	if machine.remaining != 0.0:
		printerr("FAIL: Initial remaining should be 0.0")
		ok = false

	machine.free()
	return ok


## Test all 10 states for correct action legality and hard-CC policy values.
static func _test_all_states_legality() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	# Expected legality for each state: [move, basic_attack, ability, jump]
	# DASHING's move policy is "locked": input is ignored while position is
	# driven by the action, so can("move") resolves to false there.
	var expectations = {
		MobaState.IDLE: [true, true, true, true],
		MobaState.MOVING: [true, true, true, true],
		MobaState.BASIC_ATTACK_WINDUP: [true, false, false, false],
		MobaState.BASIC_ATTACK_RECOVERY: [true, false, true, true],
		MobaState.ABILITY_CAST: [true, false, false, false],
		MobaState.ABILITY_CHANNEL: [false, false, false, false],
		MobaState.DASHING: [false, false, false, false],
		MobaState.AIRBORNE: [true, false, false, false],
		MobaState.CROWD_CONTROLLED: [false, false, false, false],
		MobaState.DEAD: [false, false, false, false],
	}

	# Expected hard-crowd-control interrupt policy for each state.
	var hard_cc_expectations = {
		MobaState.IDLE: &"yes",
		MobaState.MOVING: &"yes",
		MobaState.BASIC_ATTACK_WINDUP: &"yes",
		MobaState.BASIC_ATTACK_RECOVERY: &"yes",
		MobaState.ABILITY_CAST: &"yes",
		MobaState.ABILITY_CHANNEL: &"breaks_channel",
		MobaState.DASHING: &"displacement_only",
		MobaState.AIRBORNE: &"yes",
		MobaState.CROWD_CONTROLLED: &"per_cc",
		MobaState.DEAD: &"no",
	}

	for state in expectations.keys():
		machine.current_state = state
		var expected = expectations[state]

		var can_move = machine.can(&"move")
		var can_basic = machine.can(&"basic_attack")
		var can_ability = machine.can(&"ability")
		var can_jump = machine.can(&"jump")

		if [can_move, can_basic, can_ability, can_jump] != expected:
			var state_name = MobaState.state_to_string(state)
			printerr(
				(
					"FAIL: State %s legality mismatch. Expected %s, got [%s, %s, %s, %s]"
					% [state_name, expected, can_move, can_basic, can_ability, can_jump]
				)
			)
			ok = false

		var expected_hard_cc = hard_cc_expectations[state]
		var actual_hard_cc = machine.hard_cc_policy()
		if actual_hard_cc != expected_hard_cc:
			var state_name = MobaState.state_to_string(state)
			printerr(
				(
					"FAIL: State %s hard-CC policy mismatch. Expected %s, got %s"
					% [state_name, expected_hard_cc, actual_hard_cc]
				)
			)
			ok = false

	machine.free()
	return ok


static func _test_movement_policies() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	# Expected movement policies for each state
	var policies = {
		MobaState.IDLE: "yes",
		MobaState.MOVING: "yes",
		MobaState.BASIC_ATTACK_WINDUP: "cancels",
		MobaState.BASIC_ATTACK_RECOVERY: "yes",
		MobaState.ABILITY_CAST: "cancels",
		MobaState.ABILITY_CHANNEL: "no",
		MobaState.DASHING: "locked",
		MobaState.AIRBORNE: "air_control",
		MobaState.CROWD_CONTROLLED: "per_cc",
		MobaState.DEAD: "no",
	}

	for state in policies.keys():
		machine.current_state = state
		var expected = StringName(policies[state])
		var actual = machine.movement_policy()

		if actual != expected:
			var state_name = MobaState.state_to_string(state)
			printerr(
				(
					"FAIL: State %s movement policy mismatch. Expected %s, got %s"
					% [state_name, expected, actual]
				)
			)
			ok = false

	machine.free()
	return ok


static func _test_state_transitions() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	var signal_log = {"count": 0, "from": -1, "to": -1}
	machine.state_changed.connect(
		func(from, to):
			signal_log["count"] += 1
			signal_log["from"] = from
			signal_log["to"] = to
	)

	# Test basic transition
	var success = machine.try_enter(MobaState.MOVING, 1.0)
	if not success or machine.current_state != MobaState.MOVING:
		printerr("FAIL: try_enter to MOVING failed")
		ok = false

	if (
		signal_log["count"] != 1
		or signal_log["from"] != MobaState.IDLE
		or signal_log["to"] != MobaState.MOVING
	):
		printerr(
			(
				"FAIL: state_changed should emit once for IDLE -> MOVING, got count=%d from=%d to=%d"
				% [signal_log["count"], signal_log["from"], signal_log["to"]]
			)
		)
		ok = false

	# Test re-entering same state (should succeed, no emission)
	success = machine.try_enter(MobaState.MOVING, 1.0)
	if not success:
		printerr("FAIL: try_enter to same state should succeed")
		ok = false

	if machine.current_state != MobaState.MOVING:
		printerr("FAIL: state should still be MOVING")
		ok = false

	if signal_log["count"] != 1:
		printerr("FAIL: state_changed should not emit on re-entry, count=%d" % signal_log["count"])
		ok = false

	# Test another transition
	success = machine.try_enter(MobaState.ABILITY_CAST, 1.0)
	if not success or machine.current_state != MobaState.ABILITY_CAST:
		printerr("FAIL: transition to ABILITY_CAST failed")
		ok = false

	if (
		signal_log["count"] != 2
		or signal_log["from"] != MobaState.MOVING
		or signal_log["to"] != MobaState.ABILITY_CAST
	):
		printerr(
			(
				"FAIL: state_changed should emit for MOVING -> ABILITY_CAST, got count=%d from=%d to=%d"
				% [signal_log["count"], signal_log["from"], signal_log["to"]]
			)
		)
		ok = false

	machine.free()
	return ok


static func _test_duration_tracking() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	var signal_log = {"count": 0, "from": -1, "to": -1}
	machine.state_changed.connect(
		func(from, to):
			signal_log["count"] += 1
			signal_log["from"] = from
			signal_log["to"] = to
	)

	# Enter a state with 1.0 second duration
	machine.try_enter(MobaState.ABILITY_CAST, 1.0)

	if machine.remaining != 1.0:
		printerr("FAIL: remaining should be 1.0 after entering with duration")
		ok = false

	if machine.time_in_state != 0.0:
		printerr("FAIL: time_in_state should be 0.0 initially")
		ok = false

	# Tick 0.4 seconds
	machine.tick(0.4)

	if machine.time_in_state != 0.4:
		printerr(
			"FAIL: time_in_state should be 0.4 after tick(0.4), got %f" % machine.time_in_state
		)
		ok = false

	if machine.remaining != 0.6:
		printerr("FAIL: remaining should be 0.6 after tick(0.4), got %f" % machine.remaining)
		ok = false

	if machine.current_state != MobaState.ABILITY_CAST:
		printerr("FAIL: state should still be ABILITY_CAST")
		ok = false

	# Tick another 0.7 seconds (total 1.1, should expire)
	machine.tick(0.7)

	if machine.current_state != MobaState.IDLE:
		printerr(
			(
				"FAIL: state should return to IDLE after duration expires, got %d"
				% machine.current_state
			)
		)
		ok = false

	if machine.remaining != 0.0:
		printerr("FAIL: remaining should be 0.0 after expiration")
		ok = false

	# One emission for entering ABILITY_CAST, one for the expiry back to IDLE.
	if (
		signal_log["count"] != 2
		or signal_log["from"] != MobaState.ABILITY_CAST
		or signal_log["to"] != MobaState.IDLE
	):
		printerr(
			(
				"FAIL: state_changed should emit on duration expiry (ABILITY_CAST -> IDLE), got count=%d from=%d to=%d"
				% [signal_log["count"], signal_log["from"], signal_log["to"]]
			)
		)
		ok = false

	machine.free()
	return ok


static func _test_dead_terminal() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	# DEAD is durationless, like IDLE/MOVING/CROWD_CONTROLLED: it must be
	# reachable through the public try_enter() API with duration 0.0.
	var success = machine.try_enter(MobaState.DEAD, 0.0)
	if not success or machine.current_state != MobaState.DEAD:
		printerr("FAIL: try_enter(DEAD, 0.0) should succeed and reach DEAD")
		ok = false

	# All can() queries should return false
	if (
		machine.can(&"move")
		or machine.can(&"basic_attack")
		or machine.can(&"ability")
		or machine.can(&"jump")
	):
		printerr("FAIL: can() should always return false from DEAD")
		ok = false

	# try_enter to any state should fail
	success = machine.try_enter(MobaState.IDLE, 1.0)
	if success:
		printerr("FAIL: try_enter from DEAD should return false")
		ok = false

	if machine.current_state != MobaState.DEAD:
		printerr("FAIL: state should remain DEAD after failed try_enter")
		ok = false

	# revive() should work
	success = machine.revive()
	if not success:
		printerr("FAIL: revive() should succeed from DEAD")
		ok = false

	if machine.current_state != MobaState.IDLE:
		printerr("FAIL: revive() should transition to IDLE")
		ok = false

	# revive() from non-DEAD should fail
	success = machine.revive()
	if success:
		printerr("FAIL: revive() should fail when not in DEAD state")
		ok = false

	machine.free()
	return ok


static func _test_zero_duration_not_entered() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	var signal_log = {"count": 0}
	machine.state_changed.connect(func(_from, _to): signal_log["count"] += 1)

	machine.current_state = MobaState.IDLE

	# Try to enter ABILITY_CAST with 0 duration - ABILITY_CAST requires a
	# duration to be meaningful, so this must be rejected.
	var success = machine.try_enter(MobaState.ABILITY_CAST, 0.0)
	if success:
		printerr(
			"FAIL: try_enter with 0 duration should return false for a duration-requiring state"
		)
		ok = false

	if machine.current_state != MobaState.IDLE:
		printerr("FAIL: state should remain IDLE after rejected 0-duration entry")
		ok = false

	# Try with negative duration
	success = machine.try_enter(MobaState.ABILITY_CAST, -1.0)
	if success:
		printerr("FAIL: try_enter with negative duration should return false")
		ok = false

	if machine.current_state != MobaState.IDLE:
		printerr("FAIL: state should remain IDLE after rejected negative-duration entry")
		ok = false

	if signal_log["count"] != 0:
		printerr(
			(
				"FAIL: state_changed should not emit for a rejected zero/negative-duration try_enter, count=%d"
				% signal_log["count"]
			)
		)
		ok = false

	# Durationless states (IDLE, MOVING, DEAD, CROWD_CONTROLLED) are entered
	# normally even with duration <= 0.0 - they simply have no expiry.
	success = machine.try_enter(MobaState.MOVING, 0.0)
	if not success or machine.current_state != MobaState.MOVING:
		printerr("FAIL: try_enter(MOVING, 0.0) should succeed - MOVING is durationless")
		ok = false

	success = machine.try_enter(MobaState.CROWD_CONTROLLED, 0.0)
	if not success or machine.current_state != MobaState.CROWD_CONTROLLED:
		printerr(
			"FAIL: try_enter(CROWD_CONTROLLED, 0.0) should succeed - CROWD_CONTROLLED may be entered durationless"
		)
		ok = false

	if machine.remaining != 0.0:
		printerr(
			(
				"FAIL: durationless state should have no expiry (remaining == 0.0), got %f"
				% machine.remaining
			)
		)
		ok = false

	machine.free()
	return ok


static func _test_data_driven_mutation() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	machine.current_state = MobaState.IDLE

	# Verify ability is initially legal in IDLE
	if not machine.can(&"ability"):
		printerr("FAIL: ability should be legal in IDLE initially")
		ok = false

	# Get the table and mutate it to forbid ability
	var table = machine.get_state_table_for_testing()
	var idle_data = table[MobaState.IDLE]
	idle_data["ability"] = "no"

	# Now ability should be illegal without any code changes
	if machine.can(&"ability"):
		printerr("FAIL: ability should be illegal after table mutation")
		ok = false

	# Restore it
	idle_data["ability"] = "yes"
	if not machine.can(&"ability"):
		printerr("FAIL: ability should be legal after restoring table")
		ok = false

	machine.free()
	return ok


static func _test_airborne_cause() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	# Not airborne initially
	if machine.get_airborne_cause() != -1:
		printerr("FAIL: airborne cause should be -1 when not airborne")
		ok = false

	# Enter AIRBORNE with JUMP from IDLE
	machine.try_enter(MobaState.AIRBORNE, 1.0, MobaState.AirborneCause.JUMP)
	if machine.get_airborne_cause() != MobaState.AirborneCause.JUMP:
		printerr("FAIL: airborne cause should be JUMP")
		ok = false

	# Transition to MOVING to reset state
	machine.try_enter(MobaState.MOVING, 1.0)
	if machine.get_airborne_cause() != -1:
		printerr("FAIL: airborne cause should be -1 when not in AIRBORNE")
		ok = false

	# Enter AIRBORNE again with KNOCK_UP
	machine.try_enter(MobaState.AIRBORNE, 1.0, MobaState.AirborneCause.KNOCK_UP)
	if machine.get_airborne_cause() != MobaState.AirborneCause.KNOCK_UP:
		printerr(
			(
				"FAIL: airborne cause should be KNOCK_UP after new entry, got %d"
				% machine.get_airborne_cause()
			)
		)
		ok = false

	machine.free()
	return ok


static func _test_unknown_action_error() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	machine.current_state = MobaState.IDLE

	# Unknown actions should return false and log error
	var result = machine.can(&"unknown_action")
	if result:
		printerr("FAIL: unknown action should return false")
		ok = false

	machine.free()
	return ok


## Verify that a malformed state table is detectable, not silently permissive.
static func _test_malformed_table_detection() -> bool:
	var ok = true

	# Case 1: an unrecognized state name must fail to load, with the failure
	# detectable via `load_failed` (not just a push_error side effect), and
	# can() must fail safe afterward rather than defaulting to permissive.
	var machine_a = MobaStateMachine.new()
	machine_a._ready()
	var bad_state_name_table = {
		"NOT_A_REAL_STATE":
		{
			"move": "yes",
			"basic_attack": "yes",
			"ability": "yes",
			"jump": "yes",
			"interruptible_by_hard_cc": "yes",
		},
	}
	var load_result = machine_a.load_state_table_for_testing(bad_state_name_table)
	if load_result or not machine_a.load_failed:
		printerr("FAIL: unrecognized state name should set load_failed and return false")
		ok = false

	machine_a.current_state = MobaState.IDLE
	if machine_a.can(&"move"):
		printerr("FAIL: can() must not silently permit an action after a load failure")
		ok = false
	machine_a.free()

	# Case 2: a structurally valid, complete table (right columns, string
	# values, all 10 states) but with one unrecognized policy value must
	# fail to load, with the failure detectable via `load_failed` - policy
	# values are validated against each column's known vocabulary at load
	# time, the same way unrecognized state names are handled, so a bad
	# value never reaches a use-site check in the first place.
	var reference_machine = MobaStateMachine.new()
	reference_machine._ready()
	var internal_table: Dictionary = reference_machine.get_state_table_for_testing()

	# _parse_state_table() expects the JSON shape: state name strings as
	# keys, not the int-keyed internal representation.
	var valid_table: Dictionary = {}
	for state_idx in internal_table.keys():
		var state_name = MobaState.state_to_string(state_idx)
		valid_table[state_name] = internal_table[state_idx].duplicate(true)
	reference_machine.free()

	valid_table["BASIC_ATTACK_WINDUP"]["ability"] = "not_a_real_policy_value"

	var machine_b = MobaStateMachine.new()
	machine_b._ready()
	load_result = machine_b.load_state_table_for_testing(valid_table)
	if load_result or not machine_b.load_failed:
		printerr("FAIL: an unrecognized policy value should set load_failed and return false")
		ok = false

	machine_b.current_state = MobaState.BASIC_ATTACK_WINDUP
	if machine_b.can(&"ability"):
		printerr("FAIL: can() must not silently permit an action after a load failure")
		ok = false
	machine_b.free()

	return ok


## Verify DEAD never expires via tick(), even if entered with a positive
## duration. DEAD is durationless (like IDLE/MOVING/CROWD_CONTROLLED): a
## `remaining` timer must never be retained for it, so tick() can never
## fire the expiry-to-IDLE path from DEAD. Only revive() may leave DEAD.
static func _test_dead_does_not_expire() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	var ok = true

	var signal_log = {"count": 0, "from": -1, "to": -1}
	machine.state_changed.connect(
		func(from, to):
			signal_log["count"] += 1
			signal_log["from"] = from
			signal_log["to"] = to
	)

	var success = machine.try_enter(MobaState.DEAD, 2.0)
	if not success or machine.current_state != MobaState.DEAD:
		printerr("FAIL: try_enter(DEAD, 2.0) should succeed and reach DEAD")
		ok = false

	if machine.remaining != 0.0:
		printerr("FAIL: DEAD must not retain a duration timer, remaining=%f" % machine.remaining)
		ok = false

	machine.tick(2.0)
	if machine.current_state != MobaState.DEAD:
		printerr(
			(
				"FAIL: DEAD must not expire via tick(), got %s"
				% MobaState.state_to_string(machine.current_state)
			)
		)
		ok = false

	# Only the entry into DEAD should have emitted; tick() must not emit
	# a spurious expiry transition out of DEAD.
	if signal_log["count"] != 1 or signal_log["to"] != MobaState.DEAD:
		printerr(
			(
				"FAIL: tick() must not emit state_changed after DEAD entry, count=%d to=%d"
				% [signal_log["count"], signal_log["to"]]
			)
		)
		ok = false

	machine.free()
	return ok
