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

## Fixture files this suite needs, loaded by exact path rather than by scanning the
## whole fixtures/abilities/ directory -- that directory also holds
## AbilityLibraryTest's deliberately-broken fixtures (broken.tres, wrong_type.tres),
## which would spam validate-godot.sh with unrelated load-failure noise if scanned
## here.
const _FIXTURE_FILES: Array[String] = [
	"self_ability.tres",
	"skillshot_ability.tres",
	"ground_ability.tres",
	"area_ability.tres",
	"toggle_ability.tres",
	"channeled_ability.tres",
]

## Every ability id this suite registers on a freshly created test combatant.
const _ALL_ABILITY_IDS: Array[StringName] = [
	&"power_strike",
	&"self_ability",
	&"skillshot_ability",
	&"ground_ability",
	&"area_ability",
	&"toggle_ability",
	&"channeled_ability",
]

## Unimplemented targeting types that must each fail with targeting_not_implemented.
## Maps ability id -> targeting type name, for assertion messages.
const _UNIMPLEMENTED_TYPE_ABILITIES: Dictionary = {
	&"skillshot_ability": "SKILLSHOT",
	&"ground_ability": "GROUND",
	&"area_ability": "AREA",
	&"toggle_ability": "TOGGLE",
	&"channeled_ability": "CHANNELED",
}


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_targeted_damage_ability())
	all_violations.append_array(_test_self_ability())
	all_violations.append_array(_test_unknown_ability())
	all_violations.append_array(_test_illegal_state())
	all_violations.append_array(_test_insufficient_resource())
	all_violations.append_array(_test_no_charges())
	all_violations.append_array(_test_targeting_not_implemented_variants())
	all_violations.append_array(_test_target_freed_before_activation())
	all_violations.append_array(_test_target_freed_after_commit())
	all_violations.append_array(_test_out_of_range())
	all_violations.append_array(_test_invalid_target_reference())
	all_violations.append_array(_test_atomic_resource_commitment())
	all_violations.append_array(_test_ability_caster_activate())
	all_violations.append_array(_test_ability_caster_activate_without_preregistration())
	all_violations.append_array(_test_brace_buff_application())
	all_violations.append_array(_test_brace_buff_expiry())

	if all_violations.is_empty():
		return true

	printerr("\n=== Ability Activation Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Helper to load all abilities this suite needs into the library: the real
## power_strike.tres from rules/data/abilities/, plus this suite's own fixtures
## (loaded individually, not the whole fixtures directory).
static func _ensure_all_test_abilities_loaded() -> void:
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")

	var fixtures_dir = "res://rules/tests/fixtures/abilities/"
	for file_name in _FIXTURE_FILES:
		MobaAbilityLibrary._load_single_ability(fixtures_dir.path_join(file_name))


## Helper to create a test actor with a real MobaCombatant and MobaStateMachine
## as child nodes (not test-only metadata), matching how MobaAbilityAction looks
## them up in production via get_node_or_null().
##
## By default every ability in _ALL_ABILITY_IDS is pre-registered on the combatant.
## Pass register_abilities = false to get a bare combatant with nothing registered,
## exercising MobaAbilityCaster.activate()'s own idempotent register_ability() step.
static func _create_test_actor(register_abilities: bool = true) -> Dictionary:
	var actor = Actor.new()
	actor.owner_id = 1

	var combatant = MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)

	if register_abilities:
		for ability_id in _ALL_ABILITY_IDS:
			var ability = MobaAbilityLibrary.get_ability(ability_id)
			if ability != null:
				combatant.register_ability(ability)

	actor.add_child(combatant)

	var state_machine = MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	var wrapper = {
		"actor": actor,
		"combatant": combatant,
		"state_machine": state_machine,
	}

	return wrapper


## A lightweight stand-in for a positioned target node in tests. A plain Node
## with a real (settable, non-computed) global_position field -- not Node3D,
## whose global_position getter/setter requires the node to be inside a live
## SceneTree (Node3D::get_global_transform() errors with "!is_inside_tree()"
## otherwise), which none of this suite's nodes ever are, matching every
## other test file's pattern of constructing nodes standalone.
class _TestTarget:
	extends Node
	var global_position: Vector3 = Vector3.ZERO


## Helper to create a mock target with a real MobaCombatant child node.
static func _create_target_with_combatant() -> Node:
	var target := _TestTarget.new()

	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)
	target.add_child(combatant)

	return target


## Fetch a target's MobaCombatant child node.
static func _target_combatant(target: Node) -> MobaCombatant:
	return target.get_node("MobaCombatant") as MobaCombatant


## Test 1: Targeted damage ability activation
static func _test_targeted_damage_ability() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)  # Within 2.0 range

	# Disable crit on the CASTER so the damage figure is deterministic: crit is
	# the attacker's statistic and apply_damage() reads it off MobaDamage.source.
	# Zeroing it on the target would leave the caster's baseline 5% live and make
	# this assertion fail one run in twenty. Also seed the crit RNG for
	# deterministic replay per §34.
	caster_combatant._runtime_stat_block.crit_chance = 0.0
	MobaRules.seed_crit_rng(42)

	var initial_health = _target_combatant(target)._current_health
	var initial_resource = caster_combatant._current_resource

	# Activate Power Strike
	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	if not result.success:
		violations.append("targeted_damage: activation should succeed, got: %s" % result.reason)

	# Check the exact mitigated damage figure via MobaFormulas, not just that health
	# dropped -- §19: 100 physical vs 30 armor ≈ 76.9.
	var power_strike_ability = MobaAbilityLibrary.get_ability(&"power_strike")
	if power_strike_ability != null:
		var target_armor: float = _target_combatant(target).get_stat(MobaStatBlock.ARMOR)
		var expected_damage := MobaFormulas.physical_damage(
			power_strike_ability.base_damage, target_armor
		)
		var actual_damage: float = initial_health - _target_combatant(target)._current_health
		if not is_equal_approx(actual_damage, expected_damage):
			(
				violations
				. append(
					(
						"targeted_damage: damage should match MobaFormulas.physical_damage (expected %f, got %f)"
						% [expected_damage, actual_damage]
					)
				)
			)

	# Check resource was spent
	var power_strike = MobaAbilityLibrary.get_ability(&"power_strike")
	if power_strike != null:
		var expected_resource = initial_resource - power_strike.resource_cost
		if not is_equal_approx(caster_combatant._current_resource, expected_resource):
			violations.append(
				(
					"targeted_damage: resource should be spent (expected %f, got %f)"
					% [expected_resource, caster_combatant._current_resource]
				)
			)

	# Check cooldown was started
	if caster_combatant._cooldowns.remaining(&"power_strike") <= 0.0:
		violations.append("targeted_damage: cooldown should have started")

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
				(
					"self_ability: resource should be spent (expected %f, got %f)"
					% [expected_resource, caster_combatant._current_resource]
				)
			)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 3: Unknown ability returns failure
static func _test_unknown_ability() -> Array[String]:
	var violations: Array[String] = []

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]

	var context = MobaCastContext.new(caster, null)
	var action = MobaAbilityAction.new(caster, &"unknown_ability_xyz", context)
	var result = action.execute()

	if result.success:
		violations.append("unknown_ability: activation should fail")

	if result.reason != MobaAbilityAction.FAILURE_UNKNOWN_ABILITY:
		violations.append(
			"unknown_ability: reason should be 'unknown_ability', got '%s'" % result.reason
		)

	return violations


## Test 4: State machine denies ability activation (illegal_state)
static func _test_illegal_state() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var caster_state_machine = caster_data["state_machine"]

	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	# DASHING's "ability" column is "no" in state_transitions.json
	caster_state_machine.try_enter(MobaState.DASHING, 1.0)

	var initial_resource = caster_combatant._current_resource
	var initial_cooldown = caster_combatant._cooldowns.remaining(&"power_strike")

	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	if result.success:
		violations.append("illegal_state: activation should fail")

	if result.reason != MobaAbilityAction.FAILURE_ILLEGAL_STATE:
		violations.append(
			"illegal_state: reason should be 'illegal_state', got '%s'" % result.reason
		)

	if caster_combatant._current_resource != initial_resource:
		violations.append("illegal_state: resource should not be committed on failure")

	if caster_combatant._cooldowns.remaining(&"power_strike") != initial_cooldown:
		violations.append("illegal_state: cooldown should not be started on failure")

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 5: Insufficient resource blocks activation
static func _test_insufficient_resource() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	# Drain resource below ability cost
	var power_strike = MobaAbilityLibrary.get_ability(&"power_strike")
	if power_strike != null:
		caster_combatant._current_resource = power_strike.resource_cost - 1.0

	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	var initial_resource = caster_combatant._current_resource
	var initial_cooldown = caster_combatant._cooldowns.remaining(&"power_strike")

	# Try to activate Power Strike
	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	if result.success:
		violations.append("insufficient_resource: activation should fail")

	if result.reason != MobaAbilityAction.FAILURE_INSUFFICIENT_RESOURCE:
		violations.append(
			(
				"insufficient_resource: reason should be 'insufficient_resource', got '%s'"
				% result.reason
			)
		)

	# Check resource was NOT spent
	if caster_combatant._current_resource != initial_resource:
		violations.append("insufficient_resource: resource should not be committed on failure")

	# Check cooldown was NOT started
	if caster_combatant._cooldowns.remaining(&"power_strike") != initial_cooldown:
		violations.append("insufficient_resource: cooldown should not be started on failure")

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 6: A second activation while the single charge is recharging blocks
## activation. Power Strike has charges = 1, so exhausting that one charge
## and having an active recharge timer surfaces via
## MobaCombatant.can_activate() as NO_CHARGES -- the ON_COOLDOWN enum value
## is never produced by the current charge-based cooldown model (see
## MobaCombatant.can_activate()), which this test suite must not
## reimplement or reorder.
static func _test_no_charges() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	# Activate once to spend the only charge and start the recharge timer
	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result1 = action.execute()

	if not result1.success:
		violations.append("no_charges: first activation should succeed")
		return violations

	var resource_after_first = caster_combatant._current_resource
	var cooldown_after_first = caster_combatant._cooldowns.remaining(&"power_strike")

	# Try to activate again while the single charge is still recharging
	var action2 = MobaAbilityAction.new(caster, &"power_strike", context)
	var result2 = action2.execute()

	if result2.success:
		violations.append("no_charges: second activation should fail")

	if result2.reason != MobaAbilityAction.FAILURE_NO_CHARGES:
		violations.append("no_charges: reason should be 'no_charges', got '%s'" % result2.reason)

	if caster_combatant._current_resource != resource_after_first:
		violations.append("no_charges: resource should not change again on failure")

	if caster_combatant._cooldowns.remaining(&"power_strike") != cooldown_after_first:
		violations.append("no_charges: cooldown should not change again on failure")

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 7: Every unimplemented targeting type loads, validates, and activate()
## returns targeting_not_implemented with nothing spent.
static func _test_targeting_not_implemented_variants() -> Array[String]:
	var violations: Array[String] = []

	for ability_id: StringName in _UNIMPLEMENTED_TYPE_ABILITIES:
		var type_name: String = _UNIMPLEMENTED_TYPE_ABILITIES[ability_id]

		# Setup
		MobaAbilityLibrary._reset()
		_ensure_all_test_abilities_loaded()

		var ability = MobaAbilityLibrary.get_ability(ability_id)
		if ability == null:
			violations.append(
				"targeting_not_implemented(%s): fixture failed to load/validate" % type_name
			)
			MobaAbilityLibrary._reset()
			continue

		var caster_data = _create_test_actor()
		var caster = caster_data["actor"]
		var caster_combatant = caster_data["combatant"]
		var target = _create_target_with_combatant()
		target.global_position = Vector3(1, 0, 0)

		var initial_resource = caster_combatant._current_resource
		var initial_cooldown = caster_combatant._cooldowns.remaining(ability_id)

		var context = MobaCastContext.new(caster, target, Vector3.FORWARD)
		var action = MobaAbilityAction.new(caster, ability_id, context)
		var result = action.execute()

		if result.success:
			violations.append("targeting_not_implemented(%s): activation should fail" % type_name)

		if result.reason != MobaAbilityAction.FAILURE_TARGETING_NOT_IMPLEMENTED:
			(
				violations
				. append(
					(
						"targeting_not_implemented(%s): reason should be 'targeting_not_implemented', got '%s'"
						% [type_name, result.reason]
					)
				)
			)

		if caster_combatant._current_resource != initial_resource:
			violations.append(
				"targeting_not_implemented(%s): resource should not be spent" % type_name
			)

		if caster_combatant._cooldowns.remaining(ability_id) != initial_cooldown:
			violations.append(
				"targeting_not_implemented(%s): cooldown should not be started" % type_name
			)

		# Cleanup
		MobaAbilityLibrary._reset()

	return violations


## Test 8: A target already freed/invalid before target resolution (step 5,
## before commit) fails safely with invalid_target and commits nothing.
static func _test_target_freed_before_activation() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var target = _create_target_with_combatant()

	var initial_resource = caster_combatant._current_resource
	var initial_cooldown = caster_combatant._cooldowns.remaining(&"power_strike")

	# Build the context and action while the target is still valid -- MobaCastContext's
	# explicit_target parameter is typed as Node, and binding an already-freed object to
	# a typed parameter is itself a hard engine error, not something is_instance_valid()
	# can rescue. Free the target only after it is safely captured by reference, so
	# execute()'s is_instance_valid() guard (inside _resolve_target) is what actually
	# gets exercised.
	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	target.free()

	var result = action.execute()

	if result.success:
		violations.append("target_freed_before_activation: activation should fail")

	if result.reason != MobaAbilityAction.FAILURE_INVALID_TARGET:
		violations.append(
			(
				"target_freed_before_activation: reason should be 'invalid_target', got '%s'"
				% result.reason
			)
		)

	# Check that resource was NOT spent
	if caster_combatant._current_resource != initial_resource:
		(
			violations
			. append(
				"target_freed_before_activation: resource should not be committed when target is invalid"
			)
		)

	if caster_combatant._cooldowns.remaining(&"power_strike") != initial_cooldown:
		violations.append(
			"target_freed_before_activation: cooldown should not be started when target is invalid"
		)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 9: A target freed between activation (step 6, commit) and resolution
## (step 8, damage/effects) does not crash resolution, and the already-committed
## cost (resource + cooldown) is NOT refunded. Simulated by freeing the target
## the instant resource_changed fires during commit_activate() -- which happens
## synchronously inside execute() before the damage-resolution step runs -- so
## the target is genuinely freed (not just queued) by the time execute() reaches
## the is_instance_valid() guard before damage/effect application.
static func _test_target_freed_after_commit() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	var initial_resource = caster_combatant._current_resource
	var power_strike = MobaAbilityLibrary.get_ability(&"power_strike")
	if power_strike == null:
		violations.append("target_freed_after_commit: power_strike fixture failed to load")
		MobaAbilityLibrary._reset()
		return violations

	var free_on_commit := func(_current: float, _maximum: float):
		if is_instance_valid(target):
			target.free()

	caster_combatant.resource_changed.connect(free_on_commit)

	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	caster_combatant.resource_changed.disconnect(free_on_commit)

	if not result.success:
		violations.append(
			(
				"target_freed_after_commit: activation should still report success, got: %s"
				% result.reason
			)
		)

	# The committed cost must NOT be refunded even though resolution's target evaporated.
	var expected_resource = initial_resource - power_strike.resource_cost
	if not is_equal_approx(caster_combatant._current_resource, expected_resource):
		(
			violations
			. append(
				(
					"target_freed_after_commit: committed cost should not be refunded (expected %f, got %f)"
					% [expected_resource, caster_combatant._current_resource]
				)
			)
		)

	if caster_combatant._cooldowns.remaining(&"power_strike") <= 0.0:
		violations.append("target_freed_after_commit: committed cooldown should not be undone")

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 10: Out of range target fails
static func _test_out_of_range() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	var target = _create_target_with_combatant()
	target.global_position = Vector3(10, 0, 0)  # Beyond 2.0 range

	var initial_resource = caster_combatant._current_resource
	var initial_cooldown = caster_combatant._cooldowns.remaining(&"power_strike")

	# Try to activate Power Strike
	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	if result.success:
		violations.append("out_of_range: activation should fail")

	if result.reason != MobaAbilityAction.FAILURE_OUT_OF_RANGE:
		violations.append("out_of_range: reason should be 'out_of_range', got '%s'" % result.reason)

	# Check that resource was NOT spent
	if caster_combatant._current_resource != initial_resource:
		violations.append("out_of_range: resource should not be committed on failure")

	if caster_combatant._cooldowns.remaining(&"power_strike") != initial_cooldown:
		violations.append("out_of_range: cooldown should not be started on failure")

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 11: Invalid target reference fails
static func _test_invalid_target_reference() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
	var initial_resource = caster_combatant._current_resource
	var initial_cooldown = caster_combatant._cooldowns.remaining(&"power_strike")

	# Try to activate with null explicit_target for a targeted ability
	var context = MobaCastContext.new(caster, null)
	var action = MobaAbilityAction.new(caster, &"power_strike", context)
	var result = action.execute()

	if result.success:
		violations.append("invalid_target_reference: activation should fail")

	if result.reason != MobaAbilityAction.FAILURE_INVALID_TARGET:
		violations.append(
			"invalid_target_reference: reason should be 'invalid_target', got '%s'" % result.reason
		)

	# Check that resource was NOT spent
	if caster_combatant._current_resource != initial_resource:
		violations.append("invalid_target_reference: resource should not be committed on failure")

	if caster_combatant._cooldowns.remaining(&"power_strike") != initial_cooldown:
		violations.append("invalid_target_reference: cooldown should not be started on failure")

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 12: Resource is committed atomically
static func _test_atomic_resource_commitment() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]
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
			MobaAbilityLibrary._reset()
			return violations

		var expected_after_first = initial_resource - power_strike.resource_cost

		# Second activation should fail (no charges left) and not spend more resource
		var context2 = MobaCastContext.new(caster, target)
		var action2 = MobaAbilityAction.new(caster, &"power_strike", context2)
		var result2 = action2.execute()

		if result2.success:
			violations.append("atomic_commitment: second activation should fail")

		if caster_combatant._current_resource != expected_after_first:
			violations.append(
				(
					"atomic_commitment: resource should remain at first cost (expected %f, got %f)"
					% [expected_after_first, caster_combatant._current_resource]
				)
			)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 13: MobaAbilityCaster.activate() routes through the full pipeline for
## both a happy path and a failure path.
static func _test_ability_caster_activate() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	var caster_data = _create_test_actor()
	var caster = caster_data["actor"]

	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	var caster_node = MobaAbilityCaster.new()

	# Happy path: valid targeted activation succeeds through the caster.
	var context = MobaCastContext.new(caster, target)
	var result = caster_node.activate(&"power_strike", context)

	if not result.success:
		violations.append(
			"ability_caster: happy-path activation should succeed, got: %s" % result.reason
		)

	# Failure path: unknown ability id fails with a specific reason via the caster.
	var bad_context = MobaCastContext.new(caster, null)
	var bad_result = caster_node.activate(&"nonexistent_ability_xyz", bad_context)

	if bad_result.success:
		violations.append("ability_caster: unknown ability should fail")

	if bad_result.reason != MobaAbilityAction.FAILURE_UNKNOWN_ABILITY:
		violations.append(
			(
				"ability_caster: unknown ability reason should be 'unknown_ability', got '%s'"
				% bad_result.reason
			)
		)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 14: MobaAbilityCaster.activate() registers the ability with the caster's
## MobaCombatant before checking legality (per the Scope's "stands in for real
## loadout-time registration" step), so a caller that never separately registered
## the ability still activates successfully.
static func _test_ability_caster_activate_without_preregistration() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	_ensure_all_test_abilities_loaded()

	# register_abilities = false: nothing is registered on this combatant yet.
	var caster_data = _create_test_actor(false)
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	if &"power_strike" in caster_combatant._abilities:
		violations.append(
			"ability_caster_without_preregistration: power_strike should not be pre-registered"
		)

	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	var caster_node = MobaAbilityCaster.new()

	var context = MobaCastContext.new(caster, target)
	var result = caster_node.activate(&"power_strike", context)

	if not result.success:
		violations.append(
			(
				"ability_caster_without_preregistration: activation should succeed without"
				+ " prior registration, got: %s" % result.reason
			)
		)

	if not caster_combatant._abilities.has(&"power_strike"):
		violations.append(
			"ability_caster_without_preregistration: activate() should register the ability"
		)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 15: Brace ability buff application.
## Activates brace on a combatant with 30 base armor and asserts:
## - Armor rises from 30 to 70 due to +40 buff
## - Magic resistance rises by 30 due to +30 buff
## - Damage through MobaFormulas is materially less with the buff applied
## - The _apply_effects_seam() is exercised through ability activation
static func _test_brace_buff_application() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._load_single_ability("res://rules/data/abilities/brace.tres")

	var caster_data = _create_test_actor(false)
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	# Register brace ability with the combatant
	var brace_ability = MobaAbilityLibrary.get_ability(&"brace")
	if brace_ability != null:
		caster_combatant.register_ability(brace_ability)

	# Manually set armor to 30 base value for predictable testing
	caster_combatant._runtime_stat_block.armor = 30.0
	caster_combatant._runtime_stat_block.magic_resistance = 0.0

	var initial_armor = caster_combatant.get_stat(&"armor")
	var initial_magic_resistance = caster_combatant.get_stat(&"magic_resistance")

	# Activate Brace on self
	var context = MobaCastContext.new(caster, null)
	var action = MobaAbilityAction.new(caster, &"brace", context)
	var result = action.execute()

	if not result.success:
		violations.append("brace_buff_application: activation should succeed, got: %s" % result.reason)

	# Check armor buff was applied
	var buffed_armor = caster_combatant.get_stat(&"armor")
	if not is_equal_approx(buffed_armor, 70.0):
		violations.append(
			(
				"brace_buff_application: armor should be 70.0 after brace (+40), got %f"
				% buffed_armor
			)
		)

	# Check magic resistance buff was applied
	var buffed_magic_resistance = caster_combatant.get_stat(&"magic_resistance")
	if not is_equal_approx(buffed_magic_resistance, 30.0):
		violations.append(
			(
				"brace_buff_application: magic_resistance should be 30.0 after brace (+30), got %f"
				% buffed_magic_resistance
			)
		)

	# Check damage through MobaFormulas: 100 physical damage should deal less with 70 armor than 30
	# §8: Multiplier = 100 / (100 + Defense)
	# At 30 armor: 100 / 130 ≈ 0.769, so 100 * 0.769 ≈ 76.9
	# At 70 armor: 100 / 170 ≈ 0.588, so 100 * 0.588 ≈ 58.8
	var damage_at_initial_armor = MobaFormulas.physical_damage(100.0, initial_armor)
	var damage_at_buffed_armor = MobaFormulas.physical_damage(100.0, buffed_armor)

	if not (damage_at_buffed_armor < damage_at_initial_armor):
		violations.append(
			(
				"brace_buff_application: damage with 70 armor should be less than with 30 armor"
				+ " (got %f vs %f)" % [damage_at_buffed_armor, damage_at_initial_armor]
			)
		)

	# Check damage values match expected formulas
	var expected_damage_at_buffed = MobaFormulas.physical_damage(100.0, 70.0)
	if not is_equal_approx(damage_at_buffed_armor, expected_damage_at_buffed):
		violations.append(
			(
				"brace_buff_application: damage should match MobaFormulas (expected %f, got %f)"
				% [expected_damage_at_buffed, damage_at_buffed_armor]
			)
		)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations


## Test 16: Brace buff expiry.
## Activates brace, ticks past 4 seconds, and asserts:
## - Armor reverts exactly to 30.0
## - Magic resistance reverts to 0.0
## - Damage through MobaFormulas matches pre-buff values
static func _test_brace_buff_expiry() -> Array[String]:
	var violations: Array[String] = []

	# Setup
	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._load_single_ability("res://rules/data/abilities/brace.tres")

	var caster_data = _create_test_actor(false)
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	# Register brace ability with the combatant
	var brace_ability = MobaAbilityLibrary.get_ability(&"brace")
	if brace_ability != null:
		caster_combatant.register_ability(brace_ability)

	# Manually set armor and magic resistance to known values
	caster_combatant._runtime_stat_block.armor = 30.0
	caster_combatant._runtime_stat_block.magic_resistance = 0.0

	# Activate Brace on self
	var context = MobaCastContext.new(caster, null)
	var action = MobaAbilityAction.new(caster, &"brace", context)
	var result = action.execute()

	if not result.success:
		violations.append("brace_buff_expiry: activation should succeed, got: %s" % result.reason)

	# Check buffs were applied
	var buffed_armor = caster_combatant.get_stat(&"armor")
	if not is_equal_approx(buffed_armor, 70.0):
		violations.append(
			(
				"brace_buff_expiry: armor should be 70.0 after brace, got %f" % buffed_armor
			)
		)

	# Tick past 4 seconds (duration of brace buff)
	caster_combatant.tick(4.1)

	# Check armor reverted exactly to base 30.0
	var expired_armor = caster_combatant.get_stat(&"armor")
	if not is_equal_approx(expired_armor, 30.0):
		violations.append(
			(
				"brace_buff_expiry: armor should revert to exactly 30.0 after expiry, got %f"
				% expired_armor
			)
		)

	# Check magic resistance reverted to 0.0
	var expired_magic_resistance = caster_combatant.get_stat(&"magic_resistance")
	if not is_equal_approx(expired_magic_resistance, 0.0):
		violations.append(
			(
				"brace_buff_expiry: magic_resistance should revert to 0.0 after expiry, got %f"
				% expired_magic_resistance
			)
		)

	# Check damage through MobaFormulas matches original formula
	var expected_damage_at_expired = MobaFormulas.physical_damage(100.0, 30.0)
	var actual_damage_at_expired = MobaFormulas.physical_damage(100.0, expired_armor)
	if not is_equal_approx(actual_damage_at_expired, expected_damage_at_expired):
		violations.append(
			(
				"brace_buff_expiry: damage should match pre-buff MobaFormulas (expected %f, got %f)"
				% [expected_damage_at_expired, actual_damage_at_expired]
			)
		)

	# Cleanup
	MobaAbilityLibrary._reset()

	return violations
