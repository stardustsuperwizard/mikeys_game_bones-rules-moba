## Test suite for cooldown and activation mechanics.
##
## Covers: can_activate() failure reasons, commit_activate() atomicity,
## haste scaling, charge refill timing, and resource spend atomicity.
class_name CooldownTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaLoadout = preload("res://rules/abilities/moba_loadout.gd")


static func _approx_equal(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return abs(a - b) < tolerance


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_insufficient_resource())
	all_violations.append_array(_test_can_activate_side_effect_free())
	all_violations.append_array(_test_cooldown_vs_no_charges())
	all_violations.append_array(_test_commit_activate())
	all_violations.append_array(_test_refused_commit())
	all_violations.append_array(_test_haste_scaling())
	all_violations.append_array(_test_charge_refill_timing())
	all_violations.append_array(_test_no_timer_reset())
	all_violations.append_array(_test_large_cost_refused())
	all_violations.append_array(_test_hud_getters())

	if all_violations.is_empty():
		return true

	printerr("\n=== Cooldown Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


static func _test_insufficient_resource() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = 500.0
	combatant._current_resource = 20.0

	var ability = MobaAbility.new()
	ability.id = "test_ability"
	ability.resource_cost = 30.0
	ability.cooldown = 6.0
	ability.charges = 1

	combatant.register_ability(ability)

	var result = combatant.can_activate(&"test_ability")
	if result != MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE:
		violations.append("insufficient_resource: expected INSUFFICIENT_RESOURCE, got %d" % result)

	if not is_equal_approx(combatant._current_resource, 20.0):
		violations.append(
			(
				"insufficient_resource: resource should still be 20.0, got %f"
				% combatant._current_resource
			)
		)

	if combatant._cooldowns.remaining(&"test_ability") > 0.0:
		violations.append("insufficient_resource: cooldown should not have started")

	return violations


static func _test_can_activate_side_effect_free() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = 500.0
	combatant._current_resource = 100.0

	var ability = MobaAbility.new()
	ability.id = "test_ability"
	ability.resource_cost = 50.0
	ability.cooldown = 6.0
	ability.charges = 1

	combatant.register_ability(ability)

	var initial_resource = combatant._current_resource

	for _i in range(5):
		var result = combatant.can_activate(&"test_ability")
		if result != MobaCombatant.ActivationFailure.OK:
			violations.append("side_effect_free: can_activate should return OK, got %d" % result)

	if not is_equal_approx(combatant._current_resource, initial_resource):
		violations.append(
			(
				"side_effect_free: resource should be %f, got %f"
				% [initial_resource, combatant._current_resource]
			)
		)

	if combatant._cooldowns.remaining(&"test_ability") > 0.0:
		violations.append("side_effect_free: cooldown should not have started")

	return violations


static func _test_cooldown_vs_no_charges() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = 500.0
	combatant._current_resource = 500.0

	var ability = MobaAbility.new()
	ability.id = "test_ability"
	ability.resource_cost = 10.0
	ability.cooldown = 0.5
	ability.charges = 1

	combatant.register_ability(ability)

	# Use the ability (spend charge and start cooldown)
	var commit_result = combatant.commit_activate(&"test_ability")
	if commit_result != MobaCombatant.ActivationFailure.OK:
		violations.append("cooldown_vs_no_charges: commit should succeed, got %d" % commit_result)

	# Now cooldown is running and we have 0 charges - should report NO_CHARGES
	var check_result = combatant.can_activate(&"test_ability")
	if check_result != MobaCombatant.ActivationFailure.NO_CHARGES:
		violations.append(
			(
				"cooldown_vs_no_charges: with no charges, should report NO_CHARGES, got %d"
				% check_result
			)
		)

	return violations


static func _test_commit_activate() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = 500.0
	combatant._current_resource = 250.0
	combatant._runtime_stat_block.ability_haste = 0

	var ability = MobaAbility.new()
	ability.id = "test_ability"
	ability.resource_cost = 30.0
	ability.cooldown = 6.0
	ability.charges = 1

	combatant.register_ability(ability)

	var result = combatant.commit_activate(&"test_ability")
	if result != MobaCombatant.ActivationFailure.OK:
		violations.append("commit_activate: commit should succeed, got %d" % result)

	if not is_equal_approx(combatant._current_resource, 220.0):
		violations.append(
			"commit_activate: resource should be 220.0, got %f" % combatant._current_resource
		)

	var remaining = combatant._cooldowns.remaining(&"test_ability")
	if not _approx_equal(remaining, 6.0, 0.0001):
		violations.append("commit_activate: cooldown should be 6.0, got %f" % remaining)

	return violations


static func _test_refused_commit() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = 500.0
	combatant._current_resource = 20.0

	var ability = MobaAbility.new()
	ability.id = "test_ability"
	ability.resource_cost = 30.0
	ability.cooldown = 6.0
	ability.charges = 1

	combatant.register_ability(ability)

	var initial_resource = combatant._current_resource

	var result = combatant.commit_activate(&"test_ability")
	if result != MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE:
		violations.append("refused_commit: expected INSUFFICIENT_RESOURCE, got %d" % result)

	if not is_equal_approx(combatant._current_resource, initial_resource):
		violations.append(
			(
				"refused_commit: resource should be %f, got %f"
				% [initial_resource, combatant._current_resource]
			)
		)

	if combatant._cooldowns.remaining(&"test_ability") > 0.0:
		violations.append("refused_commit: cooldown should not have started")

	return violations


static func _test_haste_scaling() -> Array[String]:
	var violations: Array[String] = []

	var combatant0 = MobaCombatant.new()
	combatant0._runtime_stat_block = combatant0.stat_block.duplicate()
	combatant0._current_health = 500.0
	combatant0._current_resource = 500.0
	combatant0._runtime_stat_block.ability_haste = 0

	var ability0 = MobaAbility.new()
	ability0.id = "test_ability"
	ability0.resource_cost = 10.0
	ability0.cooldown = 10.0
	ability0.charges = 1

	combatant0.register_ability(ability0)
	combatant0.commit_activate(&"test_ability")

	var cooldown0 = combatant0._cooldowns.remaining(&"test_ability")
	if not _approx_equal(cooldown0, 10.0, 0.0001):
		violations.append("haste_scaling: at 0 haste, cooldown should be 10.0, got %f" % cooldown0)

	var combatant50 = MobaCombatant.new()
	combatant50._runtime_stat_block = combatant50.stat_block.duplicate()
	combatant50._current_health = 500.0
	combatant50._current_resource = 500.0
	combatant50._runtime_stat_block.ability_haste = 50

	var ability50 = MobaAbility.new()
	ability50.id = "test_ability"
	ability50.resource_cost = 10.0
	ability50.cooldown = 10.0
	ability50.charges = 1

	combatant50.register_ability(ability50)
	combatant50.commit_activate(&"test_ability")

	var cooldown50 = combatant50._cooldowns.remaining(&"test_ability")
	var expected50 = 10.0 * 100.0 / 150.0
	if not _approx_equal(cooldown50, expected50, 0.0001):
		violations.append(
			"haste_scaling: at 50 haste, cooldown should be %f, got %f" % [expected50, cooldown50]
		)

	var combatant100 = MobaCombatant.new()
	combatant100._runtime_stat_block = combatant100.stat_block.duplicate()
	combatant100._current_health = 500.0
	combatant100._current_resource = 500.0
	combatant100._runtime_stat_block.ability_haste = 100

	var ability100 = MobaAbility.new()
	ability100.id = "test_ability"
	ability100.resource_cost = 10.0
	ability100.cooldown = 10.0
	ability100.charges = 1

	combatant100.register_ability(ability100)
	combatant100.commit_activate(&"test_ability")

	var cooldown100 = combatant100._cooldowns.remaining(&"test_ability")
	if not _approx_equal(cooldown100, 5.0, 0.0001):
		violations.append(
			"haste_scaling: at 100 haste, cooldown should be 5.0, got %f" % cooldown100
		)

	return violations


static func _test_charge_refill_timing() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = 500.0
	combatant._current_resource = 500.0

	var ability = MobaAbility.new()
	ability.id = "test_ability"
	ability.resource_cost = 10.0
	ability.cooldown = 1.0
	ability.charges = 2

	combatant.register_ability(ability)

	combatant.commit_activate(&"test_ability")

	var charges_after_first = combatant._cooldowns.charges(&"test_ability")
	if charges_after_first != 1:
		violations.append(
			(
				"charge_refill_timing: after first use, charges should be 1, got %d"
				% charges_after_first
			)
		)

	combatant.tick(1.1)

	var charges_after_refill = combatant._cooldowns.charges(&"test_ability")
	if charges_after_refill != 2:
		violations.append(
			"charge_refill_timing: after refill, charges should be 2, got %d" % charges_after_refill
		)

	var remaining_after_refill = combatant._cooldowns.remaining(&"test_ability")
	if remaining_after_refill > 0.0:
		violations.append(
			"charge_refill_timing: cooldown should be 0, got %f" % remaining_after_refill
		)

	return violations


static func _test_no_timer_reset() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = 500.0
	combatant._current_resource = 500.0

	var ability = MobaAbility.new()
	ability.id = "test_ability"
	ability.resource_cost = 10.0
	ability.cooldown = 2.0
	ability.charges = 2

	combatant.register_ability(ability)

	combatant.commit_activate(&"test_ability")

	combatant.tick(0.5)

	var remaining_at_05 = combatant._cooldowns.remaining(&"test_ability")

	var second_commit_result = combatant.commit_activate(&"test_ability")

	var remaining_after_second = combatant._cooldowns.remaining(&"test_ability")
	var charges_after_second = combatant._cooldowns.charges(&"test_ability")

	if second_commit_result != MobaCombatant.ActivationFailure.OK:
		violations.append(
			"no_timer_reset: second commit should succeed, got %d" % second_commit_result
		)

	if not _approx_equal(remaining_after_second, remaining_at_05, 0.01):
		violations.append(
			(
				"no_timer_reset: timer was reset (expected ~%f, got %f)"
				% [remaining_at_05, remaining_after_second]
			)
		)

	if charges_after_second != 0:
		violations.append(
			"no_timer_reset: charges should be 0 after second use, got %d" % charges_after_second
		)

	return violations


static func _test_large_cost_refused() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = 500.0
	combatant._current_resource = 100.0

	var ability = MobaAbility.new()
	ability.id = "test_ability"
	ability.resource_cost = 150.0
	ability.cooldown = 6.0
	ability.charges = 1

	combatant.register_ability(ability)

	var initial_resource = combatant._current_resource

	var result = combatant.can_activate(&"test_ability")
	if result != MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE:
		violations.append(
			"large_cost_refused: can_activate should return INSUFFICIENT_RESOURCE, got %d" % result
		)

	var commit_result = combatant.commit_activate(&"test_ability")
	if commit_result != MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE:
		violations.append(
			(
				"large_cost_refused: commit_activate should return INSUFFICIENT_RESOURCE, got %d"
				% commit_result
			)
		)

	if not is_equal_approx(combatant._current_resource, initial_resource):
		violations.append(
			(
				"large_cost_refused: resource should be %f, got %f"
				% [initial_resource, combatant._current_resource]
			)
		)

	if combatant._cooldowns.remaining(&"test_ability") > 0.0:
		violations.append("large_cost_refused: cooldown should not have started")

	return violations


static func _test_hud_getters() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = 500.0
	combatant._current_resource = 500.0
	combatant._runtime_stat_block.ability_haste = 0

	var ability = MobaAbility.new()
	ability.id = "test_ability"
	ability.resource_cost = 10.0
	ability.cooldown = 4.0
	ability.charges = 2

	combatant.register_ability(ability)

	# Unknown ability id: every getter must answer safely and mutate nothing.
	if not is_equal_approx(combatant.get_cooldown_remaining(&"nope"), 0.0):
		violations.append("hud_getters: unknown id remaining should be 0.0")
	if not is_equal_approx(combatant.get_cooldown_duration(&"nope"), 0.0):
		violations.append("hud_getters: unknown id duration should be 0.0")
	if combatant.get_charges(&"nope") != 0:
		violations.append("hud_getters: unknown id charges should be 0")
	if combatant.get_max_charges(&"nope") != 0:
		violations.append("hud_getters: unknown id max charges should be 0")
	if combatant.get_ability(&"nope") != null:
		violations.append("hud_getters: unknown id ability should be null")
	if not is_equal_approx(combatant._current_resource, 500.0):
		violations.append("hud_getters: unknown id getters must not spend resource")

	# Registered but never started.
	if not is_equal_approx(combatant.get_cooldown_remaining(&"test_ability"), 0.0):
		violations.append("hud_getters: unstarted remaining should be 0.0")
	if not is_equal_approx(combatant.get_cooldown_duration(&"test_ability"), 0.0):
		violations.append("hud_getters: unstarted duration should be 0.0")
	if combatant.get_ability(&"test_ability") != ability:
		violations.append("hud_getters: get_ability should return the registered ability")

	combatant.commit_activate(&"test_ability")

	var ledger_remaining = combatant._cooldowns.remaining(&"test_ability")
	if not _approx_equal(combatant.get_cooldown_remaining(&"test_ability"), ledger_remaining):
		violations.append("hud_getters: remaining should match the ledger")
	if not _approx_equal(combatant.get_cooldown_duration(&"test_ability"), 4.0):
		violations.append(
			(
				"hud_getters: duration should be 4.0, got %f"
				% combatant.get_cooldown_duration(&"test_ability")
			)
		)
	if combatant.get_charges(&"test_ability") != 1:
		violations.append("hud_getters: charges should be 1 after one use")
	if combatant.get_max_charges(&"test_ability") != 2:
		violations.append("hud_getters: max charges should be 2")

	# Remaining stays a pure read: repeated calls must not advance the timer.
	var repeated = combatant.get_cooldown_remaining(&"test_ability")
	for _i in range(5):
		if not _approx_equal(combatant.get_cooldown_remaining(&"test_ability"), repeated):
			violations.append("hud_getters: get_cooldown_remaining mutated the timer")

	# Passive slot.
	if combatant.get_passive_slot_id() != &"":
		violations.append("hud_getters: no loadout should yield empty passive id")

	var loadout = MobaLoadout.new()
	combatant.loadout = loadout
	if combatant.get_passive_slot_id() != &"":
		violations.append("hud_getters: empty passive slot should yield empty passive id")

	loadout.set_passive_slot("test_passive")
	if combatant.get_passive_slot_id() != &"test_passive":
		violations.append(
			(
				"hud_getters: passive id should be test_passive, got %s"
				% combatant.get_passive_slot_id()
			)
		)

	return violations
