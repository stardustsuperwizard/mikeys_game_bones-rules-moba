## Test suite for MobaCombatant resource pool and regeneration.
##
## Covers: resource seeding, spend/restore operations, clamping at maximum,
## regeneration accumulation, partial-tick equivalence, and health regeneration.
class_name ResourceTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaDamage = preload("res://rules/core/moba_damage.gd")


## Helper function to compare floats with tolerance
static func _approx_equal(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return abs(a - b) < tolerance


## Run the resource test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []
	
	# Test 1: Resource defaults and seeding
	var seeding_violations = _test_resource_seeding()
	all_violations.append_array(seeding_violations)
	
	# Test 2: spend_resource returns true and deducts amount
	var spend_violations = _test_spend_resource()
	all_violations.append_array(spend_violations)
	
	# Test 3: spend_resource returns false when amount exceeds current
	var spend_fail_violations = _test_spend_resource_insufficient()
	all_violations.append_array(spend_fail_violations)
	
	# Test 4: spend_resource(0.0) returns true at zero current
	var spend_zero_violations = _test_spend_resource_zero()
	all_violations.append_array(spend_zero_violations)
	
	# Test 5: restore_resource clamps at maximum
	var restore_violations = _test_restore_resource_clamped()
	all_violations.append_array(restore_violations)
	
	# Test 6: Regeneration accumulation over time
	var regen_violations = _test_regeneration_accumulation()
	all_violations.append_array(regen_violations)
	
	# Test 7: Partial-tick accumulation equivalence
	var partial_tick_violations = _test_partial_tick_accumulation()
	all_violations.append_array(partial_tick_violations)
	
	# Test 8: Health regeneration works with tick
	var health_regen_violations = _test_health_regeneration()
	all_violations.append_array(health_regen_violations)
	
	# Test 9: Dead combatant does not regenerate health
	var dead_regen_violations = _test_dead_combatant_no_health_regen()
	all_violations.append_array(dead_regen_violations)
	
	if all_violations.is_empty():
		return true
	
	# Print violations
	printerr("\n=== Resource Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)
	
	return false


## Test resource seeding from stat block
static func _test_resource_seeding() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	
	# Manually initialize without parent
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)
	
	# Check that resource is seeded to full (250.0 from baseline)
	var expected_resource = 250.0
	var actual_resource = combatant.current_resource
	if not is_equal_approx(actual_resource, expected_resource):
		violations.append("resource_seeding: current_resource mismatch (expected %f, got %f)" % [expected_resource, actual_resource])
	
	var expected_max = 250.0
	var actual_max = combatant.maximum_resource
	if not is_equal_approx(actual_max, expected_max):
		violations.append("resource_seeding: maximum_resource mismatch (expected %f, got %f)" % [expected_max, actual_max])
	
	return violations


## Test spend_resource returns true and deducts amount
static func _test_spend_resource() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)
	
	var initial_resource = combatant.current_resource
	var spend_amount = 30.0
	var result = combatant.spend_resource(spend_amount)
	
	if result != true:
		violations.append("spend_resource: expected true, got false")
	
	var expected_resource = initial_resource - spend_amount
	var actual_resource = combatant.current_resource
	if not is_equal_approx(actual_resource, expected_resource):
		violations.append("spend_resource: expected %f, got %f" % [expected_resource, actual_resource])
	
	return violations


## Test spend_resource returns false when amount exceeds current
static func _test_spend_resource_insufficient() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = 20.0
	
	var spend_amount = 30.0
	var result = combatant.spend_resource(spend_amount)
	
	if result != false:
		violations.append("spend_resource_insufficient: expected false, got true")
	
	# Current should remain unchanged at 20.0
	if not is_equal_approx(combatant.current_resource, 20.0):
		violations.append("spend_resource_insufficient: resource should not change when spend fails (expected 20.0, got %f)" % combatant.current_resource)
	
	return violations


## Test spend_resource(0.0) returns true at zero current
static func _test_spend_resource_zero() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = 0.0
	
	var result = combatant.spend_resource(0.0)
	
	if result != true:
		violations.append("spend_resource_zero: expected true at zero resource, got false")
	
	return violations


## Test restore_resource clamps at maximum
static func _test_restore_resource_clamped() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)
	
	# Spend some resource
	combatant.spend_resource(30.0)
	
	# Restore more than we need to reach maximum
	combatant.restore_resource(100.0)
	
	# Should be clamped at maximum (250.0)
	var max_resource = combatant.maximum_resource
	if not is_equal_approx(combatant.current_resource, max_resource):
		violations.append("restore_resource_clamped: expected %f, got %f" % [max_resource, combatant.current_resource])
	
	return violations


## Test regeneration accumulation over time
static func _test_regeneration_accumulation() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)
	
	# Spend 30 from full (250)
	combatant.spend_resource(30.0)
	var current_after_spend = combatant.current_resource  # Should be 220
	
	# Tick for 10 seconds at 3.0 regen/sec (10 * 3.0 = 30.0 regen)
	# Should go from 220 to 250, clamped at maximum
	for _i in range(10):
		combatant.tick(1.0)
	
	var max_resource = combatant.maximum_resource
	if not is_equal_approx(combatant.current_resource, max_resource):
		violations.append("regeneration_accumulation: after 10 seconds of 3.0 regen, expected %f, got %f" % [max_resource, combatant.current_resource])
	
	return violations


## Test partial-tick accumulation equivalence
static func _test_partial_tick_accumulation() -> Array[String]:
	var violations: Array[String] = []
	
	# Run 1: Single 1-second tick
	var combatant1 = MobaCombatant.new()
	combatant1.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant1._runtime_stat_block = combatant1.stat_block.duplicate()
	combatant1._current_health = combatant1._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant1._current_resource = combatant1._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)
	
	combatant1.tick(1.0)
	var result1 = combatant1.current_resource
	
	# Run 2: Ten 0.1-second ticks
	var combatant2 = MobaCombatant.new()
	combatant2.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant2._runtime_stat_block = combatant2.stat_block.duplicate()
	combatant2._current_health = combatant2._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant2._current_resource = combatant2._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)
	
	for _i in range(10):
		combatant2.tick(0.1)
	var result2 = combatant2.current_resource
	
	# Results should be equal within float tolerance
	if not _approx_equal(result1, result2, 0.0001):
		violations.append("partial_tick_accumulation: single 1.0s tick gave %f, ten 0.1s ticks gave %f" % [result1, result2])
	
	return violations


## Test health regeneration works with tick
static func _test_health_regeneration() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)
	
	# Disable crit to make damage predictable
	combatant._runtime_stat_block.crit_chance = 0.0
	MobaRules.seed_crit_rng(42)
	
	# Apply some damage (100 PHYSICAL vs 30 armor = ~61 damage)
	var damage = MobaDamage.new(100.0, MobaDamage.DamageType.PHYSICAL)
	combatant.apply_damage(damage)
	
	var health_after_damage = combatant._current_health
	
	# Tick for 10 seconds at 5.0 health_regen/sec (10 * 5.0 = 50.0 regen)
	for _i in range(10):
		combatant.tick(1.0)
	
	# Health should regenerate (but may be clamped at max)
	var max_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	var health_after_regen = combatant._current_health
	
	if health_after_regen <= health_after_damage:
		violations.append("health_regeneration: health should increase after tick (before %f, after %f)" % [health_after_damage, health_after_regen])
	
	return violations


## Test dead combatant does not regenerate health
static func _test_dead_combatant_no_health_regen() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)
	
	# Disable crit
	combatant._runtime_stat_block.crit_chance = 0.0
	MobaRules.seed_crit_rng(42)
	
	# Kill the combatant with lethal damage
	var lethal_damage = MobaDamage.new(1000.0, MobaDamage.DamageType.PHYSICAL)
	combatant.apply_damage(lethal_damage)
	
	if combatant.is_alive():
		violations.append("dead_combatant_no_health_regen: combatant should be dead")
	
	var health_when_dead = combatant._current_health
	
	# Tick for 1 second
	combatant.tick(1.0)
	
	# Health should remain at or below 0, not regenerate
	if combatant._current_health > health_when_dead:
		violations.append("dead_combatant_no_health_regen: dead combatant should not regenerate health (before %f, after %f)" % [health_when_dead, combatant._current_health])
	
	return violations
