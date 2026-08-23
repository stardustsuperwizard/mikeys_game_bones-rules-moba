## Test suite for ability activation pipeline.
##
## Covers: MobaAbilityAction, MobaAbilityCaster, and MobaCastContext.
## Tests legality checks, target resolution, resource commitment, damage application,
## and edge cases like freed targets.
class_name AbilityActivationTest

const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaAbilityCaster = preload("res://rules/abilities/moba_ability_caster.gd")
const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaAbilityAction = preload("res://rules/abilities/moba_ability_action.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")


static func run() -> bool:
	var all_violations: Array[String] = []

	# Test 1: Targeted damage ability activation
	all_violations.append_array(_test_targeted_damage_ability())

	# Test 2: Self buff-less ability activation
	all_violations.append_array(_test_self_ability())

	# Test 3: Unknown ability returns failure
	all_violations.append_array(_test_unknown_ability())

	# Test 4: Insufficient resource blocks activation
	all_violations.append_array(_test_insufficient_resource())

	# Test 5: Ability on cooldown blocks activation
	all_violations.append_array(_test_on_cooldown())

	# Test 6: Unimplemented targeting type fails
	all_violations.append_array(_test_targeting_not_implemented())

	# Test 7: Freed target doesn't crash and fails safely
	all_violations.append_array(_test_freed_target())

	# Test 8: Out of range target fails
	all_violations.append_array(_test_out_of_range())

	# Test 9: Invalid target reference fails
	all_violations.append_array(_test_invalid_target_reference())

	# Test 10: Resource is committed atomically
	all_violations.append_array(_test_atomic_resource_commitment())

	if all_violations.is_empty():
		return true

	printerr("\n=== Ability Activation Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Helper to load all test abilities into the library
static func _ensure_all_test_abilities_loaded() -> void:
	# Ensure the library is loaded
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")

	# Also load test fixtures into the cache directly (without resetting)
	var fixtures_dir = "res://rules/tests/fixtures/abilities/"
	MobaAbilityLibrary._load_and_index(fixtures_dir)


## Helper to create a test wrapper around actor with combatant and state machine
static func _create_test_actor() -> Dictionary:
	var actor = Actor.new()
	actor.owner_id = 1

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)

	# Register all available abilities
	var power_strike = MobaAbilityLibrary.get_ability(&"power_strike")
	if power_strike != null:
		combatant.register_ability(power_strike)

	var self_ability = MobaAbilityLibrary.get_ability(&"self_ability")
	if self_ability != null:
		combatant.register_ability(self_ability)

	var skillshot_ability = MobaAbilityLibrary.get_ability(&"skillshot_ability")
	if skillshot_ability != null:
		combatant.register_ability(skillshot_ability)

	var state_machine = MobaStateMachine.new()
	state_machine._load_state_table()

	# Create a wrapper dictionary for test access
	var wrapper = {
		"actor": actor,
		"combatant": combatant,
		"state_machine": state_machine,
	}

	return wrapper


## Helper to create a mock target with combatant
static func _create_target_with_combatant() -> Node:
	var target = Node.new()
	target.global_position = Vector3(0, 0, 0)

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)

	# Store combatant as test metadata
	target.set_meta("_test_combatant", combatant)

	return target


## Test 1: Targeted damage ability activation
static func _test_targeted_damage_ability() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	# Set up test metadata for the action to find combatant and state machine
	caster.set_meta("_test_combatant", caster_combatant)
	caster.set_meta("_test_state_machine", caster_state_machine)

	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)  # Within 2.0 range

	var initial_health = target.get_meta("_test_combatant")._current_health
	var initial_resource = caster_combatant._current_resource

	# Activate Power Strike
	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	if not result.success:
		violations.append("targeted_damage: activation should succeed, got: %s" % result.reason)

	# Check damage was applied
	if target.get_meta("_test_combatant")._current_health >= initial_health:
		violations.append("targeted_damage: target should take damage")

	# Check resource was spent
	var power_strike = MobaAbilityLibrary.get_ability(&"power_strike")
	if power_strike != null:
		var expected_resource = initial_resource - power_strike.resource_cost
		if not is_equal_approx(caster_combatant._current_resource, expected_resource):
			violations.append(
				"targeted_damage: resource should be spent (expected %f, got %f)"
				% [expected_resource, caster_combatant._current_resource]
			)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 2: Self buff-less ability activation
static func _test_self_ability() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	# Set up test metadata for the action to find combatant and state machine
	caster.set_meta("_test_combatant", caster_combatant)
	caster.set_meta("_test_state_machine", caster_state_machine)

	var initial_resource = caster_combatant._current_resource

	# Activate self ability (no target needed)
	var context = MobaCastContext.new(caster, null)
	var action = MobaAbilityAction.new(caster, &"self_ability", context)
	var result = action.execute()

	if not result.success:
		violations.append("self_ability: activation should succeed, got: %s" % result.reason)

	# Check resource was spent
	var self_ability = MobaAbilityLibrary.get_ability(&"self_ability")
	if self_ability != null:
		var expected_resource = initial_resource - self_ability.resource_cost
		if not is_equal_approx(caster_combatant._current_resource, expected_resource):
			violations.append(
				"self_ability: resource should be spent (expected %f, got %f)"
				% [expected_resource, caster_combatant._current_resource]
			)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 3: Unknown ability returns failure
static func _test_unknown_ability() -> Array[String]:
	var violations: Array[String] = []

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	# Set up test metadata for the action to find combatant and state machine
	caster.set_meta("_test_combatant", caster_combatant)
	caster.set_meta("_test_state_machine", caster_state_machine)

	var context = MobaCastContext.new(caster, null)
	var action = MobaAbilityAction.new(caster, &"unknown_ability_xyz", context)
	var result = action.execute()

	if result.success:
		violations.append("unknown_ability: activation should fail")

	if result.reason != &"unknown_ability":
		violations.append(
			"unknown_ability: reason should be 'unknown_ability', got '%s'" % result.reason
		)

	return violations


## Test 4: Insufficient resource blocks activation
static func _test_insufficient_resource() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	# Set up test metadata for the action to find combatant and state machine
	caster.set_meta("_test_combatant", caster_combatant)
	caster.set_meta("_test_state_machine", caster_state_machine)

	# Drain resource below ability cost
	var power_strike = MobaAbilityLibrary.get_ability(&"power_strike")
	if power_strike != null:
		caster_combatant._current_resource = power_strike.resource_cost - 1.0

	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	var initial_resource = caster_combatant._current_resource

	# Try to activate Power Strike
	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	if result.success:
		violations.append("insufficient_resource: activation should fail")

	if result.reason != &"insufficient_resource":
		violations.append(
			"insufficient_resource: reason should be 'insufficient_resource', got '%s'" % result.reason
		)

	# Check resource was NOT spent
	if caster_combatant._current_resource != initial_resource:
		violations.append("insufficient_resource: resource should not be committed on failure")

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 5: Ability on cooldown blocks activation
static func _test_on_cooldown() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	# Set up test metadata for the action to find combatant and state machine
	caster.set_meta("_test_combatant", caster_combatant)
	caster.set_meta("_test_state_machine", caster_state_machine)
	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	# Activate once to start cooldown
	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result1 = action.execute()

	if not result1.success:
		violations.append("on_cooldown: first activation should succeed")
		return violations

	# Try to activate again while on cooldown
	var action2 = MobaAbilityAction.new(caster, &"power_strike", context)
	var result2 = action2.execute()

	if result2.success:
		violations.append("on_cooldown: second activation should fail")

	if result2.reason != &"on_cooldown":
		violations.append(
			"on_cooldown: reason should be 'on_cooldown', got '%s'" % result2.reason
		)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 6: Unimplemented targeting type fails
static func _test_targeting_not_implemented() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	# Set up test metadata for the action to find combatant and state machine
	caster.set_meta("_test_combatant", caster_combatant)
	caster.set_meta("_test_state_machine", caster_state_machine)
	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	# Try to activate skillshot ability (SKILLSHOT targeting type)
	var context = MobaCastContext.new(caster, target, Vector3.FORWARD)
	var action = MobaAbilityAction.new(caster, &"skillshot_ability", context)
	var result = action.execute()

	if result.success:
		violations.append("targeting_not_implemented: activation should fail")

	if result.reason != &"targeting_not_implemented":
		violations.append(
			"targeting_not_implemented: reason should be 'targeting_not_implemented', got '%s'" % result.reason
		)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 7: Freed target doesn't crash and fails safely
static func _test_freed_target() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	# Set up test metadata for the action to find combatant and state machine
	caster.set_meta("_test_combatant", caster_combatant)
	caster.set_meta("_test_state_machine", caster_state_machine)
	var target = _create_target_with_combatant()

	# Get the initial state before target is freed
	var initial_resource = caster_combatant._current_resource

	# Reference the target but then simulate it being freed
	# We can't actually free it in GDScript without a proper scene tree,
	# but we can test that is_instance_valid() guard works
	var freed_target = target
	target = null  # Dereference
	freed_target.queue_free()

	# Try to activate with the freed target
	var context = MobaCastContext.new(caster, freed_target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	if result.success:
		violations.append("freed_target: activation should fail")

	if result.reason != &"invalid_target":
		violations.append(
			"freed_target: reason should be 'invalid_target', got '%s'" % result.reason
		)

	# Check that resource was NOT spent
	if caster_combatant._current_resource != initial_resource:
		violations.append("freed_target: resource should not be committed when target is invalid")

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 8: Out of range target fails
static func _test_out_of_range() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	# Set up test metadata for the action to find combatant and state machine
	caster.set_meta("_test_combatant", caster_combatant)
	caster.set_meta("_test_state_machine", caster_state_machine)
	caster.global_position = Vector3(0, 0, 0)

	var target = _create_target_with_combatant()
	target.global_position = Vector3(10, 0, 0)  # Beyond 2.0 range

	var initial_resource = caster_combatant._current_resource

	# Try to activate Power Strike
	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	if result.success:
		violations.append("out_of_range: activation should fail")

	if result.reason != &"out_of_range":
		violations.append(
			"out_of_range: reason should be 'out_of_range', got '%s'" % result.reason
		)

	# Check that resource was NOT spent
	if caster_combatant._current_resource != initial_resource:
		violations.append("out_of_range: resource should not be committed on failure")

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 9: Invalid target reference fails
static func _test_invalid_target_reference() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	# Set up test metadata for the action to find combatant and state machine
	caster.set_meta("_test_combatant", caster_combatant)
	caster.set_meta("_test_state_machine", caster_state_machine)
	var initial_resource = caster_combatant._current_resource

	# Try to activate with null explicit_target for a targeted ability
	var context = MobaCastContext.new(caster, null)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	if result.success:
		violations.append("invalid_target_reference: activation should fail")

	if result.reason != &"invalid_target":
		violations.append(
			"invalid_target_reference: reason should be 'invalid_target', got '%s'" % result.reason
		)

	# Check that resource was NOT spent
	if caster_combatant._current_resource != initial_resource:
		violations.append("invalid_target_reference: resource should not be committed on failure")

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 10: Resource is committed atomically
static func _test_atomic_resource_commitment() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	# Set up test metadata for the action to find combatant and state machine
	caster.set_meta("_test_combatant", caster_combatant)
	caster.set_meta("_test_state_machine", caster_state_machine)
	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	var initial_resource = caster_combatant._current_resource
	var power_strike = MobaAbilityLibrary.get_ability(&"power_strike")

	if power_strike != null:
		# First activation should succeed
		var context1 = MobaCastContext.new(caster, target)
		var action1 = MobaAbilityAction.new(caster, &"power_strike", context1)
		var result1 = action1.execute()

		if not result1.success:
			violations.append("atomic_commitment: first activation should succeed")
			return violations

		var expected_after_first = initial_resource - power_strike.resource_cost

		# Second activation should fail (on cooldown) and not spend more resource
		var context2 = MobaCastContext.new(caster, target)
		var action2 = MobaAbilityAction.new(caster, &"power_strike", context2)
		var result2 = action2.execute()

		if result2.success:
			violations.append("atomic_commitment: second activation should fail")

		if caster_combatant._current_resource != expected_after_first:
			violations.append(
				"atomic_commitment: resource should remain at first cost (expected %f, got %f)"
				% [expected_after_first, caster_combatant._current_resource]
			)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations
