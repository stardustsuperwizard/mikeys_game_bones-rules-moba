## Test suite for shield pool and damage pipeline integration.
##
## Covers: shield pool creation, total_shield calculation, apply_shield,
## shield consumption in damage pipeline (shortest-remaining-duration first),
## shield expiry through tick(), signal emission, and multi-shield scenarios.
class_name SustainTest

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

	if combatant._active_shields.size() != 1:
		violations.append(
			(
				"shield_application: expected 1 active shield, got %d"
				% combatant._active_shields.size()
			)
		)

	var shield = combatant._active_shields[0] as MobaShield
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
	if combatant._active_shields.size() != 1:
		violations.append(
			"two_shields: expected 1 shield remaining, got %d" % combatant._active_shields.size()
		)

	if not _approx_equal(combatant.total_shield(), 90.0):
		violations.append("two_shields: total should be 90.0, got %f" % combatant.total_shield())

	# Verify the remaining shield is the 5s one
	var remaining = combatant._active_shields[0] as MobaShield
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

	if combatant._active_shields.size() != 0:
		violations.append(
			(
				"no_op_zero: shield list should be empty, got %d shields"
				% combatant._active_shields.size()
			)
		)

	if signal_log["count"] != 0:
		violations.append("no_op_zero: shield_changed should not fire for 0 amount")

	# Try to apply shield with negative amount
	combatant.apply_shield(-50.0, &"test", 5.0)

	if combatant._active_shields.size() != 0:
		violations.append(
			(
				"no_op_zero: shield list should still be empty, got %d shields"
				% combatant._active_shields.size()
			)
		)

	if signal_log["count"] != 0:
		violations.append("no_op_zero: shield_changed should not fire for negative amount")

	return violations
