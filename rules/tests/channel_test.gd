## Test suite for channeled abilities.
##
## Covers: tick cadence and repeat application, channel break on resource
## exhaustion, break via cancel, break via hard crowd control, and both
## on_channel_break economic outcomes.
##
## Split out of cast_cancel_test.gd when that file passed the gdlint
## max-file-lines cap. The fixture and actor helpers below are copied from it
## verbatim rather than shared, matching how crowd_control_test.gd and
## crowd_control_displacement_test.gd each carry their own.
class_name ChannelTest

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
	"suppressing_fire.tres",
]

const _ALL_ABILITY_IDS: Array[StringName] = [
	&"cast_time_ability",
	&"self_ability",
	&"suppressing_fire",
	&"cataclysm",
	&"power_strike",
]


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_channel_ticks_apply_damage())
	all_violations.append_array(_test_channel_breaks_when_resource_exhausted())
	all_violations.append_array(_test_channel_break_via_cancel())
	all_violations.append_array(_test_hard_cc_breaks_channel())
	all_violations.append_array(_test_on_channel_break_no_effect_remaining())
	all_violations.append_array(_test_on_channel_break_partial_effect_already_applied())
	all_violations.append_array(_test_suppressing_fire_ability_data())
	all_violations.append_array(_test_channel_time_getters())

	# Several cases above inject synthetic abilities into the shared library
	# cache. Reset once here so none of them reach the suites that run after
	# this one, matching how ability_activation_test.gd leaves the library.
	MobaAbilityLibrary._reset()

	if all_violations.is_empty():
		return true

	printerr("\n=== Channel Test Violations ===")
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


## Test: Channel ticks apply damage repeatedly at the declared interval
static func _test_channel_ticks_apply_damage() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]
	var state_machine = test_actor["state_machine"]
	var target = _create_target_with_combatant()
	var target_combatant = target.get_node("MobaCombatant") as MobaCombatant

	var initial_target_health = target_combatant._current_health

	# Activate suppressing_fire (channel_duration = 2.5s, tick_interval = 0.25s, damage = 20.0)
	var context = MobaCastContext.new(actor, target)

	var result = MobaAbilityCaster.new().activate(&"suppressing_fire", context)
	if not result.success:
		violations.append("channel_ticks: activation should succeed, got %s" % result.reason)
		return violations

	# Should be in ABILITY_CHANNEL state
	if state_machine.current_state != MobaState.ABILITY_CHANNEL:
		violations.append("channel_ticks: should be in ABILITY_CHANNEL state")

	# First tick should have already applied immediately (t = 0)
	var health_after_first_tick = target_combatant._current_health
	if is_equal_approx(health_after_first_tick, initial_target_health):
		violations.append("channel_ticks: first tick should apply immediately")

	# After 0.25 seconds, second tick should apply
	combatant.tick(0.25)
	var health_after_second_tick = target_combatant._current_health
	if not (health_after_second_tick < health_after_first_tick):
		violations.append("channel_ticks: second tick should apply after 0.25s")

	# After 0.5 more seconds (total 0.75s), third tick should have applied
	combatant.tick(0.5)
	var health_after_third_tick = target_combatant._current_health
	if not (health_after_third_tick < health_after_second_tick):
		violations.append("channel_ticks: third tick should apply")

	return violations


## Test: a channel that runs out of per-tick resource mid-tick breaks safely.
## Regression for a crash where a second tick due in the same tick(delta) call
## dereferenced the tracker after the first had already broken the channel.
static func _test_channel_breaks_when_resource_exhausted() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]
	var target = _create_target_with_combatant()

	# Enough for the tick at activation (10) plus one more (10), but not a
	# third: tick(0.5) below must break the channel mid-loop, on a tick it can
	# no longer afford, rather than fault on the one scheduled after it.
	combatant._current_resource = 25.0
	var context = MobaCastContext.new(actor, target)

	var result = MobaAbilityCaster.new().activate(&"suppressing_fire", context)
	if not result.success:
		violations.append("channel_resource_exhausted: activation should succeed")
		return violations

	combatant.tick(0.5)

	if combatant.is_channeling():
		violations.append("channel_resource_exhausted: channel should break when resource runs out")

	if combatant._current_resource < 0.0:
		violations.append("channel_resource_exhausted: resource should never go negative")

	return violations


## Test: Breaking a channel via cancel() does not refund resource and leaves cooldown running
static func _test_channel_break_via_cancel() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]
	var target = _create_target_with_combatant()

	var initial_resource = combatant._current_resource
	var context = MobaCastContext.new(actor, target)

	var result = MobaAbilityCaster.new().activate(&"suppressing_fire", context)
	if not result.success:
		violations.append("channel_break_cancel: activation should succeed")
		return violations

	var resource_after_commit = combatant._current_resource
	var expected_after_commit = initial_resource - 10.0  # First tick costs resource
	if not is_equal_approx(resource_after_commit, expected_after_commit):
		violations.append(
			(
				"channel_break_cancel: resource should be spent for first tick, expected %f, got %f"
				% [expected_after_commit, resource_after_commit]
			)
		)

	var cooldown_after_commit = combatant._cooldowns.remaining(&"suppressing_fire")
	if cooldown_after_commit <= 0.0:
		violations.append("channel_break_cancel: cooldown should be started at commit")

	# Break the channel
	MobaAbilityCaster.new().cancel(actor)

	var resource_after_break = combatant._current_resource
	if not is_equal_approx(resource_after_break, resource_after_commit):
		(
			violations
			. append(
				(
					"channel_break_cancel: resource should not be refunded on channel break, expected %f, got %f"
					% [resource_after_commit, resource_after_break]
				)
			)
		)

	var cooldown_after_break = combatant._cooldowns.remaining(&"suppressing_fire")
	if not is_equal_approx(cooldown_after_break, cooldown_after_commit):
		violations.append(
			"channel_break_cancel: cooldown should stay running (not undone) on channel break"
		)

	return violations


## Test: Hard CC landing during ABILITY_CHANNEL breaks the channel
static func _test_hard_cc_breaks_channel() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]
	var target = _create_target_with_combatant()

	var initial_resource = combatant._current_resource
	var context = MobaCastContext.new(actor, target)

	var result = MobaAbilityCaster.new().activate(&"suppressing_fire", context)
	if not result.success:
		violations.append("hard_cc_break_channel: activation should succeed")
		return violations

	var resource_after_commit = combatant._current_resource
	var cooldown_after_commit = combatant._cooldowns.remaining(&"suppressing_fire")

	# Create and apply a hard CC that interrupts the channel
	var cc_spec = MobaCrowdControlSpec.new()
	cc_spec.type = MobaCrowdControlSpec.CCType.STUN
	cc_spec.duration = 2.0
	cc_spec.magnitude = 1.0
	cc_spec.affected_by_tenacity = false

	var cc_source = MobaCombatant.new()
	cc_source._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()

	combatant.apply_crowd_control(cc_spec, cc_source)

	# Channel should be broken, resource not refunded, cooldown still running
	var resource_after_cc = combatant._current_resource
	if not is_equal_approx(resource_after_cc, resource_after_commit):
		violations.append(
			"hard_cc_break_channel: resource should stay spent (not refunded) by CC interrupt"
		)

	var cooldown_after_cc = combatant._cooldowns.remaining(&"suppressing_fire")
	if not is_equal_approx(cooldown_after_cc, cooldown_after_commit):
		violations.append(
			"hard_cc_break_channel: cooldown should still be running after CC interrupt"
		)

	if combatant.is_channeling():
		violations.append("hard_cc_break_channel: channel should be broken by CC interrupt")

	return violations


## Test: on_channel_break = NO_EFFECT_REMAINING removes debuffs
static func _test_on_channel_break_no_effect_remaining() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]
	var target = _create_target_with_combatant()
	var target_combatant = target.get_node("MobaCombatant") as MobaCombatant

	var context = MobaCastContext.new(actor, target)

	# suppressing_fire has on_channel_break = NO_EFFECT_REMAINING
	var result = MobaAbilityCaster.new().activate(&"suppressing_fire", context)
	if not result.success:
		violations.append("on_channel_break_no_effect: activation should succeed")
		return violations

	# Tick to apply the first debuff
	combatant.tick(0.0)

	# Check that debuff was applied to target
	var target_container := target_combatant.get_effect_container()
	if not target_container.has_modifier(&"suppressing_fire", &"movement_speed"):
		violations.append("on_channel_break_no_effect: debuff should be applied")

	# Break the channel (which should remove the debuff since on_channel_break = NO_EFFECT_REMAINING)
	MobaAbilityCaster.new().cancel(actor)

	if target_container.has_modifier(&"suppressing_fire", &"movement_speed"):
		violations.append("on_channel_break_no_effect: debuff should be removed on channel break")

	return violations


## Test: on_channel_break = PARTIAL_EFFECT_ALREADY_APPLIED leaves debuffs running
static func _test_on_channel_break_partial_effect_already_applied() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]

	# Create an ability with on_channel_break = PARTIAL_EFFECT_ALREADY_APPLIED
	var ability = MobaAbility.new()
	ability.id = "partial_effect_channel_test"
	ability.resource_cost = 10.0
	ability.cooldown = 5.0
	ability.channel_duration = 2.5
	ability.channel_tick_interval = 0.25
	ability.charges = 1
	ability.range = 10.0
	ability.targeting_type = MobaAbility.TargetingType.CHANNELED
	ability.base_damage = 20.0
	ability.on_channel_break = MobaAbility.OnChannelBreak.PARTIAL_EFFECT_ALREADY_APPLIED
	ability.cancellable_by_hard_cc = true

	# Add a debuff
	var slow_modifier = MobaStatModifier.new()
	slow_modifier.stat = "movement_speed"
	slow_modifier.amount = -0.3
	slow_modifier.is_percentage = true
	slow_modifier.duration = 2.0
	var debuff_list: Array[MobaStatModifier] = [slow_modifier]
	ability.debuffs = debuff_list

	combatant.register_ability(ability)
	MobaAbilityLibrary._cache[StringName(ability.id)] = ability

	var target = _create_target_with_combatant()
	var target_combatant = target.get_node("MobaCombatant") as MobaCombatant

	var context = MobaCastContext.new(actor, target)

	var result = MobaAbilityAction.new(actor, &"partial_effect_channel_test", context)
	var action_result = ActionRunner.run(result)
	if not action_result.success:
		violations.append("partial_effect: activation should succeed")
		return violations

	# Tick to apply the first debuff
	combatant.tick(0.0)

	# Check that debuff was applied
	var target_container := target_combatant.get_effect_container()
	if not target_container.has_modifier(&"partial_effect_channel_test", &"movement_speed"):
		violations.append("partial_effect: debuff should be applied")

	# Break the channel (should leave the debuff: on_channel_break = PARTIAL_EFFECT_ALREADY_APPLIED)
	combatant.break_channel()

	if not target_container.has_modifier(&"partial_effect_channel_test", &"movement_speed"):
		violations.append("partial_effect: debuff should remain on channel break")

	return violations


## Test: Suppressing Fire.tres exists and has correct values
static func _test_suppressing_fire_ability_data() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var suppressing_fire = MobaAbilityLibrary.get_ability(&"suppressing_fire")

	if suppressing_fire == null:
		violations.append("suppressing_fire_data: ability should exist")
		return violations

	if suppressing_fire.id != "suppressing_fire":
		violations.append("suppressing_fire_data: id should be 'suppressing_fire'")
	if suppressing_fire.targeting_type != MobaAbility.TargetingType.CHANNELED:
		violations.append("suppressing_fire_data: targeting_type should be CHANNELED")
	if suppressing_fire.damage_type != MobaAbility.DamageType.PHYSICAL:
		violations.append("suppressing_fire_data: damage_type should be PHYSICAL")
	if not is_equal_approx(suppressing_fire.base_damage, 20.0):
		violations.append("suppressing_fire_data: base_damage should be 20.0")
	if not is_equal_approx(suppressing_fire.resource_cost, 10.0):
		violations.append("suppressing_fire_data: resource_cost should be 10.0 per tick")
	if not is_equal_approx(suppressing_fire.cooldown, 12.0):
		violations.append("suppressing_fire_data: cooldown should be 12.0")
	if not is_equal_approx(suppressing_fire.channel_duration, 2.5):
		violations.append("suppressing_fire_data: channel_duration should be 2.5")
	if not is_equal_approx(suppressing_fire.channel_tick_interval, 0.25):
		violations.append("suppressing_fire_data: channel_tick_interval should be 0.25")
	if suppressing_fire.debuffs.size() == 0:
		violations.append("suppressing_fire_data: should have at least one debuff")

	return violations


## Test: Channel time remaining getters report correct values.
static func _test_channel_time_getters() -> Array[String]:
	var violations: Array[String] = []

	_ensure_all_test_abilities_loaded()
	var test_actor = _create_test_actor()
	var actor = test_actor["actor"]
	var combatant = test_actor["combatant"]
	var target = _create_target_with_combatant()

	# Before any channel, getters should return null/0.0
	if combatant.get_channeling_ability() != null:
		violations.append(
			"channel_time_getters: get_channeling_ability() should return null when not channeling"
		)

	if not is_equal_approx(combatant.get_channel_time_remaining(), 0.0):
		(
			violations
			. append(
				"channel_time_getters: get_channel_time_remaining() should return 0.0 when not channeling"
			)
		)

	# Start a channel (suppressing_fire has channel_duration = 2.5)
	var context = MobaCastContext.new(actor, target)
	var result = MobaAbilityCaster.new().activate(&"suppressing_fire", context)
	if not result.success:
		violations.append("channel_time_getters: activation should succeed, got %s" % result.reason)
		return violations

	# Immediately after activation, should have the ability
	var channeling_ability = combatant.get_channeling_ability()
	if channeling_ability == null:
		violations.append(
			"channel_time_getters: get_channeling_ability() should return ability while channeling"
		)
		return violations

	if channeling_ability.id != "suppressing_fire":
		violations.append(
			"channel_time_getters: get_channeling_ability() should return the correct ability"
		)

	# Check remaining time at activation (should be close to 2.5)
	var remaining_at_start = combatant.get_channel_time_remaining()
	if not is_equal_approx(remaining_at_start, 2.5):
		(
			violations
			. append(
				(
					"channel_time_getters: get_channel_time_remaining() should be close to 2.5 at start, got %f"
					% remaining_at_start
				)
			)
		)

	# Advance time by 1.5 seconds
	combatant.tick(1.5)

	# Remaining time should be around 1.0
	var remaining_after_tick = combatant.get_channel_time_remaining()
	if remaining_after_tick >= remaining_at_start:
		(
			violations
			. append(
				(
					"channel_time_getters: after partial tick, remaining should be less than original, got %f"
					% remaining_after_tick
				)
			)
		)

	# Advance to completion
	combatant.tick(1.5)

	# After completion, getters should reset
	if combatant.get_channeling_ability() != null:
		(
			violations
			. append(
				"channel_time_getters: get_channeling_ability() should return null after channel completes"
			)
		)

	if not is_equal_approx(combatant.get_channel_time_remaining(), 0.0):
		(
			violations
			. append(
				"channel_time_getters: get_channel_time_remaining() should return 0.0 after channel completes"
			)
		)

	return violations
