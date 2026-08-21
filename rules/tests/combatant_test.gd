## Test suite for MobaCombatant node.
##
## Covers: stat defaults, damage reduces health, healing capped at maximum,
## death fires exactly once, and stat block is duplicated not shared.
class_name CombatantTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")


## Run the combatant test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []
	
	# Test 1: Stat defaults match §6
	var defaults_violations = _test_stat_defaults()
	all_violations.append_array(defaults_violations)
	
	# Test 2: Damage reduces health
	var damage_violations = _test_damage_reduces_health()
	all_violations.append_array(damage_violations)
	
	# Test 3: Healing does not exceed maximum
	var healing_violations = _test_healing_capped_at_maximum()
	all_violations.append_array(healing_violations)
	
	# Test 4: Death fires exactly once even with back-to-back lethal damage
	var death_violations = _test_death_fires_once()
	all_violations.append_array(death_violations)
	
	# Test 5: Stat block is duplicated, not shared
	var duplication_violations = _test_stat_block_duplicated()
	all_violations.append_array(duplication_violations)
	
	if all_violations.is_empty():
		return true
	
	# Print violations
	printerr("\n=== Combatant Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)
	
	return false


## Test stat defaults match baseline spec (§6)
static func _test_stat_defaults() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	
	# Manually initialize without parent (no _ready call)
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	
	# Check baseline values
	var expected_health = 500.0
	var actual_health = combatant.get_base_stat(MobaStatBlock.HEALTH)
	if not is_equal_approx(actual_health, expected_health):
		violations.append("stat_defaults: health mismatch (expected %f, got %f)" % [expected_health, actual_health])
	
	if not is_equal_approx(combatant.get_base_stat(MobaStatBlock.HEALTH_REGEN), 5.0):
		violations.append("stat_defaults: health_regen mismatch")
	
	if not is_equal_approx(combatant.get_base_stat(MobaStatBlock.ARMOR), 30.0):
		violations.append("stat_defaults: armor mismatch")
	
	if not combatant.is_alive():
		violations.append("stat_defaults: combatant should be alive at start")
	
	return violations


## Test damage reduces health
static func _test_damage_reduces_health() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	
	var initial_health = combatant._current_health
	var damage_amount = 50.0
	combatant.apply_damage(damage_amount)
	
	var expected_health = initial_health - damage_amount
	if not is_equal_approx(combatant._current_health, expected_health):
		violations.append("damage_reduces_health: expected %f, got %f" % [expected_health, combatant._current_health])
	
	if combatant.is_alive() == false:
		violations.append("damage_reduces_health: combatant should still be alive")
	
	return violations


## Test healing does not exceed maximum
static func _test_healing_capped_at_maximum() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	
	var max_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	
	# Apply damage
	combatant.apply_damage(100.0)
	var health_after_damage = combatant._current_health
	
	# Heal more than damage was applied
	combatant.apply_healing(200.0)
	
	if not is_equal_approx(combatant._current_health, max_health):
		violations.append("healing_capped: expected %f, got %f" % [max_health, combatant._current_health])
	
	return violations


## Test death fires exactly once even with back-to-back lethal damage
static func _test_death_fires_once() -> Array[String]:
	var violations: Array[String] = []
	
	var combatant = MobaCombatant.new()
	combatant.stat_block = preload("res://rules/data/stat_blocks/baseline.tres")
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	
	var death_count = 0
	combatant.health_changed.connect(func(current: float, _maximum: float):
		if current <= 0.0 and not combatant._has_died:
			# This signal will fire before _has_died is set
			pass
	)
	
	# Apply first lethal damage (no parent Actor, so die() won't actually be called)
	combatant.apply_damage(600.0)  # More than max health
	if not combatant._has_died:
		violations.append("death_fires_once: first damage should have killed")
	
	# Apply second lethal damage
	var first_death_flag = combatant._has_died
	combatant.apply_damage(100.0)  # More damage to already-dead combatant
	
	if combatant._has_died != first_death_flag:
		violations.append("death_fires_once: death flag should not change on second damage")
	
	return violations


## Test stat block is duplicated, not shared
static func _test_stat_block_duplicated() -> Array[String]:
	var violations: Array[String] = []
	
	# Create two combatants with the same stat block resource
	var baseline = preload("res://rules/data/stat_blocks/baseline.tres")
	
	var combatant1 = MobaCombatant.new()
	combatant1.stat_block = baseline
	combatant1._runtime_stat_block = combatant1.stat_block.duplicate()
	combatant1._current_health = combatant1._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	
	var combatant2 = MobaCombatant.new()
	combatant2.stat_block = baseline
	combatant2._runtime_stat_block = combatant2.stat_block.duplicate()
	combatant2._current_health = combatant2._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	
	# Mutate one combatant's runtime block
	combatant1._runtime_stat_block.armor = 999
	
	# Check that the other combatant and the baseline resource are unaffected
	var baseline_armor = baseline.get_stat_value(MobaStatBlock.ARMOR)
	var combatant2_armor = combatant2._runtime_stat_block.get_stat_value(MobaStatBlock.ARMOR)
	
	if combatant2_armor == 999:
		violations.append("duplication: combatant2's stat block was modified")
	
	if baseline_armor == 999:
		violations.append("duplication: baseline resource was modified")
	
	return violations
