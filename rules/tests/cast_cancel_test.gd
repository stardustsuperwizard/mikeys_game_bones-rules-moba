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
	&"power_strike",
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
	all_violations.append_array(_test_cast_target_freed_before_resolution())
	all_violations.append_array(_test_cast_target_freed_during_commit())
	all_violations.append_array(_test_cataclysm_ability_data())

	# Several cases above inject synthetic abilities into the shared library
	# cache. Reset once here so none of them reach the suites that run after
	# this one, matching how ability_activation_test.gd leaves the library.
	MobaAbilityLibrary._reset()

	if all_violations.is_empty():
		return true

	printerr("\n=== Cast Cancel Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Load the shipped abilities plus this suite's fixtures into the library.
##
## Resets first so each case starts from a clean cache: several cases inject
## synthetic abilities directly, and any of them can return early on a
## violation before it would have cleaned up after itself.
static func _ensure_all_test_abilities_loaded() -> void:
	MobaAbilityLibrary._reset()
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
	var context = MobaCastContext.new(actor, target)

	var result = MobaAbilityCaster.new().activate(&"cast_time_ability", context)
	if not result.success:
		violations.append("cast_time_defers: activation should succeed, got %s" % result.reason)
		return violations

	# Should be in ABILITY_CAST state
	if state_machine.current_state != MobaState.ABILITY_CAST:
		violations.append(
			(
				"cast_time_defers: should be in ABILITY_CAST state, got %d"
				% state_machine.current_state
			)
		)

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

	# power_strike is targeted with cast_time = 0.0 and base_damage = 100.0, so
	# "resolved instantly" is observable as damage rather than merely assumed.
	# self_ability would deal none and could not tell resolution from a no-op.
	var context = MobaCastContext.new(actor, target)

	var result = MobaAbilityCaster.new().activate(&"power_strike", context)
	if not result.success:
		violations.append("instant_ability: activation should succeed, got %s" % result.reason)
		return violations

	# Resolution happens on activation: damage lands with no tick() at all.
	if is_equal_approx(target_combatant._current_health, initial_target_health):
		violations.append(
			(
				"instant_ability: damage should apply immediately, health still %f"
				% target_combatant._current_health
			)
		)

	# AC 2: an instant ability never enters ABILITY_CAST.
	if state_machine.current_state == MobaState.ABILITY_CAST:
		violations.append(
			(
				"instant_ability: should never enter ABILITY_CAST, got state %d"
				% state_machine.current_state
			)
		)

	# ...and leaves nothing for the cast tracker to resolve or cancel.
	if combatant.is_casting():
		violations.append("instant_ability: should not have in-progress cast for instant ability")

	return violations


## Test: cancel() with no cast in progress is a no-op, not an error
static func _test_cancel_no_op_when_no_cast_in_progress() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant := test_actor["combatant"] as MobaCombatant

	var initial_resource = combatant._current_resource
	var initial_cooldown = combatant.get_cooldown_remaining(&"cast_time_ability")

	# Call cancel with nothing in progress via the Actor dispatch branch -
	# should not error, and must not mutate resource, cooldown, or casting state.
	MobaAbilityCaster.new().cancel(actor)
	MobaAbilityCaster.new().cancel(actor)  # Call again to ensure it's safe

	if combatant.is_casting():
		violations.append("cancel_no_op: should not be casting after a speculative cancel")

	if not is_equal_approx(combatant._current_resource, initial_resource):
		(
			violations
			. append(
				(
					"cancel_no_op: resource should be unchanged by a speculative cancel, expected %f, got %f"
					% [initial_resource, combatant._current_resource]
				)
			)
		)

	if not is_equal_approx(
		combatant.get_cooldown_remaining(&"cast_time_ability"), initial_cooldown
	):
		violations.append("cancel_no_op: cooldown should be unchanged by a speculative cancel")

	# Also test with MobaCastContext - the other dispatch branch
	var context = MobaCastContext.new(actor, null)
	MobaAbilityCaster.new().cancel(context)

	if combatant.is_casting():
		violations.append(
			"cancel_no_op: should not be casting after a speculative cancel via context"
		)

	if not is_equal_approx(combatant._current_resource, initial_resource):
		violations.append(
			"cancel_no_op: resource should be unchanged by a speculative cancel via context"
		)

	if not is_equal_approx(
		combatant.get_cooldown_remaining(&"cast_time_ability"), initial_cooldown
	):
		violations.append(
			"cancel_no_op: cooldown should be unchanged by a speculative cancel via context"
		)

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
	ability.range = 10.0
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	ability.base_damage = 20.0

	combatant.register_ability(ability)
	MobaAbilityLibrary._cache[StringName(ability.id)] = ability

	var initial_resource = combatant._current_resource
	var target = _create_target_with_combatant()

	# Start the cast
	var context = MobaCastContext.new(actor, target)

	var action = MobaAbilityAction.new(actor, &"full_refund_test", context)
	var result = ActionRunner.run(action)
	if not result.success:
		violations.append("full_refund: activation should succeed, got failure: %s" % result.reason)
		return violations

	var resource_after_commit = combatant._current_resource
	if not is_equal_approx(resource_after_commit, initial_resource - 40.0):
		violations.append("full_refund: resource should be spent at commit")

	var cooldown_after_commit = combatant._cooldowns.remaining(&"full_refund_test")
	if cooldown_after_commit <= 0.0:
		violations.append("full_refund: cooldown should be started at commit")

	# Cancel the cast through the public API this task adds, routed via the
	# Actor dispatch branch of MobaAbilityCaster.cancel().
	MobaAbilityCaster.new().cancel(actor)

	var resource_after_cancel = combatant._current_resource
	if not is_equal_approx(resource_after_cancel, initial_resource):
		violations.append(
			(
				"full_refund: resource should be fully refunded after cancel, expected %f, got %f"
				% [initial_resource, resource_after_cancel]
			)
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
	ability.range = 10.0
	ability.refund_resource_on_cancel = 0.5  # Refund 50%
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	ability.base_damage = 20.0

	combatant.register_ability(ability)
	MobaAbilityLibrary._cache[StringName(ability.id)] = ability

	var initial_resource = combatant._current_resource
	var target = _create_target_with_combatant()

	# Start the cast
	var context = MobaCastContext.new(actor, target)

	var action = MobaAbilityAction.new(actor, &"partial_refund_test", context)
	var result = ActionRunner.run(action)
	if not result.success:
		violations.append(
			"partial_refund: activation should succeed, got failure: %s" % result.reason
		)
		return violations

	var resource_after_commit = combatant._current_resource
	var expected_after_commit = initial_resource - 40.0
	if not is_equal_approx(resource_after_commit, expected_after_commit):
		violations.append("partial_refund: resource should be spent at commit")

	# Cancel the cast through the public API this task adds, routed via the
	# MobaCastContext dispatch branch of MobaAbilityCaster.cancel().
	MobaAbilityCaster.new().cancel(context)

	var resource_after_cancel = combatant._current_resource
	var expected_after_cancel = expected_after_commit + (40.0 * 0.5)  # Refund 50%
	if not is_equal_approx(resource_after_cancel, expected_after_cancel):
		violations.append(
			(
				"partial_refund: resource should be partially refunded, expected %f, got %f"
				% [expected_after_cancel, resource_after_cancel]
			)
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
	ability.range = 10.0
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	ability.base_damage = 20.0

	combatant.register_ability(ability)
	MobaAbilityLibrary._cache[StringName(ability.id)] = ability

	var initial_resource = combatant._current_resource
	var target = _create_target_with_combatant()

	# Start the cast
	var context = MobaCastContext.new(actor, target)

	var action = MobaAbilityAction.new(actor, &"no_refund_test", context)
	var result = ActionRunner.run(action)
	if not result.success:
		violations.append("no_refund: activation should succeed, got failure: %s" % result.reason)
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
			(
				"no_refund: resource should not be refunded, expected %f, got %f"
				% [expected_after_commit, resource_after_cancel]
			)
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
	ability.range = 10.0
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	ability.base_damage = 20.0

	combatant.register_ability(ability)
	MobaAbilityLibrary._cache[StringName(ability.id)] = ability

	var initial_resource = combatant._current_resource
	var target = _create_target_with_combatant()

	# Start the cast
	var context = MobaCastContext.new(actor, target)

	var action = MobaAbilityAction.new(actor, &"cooldown_still_applies_test", context)
	var result = ActionRunner.run(action)
	if not result.success:
		violations.append(
			"cooldown_still_applies: activation should succeed, got failure: %s" % result.reason
		)
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
			(
				"cooldown_still_applies: resource should not be refunded, expected %f, got %f"
				% [expected_after_commit, resource_after_cancel]
			)
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
	ability.range = 10.0
	ability.refund_resource_on_cancel = 0.25  # Refund 25%
	ability.cancellable_by_hard_cc = true
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	ability.base_damage = 20.0

	combatant.register_ability(ability)
	MobaAbilityLibrary._cache[StringName(ability.id)] = ability

	var initial_resource = combatant._current_resource
	var target = _create_target_with_combatant()

	# Start the cast
	var context = MobaCastContext.new(actor, target)

	var action = MobaAbilityAction.new(actor, &"cc_cancel_test", context)
	var result = ActionRunner.run(action)
	if not result.success:
		violations.append(
			"hard_cc_cancel: activation should succeed, got failure: %s" % result.reason
		)
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
		(
			violations
			. append(
				(
					"hard_cc_cancel: resource should be partially refunded by CC interrupt, expected %f, got %f"
					% [expected_after_cc, resource_after_cc]
				)
			)
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
	var combatant := test_actor["combatant"] as MobaCombatant
	var target = _create_target_with_combatant()
	var target_combatant = target.get_node("MobaCombatant") as MobaCombatant

	var initial_target_health = target_combatant._current_health

	# Activate cast_time_ability with 0.5s cast time
	var context = MobaCastContext.new(actor, target)

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

	# Now call cancel() after resolution - should be a no-op in BOTH halves of
	# the outcome: no refund, and no change to the cooldown started at commit.
	var resource_before_cancel = combatant._current_resource
	var cooldown_before_cancel = combatant.get_cooldown_remaining(&"cast_time_ability")
	combatant.cancel_cast()
	var resource_after_cancel = combatant._current_resource
	var cooldown_after_cancel = combatant.get_cooldown_remaining(&"cast_time_ability")

	if not is_equal_approx(resource_before_cancel, resource_after_cancel):
		violations.append("resolution_wins_ties: cancel after resolution should not refund")

	# Catches a stray cancel_cooldown() on the already-resolved path.
	if not is_equal_approx(cooldown_before_cancel, cooldown_after_cancel):
		(
			violations
			. append(
				(
					"resolution_wins_ties: cancel after resolution should not touch the cooldown, %f -> %f"
					% [cooldown_before_cancel, cooldown_after_cancel]
				)
			)
		)

	return violations


## Test: a target freed while the cast is in flight makes resolution a safe
## no-op instead of a runtime fault.
##
## The deferred path narrows the stored target only after is_instance_valid(),
## for the same reason the instant path does (see
## ability_activation_test.gd::_test_target_freed_after_commit): passing a
## freed object into a Node-typed parameter faults before any guard can run.
##
## A target that evaporated is not a cancellation, so the resource and cooldown
## committed at activation stay spent.
static func _test_cast_target_freed_before_resolution() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant := test_actor["combatant"] as MobaCombatant
	var target = _create_target_with_combatant()

	var context = MobaCastContext.new(actor, target)
	var result = MobaAbilityCaster.new().activate(&"cast_time_ability", context)
	if not result.success:
		violations.append("cast_target_freed: activation should succeed, got %s" % result.reason)
		return violations

	var resource_after_commit = combatant._current_resource
	var cooldown_after_commit = combatant.get_cooldown_remaining(&"cast_time_ability")

	# The target evaporates mid-cast.
	target.free()

	# Resolution must complete without faulting.
	combatant.tick(0.5)

	if combatant.is_casting():
		violations.append("cast_target_freed: cast should be finished after the resolving tick")

	# tick() also accrues resource regeneration, so the resource legitimately
	# rises a little across the resolving tick. What must not happen is a
	# refund, which would return the whole resource_cost at once.
	var resource_gain: float = combatant._current_resource - resource_after_commit
	var ability := MobaAbilityLibrary.get_ability(&"cast_time_ability")
	if resource_gain >= ability.resource_cost:
		violations.append(
			(
				"cast_target_freed: resource should stay spent, gained %f of a %f cost"
				% [resource_gain, ability.resource_cost]
			)
		)

	# The sharp assertion: cast_time_ability is on_cancel = no_refund, which
	# undoes the cooldown. So a cooldown still running proves the freed target
	# resolved (and safely no-opped) rather than being routed through
	# cancellation, which nothing about a vanished target should trigger.
	var cooldown_after_resolve := combatant.get_cooldown_remaining(&"cast_time_ability")
	if cooldown_after_resolve <= 0.0:
		violations.append(
			"cast_target_freed: cooldown should still be running, not undone as a cancel"
		)
	if cooldown_after_resolve > cooldown_after_commit:
		violations.append("cast_target_freed: cooldown should not be extended by resolution")

	return violations


## Test: a target freed synchronously during commit -- before start_cast() is even
## called -- must not fault the cast_time > 0 path the way it does the instant one.
##
## Mirrors ability_activation_test.gd::_test_target_freed_after_commit's technique:
## commit_activate() emits resource_changed synchronously, and a handler on that
## signal frees the target before execute() reaches start_cast(). Unlike the
## already-freed-before-tick case covered by _test_cast_target_freed_before_resolution
## above, this exercises the commit -> start_cast window itself, where the resolved
## target is still passed to a chain of typed Node parameters
## (MobaCombatant.start_cast -> MobaCastTracker.start -> _CastInProgress._init).
static func _test_cast_target_freed_during_commit() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant := test_actor["combatant"] as MobaCombatant
	var target = _create_target_with_combatant()
	target.global_position = Vector3(1, 0, 0)

	var free_on_commit := func(_current: float, _maximum: float):
		if is_instance_valid(target):
			target.free()

	combatant.resource_changed.connect(free_on_commit)

	var context = MobaCastContext.new(actor, target)
	var result = MobaAbilityCaster.new().activate(&"cast_time_ability", context)

	combatant.resource_changed.disconnect(free_on_commit)

	if result == null:
		violations.append("cast_target_freed_during_commit: execute() should not return null")
		return violations

	if not result.success:
		violations.append(
			(
				"cast_target_freed_during_commit: activation should still report success, got: %s"
				% result.reason
			)
		)

	# The cast must still be registered -- not left stranded in ABILITY_CAST with
	# nothing for tick()/cancel() to find.
	if not combatant.is_casting():
		violations.append(
			"cast_target_freed_during_commit: cast should still be registered after commit"
		)

	# Resolution must complete without faulting when the tick fires.
	combatant.tick(0.5)

	if combatant.is_casting():
		violations.append(
			"cast_target_freed_during_commit: cast should be finished after the resolving tick"
		)

	# Control case: a target that survives the same commit -> resolve path must
	# actually take damage on the resolving tick. Without this, the freed-target
	# assertions above cannot distinguish "resolution no-opped correctly on the
	# freed target" from "resolution silently faulted and returned before doing
	# anything" -- both look identical from the freed-target case alone.
	var control_wrapper = _create_test_actor()
	var control_actor = control_wrapper["actor"]
	var control_combatant := control_wrapper["combatant"] as MobaCombatant
	var control_target = _create_target_with_combatant()
	var control_target_combatant = control_target.get_node("MobaCombatant") as MobaCombatant
	var control_initial_health = control_target_combatant._current_health

	var control_context = MobaCastContext.new(control_actor, control_target)
	var control_result = MobaAbilityCaster.new().activate(&"cast_time_ability", control_context)
	if not control_result.success:
		violations.append(
			(
				"cast_target_freed_during_commit: control activation should succeed, got %s"
				% control_result.reason
			)
		)
		return violations

	control_combatant.tick(0.5)

	if is_equal_approx(control_target_combatant._current_health, control_initial_health):
		violations.append(
			(
				"cast_target_freed_during_commit: control case with a surviving target should"
				+ " take damage on resolution, not silently no-op"
			)
		)

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
