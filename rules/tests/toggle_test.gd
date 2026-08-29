## Test suite for toggle ability lifecycle.
##
## Covers: MobaToggleTracker, toggle activation, per-second drain, deactivation
## on second press, resource exhaustion, death, and silence crowd control.
class_name ToggleTest

const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaAbilityAction = preload("res://rules/abilities/moba_ability_action.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaCrowdControlSpec = preload("res://rules/effects/moba_crowd_control_spec.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

const _FIXTURE_FILE := "res://rules/tests/fixtures/abilities/toggle_ability.tres"
const _TOGGLE_ABILITY_ID := &"toggle_ability"


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_activation_drains_resource())
	all_violations.append_array(_test_second_press_deactivates())
	all_violations.append_array(_test_resource_exhaustion_deactivates())
	all_violations.append_array(_test_death_deactivates())
	all_violations.append_array(_test_silence_deactivates())

	if all_violations.is_empty():
		return true

	printerr("\n=== Toggle Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Test 1: A toggle activates on press and drains its per-second resource cost.
static func _test_activation_drains_resource() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_test_ability_loaded()

	var ability = MobaAbilityLibrary.get_ability(_TOGGLE_ABILITY_ID)
	if ability == null:
		violations.append("activation_drains_resource: fixture failed to load")
		MobaAbilityLibrary._reset()
		return violations

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	var initial_resource = caster_combatant._current_resource
	var per_second_drain = ability.resource_cost
	# Account for resource regeneration happening alongside the drain
	var resource_regen = caster_combatant.get_stat(MobaStatBlock.RESOURCE_REGEN)
	var net_drain = per_second_drain - resource_regen

	# Activate the toggle
	var context = MobaCastContext.new(caster, null, Vector3.FORWARD)
	var action = MobaAbilityAction.new(caster, _TOGGLE_ABILITY_ID, context)
	var result = action.execute()

	if not result.success:
		violations.append(
			"activation_drains_resource: activation should succeed, got '%s'" % result.reason
		)
		MobaAbilityLibrary._reset()
		return violations

	if not caster_combatant.is_toggled_on(_TOGGLE_ABILITY_ID):
		violations.append("activation_drains_resource: toggle should be active after activation")
		MobaAbilityLibrary._reset()
		return violations

	# Resource should not be spent at activation (only on drain ticks)
	if caster_combatant._current_resource != initial_resource:
		violations.append("activation_drains_resource: resource should not be spent at activation")
		MobaAbilityLibrary._reset()
		return violations

	# Advance one second tick - should drain once (accounting for regen)
	caster_combatant.tick(1.0)

	if not _is_close(caster_combatant._current_resource, initial_resource - net_drain, 0.1):
		(
			violations
			. append(
				(
					(
						"activation_drains_resource: expected net drain %.1f after 1s"
						+ " (drain %.1f, regen %.1f), got %.1f"
					)
					% [
						net_drain,
						per_second_drain,
						resource_regen,
						initial_resource - caster_combatant._current_resource,
					]
				)
			)
		)
		MobaAbilityLibrary._reset()
		return violations

	# Advance another second - should drain again
	var after_first_tick = caster_combatant._current_resource
	caster_combatant.tick(1.0)

	if not _is_close(caster_combatant._current_resource, after_first_tick - net_drain, 0.1):
		violations.append(
			"activation_drains_resource: resource should be drained twice after 2 seconds"
		)
		MobaAbilityLibrary._reset()
		return violations

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 2: A second press while toggled on deactivates it immediately,
## bypassing cooldown/resource legality.
static func _test_second_press_deactivates() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_test_ability_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	# First press: activate
	var context1 = MobaCastContext.new(caster, null, Vector3.FORWARD)
	var action1 = MobaAbilityAction.new(caster, _TOGGLE_ABILITY_ID, context1)
	var result1 = action1.execute()

	if not result1.success:
		violations.append("second_press_deactivates: first activation should succeed")
		MobaAbilityLibrary._reset()
		return violations

	if not caster_combatant.is_toggled_on(_TOGGLE_ABILITY_ID):
		violations.append("second_press_deactivates: toggle should be active after first press")
		MobaAbilityLibrary._reset()
		return violations

	# Drain enough resource to make activation impossible
	caster_combatant._current_resource = 1.0

	# Second press: should deactivate even with insufficient resource
	var context2 = MobaCastContext.new(caster, null, Vector3.FORWARD)
	var action2 = MobaAbilityAction.new(caster, _TOGGLE_ABILITY_ID, context2)
	var result2 = action2.execute()

	if not result2.success:
		(
			violations
			. append(
				(
					"second_press_deactivates: second press should succeed even with low resource, got '%s'"
					% result2.reason
				)
			)
		)
		MobaAbilityLibrary._reset()
		return violations

	if caster_combatant.is_toggled_on(_TOGGLE_ABILITY_ID):
		violations.append(
			"second_press_deactivates: toggle should be deactivated after second press"
		)
		MobaAbilityLibrary._reset()
		return violations

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 3: Running out of resource deactivates an active toggle automatically.
static func _test_resource_exhaustion_deactivates() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_test_ability_loaded()

	var ability = MobaAbilityLibrary.get_ability(_TOGGLE_ABILITY_ID)
	if ability == null:
		violations.append("resource_exhaustion_deactivates: fixture failed to load")
		MobaAbilityLibrary._reset()
		return violations

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	# Activate the toggle
	var context = MobaCastContext.new(caster, null, Vector3.FORWARD)
	var action = MobaAbilityAction.new(caster, _TOGGLE_ABILITY_ID, context)
	var result = action.execute()

	if not result.success:
		violations.append("resource_exhaustion_deactivates: activation should succeed")
		MobaAbilityLibrary._reset()
		return violations

	# Set resource to less than one drain cost
	caster_combatant._current_resource = ability.resource_cost - 1.0

	# Advance one second - should deactivate due to insufficient resource
	caster_combatant.tick(1.0)

	if caster_combatant.is_toggled_on(_TOGGLE_ABILITY_ID):
		violations.append(
			"resource_exhaustion_deactivates: toggle should be deactivated when resource exhausted"
		)
		MobaAbilityLibrary._reset()
		return violations

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 4: Death deactivates an active toggle.
static func _test_death_deactivates() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_test_ability_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	# Activate the toggle
	var context = MobaCastContext.new(caster, null, Vector3.FORWARD)
	var action = MobaAbilityAction.new(caster, _TOGGLE_ABILITY_ID, context)
	var result = action.execute()

	if not result.success:
		violations.append("death_deactivates: activation should succeed")
		MobaAbilityLibrary._reset()
		return violations

	if not caster_combatant.is_toggled_on(_TOGGLE_ABILITY_ID):
		violations.append("death_deactivates: toggle should be active after activation")
		MobaAbilityLibrary._reset()
		return violations

	# Kill the combatant
	caster_combatant._current_health = 0.0
	caster_combatant._update_health()

	# Check that toggle is deactivated
	if caster_combatant.is_toggled_on(_TOGGLE_ABILITY_ID):
		violations.append("death_deactivates: toggle should be deactivated on death")
		MobaAbilityLibrary._reset()
		return violations

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 5: Applying a crowd control that forbids abilities (silence) deactivates an active toggle.
static func _test_silence_deactivates() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_test_ability_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	# Activate the toggle
	var context = MobaCastContext.new(caster, null, Vector3.FORWARD)
	var action = MobaAbilityAction.new(caster, _TOGGLE_ABILITY_ID, context)
	var result = action.execute()

	if not result.success:
		violations.append("silence_deactivates: activation should succeed")
		MobaAbilityLibrary._reset()
		return violations

	if not caster_combatant.is_toggled_on(_TOGGLE_ABILITY_ID):
		violations.append("silence_deactivates: toggle should be active after activation")
		MobaAbilityLibrary._reset()
		return violations

	# Apply a silence crowd control
	var silence_spec = MobaCrowdControlSpec.new()
	silence_spec.type = MobaCrowdControlSpec.CCType.SILENCE
	silence_spec.duration = 1.0
	caster_combatant.apply_crowd_control(silence_spec, caster_combatant)

	# Advance one tick - toggle should deactivate due to silence
	caster_combatant.tick(0.1)

	if caster_combatant.is_toggled_on(_TOGGLE_ABILITY_ID):
		violations.append(
			"silence_deactivates: toggle should be deactivated when silence is applied"
		)
		MobaAbilityLibrary._reset()
		return violations

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Helper to check if two floats are close within a tolerance.
static func _is_close(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


## Helper to load the test ability fixture into the library.
static func _ensure_test_ability_loaded() -> void:
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")
	MobaAbilityLibrary._load_single_ability(_FIXTURE_FILE)


## Helper to create a test actor with a real MobaCombatant and MobaStateMachine.
static func _create_test_actor() -> Dictionary:
	var actor = Actor.new()
	actor.owner_id = 1

	var combatant = MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = _BASELINE_STAT_BLOCK.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = _BASELINE_STAT_BLOCK.get_stat_value(MobaStatBlock.RESOURCE)
	combatant.register_ability(MobaAbilityLibrary.get_ability(_TOGGLE_ABILITY_ID))
	actor.add_child(combatant)

	var state_machine = MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	return {
		"actor": actor,
		"combatant": combatant,
		"state_machine": state_machine,
	}
