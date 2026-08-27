## Test suite for cast time delay and cast cancellation economics.
##
## Covers: cast_time deferred resolution, in-progress cast tracking, cancel() method,
## hard-CC cancellation, and all four on_cancel outcome mappings.
class_name CastCancelTest

const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaAbilityCaster = preload("res://rules/abilities/moba_ability_caster.gd")
const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaAbilityAction = preload("res://rules/abilities/moba_ability_action.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaCrowdControlSpec = preload("res://rules/effects/moba_crowd_control_spec.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

const _FIXTURE_FILES: Array[String] = [
	"cast_time_ability.tres",
	"self_ability.tres",
]

const _ALL_ABILITY_IDS: Array[StringName] = [
	&"cast_time_ability",
	&"self_ability",
	&"cataclysm",
]


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_cast_time_defers_resolution())
	all_violations.append_array(_test_instant_ability_resolves_immediately())
	all_violations.append_array(_test_cancel_no_op_when_no_cast_in_progress())
	all_violations.append_array(_test_on_cancel_full_refund())
	all_violations.append_array(_test_on_cancel_partial_refund())
	all_violations.append_array(_test_on_cancel_no_refund())
	all_violations.append_array(_test_on_cancel_cooldown_still_applies())
	all_violations.append_array(_test_hard_cc_cancels_cast())
	all_violations.append_array(_test_resolution_wins_ties())
	all_violations.append_array(_test_cataclysm_ability_data())

	if all_violations.is_empty():
		return true

	printerr("\n=== Cast Cancel Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


static func _ensure_all_test_abilities_loaded() -> void:
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")

	var fixtures_dir = "res://rules/tests/fixtures/abilities/"
	for file_name in _FIXTURE_FILES:
		MobaAbilityLibrary._load_single_ability(fixtures_dir.path_join(file_name))


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


class _TestTarget:
	extends Node
	var global_position: Vector3 = Vector3.ZERO


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


## Test: Cast time > 0 enters ABILITY_CAST and defers damage/effects until cast completes
static func _test_cast_time_defers_resolution() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]
	var state_machine = test_actor["state_machine"]
	var target = _create_target_with_combatant()
	var target_combatant = target.get_node("MobaCombatant") as MobaCombatant

	var initial_target_health = target_combatant._current_health

	# Activate cast_time_ability (cast_time = 0.5)
	var context = MobaCastContext.new()
	context.caster = actor
	context.explicit_target = target

	var result = MobaAbilityCaster.new().activate(&"cast_time_ability", context)
	if not result.success:
		violations.append("cast_time_defers: activation should succeed, got %s" % result.reason)
		return violations

	# Should be in ABILITY_CAST state
	if state_machine.current_state != MobaState.ABILITY_CAST:
		violations.append("cast_time_defers: should be in ABILITY_CAST state, got %d" % state_machine.current_state)

	# Damage should not be applied yet
	if not is_equal_approx(target_combatant._current_health, initial_target_health):
		violations.append("cast_time_defers: target health should not change before cast completes")

	# After 0.5 seconds, damage should be applied
	combatant.tick(0.5)
	if is_equal_approx(target_combatant._current_health, initial_target_health):
		violations.append("cast_time_defers: target health should decrease after cast completes")

	return violations


## Test: Cast time == 0 resolves instantly and never enters ABILITY_CAST
static func _test_instant_ability_resolves_immediately() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]
	var state_machine = test_actor["state_machine"]
	var target = _create_target_with_combatant()
	var target_combatant = target.get_node("MobaCombatant") as MobaCombatant

	var initial_target_health = target_combatant._current_health

	# Activate self_ability (cast_time = 0) - it's a self-targeted ability, so use actor as target
	var context = MobaCastContext.new()
	context.caster = actor
	context.explicit_target = actor

	var result = MobaAbilityCaster.new().activate(&"self_ability", context)
	if not result.success:
		violations.append("instant_ability: activation should succeed, got %s" % result.reason)
		return violations

	# For self_ability (self-targeted, no damage), verify it resolves instantly without entering ABILITY_CAST
	# self_ability has cast_time = 0, so it should not enter ABILITY_CAST state
	# We can verify this by checking that _cast_in_progress is null after the ability is activated
	if combatant._cast_in_progress != null:
		violations.append("instant_ability: should not have in-progress cast for instant ability")

	return violations


## Test: cancel() with no cast in progress is a no-op, not an error
static func _test_cancel_no_op_when_no_cast_in_progress() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]

	# Call cancel with nothing in progress - should not error
	MobaAbilityCaster.new().cancel(actor)
	MobaAbilityCaster.new().cancel(actor)  # Call again to ensure it's safe

	# Also test with MobaCastContext
	var context = MobaCastContext.new()
	context.caster = actor
	MobaAbilityCaster.new().cancel(context)

	# If we get here without crashing, the test passes
	return violations


## Test: on_cancel = FULL_REFUND refunds 100% of resource and undoes cooldown
static func _test_on_cancel_full_refund() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]

	# Create an ability with on_cancel = FULL_REFUND
	var ability = MobaAbility.new()
	ability.id = "full_refund_test"
	ability.resource_cost = 40.0
	ability.cooldown = 5.0
	ability.cast_time = 1.0
	ability.charges = 1
	ability.on_cancel = MobaAbility.OnCancel.FULL_REFUND
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	ability.base_damage = 20.0

	combatant.register_ability(ability)

	var initial_resource = combatant._current_resource
	var target = _create_target_with_combatant()

	# Start the cast
	var context = MobaCastContext.new()
	context.caster = actor
	context.explicit_target = target

	var action = MobaAbilityAction.new(actor, &"full_refund_test", context)
	var result = ActionRunner.run(action)
	if not result.success:
		violations.append("full_refund: activation should succeed")
		return violations

	var resource_after_commit = combatant._current_resource
	if not is_equal_approx(resource_after_commit, initial_resource - 40.0):
		violations.append("full_refund: resource should be spent at commit")

	var cooldown_after_commit = combatant._cooldowns.remaining(&"full_refund_test")
	if cooldown_after_commit <= 0.0:
		violations.append("full_refund: cooldown should be started at commit")

	# Cancel the cast
	combatant.cancel_cast()

	var resource_after_cancel = combatant._current_resource
	if not is_equal_approx(resource_after_cancel, initial_resource):
		violations.append(
			"full_refund: resource should be fully refunded after cancel, expected %f, got %f"
			% [initial_resource, resource_after_cancel]
		)

	var cooldown_after_cancel = combatant._cooldowns.remaining(&"full_refund_test")
	if cooldown_after_cancel > 0.0:
		violations.append("full_refund: cooldown should be undone after cancel")

	return violations


## Test: on_cancel = PARTIAL_REFUND refunds the specified fraction and undoes cooldown
static func _test_on_cancel_partial_refund() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]

	# Create an ability with on_cancel = PARTIAL_REFUND
	var ability = MobaAbility.new()
	ability.id = "partial_refund_test"
	ability.resource_cost = 40.0
	ability.cooldown = 5.0
	ability.cast_time = 1.0
	ability.charges = 1
	ability.on_cancel = MobaAbility.OnCancel.PARTIAL_REFUND
	ability.refund_resource_on_cancel = 0.5  # Refund 50%
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	ability.base_damage = 20.0

	combatant.register_ability(ability)

	var initial_resource = combatant._current_resource
	var target = _create_target_with_combatant()

	# Start the cast
	var context = MobaCastContext.new()
	context.caster = actor
	context.explicit_target = target

	var action = MobaAbilityAction.new(actor, &"partial_refund_test", context)
	var result = ActionRunner.run(action)
	if not result.success:
		violations.append("partial_refund: activation should succeed")
		return violations

	var resource_after_commit = combatant._current_resource
	var expected_after_commit = initial_resource - 40.0
	if not is_equal_approx(resource_after_commit, expected_after_commit):
		violations.append("partial_refund: resource should be spent at commit")

	# Cancel the cast
	combatant.cancel_cast()

	var resource_after_cancel = combatant._current_resource
	var expected_after_cancel = expected_after_commit + (40.0 * 0.5)  # Refund 50%
	if not is_equal_approx(resource_after_cancel, expected_after_cancel):
		violations.append(
			"partial_refund: resource should be partially refunded, expected %f, got %f"
			% [expected_after_cancel, resource_after_cancel]
		)

	var cooldown_after_cancel = combatant._cooldowns.remaining(&"partial_refund_test")
	if cooldown_after_cancel > 0.0:
		violations.append("partial_refund: cooldown should be undone after cancel")

	return violations


## Test: on_cancel = NO_REFUND refunds nothing but undoes cooldown
static func _test_on_cancel_no_refund() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]

	# Create an ability with on_cancel = NO_REFUND
	var ability = MobaAbility.new()
	ability.id = "no_refund_test"
	ability.resource_cost = 40.0
	ability.cooldown = 5.0
	ability.cast_time = 1.0
	ability.charges = 1
	ability.on_cancel = MobaAbility.OnCancel.NO_REFUND
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	ability.base_damage = 20.0

	combatant.register_ability(ability)

	var initial_resource = combatant._current_resource
	var target = _create_target_with_combatant()

	# Start the cast
	var context = MobaCastContext.new()
	context.caster = actor
	context.explicit_target = target

	var action = MobaAbilityAction.new(actor, &"no_refund_test", context)
	var result = ActionRunner.run(action)
	if not result.success:
		violations.append("no_refund: activation should succeed")
		return violations

	var resource_after_commit = combatant._current_resource
	var expected_after_commit = initial_resource - 40.0
	if not is_equal_approx(resource_after_commit, expected_after_commit):
		violations.append("no_refund: resource should be spent at commit")

	# Cancel the cast
	combatant.cancel_cast()

	var resource_after_cancel = combatant._current_resource
	if not is_equal_approx(resource_after_cancel, expected_after_commit):
		violations.append(
			"no_refund: resource should not be refunded, expected %f, got %f"
			% [expected_after_commit, resource_after_cancel]
		)

	var cooldown_after_cancel = combatant._cooldowns.remaining(&"no_refund_test")
	if cooldown_after_cancel > 0.0:
		violations.append("no_refund: cooldown should be undone after cancel")

	return violations


## Test: on_cancel = COOLDOWN_STILL_APPLIES leaves cooldown running and refunds nothing
static func _test_on_cancel_cooldown_still_applies() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]

	# Create an ability with on_cancel = COOLDOWN_STILL_APPLIES
	var ability = MobaAbility.new()
	ability.id = "cooldown_still_applies_test"
	ability.resource_cost = 40.0
	ability.cooldown = 5.0
	ability.cast_time = 1.0
	ability.charges = 1
	ability.on_cancel = MobaAbility.OnCancel.COOLDOWN_STILL_APPLIES
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	ability.base_damage = 20.0

	combatant.register_ability(ability)

	var initial_resource = combatant._current_resource
	var target = _create_target_with_combatant()

	# Start the cast
	var context = MobaCastContext.new()
	context.caster = actor
	context.explicit_target = target

	var action = MobaAbilityAction.new(actor, &"cooldown_still_applies_test", context)
	var result = ActionRunner.run(action)
	if not result.success:
		violations.append("cooldown_still_applies: activation should succeed")
		return violations

	var resource_after_commit = combatant._current_resource
	var expected_after_commit = initial_resource - 40.0
	if not is_equal_approx(resource_after_commit, expected_after_commit):
		violations.append("cooldown_still_applies: resource should be spent at commit")

	var cooldown_after_commit = combatant._cooldowns.remaining(&"cooldown_still_applies_test")
	if cooldown_after_commit <= 0.0:
		violations.append("cooldown_still_applies: cooldown should be started at commit")

	# Cancel the cast
	combatant.cancel_cast()

	var resource_after_cancel = combatant._current_resource
	if not is_equal_approx(resource_after_cancel, expected_after_commit):
		violations.append(
			"cooldown_still_applies: resource should not be refunded, expected %f, got %f"
			% [expected_after_commit, resource_after_cancel]
		)

	var cooldown_after_cancel = combatant._cooldowns.remaining(&"cooldown_still_applies_test")
	if cooldown_after_cancel <= 0.0:
		violations.append("cooldown_still_applies: cooldown should still be running after cancel")

	return violations


## Test: Hard-CC interrupt produces identical outcome to cancel()
static func _test_hard_cc_cancels_cast() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]

	# Create an ability with on_cancel = PARTIAL_REFUND (use non-default value)
	var ability = MobaAbility.new()
	ability.id = "cc_cancel_test"
	ability.resource_cost = 40.0
	ability.cooldown = 5.0
	ability.cast_time = 1.0
	ability.charges = 1
	ability.on_cancel = MobaAbility.OnCancel.PARTIAL_REFUND
	ability.refund_resource_on_cancel = 0.25  # Refund 25%
	ability.cancellable_by_hard_cc = true
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	ability.base_damage = 20.0

	combatant.register_ability(ability)

	var initial_resource = combatant._current_resource
	var target = _create_target_with_combatant()

	# Start the cast
	var context = MobaCastContext.new()
	context.caster = actor
	context.explicit_target = target

	var action = MobaAbilityAction.new(actor, &"cc_cancel_test", context)
	var result = ActionRunner.run(action)
	if not result.success:
		violations.append("hard_cc_cancel: activation should succeed")
		return violations

	var resource_after_commit = combatant._current_resource
	var expected_after_commit = initial_resource - 40.0
	if not is_equal_approx(resource_after_commit, expected_after_commit):
		violations.append("hard_cc_cancel: resource should be spent at commit")

	# Create and apply a hard CC that interrupts the cast
	var cc_spec = MobaCrowdControlSpec.new()
	cc_spec.type = MobaCrowdControlSpec.CCType.STUN
	cc_spec.duration = 2.0
	cc_spec.magnitude = 1.0
	cc_spec.affected_by_tenacity = false

	var cc_source = MobaCombatant.new()
	cc_source._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()

	combatant.apply_crowd_control(cc_spec, cc_source)

	var resource_after_cc = combatant._current_resource
	var expected_after_cc = expected_after_commit + (40.0 * 0.25)  # Partial refund

	if not is_equal_approx(resource_after_cc, expected_after_cc):
		violations.append(
			"hard_cc_cancel: resource should be partially refunded by CC interrupt, expected %f, got %f"
			% [expected_after_cc, resource_after_cc]
		)

	var cooldown_after_cc = combatant._cooldowns.remaining(&"cc_cancel_test")
	if cooldown_after_cc > 0.0:
		violations.append("hard_cc_cancel: cooldown should be undone by CC interrupt")

	return violations


## Test: Resolution wins ties - casting at exactly the resolution time resolves the ability
static func _test_resolution_wins_ties() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]
	var state_machine = test_actor["state_machine"]
	var target = _create_target_with_combatant()
	var target_combatant = target.get_node("MobaCombatant") as MobaCombatant

	var initial_target_health = target_combatant._current_health

	# Activate cast_time_ability with 0.5s cast time
	var context = MobaCastContext.new()
	context.caster = actor
	context.explicit_target = target

	var result = MobaAbilityCaster.new().activate(&"cast_time_ability", context)
	if not result.success:
		violations.append("resolution_wins_ties: activation should succeed")
		return violations

	# Tick exactly 0.5 seconds - should resolve
	combatant.tick(0.5)

	# Damage should be applied
	if is_equal_approx(target_combatant._current_health, initial_target_health):
		violations.append("resolution_wins_ties: cast should resolve at exactly 0.5s")
		return violations

	# Now call cancel() after resolution - should be a no-op
	var resource_before_cancel = combatant._current_resource
	combatant.cancel_cast()
	var resource_after_cancel = combatant._current_resource

	if not is_equal_approx(resource_before_cancel, resource_after_cancel):
		violations.append("resolution_wins_ties: cancel after resolution should be a no-op")

	return violations


## Test: Cataclysm.tres exists and has correct values
static func _test_cataclysm_ability_data() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var cataclysm = MobaAbilityLibrary.get_ability(&"cataclysm")

	if cataclysm == null:
		violations.append("cataclysm_data: ability should exist")
		return violations

	if cataclysm.id != "cataclysm":
		violations.append("cataclysm_data: id should be 'cataclysm'")

	if cataclysm.discipline != MobaAbility.Discipline.MYSTIC:
		violations.append("cataclysm_data: discipline should be MYSTIC")

	if cataclysm.targeting_type != MobaAbility.TargetingType.GROUND:
		violations.append("cataclysm_data: targeting_type should be GROUND")

	if cataclysm.damage_type != MobaAbility.DamageType.MAGICAL:
		violations.append("cataclysm_data: damage_type should be MAGICAL")

	if not is_equal_approx(cataclysm.base_damage, 160.0):
		violations.append("cataclysm_data: base_damage should be 160.0")

	if not is_equal_approx(cataclysm.resource_cost, 75.0):
		violations.append("cataclysm_data: resource_cost should be 75.0")

	if not is_equal_approx(cataclysm.cooldown, 18.0):
		violations.append("cataclysm_data: cooldown should be 18.0")

	if not is_equal_approx(cataclysm.cast_time, 0.75):
		violations.append("cataclysm_data: cast_time should be 0.75")

	if not is_equal_approx(cataclysm.area_radius, 4.0):
		violations.append("cataclysm_data: area_radius should be 4.0")

	return violations
