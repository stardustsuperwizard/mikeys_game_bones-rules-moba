## Comprehensive tests for MobaStateMachine.
##
## Exercises every row of the state transition table, verifies data-driven behavior,
## tests state transitions, duration handling, and terminal state semantics.
class_name StateMachineTest


static func run() -> bool:
	var all_passed = true
	
	# Test 1: State machine initializes correctly
	if not _test_initialization():
		all_passed = false
	
	# Test 2: Table-covering test for all state legalities
	if not _test_all_states_legality():
		all_passed = false
	
	# Test 3: Movement policies for all states
	if not _test_movement_policies():
		all_passed = false
	
	# Test 4: State transitions and signal emission
	if not _test_state_transitions():
		all_passed = false
	
	# Test 5: Duration tracking and expiration
	if not _test_duration_tracking():
		all_passed = false
	
	# Test 6: DEAD is terminal
	if not _test_dead_terminal():
		all_passed = false
	
	# Test 7: Zero-duration states not entered
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
	
	if all_passed:
		return true
	return false


static func _test_initialization() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	
	if machine.current_state != MobaState.IDLE:
		printerr("FAIL: Initial state should be IDLE")
		return false
	
	if machine.time_in_state != 0.0:
		printerr("FAIL: Initial time_in_state should be 0.0")
		return false
	
	if machine.remaining != 0.0:
		printerr("FAIL: Initial remaining should be 0.0")
		return false
	
	return true


## Test all 10 states for correct action legality values.
static func _test_all_states_legality() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	
	# Expected legality for each state: [move, basic_attack, ability, jump]
	var expectations = {
		MobaState.IDLE: [true, true, true, true],
		MobaState.MOVING: [true, true, true, true],
		MobaState.BASIC_ATTACK_WINDUP: [true, false, false, false],
		MobaState.BASIC_ATTACK_RECOVERY: [true, false, true, true],
		MobaState.ABILITY_CAST: [true, false, false, false],
		MobaState.ABILITY_CHANNEL: [false, false, false, false],
		MobaState.DASHING: [true, false, false, false],
		MobaState.AIRBORNE: [true, false, false, false],
		MobaState.CROWD_CONTROLLED: [false, false, false, false],
		MobaState.DEAD: [false, false, false, false],
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
			printerr("FAIL: State %s legality mismatch. Expected %s, got [%s, %s, %s, %s]" % [
				state_name, expected, can_move, can_basic, can_ability, can_jump
			])
			return false
	
	return true


static func _test_movement_policies() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	
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
			printerr("FAIL: State %s movement policy mismatch. Expected %s, got %s" % [
				state_name, expected, actual
			])
			return false
	
	return true


static func _test_state_transitions() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	
	# Test basic transition
	var signal_emitted = false
	var signal_from = -1
	var signal_to = -1
	
	machine.state_changed.connect(func(from, to):
		signal_emitted = true
		signal_from = from
		signal_to = to
	)
	
	var success = machine.try_enter(MobaState.MOVING, 1.0)
	if not success or machine.current_state != MobaState.MOVING:
		printerr("FAIL: try_enter to MOVING failed")
		return false
	
	if not signal_emitted or signal_from != MobaState.IDLE or signal_to != MobaState.MOVING:
		printerr("FAIL: state_changed signal not emitted correctly on transition")
		return false
	
	# Test re-entering same state (should not emit)
	signal_emitted = false
	success = machine.try_enter(MobaState.MOVING, 1.0)
	if not success:
		printerr("FAIL: try_enter to same state should succeed")
		return false
	
	if signal_emitted:
		printerr("FAIL: state_changed should not emit when re-entering same state")
		return false
	
	if machine.current_state != MobaState.MOVING:
		printerr("FAIL: state should still be MOVING")
		return false
	
	return true


static func _test_duration_tracking() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	
	# Enter a state with 1.0 second duration
	machine.try_enter(MobaState.ABILITY_CAST, 1.0)
	
	if machine.remaining != 1.0:
		printerr("FAIL: remaining should be 1.0 after entering with duration")
		return false
	
	if machine.time_in_state != 0.0:
		printerr("FAIL: time_in_state should be 0.0 initially")
		return false
	
	# Tick 0.4 seconds
	machine.tick(0.4)
	
	if machine.time_in_state != 0.4:
		printerr("FAIL: time_in_state should be 0.4 after tick(0.4)")
		return false
	
	if machine.remaining != 0.6:
		printerr("FAIL: remaining should be 0.6 after tick(0.4)")
		return false
	
	if machine.current_state != MobaState.ABILITY_CAST:
		printerr("FAIL: state should still be ABILITY_CAST")
		return false
	
	# Tick another 0.7 seconds (total 1.1, should expire)
	var expired = false
	machine.state_changed.connect(func(from, to):
		if from == MobaState.ABILITY_CAST and to == MobaState.IDLE:
			expired = true
	)
	
	machine.tick(0.7)
	
	if not expired:
		printerr("FAIL: state_changed should emit when duration expires")
		return false
	
	if machine.current_state != MobaState.IDLE:
		printerr("FAIL: state should return to IDLE after duration expires")
		return false
	
	if machine.remaining != 0.0:
		printerr("FAIL: remaining should be 0.0 after expiration")
		return false
	
	return true


static func _test_dead_terminal() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	
	# Try to enter DEAD normally (with 0 duration, should fail)
	var success = machine.try_enter(MobaState.DEAD, 0.0)
	if success:
		printerr("FAIL: try_enter with 0 duration should return false")
		return false
	
	# Manually set to DEAD for testing terminal behavior
	machine.current_state = MobaState.DEAD
	
	# All can() queries should return false
	if machine.can(&"move") or machine.can(&"basic_attack") or \
		machine.can(&"ability") or machine.can(&"jump"):
		printerr("FAIL: can() should always return false from DEAD")
		return false
	
	# try_enter to any state should fail
	success = machine.try_enter(MobaState.IDLE, 1.0)
	if success:
		printerr("FAIL: try_enter from DEAD should return false")
		return false
	
	if machine.current_state != MobaState.DEAD:
		printerr("FAIL: state should remain DEAD after failed try_enter")
		return false
	
	# revive() should work
	success = machine.revive()
	if not success:
		printerr("FAIL: revive() should succeed from DEAD")
		return false
	
	if machine.current_state != MobaState.IDLE:
		printerr("FAIL: revive() should transition to IDLE")
		return false
	
	# revive() from non-DEAD should fail
	success = machine.revive()
	if success:
		printerr("FAIL: revive() should fail when not in DEAD state")
		return false
	
	return true


static func _test_zero_duration_not_entered() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	
	machine.current_state = MobaState.IDLE
	
	# Try to enter ABILITY_CAST with 0 duration
	var success = machine.try_enter(MobaState.ABILITY_CAST, 0.0)
	if success:
		printerr("FAIL: try_enter with 0 duration should return false")
		return false
	
	if machine.current_state != MobaState.IDLE:
		printerr("FAIL: state should remain IDLE after rejected 0-duration entry")
		return false
	
	# Try with negative duration
	success = machine.try_enter(MobaState.ABILITY_CAST, -1.0)
	if success:
		printerr("FAIL: try_enter with negative duration should return false")
		return false
	
	if machine.current_state != MobaState.IDLE:
		printerr("FAIL: state should remain IDLE after rejected negative-duration entry")
		return false
	
	return true


static func _test_data_driven_mutation() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	
	machine.current_state = MobaState.IDLE
	
	# Verify ability is initially legal in IDLE
	if not machine.can(&"ability"):
		printerr("FAIL: ability should be legal in IDLE initially")
		return false
	
	# Get the table and mutate it to forbid ability
	var table = machine.get_state_table_for_testing()
	var idle_data = table[MobaState.IDLE]
	idle_data["ability"] = "no"
	
	# Now ability should be illegal without any code changes
	if machine.can(&"ability"):
		printerr("FAIL: ability should be illegal after table mutation")
		return false
	
	# Restore it
	idle_data["ability"] = "yes"
	if not machine.can(&"ability"):
		printerr("FAIL: ability should be legal after restoring table")
		return false
	
	return true


static func _test_airborne_cause() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	
	# Not airborne initially
	if machine.get_airborne_cause() != -1:
		printerr("FAIL: airborne cause should be -1 when not airborne")
		return false
	
	# Enter AIRBORNE with JUMP
	machine.try_enter(MobaState.AIRBORNE, 1.0, MobaState.AirborneCause.JUMP)
	if machine.get_airborne_cause() != MobaState.AirborneCause.JUMP:
		printerr("FAIL: airborne cause should be JUMP")
		return false
	
	# Re-enter AIRBORNE with KNOCK_UP
	machine.try_enter(MobaState.AIRBORNE, 1.0, MobaState.AirborneCause.KNOCK_UP)
	if machine.get_airborne_cause() != MobaState.AirborneCause.KNOCK_UP:
		printerr("FAIL: airborne cause should be KNOCK_UP")
		return false
	
	# Leave AIRBORNE
	machine.revive()
	if machine.get_airborne_cause() != -1:
		printerr("FAIL: airborne cause should be -1 when not airborne")
		return false
	
	return true


static func _test_unknown_action_error() -> bool:
	var machine = MobaStateMachine.new()
	machine._ready()
	
	machine.current_state = MobaState.IDLE
	
	# Unknown actions should return false and log error
	var result = machine.can(&"unknown_action")
	if result:
		printerr("FAIL: unknown action should return false")
		return false
	
	return true
