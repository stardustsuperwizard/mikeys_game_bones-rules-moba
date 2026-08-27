## Test suite for shield pool and damage pipeline integration.
##
## Covers: shield pool creation, total_shield calculation, apply_shield,
## shield consumption in damage pipeline (shortest-remaining-duration first),
## shield expiry through tick(), signal emission, and multi-shield scenarios.
## Also covers Force Barrier and Field Dressing ability integration through
## the MobaAbilityAction pipeline.
class_name SustainTest

const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaAbilityAction = preload("res://rules/abilities/moba_ability_action.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaDamage = preload("res://rules/core/moba_damage.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")


## Helper function to compare floats with tolerance
static func _approx_equal(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return abs(a - b) < tolerance


## Build a standalone combatant fixture that never enters the scene tree.
static func _make_combatant() -> MobaCombatant:
	var combatant := MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	# Crit is rolled before damage-type routing, so a stray crit would double the
	# damage dealt -- and therefore the sustain payout -- on any of these cases.
	# Disable it for predictable tests, as combatant_test.gd does.
	combatant._runtime_stat_block.crit_chance = 0.0
	return combatant


## Run the sustain test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_shield_creation())
	all_violations.append_array(_test_total_shield())
	all_violations.append_array(_test_shield_application())
	all_violations.append_array(_test_shield_changed_signal())
	all_violations.append_array(_test_shield_consumption_happy_path())
	all_violations.append_array(_test_shield_consumption_two_shields())
	all_violations.append_array(_test_shield_expiry())
	all_violations.append_array(_test_shield_no_op_on_zero_amount())
	all_violations.append_array(_test_sustain_healing_formula())
	all_violations.append_array(_test_clamped_heal_formula())
	all_violations.append_array(_test_lifesteal_on_basic_attack())
	all_violations.append_array(_test_lifesteal_not_on_ability())
	all_violations.append_array(_test_omnivamp_on_basic_attack())
	all_violations.append_array(_test_omnivamp_on_ability())
	all_violations.append_array(_test_lifesteal_and_omnivamp_sum())
	all_violations.append_array(_test_lifesteal_on_damage_dealt())
	all_violations.append_array(_test_overkill_boundary())
	all_violations.append_array(_test_apply_healing_returns_amount())
	all_violations.append_array(_test_apply_healing_on_dead_combatant())
	all_violations.append_array(_test_healing_applied_signal())
	all_violations.append_array(_test_force_barrier_shield_application())
	all_violations.append_array(_test_field_dressing_healing_application())

	if all_violations.is_empty():
		return true

	# Print violations
	printerr("\n=== Sustain Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Test: Shield can be created with amount, source, and remaining duration
static func _test_shield_creation() -> Array[String]:
	var violations: Array[String] = []

	var shield := MobaShield.new(100.0, &"test_source", 5.0)
	if not _approx_equal(shield.amount, 100.0):
		violations.append("shield_creation: expected amount 100.0, got %f" % shield.amount)
	if shield.source != &"test_source":
		violations.append(
			"shield_creation: expected source 'test_source', got '%s'" % shield.source
		)
	if not _approx_equal(shield.remaining, 5.0):
		violations.append("shield_creation: expected remaining 5.0, got %f" % shield.remaining)

	return violations


## Test: total_shield() returns the sum of all active shields
static func _test_total_shield() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()

	# Empty shield pool
	if not _approx_equal(combatant.total_shield(), 0.0):
		violations.append(
			"total_shield: expected 0.0 with no shields, got %f" % combatant.total_shield()
		)

	# One shield
	combatant.apply_shield(100.0, &"source1", 5.0)
	if not _approx_equal(combatant.total_shield(), 100.0):
		violations.append(
			"total_shield: expected 100.0 with one shield, got %f" % combatant.total_shield()
		)

	# Two shields
	combatant.apply_shield(50.0, &"source2", 3.0)
	if not _approx_equal(combatant.total_shield(), 150.0):
		violations.append(
			"total_shield: expected 150.0 with two shields, got %f" % combatant.total_shield()
		)

	return violations


## Test: apply_shield adds a new shield to the pool
static func _test_shield_application() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()

	combatant.apply_shield(75.0, &"shield_source", 10.0)

	if combatant.get_active_shields().size() != 1:
		violations.append(
			(
				"shield_application: expected 1 active shield, got %d"
				% combatant.get_active_shields().size()
			)
		)

	var shield = combatant.get_active_shields()[0] as MobaShield
	if not _approx_equal(shield.amount, 75.0):
		violations.append("shield_application: expected shield amount 75.0, got %f" % shield.amount)
	if shield.source != &"shield_source":
		violations.append(
			"shield_application: expected source 'shield_source', got '%s'" % shield.source
		)
	if not _approx_equal(shield.remaining, 10.0):
		violations.append("shield_application: expected remaining 10.0, got %f" % shield.remaining)

	return violations


## Test: shield_changed signal is emitted when shields are applied
static func _test_shield_changed_signal() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	# GDScript lambdas capture local variables by value, so plain int/float
	# locals mutated inside the lambda would not be visible outside it. A
	# Dictionary is a reference type, so mutating its entries from the lambda
	# is visible to this function after the signal fires.
	var signal_log := {"count": 0, "total": 0.0}

	combatant.shield_changed.connect(
		func(total: float):
			signal_log["count"] += 1
			signal_log["total"] = total
	)

	combatant.apply_shield(50.0, &"test", 5.0)

	if signal_log["count"] != 1:
		violations.append(
			"shield_changed_signal: expected 1 signal emission, got %d" % signal_log["count"]
		)

	if not _approx_equal(signal_log["total"], 50.0):
		violations.append(
			"shield_changed_signal: expected signal total 50.0, got %f" % signal_log["total"]
		)

	combatant.apply_shield(30.0, &"test", 5.0)

	if signal_log["count"] != 2:
		violations.append(
			(
				"shield_changed_signal: expected 2 signal emissions after second apply, got %d"
				% signal_log["count"]
			)
		)

	if not _approx_equal(signal_log["total"], 80.0):
		violations.append(
			(
				"shield_changed_signal: expected signal total 80.0 after second apply, got %f"
				% signal_log["total"]
			)
		)

	return violations


## Test: Happy path - 500 health + 100 shield, 130 damage leaves 470 health, consumed shield
static func _test_shield_consumption_happy_path() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	# See _test_shield_changed_signal() for why signal counters are boxed in
	# a Dictionary rather than plain locals.
	var signal_log := {"shield": 0, "health": 0}

	combatant.shield_changed.connect(func(_total): signal_log["shield"] += 1)
	combatant.health_changed.connect(func(_current, _max): signal_log["health"] += 1)

	# Setup: 500 health, 100 shield
	if not _approx_equal(combatant.current_health, 500.0):
		violations.append(
			"happy_path: initial health should be 500.0, got %f" % combatant.current_health
		)

	combatant.apply_shield(100.0, &"test_shield", 10.0)

	if not _approx_equal(combatant.total_shield(), 100.0):
		violations.append(
			"happy_path: total shield should be 100.0, got %f" % combatant.total_shield()
		)

	# Clear signals from apply_shield
	signal_log["shield"] = 0
	signal_log["health"] = 0

	# Apply 130 damage
	var damage := MobaDamage.new(130.0, MobaDamage.DamageType.TRUE)
	combatant.apply_damage(damage)

	# Verify results
	if not _approx_equal(combatant.current_health, 470.0):
		violations.append(
			(
				"happy_path: health should be 470.0 after 130 damage on 100 shield, got %f"
				% combatant.current_health
			)
		)

	if not _approx_equal(combatant.total_shield(), 0.0):
		violations.append(
			"happy_path: shield should be 0.0 (consumed), got %f" % combatant.total_shield()
		)

	if signal_log["shield"] == 0:
		violations.append("happy_path: shield_changed should have fired during damage")

	if signal_log["health"] == 0:
		violations.append("happy_path: health_changed should have fired during damage")

	return violations


## Test: Two shields boundary - 50-shield (1s) and 100-shield (5s), 60 damage
## Shortest duration (1s shield) is consumed first, then 10 damage taken from 5s shield
static func _test_shield_consumption_two_shields() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()

	# Setup: two shields with different durations
	combatant.apply_shield(50.0, &"short_shield", 1.0)
	combatant.apply_shield(100.0, &"long_shield", 5.0)

	if not _approx_equal(combatant.total_shield(), 150.0):
		violations.append("two_shields: total should be 150.0, got %f" % combatant.total_shield())

	# Apply 60 damage
	var damage := MobaDamage.new(60.0, MobaDamage.DamageType.TRUE)
	combatant.apply_damage(damage)

	# Verify: 1s shield fully consumed, 5s shield reduced by 10
	if combatant.get_active_shields().size() != 1:
		violations.append(
			(
				"two_shields: expected 1 shield remaining, got %d"
				% combatant.get_active_shields().size()
			)
		)

	if not _approx_equal(combatant.total_shield(), 90.0):
		violations.append("two_shields: total should be 90.0, got %f" % combatant.total_shield())

	# Verify the remaining shield is the 5s one
	var remaining = combatant.get_active_shields()[0] as MobaShield
	if not _approx_equal(remaining.amount, 90.0):
		violations.append(
			"two_shields: remaining shield amount should be 90.0, got %f" % remaining.amount
		)

	if not _approx_equal(remaining.remaining, 5.0):
		violations.append(
			(
				"two_shields: remaining shield duration should still be 5.0, got %f"
				% remaining.remaining
			)
		)

	# Verify health is untouched
	if not _approx_equal(combatant.current_health, 500.0):
		violations.append(
			"two_shields: health should be untouched at 500.0, got %f" % combatant.current_health
		)

	return violations


## Test: Shields expire via tick() and stop absorbing on next apply_damage
static func _test_shield_expiry() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	# See _test_shield_changed_signal() for why signal counters are boxed in
	# a Dictionary rather than plain locals.
	var signal_log := {"count": 0}

	combatant.shield_changed.connect(func(_total): signal_log["count"] += 1)

	# Setup: shield with 1.0 second duration
	combatant.apply_shield(100.0, &"test", 1.0)
	signal_log["count"] = 0  # Reset after apply

	# Tick for 1.5 seconds - shield should expire
	combatant.tick(1.5)

	if not _approx_equal(combatant.total_shield(), 0.0):
		violations.append(
			(
				"shield_expiry: shield should be expired after tick(1.5), got %f"
				% combatant.total_shield()
			)
		)

	if signal_log["count"] == 0:
		violations.append("shield_expiry: shield_changed should have fired during expiry")

	# Apply damage - should reduce health entirely
	signal_log["count"] = 0
	var damage := MobaDamage.new(50.0, MobaDamage.DamageType.TRUE)
	combatant.apply_damage(damage)

	if not _approx_equal(combatant.current_health, 450.0):
		violations.append(
			(
				"shield_expiry: health should be 450.0 after expired shield + 50 damage, got %f"
				% combatant.current_health
			)
		)

	return violations


## Test: apply_shield is a no-op when amount <= 0.0
static func _test_shield_no_op_on_zero_amount() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	# See _test_shield_changed_signal() for why signal counters are boxed in
	# a Dictionary rather than plain locals.
	var signal_log := {"count": 0}

	combatant.shield_changed.connect(func(_total): signal_log["count"] += 1)

	# Try to apply shield with 0 amount
	combatant.apply_shield(0.0, &"test", 5.0)

	if combatant.get_active_shields().size() != 0:
		violations.append(
			(
				"no_op_zero: shield list should be empty, got %d shields"
				% combatant.get_active_shields().size()
			)
		)

	if signal_log["count"] != 0:
		violations.append("no_op_zero: shield_changed should not fire for 0 amount")

	# Try to apply shield with negative amount
	combatant.apply_shield(-50.0, &"test", 5.0)

	if combatant.get_active_shields().size() != 0:
		violations.append(
			(
				"no_op_zero: shield list should still be empty, got %d shields"
				% combatant.get_active_shields().size()
			)
		)

	if signal_log["count"] != 0:
		violations.append("no_op_zero: shield_changed should not fire for negative amount")

	return violations


## Test: sustain_healing formula returns damage_dealt * sustain_pct
static func _test_sustain_healing_formula() -> Array[String]:
	var violations: Array[String] = []

	# Worked example: 40 damage dealt, 10% lifesteal → exactly 4.0 healing
	var heal1 := MobaFormulas.sustain_healing(40.0, 0.10)
	if not _approx_equal(heal1, 4.0):
		violations.append("sustain_healing: 40 * 0.10 should be 4.0, got %f" % heal1)

	# Zero damage → zero healing
	var heal2 := MobaFormulas.sustain_healing(0.0, 0.10)
	if not _approx_equal(heal2, 0.0):
		violations.append("sustain_healing: 0 * 0.10 should be 0.0, got %f" % heal2)

	# Negative damage clamps to zero
	var heal3 := MobaFormulas.sustain_healing(-10.0, 0.10)
	if not _approx_equal(heal3, 0.0):
		violations.append("sustain_healing: -10 * 0.10 should clamp to 0.0, got %f" % heal3)

	# High sustain: 100 * 0.50 = 50.0
	var heal4 := MobaFormulas.sustain_healing(100.0, 0.50)
	if not _approx_equal(heal4, 50.0):
		violations.append("sustain_healing: 100 * 0.50 should be 50.0, got %f" % heal4)

	return violations


## Test: clamped_heal formula clamps healing to remaining capacity
static func _test_clamped_heal_formula() -> Array[String]:
	var violations: Array[String] = []

	# Normal case: 480 / 500, heal 100 → applies 20
	var actual1 := MobaFormulas.clamped_heal(480.0, 500.0, 100.0)
	if not _approx_equal(actual1, 20.0):
		violations.append(
			"clamped_heal: 480 -> 500 with 100 heal should apply 20.0, got %f" % actual1
		)

	# At full health: 500 / 500, heal 100 → applies 0
	var actual2 := MobaFormulas.clamped_heal(500.0, 500.0, 100.0)
	if not _approx_equal(actual2, 0.0):
		violations.append(
			"clamped_heal: at full health with 100 heal should apply 0.0, got %f" % actual2
		)

	# Negative heal clamps to zero
	var actual3 := MobaFormulas.clamped_heal(100.0, 500.0, -10.0)
	if not _approx_equal(actual3, 0.0):
		violations.append("clamped_heal: negative heal should apply 0.0, got %f" % actual3)

	# Exact to full: 490 / 500, heal 10 → applies 10
	var actual4 := MobaFormulas.clamped_heal(490.0, 500.0, 10.0)
	if not _approx_equal(actual4, 10.0):
		violations.append(
			"clamped_heal: 490 -> 500 with 10 heal should apply 10.0, got %f" % actual4
		)

	return violations


## Test: Lifesteal heals attacker on basic attacks only
static func _test_lifesteal_on_basic_attack() -> Array[String]:
	var violations: Array[String] = []

	var attacker := _make_combatant()
	var target := _make_combatant()

	# Set lifesteal on attacker and reduce health so it can heal
	attacker._runtime_stat_block.lifesteal = 0.10
	attacker._current_health = 450.0  # Leave room to heal

	# Record healing
	var healing_signal_log := {"amount": 0.0, "count": 0}
	attacker.healing_applied.connect(
		func(amount: float):
			healing_signal_log["amount"] = amount
			healing_signal_log["count"] += 1
	)

	# Apply basic attack damage (50 raw, TRUE type so no mitigation, no shield)
	var damage := MobaDamage.new(50.0, MobaDamage.DamageType.TRUE, attacker, true, 0.0, 0.0, true)
	target.apply_damage(damage)

	# Attacker should have healed for 50 * 0.10 = 5.0
	if not _approx_equal(healing_signal_log["amount"], 5.0):
		violations.append(
			(
				"lifesteal_basic: attacker should heal 5.0 from 50 damage, got %f"
				% healing_signal_log["amount"]
			)
		)

	return violations


## Test: Lifesteal does NOT trigger on ability damage
static func _test_lifesteal_not_on_ability() -> Array[String]:
	var violations: Array[String] = []

	var attacker := _make_combatant()
	var target := _make_combatant()

	# Set lifesteal on attacker and reduce health so it can heal
	attacker._runtime_stat_block.lifesteal = 0.10
	attacker._current_health = 450.0  # Leave room to heal

	# Record healing
	var healing_signal_log := {"count": 0}
	attacker.healing_applied.connect(func(_amount: float): healing_signal_log["count"] += 1)

	# Apply ability damage (50 raw, is_basic_attack = false)
	var damage := MobaDamage.new(50.0, MobaDamage.DamageType.TRUE, attacker, true, 0.0, 0.0, false)
	target.apply_damage(damage)

	# Attacker should NOT have healed from lifesteal (omnivamp is 0 by default)
	if healing_signal_log["count"] != 0:
		violations.append("lifesteal_ability: lifesteal should not trigger on ability damage")

	return violations


## Test: Omnivamp heals on basic attacks
static func _test_omnivamp_on_basic_attack() -> Array[String]:
	var violations: Array[String] = []

	var attacker := _make_combatant()
	var target := _make_combatant()

	# Set omnivamp on attacker and reduce health so it can heal
	attacker._runtime_stat_block.omnivamp = 0.10
	attacker._current_health = 450.0  # Leave room to heal

	# Record healing
	var healing_signal_log := {"amount": 0.0, "count": 0}
	attacker.healing_applied.connect(
		func(amount: float):
			healing_signal_log["amount"] = amount
			healing_signal_log["count"] += 1
	)

	# Apply basic attack damage (50 raw, TRUE type so no mitigation)
	var damage := MobaDamage.new(50.0, MobaDamage.DamageType.TRUE, attacker, true, 0.0, 0.0, true)
	target.apply_damage(damage)

	# Attacker should have healed for 50 * 0.10 = 5.0
	if not _approx_equal(healing_signal_log["amount"], 5.0):
		violations.append(
			(
				"omnivamp_basic: attacker should heal 5.0 from 50 damage, got %f"
				% healing_signal_log["amount"]
			)
		)

	return violations


## Test: Omnivamp heals on ability damage
static func _test_omnivamp_on_ability() -> Array[String]:
	var violations: Array[String] = []

	var attacker := _make_combatant()
	var target := _make_combatant()

	# Set omnivamp on attacker and reduce health so it can heal
	attacker._runtime_stat_block.omnivamp = 0.10
	attacker._current_health = 450.0  # Leave room to heal

	# Record healing
	var healing_signal_log := {"amount": 0.0, "count": 0}
	attacker.healing_applied.connect(
		func(amount: float):
			healing_signal_log["amount"] = amount
			healing_signal_log["count"] += 1
	)

	# Apply ability damage (50 raw, is_basic_attack = false)
	var damage := MobaDamage.new(50.0, MobaDamage.DamageType.TRUE, attacker, true, 0.0, 0.0, false)
	target.apply_damage(damage)

	# Attacker should have healed for 50 * 0.10 = 5.0
	if not _approx_equal(healing_signal_log["amount"], 5.0):
		violations.append(
			(
				"omnivamp_ability: attacker should heal 5.0 from 50 damage, got %f"
				% healing_signal_log["amount"]
			)
		)

	return violations


## Test: Lifesteal and omnivamp sum on basic attacks
static func _test_lifesteal_and_omnivamp_sum() -> Array[String]:
	var violations: Array[String] = []

	var attacker := _make_combatant()
	var target := _make_combatant()

	# Set both lifesteal and omnivamp on attacker and reduce health so it can heal
	attacker._runtime_stat_block.lifesteal = 0.05
	attacker._runtime_stat_block.omnivamp = 0.05
	attacker._current_health = 450.0  # Leave room to heal

	# Record healing
	var healing_signal_log := {"amount": 0.0, "count": 0}
	attacker.healing_applied.connect(
		func(amount: float):
			healing_signal_log["amount"] = amount
			healing_signal_log["count"] += 1
	)

	# Apply basic attack damage (100 raw, TRUE type)
	var damage := MobaDamage.new(100.0, MobaDamage.DamageType.TRUE, attacker, true, 0.0, 0.0, true)
	target.apply_damage(damage)

	# Attacker should have healed for 100 * (0.05 + 0.05) = 10.0
	if not _approx_equal(healing_signal_log["amount"], 10.0):
		violations.append(
			(
				"lifesteal_omnivamp_sum: attacker should heal 10.0 (5% + 5%), got %f"
				% healing_signal_log["amount"]
			)
		)

	return violations


## Test: Lifesteal applied on damage_dealt, not raw (after armor mitigation)
static func _test_lifesteal_on_damage_dealt() -> Array[String]:
	var violations: Array[String] = []

	var attacker := _make_combatant()
	var target := _make_combatant()

	# Set lifesteal on attacker and reduce health so it can heal
	attacker._runtime_stat_block.lifesteal = 0.10
	attacker._current_health = 450.0  # Leave room to heal

	# Set target armor to reduce damage
	target._runtime_stat_block.armor = 30

	# Record healing
	var healing_signal_log := {"amount": 0.0, "count": 0}
	attacker.healing_applied.connect(
		func(amount: float):
			healing_signal_log["amount"] = amount
			healing_signal_log["count"] += 1
	)

	# Apply basic attack damage
	# 50 raw physical damage, 30 armor on target
	# Final damage = 50 * (100 / (100 + 30)) = 50 * (100/130) ≈ 38.46
	# Lifesteal = 38.46 * 0.10 ≈ 3.846, not 50 * 0.10 = 5.0
	var damage := MobaDamage.new(
		50.0, MobaDamage.DamageType.PHYSICAL, attacker, true, 0.0, 0.0, true
	)
	target.apply_damage(damage)

	# Lifesteal is 10% of the 38.4615 actually dealt, not of the 50 raw.
	var expected_dealt := 50.0 * (100.0 / 130.0)
	if not _approx_equal(healing_signal_log["amount"], expected_dealt * 0.10):
		violations.append(
			(
				"lifesteal_on_dealt: lifesteal should be %f (10%% of damage dealt), got %f"
				% [expected_dealt * 0.10, healing_signal_log["amount"]]
			)
		)

	return violations


## Test: Overkill boundary (10 health, 200 damage, 10% lifesteal → 1.0 healing)
static func _test_overkill_boundary() -> Array[String]:
	var violations: Array[String] = []

	var attacker := _make_combatant()
	var target := _make_combatant()

	# Set target to 10 health
	target._current_health = 10.0

	# Set lifesteal on attacker and reduce health so it can heal
	attacker._runtime_stat_block.lifesteal = 0.10
	attacker._current_health = 450.0  # Leave room to heal

	# Record healing
	var healing_signal_log := {"amount": 0.0, "count": 0}
	attacker.healing_applied.connect(
		func(amount: float):
			healing_signal_log["amount"] = amount
			healing_signal_log["count"] += 1
	)

	# Apply 200 damage (TRUE type so no mitigation)
	var damage := MobaDamage.new(200.0, MobaDamage.DamageType.TRUE, attacker, true, 0.0, 0.0, true)
	target.apply_damage(damage)

	# Only 10 damage applied to health, so lifesteal = 10 * 0.10 = 1.0, not 200 * 0.10 = 20.0
	if not _approx_equal(healing_signal_log["amount"], 1.0):
		violations.append(
			(
				"overkill: overkill should only heal based on actual damage dealt (1.0), got %f"
				% healing_signal_log["amount"]
			)
		)

	return violations


## Test: apply_healing returns actual amount applied (clamped at max health)
static func _test_apply_healing_returns_amount() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()

	# Start at 400 / 500 health
	combatant._current_health = 400.0

	# Heal 100 (would overheal by 0) → should apply 100
	var result1 := combatant.apply_healing(100.0)
	if not _approx_equal(result1, 100.0):
		violations.append(
			"apply_healing_return: heal 100 into 400/500 should return 100.0, got %f" % result1
		)

	# Reset to 480 / 500
	combatant._current_health = 480.0

	# Heal 100 (would overheal by 80) → should apply 20
	var result2 := combatant.apply_healing(100.0)
	if not _approx_equal(result2, 20.0):
		violations.append(
			"apply_healing_return: heal 100 into 480/500 should return 20.0, got %f" % result2
		)

	# At full health 500 / 500
	combatant._current_health = 500.0

	# Heal 100 → should apply 0
	var result3 := combatant.apply_healing(100.0)
	if not _approx_equal(result3, 0.0):
		violations.append(
			"apply_healing_return: heal 100 into 500/500 should return 0.0, got %f" % result3
		)

	return violations


## Test: apply_healing on dead combatant returns 0.0 and mutates nothing
static func _test_apply_healing_on_dead_combatant() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()

	# Kill the combatant
	combatant._current_health = 0.0

	# Try to heal → should return 0.0 and not change health
	var health_before := combatant._current_health
	var result := combatant.apply_healing(100.0)

	if not _approx_equal(result, 0.0):
		violations.append(
			"dead_heal_return: apply_healing on dead should return 0.0, got %f" % result
		)

	if combatant._current_health != health_before:
		(
			violations
			. append(
				(
					"dead_heal_mutation: apply_healing on dead should not mutate health, changed from %f to %f"
					% [health_before, combatant._current_health]
				)
			)
		)

	return violations


## Test: healing_applied signal fires whenever apply_healing is not refused
static func _test_healing_applied_signal() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()

	# Record signal fires
	var signal_log := {"count": 0, "amounts": []}
	combatant.healing_applied.connect(
		func(amount: float):
			signal_log["count"] += 1
			signal_log["amounts"].append(amount)
	)

	# Heal normally → should fire
	combatant._current_health = 400.0
	combatant.apply_healing(50.0)
	if signal_log["count"] != 1:
		violations.append(
			"healing_signal: first heal should fire signal, count = %d" % signal_log["count"]
		)

	# Heal with overheal → should still fire (with clamped amount)
	signal_log["count"] = 0
	signal_log["amounts"].clear()
	combatant._current_health = 490.0
	combatant.apply_healing(100.0)
	if signal_log["count"] != 1:
		violations.append(
			"healing_signal: overheal should fire signal, count = %d" % signal_log["count"]
		)
	if not _approx_equal(signal_log["amounts"][0], 10.0):
		violations.append(
			(
				"healing_signal: overheal should fire with clamped amount (10.0), got %f"
				% signal_log["amounts"][0]
			)
		)

	# Heal at full health → should fire with 0.0
	signal_log["count"] = 0
	signal_log["amounts"].clear()
	combatant._current_health = 500.0
	combatant.apply_healing(50.0)
	if signal_log["count"] != 1:
		violations.append(
			"healing_signal: heal at full should fire signal, count = %d" % signal_log["count"]
		)
	if not _approx_equal(signal_log["amounts"][0], 0.0):
		violations.append(
			"healing_signal: heal at full should fire with 0.0, got %f" % signal_log["amounts"][0]
		)

	# Heal while dead → should NOT fire
	signal_log["count"] = 0
	signal_log["amounts"].clear()
	combatant._current_health = 0.0
	combatant.apply_healing(50.0)
	if signal_log["count"] != 0:
		violations.append(
			"healing_signal: heal on dead should NOT fire signal, count = %d" % signal_log["count"]
		)

	return violations


## Build a caster with a real MobaCombatant and MobaStateMachine as child nodes
## for ability activation testing.
static func _create_caster_for_ability() -> Dictionary:
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
	actor.add_child(combatant)

	var state_machine = MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	return {"actor": actor, "combatant": combatant}


## Activate an ability on the caster through the real ability pipeline.
static func _activate_ability(caster: Node, ability_id: StringName):
	var context = MobaCastContext.new(caster, null)
	var action = MobaAbilityAction.new(caster, ability_id, context)
	return action.execute()


## Test: Force Barrier applies shield to caster and shield absorbs damage
static func _test_force_barrier_shield_application() -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()

	var force_barrier_ability = MobaAbilityLibrary.get_ability(&"force_barrier")
	if force_barrier_ability == null:
		MobaAbilityLibrary._reset()
		(
			violations
			. append(
				"force_barrier_shield: force_barrier.tres did not load as a MobaAbility with id 'force_barrier'"
			)
		)
		return violations

	var caster_data = _create_caster_for_ability()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	caster_combatant.register_ability(force_barrier_ability)

	# Expectations are read from the authored resource, never restated here.
	var expected_shield: float = force_barrier_ability.shield_amount
	var expected_duration: float = force_barrier_ability.duration
	var starting_resource: float = caster_combatant.current_resource
	var starting_health: float = caster_combatant.current_health

	var result = _activate_ability(caster, &"force_barrier")
	if not result.success:
		violations.append(
			"force_barrier_shield: activation should succeed, got: %s" % result.reason
		)

	var shield_total = caster_combatant.total_shield()
	if not _approx_equal(shield_total, expected_shield):
		violations.append(
			(
				"force_barrier_shield: total shield should be %f, got %f"
				% [expected_shield, shield_total]
			)
		)

	if caster_combatant.get_active_shields().size() != 1:
		violations.append(
			(
				"force_barrier_shield: should have exactly 1 shield, got %d"
				% caster_combatant.get_active_shields().size()
			)
		)
		MobaAbilityLibrary._reset()
		return violations

	var shield = caster_combatant.get_active_shields()[0] as MobaShield
	if not _approx_equal(shield.remaining, expected_duration):
		violations.append(
			(
				"force_barrier_shield: shield duration should be %f, got %f"
				% [expected_duration, shield.remaining]
			)
		)

	# The cost is spent through the ordinary activation path, not a special case.
	var expected_resource: float = starting_resource - force_barrier_ability.resource_cost
	if not _approx_equal(caster_combatant.current_resource, expected_resource):
		violations.append(
			(
				"force_barrier_shield: resource should be spent down to %f, got %f"
				% [expected_resource, caster_combatant.current_resource]
			)
		)

	# The shield absorbs damage exactly as any other shield does.
	var damage_amount := 80.0
	var damage := MobaDamage.new(damage_amount, MobaDamage.DamageType.TRUE)
	caster_combatant.apply_damage(damage)

	var expected_remaining_shield: float = expected_shield - damage_amount
	if not _approx_equal(caster_combatant.total_shield(), expected_remaining_shield):
		violations.append(
			(
				"force_barrier_shield: shield should be %f after %f damage, got %f"
				% [expected_remaining_shield, damage_amount, caster_combatant.total_shield()]
			)
		)

	if not _approx_equal(caster_combatant.current_health, starting_health):
		violations.append(
			(
				"force_barrier_shield: health should be unchanged at %f, got %f"
				% [starting_health, caster_combatant.current_health]
			)
		)

	MobaAbilityLibrary._reset()

	return violations


## Test: Field Dressing applies healing to caster, clamped at max health
static func _test_field_dressing_healing_application() -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()

	var field_dressing_ability = MobaAbilityLibrary.get_ability(&"field_dressing")
	if field_dressing_ability == null:
		MobaAbilityLibrary._reset()
		violations.append(
			(
				"field_dressing_heal: field_dressing.tres did not load as a "
				+ "MobaAbility with id 'field_dressing'"
			)
		)
		return violations

	var caster_data = _create_caster_for_ability()
	var caster = caster_data["actor"]
	var caster_combatant = caster_data["combatant"]

	caster_combatant.register_ability(field_dressing_ability)

	var max_health: float = caster_combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.HEALTH
	)
	var expected_heal: float = field_dressing_ability.heal_amount

	# Wound the caster by more than the heal so the heal is not clamped.
	var missing_health: float = expected_heal + 50.0
	caster_combatant._current_health = max_health - missing_health

	var starting_resource: float = caster_combatant.current_resource
	var wounded_health: float = caster_combatant.current_health

	var result = _activate_ability(caster, &"field_dressing")
	if not result.success:
		violations.append("field_dressing_heal: activation should succeed, got: %s" % result.reason)

	var expected_health: float = minf(wounded_health + expected_heal, max_health)
	if not _approx_equal(caster_combatant.current_health, expected_health):
		violations.append(
			(
				"field_dressing_heal: health should be %f after heal, got %f"
				% [expected_health, caster_combatant.current_health]
			)
		)

	# The cost is spent through the ordinary activation path, not a special case.
	var expected_resource: float = starting_resource - field_dressing_ability.resource_cost
	if not _approx_equal(caster_combatant.current_resource, expected_resource):
		violations.append(
			(
				"field_dressing_heal: resource should be spent down to %f, got %f"
				% [expected_resource, caster_combatant.current_resource]
			)
		)

	if caster_combatant.total_shield() > 0.0:
		violations.append(
			"field_dressing_heal: shield should be 0.0, got %f" % caster_combatant.total_shield()
		)

	# Healing at full health is clamped at maximum rather than overhealing.
	var caster_data2 = _create_caster_for_ability()
	var caster2 = caster_data2["actor"]
	var caster_combatant2 = caster_data2["combatant"]
	caster_combatant2.register_ability(field_dressing_ability)

	if not _approx_equal(caster_combatant2.current_health, max_health):
		violations.append(
			(
				"field_dressing_heal: caster2 should start at %f health, got %f"
				% [max_health, caster_combatant2.current_health]
			)
		)

	var result2 = _activate_ability(caster2, &"field_dressing")
	if not result2.success:
		violations.append(
			(
				"field_dressing_heal: activation at full health should succeed, got: %s"
				% result2.reason
			)
		)

	if not _approx_equal(caster_combatant2.current_health, max_health):
		violations.append(
			(
				"field_dressing_heal: health should remain at %f at full, got %f"
				% [max_health, caster_combatant2.current_health]
			)
		)

	MobaAbilityLibrary._reset()

	return violations
