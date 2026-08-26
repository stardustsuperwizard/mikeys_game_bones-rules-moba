## Test suite for MobaCrowdControl data model.
##
## Covers loading and validation of the crowd_control_effects.json table,
## and all three query methods (blocks_move, blocks_basic_attack, blocks_ability)
## for each of the eleven crowd control types.
class_name CrowdControlDataTest


## Run the crowd control data test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []

	# Test 1: Table loads successfully without error
	all_violations.append_array(_test_table_loads())

	# Test 2: blocks_move query for each CC type
	all_violations.append_array(_test_blocks_move_all_types())

	# Test 3: blocks_basic_attack query for each CC type
	all_violations.append_array(_test_blocks_basic_attack_all_types())

	# Test 4: blocks_ability query for each CC type
	all_violations.append_array(_test_blocks_ability_all_types())

	# Test 5: Malformed table detection - missing row
	all_violations.append_array(_test_malformed_table_missing_row())

	# Test 6: Malformed table detection - missing column
	all_violations.append_array(_test_malformed_table_missing_column())

	# Test 7: Malformed table detection - non-boolean value
	all_violations.append_array(_test_malformed_table_non_boolean())

	if all_violations.is_empty():
		return true

	# Print violations
	printerr("\n=== Crowd Control Data Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Test that the table loads successfully.
static func _test_table_loads() -> Array[String]:
	var violations: Array[String] = []

	# Reset state before testing
	MobaCrowdControl._reset_for_testing()

	# Trigger load by calling a static method
	MobaCrowdControl.blocks_move(MobaCrowdControlSpec.CCType.STUN)

	if MobaCrowdControl.load_failed:
		violations.append("MobaCrowdControl failed to load table")

	return violations


## Test blocks_move for all eleven CC types per the spec.
static func _test_blocks_move_all_types() -> Array[String]:
	var violations: Array[String] = []

	# Reset state before testing
	MobaCrowdControl._reset_for_testing()

	# Expected values per the issue's Per-Effect Behavior table
	var expectations = {
		MobaCrowdControlSpec.CCType.STUN: true,
		MobaCrowdControlSpec.CCType.ROOT: true,
		MobaCrowdControlSpec.CCType.SLOW: false,
		MobaCrowdControlSpec.CCType.SILENCE: false,
		MobaCrowdControlSpec.CCType.DISARM: false,
		MobaCrowdControlSpec.CCType.KNOCKBACK: false,
		MobaCrowdControlSpec.CCType.PULL: false,
		MobaCrowdControlSpec.CCType.KNOCK_UP: false,
		MobaCrowdControlSpec.CCType.FEAR: false,
		MobaCrowdControlSpec.CCType.TAUNT: false,
		MobaCrowdControlSpec.CCType.BLIND: false,
	}

	for cc_type: int in expectations.keys():
		var expected = expectations[cc_type]
		var result = MobaCrowdControl.blocks_move(cc_type)
		if result != expected:
			var cc_name = MobaCrowdControlSpec.CCType.keys()[cc_type]
			violations.append(
				"blocks_move(%s): expected %s, got %s" % [cc_name, expected, result]
			)

	return violations


## Test blocks_basic_attack for all eleven CC types per the spec.
static func _test_blocks_basic_attack_all_types() -> Array[String]:
	var violations: Array[String] = []

	# Reset state before testing
	MobaCrowdControl._reset_for_testing()

	# Expected values per the issue's Per-Effect Behavior table
	var expectations = {
		MobaCrowdControlSpec.CCType.STUN: true,
		MobaCrowdControlSpec.CCType.ROOT: false,
		MobaCrowdControlSpec.CCType.SLOW: false,
		MobaCrowdControlSpec.CCType.SILENCE: false,
		MobaCrowdControlSpec.CCType.DISARM: true,
		MobaCrowdControlSpec.CCType.KNOCKBACK: false,
		MobaCrowdControlSpec.CCType.PULL: false,
		MobaCrowdControlSpec.CCType.KNOCK_UP: false,
		MobaCrowdControlSpec.CCType.FEAR: false,
		MobaCrowdControlSpec.CCType.TAUNT: false,
		MobaCrowdControlSpec.CCType.BLIND: false,
	}

	for cc_type: int in expectations.keys():
		var expected = expectations[cc_type]
		var result = MobaCrowdControl.blocks_basic_attack(cc_type)
		if result != expected:
			var cc_name = MobaCrowdControlSpec.CCType.keys()[cc_type]
			violations.append(
				"blocks_basic_attack(%s): expected %s, got %s" % [cc_name, expected, result]
			)

	return violations


## Test blocks_ability for all eleven CC types per the spec.
static func _test_blocks_ability_all_types() -> Array[String]:
	var violations: Array[String] = []

	# Reset state before testing
	MobaCrowdControl._reset_for_testing()

	# Expected values per the issue's Per-Effect Behavior table
	var expectations = {
		MobaCrowdControlSpec.CCType.STUN: true,
		MobaCrowdControlSpec.CCType.ROOT: false,
		MobaCrowdControlSpec.CCType.SLOW: false,
		MobaCrowdControlSpec.CCType.SILENCE: true,
		MobaCrowdControlSpec.CCType.DISARM: false,
		MobaCrowdControlSpec.CCType.KNOCKBACK: false,
		MobaCrowdControlSpec.CCType.PULL: false,
		MobaCrowdControlSpec.CCType.KNOCK_UP: false,
		MobaCrowdControlSpec.CCType.FEAR: false,
		MobaCrowdControlSpec.CCType.TAUNT: false,
		MobaCrowdControlSpec.CCType.BLIND: false,
	}

	for cc_type: int in expectations.keys():
		var expected = expectations[cc_type]
		var result = MobaCrowdControl.blocks_ability(cc_type)
		if result != expected:
			var cc_name = MobaCrowdControlSpec.CCType.keys()[cc_type]
			violations.append(
				"blocks_ability(%s): expected %s, got %s" % [cc_name, expected, result]
			)

	return violations


## Test that a missing CC type is detected at load time.
static func _test_malformed_table_missing_row() -> Array[String]:
	var violations: Array[String] = []

	# Reset state before testing
	MobaCrowdControl._reset_for_testing()

	# Hand-build a malformed table with a missing CC type
	var bad_data = {
		"STUN": {"blocks_move": true, "blocks_basic_attack": true, "blocks_ability": true},
		# Missing ROOT intentionally
	}

	if MobaCrowdControl._parse_cc_table(bad_data):
		violations.append("Malformed table (missing row) should fail validation")

	if not MobaCrowdControl.load_failed:
		violations.append("Malformed table (missing row) should set load_failed flag")

	return violations


## Test that a missing column is detected at load time.
static func _test_malformed_table_missing_column() -> Array[String]:
	var violations: Array[String] = []

	# Reset state before testing
	MobaCrowdControl._reset_for_testing()

	# Hand-build a malformed table with a missing column
	var bad_data = {
		"STUN": {"blocks_move": true, "blocks_basic_attack": true},
		# Missing blocks_ability intentionally
		"ROOT": {"blocks_move": true, "blocks_basic_attack": false, "blocks_ability": false},
	}

	if MobaCrowdControl._parse_cc_table(bad_data):
		violations.append("Malformed table (missing column) should fail validation")

	if not MobaCrowdControl.load_failed:
		violations.append("Malformed table (missing column) should set load_failed flag")

	return violations


## Test that a non-boolean value is detected at load time.
static func _test_malformed_table_non_boolean() -> Array[String]:
	var violations: Array[String] = []

	# Reset state before testing
	MobaCrowdControl._reset_for_testing()

	# Hand-build a malformed table with a non-boolean value
	var bad_data = {
		"STUN": {"blocks_move": "yes", "blocks_basic_attack": true, "blocks_ability": true},
		# "yes" is not a boolean; should be true/false
		"ROOT": {"blocks_move": true, "blocks_basic_attack": false, "blocks_ability": false},
	}

	if MobaCrowdControl._parse_cc_table(bad_data):
		violations.append("Malformed table (non-boolean value) should fail validation")

	if not MobaCrowdControl.load_failed:
		violations.append("Malformed table (non-boolean value) should set load_failed flag")

	return violations
