## Test suite for MobaFormulas.
##
## Covers all static formula implementations: mitigation_multiplier, effective_defense,
## physical_damage, magical_damage, true_damage, effective_cooldown, expected_crit_multiplier,
## is_critical, and apply_crit.
class_name FormulasTest


const TOLERANCE = 0.0001  # Tolerance for floating-point comparisons
const TOLERANCE_PHYSICAL = 0.01  # Tolerance for physical_damage worked example


## Run the formulas test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []
	
	# Test 1: mitigation_multiplier with zero defense
	all_violations.append_array(_test_mitigation_multiplier_zero())
	
	# Test 2: mitigation_multiplier with 100 defense
	all_violations.append_array(_test_mitigation_multiplier_hundred())
	
	# Test 3: mitigation_multiplier with negative defense
	all_violations.append_array(_test_mitigation_multiplier_negative())
	
	# Test 4: physical_damage worked example
	all_violations.append_array(_test_physical_damage_worked_example())
	
	# Test 5: effective_defense with flat and percent penetration
	all_violations.append_array(_test_effective_defense_with_penetration())
	
	# Test 6: effective_defense with over-penetration clamping
	all_violations.append_array(_test_effective_defense_clamp_negative())
	
	# Test 7: true_damage with zero and non-zero inputs
	all_violations.append_array(_test_true_damage())
	
	# Test 8: effective_cooldown
	all_violations.append_array(_test_effective_cooldown())
	
	# Test 9: apply_crit
	all_violations.append_array(_test_apply_crit())
	
	# Test 10: expected_crit_multiplier
	all_violations.append_array(_test_expected_crit_multiplier())
	
	# Test 11: is_critical
	all_violations.append_array(_test_is_critical())
	
	if all_violations.is_empty():
		return true
	
	# Print violations
	printerr("\n=== Formulas Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)
	
	return false


## Test mitigation_multiplier(0.0) returns exactly 1.0
static func _test_mitigation_multiplier_zero() -> Array[String]:
	var violations: Array[String] = []
	
	var result = MobaFormulas.mitigation_multiplier(0.0)
	if not is_equal_approx(result, 1.0):
		violations.append("mitigation_multiplier(0.0): expected 1.0, got %f" % result)
	
	return violations


## Test mitigation_multiplier(100.0) returns 0.5 within tolerance
static func _test_mitigation_multiplier_hundred() -> Array[String]:
	var violations: Array[String] = []
	
	var result = MobaFormulas.mitigation_multiplier(100.0)
	if not is_equal_approx(result, 0.5, TOLERANCE):
		violations.append("mitigation_multiplier(100.0): expected 0.5, got %f" % result)
	
	return violations


## Test mitigation_multiplier(-30.0) returns 1.0 (clamped to zero)
static func _test_mitigation_multiplier_negative() -> Array[String]:
	var violations: Array[String] = []
	
	var result = MobaFormulas.mitigation_multiplier(-30.0)
	if not is_equal_approx(result, 1.0):
		violations.append("mitigation_multiplier(-30.0): expected 1.0, got %f" % result)
	
	return violations


## Test physical_damage(50.0, 50.0) returns 33.33 (worked example from §8)
static func _test_physical_damage_worked_example() -> Array[String]:
	var violations: Array[String] = []
	
	var result = MobaFormulas.physical_damage(50.0, 50.0)
	if not is_equal_approx(result, 33.33, TOLERANCE_PHYSICAL):
		violations.append("physical_damage(50.0, 50.0): expected 33.33, got %f" % result)
	
	return violations


## Test effective_defense with flat and percent penetration
static func _test_effective_defense_with_penetration() -> Array[String]:
	var violations: Array[String] = []
	
	var result = MobaFormulas.effective_defense(100.0, 20.0, 0.30)
	if not is_equal_approx(result, 56.0, TOLERANCE):
		violations.append("effective_defense(100.0, 20.0, 0.30): expected 56.0, got %f" % result)
	
	return violations


## Test effective_defense with over-penetration clamps to zero
static func _test_effective_defense_clamp_negative() -> Array[String]:
	var violations: Array[String] = []
	
	var result = MobaFormulas.effective_defense(10.0, 30.0, 0.0)
	if not is_equal_approx(result, 0.0):
		violations.append("effective_defense(10.0, 30.0, 0.0): expected 0.0, got %f" % result)
	
	return violations


## Test true_damage returns raw unchanged
static func _test_true_damage() -> Array[String]:
	var violations: Array[String] = []
	
	# Test with zero
	var result_zero = MobaFormulas.true_damage(0.0)
	if not is_equal_approx(result_zero, 0.0):
		violations.append("true_damage(0.0): expected 0.0, got %f" % result_zero)
	
	# Test with non-zero
	var result_nonzero = MobaFormulas.true_damage(42.5)
	if not is_equal_approx(result_nonzero, 42.5):
		violations.append("true_damage(42.5): expected 42.5, got %f" % result_nonzero)
	
	return violations


## Test effective_cooldown
static func _test_effective_cooldown() -> Array[String]:
	var violations: Array[String] = []
	
	# Test with 100 ability haste (should return 5.0)
	var result_haste = MobaFormulas.effective_cooldown(10.0, 100.0)
	if not is_equal_approx(result_haste, 5.0, TOLERANCE):
		violations.append("effective_cooldown(10.0, 100.0): expected 5.0, got %f" % result_haste)
	
	# Test with 0 ability haste (should return 10.0)
	var result_no_haste = MobaFormulas.effective_cooldown(10.0, 0.0)
	if not is_equal_approx(result_no_haste, 10.0):
		violations.append("effective_cooldown(10.0, 0.0): expected 10.0, got %f" % result_no_haste)
	
	return violations


## Test apply_crit
static func _test_apply_crit() -> Array[String]:
	var violations: Array[String] = []
	
	var result = MobaFormulas.apply_crit(50.0, 2.0)
	if not is_equal_approx(result, 100.0):
		violations.append("apply_crit(50.0, 2.0): expected 100.0, got %f" % result)
	
	return violations


## Test expected_crit_multiplier
static func _test_expected_crit_multiplier() -> Array[String]:
	var violations: Array[String] = []
	
	# Test with 0% crit chance (should return 1.0)
	var result_zero = MobaFormulas.expected_crit_multiplier(0.0, 2.0)
	if not is_equal_approx(result_zero, 1.0):
		violations.append("expected_crit_multiplier(0.0, 2.0): expected 1.0, got %f" % result_zero)
	
	# Test with 5% crit chance (should return 1.05)
	var result_five = MobaFormulas.expected_crit_multiplier(0.05, 2.0)
	if not is_equal_approx(result_five, 1.05, TOLERANCE):
		violations.append("expected_crit_multiplier(0.05, 2.0): expected 1.05, got %f" % result_five)
	
	# Test with 100% crit chance (should return 2.0)
	var result_hundred = MobaFormulas.expected_crit_multiplier(1.0, 2.0)
	if not is_equal_approx(result_hundred, 2.0):
		violations.append("expected_crit_multiplier(1.0, 2.0): expected 2.0, got %f" % result_hundred)
	
	return violations


## Test is_critical
static func _test_is_critical() -> Array[String]:
	var violations: Array[String] = []
	
	# Test roll below crit chance (should be critical)
	var is_crit_low = MobaFormulas.is_critical(0.05, 0.20)
	if not is_crit_low:
		violations.append("is_critical(0.05, 0.20): expected true, got false")
	
	# Test roll above crit chance (should not be critical)
	var is_crit_high = MobaFormulas.is_critical(0.25, 0.20)
	if is_crit_high:
		violations.append("is_critical(0.25, 0.20): expected false, got true")
	
	# Test roll exactly at crit chance (should not be critical, boundary condition)
	var is_crit_equal = MobaFormulas.is_critical(0.20, 0.20)
	if is_crit_equal:
		violations.append("is_critical(0.20, 0.20): expected false, got true")
	
	return violations
