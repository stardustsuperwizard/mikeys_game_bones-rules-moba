## Test suite for MobaCombatant node.
##
## Covers: stat defaults, damage reduces health, healing capped at maximum,
## death fires exactly once, and stat block is duplicated not shared, plus
## the new MobaDamage pipeline tests: physical vs magical mitigation, TRUE damage,
## crit before mitigation, and seedable RNG.
class_name CombatantTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaDamage = preload("res://rules/core/moba_damage.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")


## Helper function to compare floats with tolerance
static func _approx_equal(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return abs(a - b) < tolerance


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

	# Test 5b: Loadout is duplicated, not shared
	var loadout_duplication_violations = _test_loadout_duplicated()
	all_violations.append_array(loadout_duplication_violations)

	# Test 6: 50 raw PHYSICAL vs 50 armor = 33.33 health reduction
	var physical_mitigation_violations = _test_physical_armor_mitigation()
	all_violations.append_array(physical_mitigation_violations)

	# Test 7: MAGICAL vs PHYSICAL use correct defense stats
	var defense_routing_violations = _test_damage_type_routing()
	all_violations.append_array(defense_routing_violations)

	# Test 8: TRUE damage ignores defenses and penetration
	var true_damage_violations = _test_true_damage_ignores_defenses()
	all_violations.append_array(true_damage_violations)

	# Test 9: Critical hit multiplier applied before mitigation
	var crit_before_mitigation_violations = _test_crit_before_mitigation()
	all_violations.append_array(crit_before_mitigation_violations)

	# Test 10: Seeded RNG produces deterministic results
	var rng_seeding_violations = _test_seeded_rng()
	all_violations.append_array(rng_seeding_violations)

	# Test 11: shield_absorbed on damage_resolved: none, full, and partial absorption
	var shield_absorbed_violations = _test_shield_absorbed_signal()
	all_violations.append_array(shield_absorbed_violations)

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
	combatant.stat_block = _BASELINE_STAT_BLOCK

	# Manually initialize without parent (no _ready call)
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Check baseline values
	var expected_health = 500.0
	var actual_health = combatant.get_base_stat(MobaStatBlock.HEALTH)
	if not is_equal_approx(actual_health, expected_health):
		violations.append(
			(
				"stat_defaults: health mismatch (expected %f, got %f)"
				% [expected_health, actual_health]
			)
		)

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

	MobaRules.seed_crit_rng(42)  # Seed for deterministic results

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._runtime_stat_block.crit_chance = 0.0  # Disable crit for predictable test

	var initial_health = combatant._current_health
	var damage_packet = MobaDamage.new(50.0, MobaDamage.DamageType.PHYSICAL)
	combatant.apply_damage(damage_packet)

	# With armor=30, 50 raw PHYSICAL damage becomes 38.46 (50 * 100 / (100 + 30))
	var expected_health = initial_health - 38.46
	if not _approx_equal(combatant._current_health, expected_health, 0.01):
		violations.append(
			(
				"damage_reduces_health: expected ~%f, got %f"
				% [expected_health, combatant._current_health]
			)
		)

	if combatant.is_alive() == false:
		violations.append("damage_reduces_health: combatant should still be alive")

	return violations


## Test healing does not exceed maximum
static func _test_healing_capped_at_maximum() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	var max_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Apply damage
	var damage_packet = MobaDamage.new(100.0, MobaDamage.DamageType.PHYSICAL)
	combatant.apply_damage(damage_packet)
	var health_after_damage = combatant._current_health

	# Heal more than damage was applied
	combatant.apply_healing(200.0)

	if not is_equal_approx(combatant._current_health, max_health):
		violations.append(
			"healing_capped: expected %f, got %f" % [max_health, combatant._current_health]
		)

	return violations


## Test death fires exactly once even with back-to-back lethal damage
static func _test_death_fires_once() -> Array[String]:
	var violations: Array[String] = []

	MobaRules.seed_crit_rng(42)  # Seed for deterministic results

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._runtime_stat_block.crit_chance = 0.0  # Disable crit for predictable test

	# _has_died is only set once the sibling state machine's DEAD transition
	# actually succeeds (#241 review fix), so a state machine parent is
	# required here -- a combatant with no parent can never fire death.
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"
	parent.add_child(combatant)

	var death_count = 0
	combatant.health_changed.connect(
		func(current: float, _maximum: float):
			if current <= 0.0 and not combatant.has_died():
				# This signal will fire before _has_died is set
				pass
	)

	# Apply first lethal damage.
	# Use 1000 raw to ensure lethal even with armor mitigation
	var lethal_damage = MobaDamage.new(1000.0, MobaDamage.DamageType.PHYSICAL)
	combatant.apply_damage(lethal_damage)
	if not combatant.has_died():
		violations.append("death_fires_once: first damage should have killed")

	# Apply second lethal damage
	var first_death_flag = combatant.has_died()
	var second_lethal = MobaDamage.new(100.0, MobaDamage.DamageType.PHYSICAL)
	combatant.apply_damage(second_lethal)

	if combatant.has_died() != first_death_flag:
		violations.append("death_fires_once: death flag should not change on second damage")

	parent.queue_free()
	return violations


## Test stat block is duplicated, not shared
static func _test_stat_block_duplicated() -> Array[String]:
	var violations: Array[String] = []

	# Create two combatants with the same stat block resource
	var combatant1 = MobaCombatant.new()
	combatant1.stat_block = _BASELINE_STAT_BLOCK
	combatant1._runtime_stat_block = combatant1.stat_block.duplicate()
	combatant1._current_health = combatant1._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	var combatant2 = MobaCombatant.new()
	combatant2.stat_block = _BASELINE_STAT_BLOCK
	combatant2._runtime_stat_block = combatant2.stat_block.duplicate()
	combatant2._current_health = combatant2._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Mutate one combatant's runtime block
	combatant1._runtime_stat_block.armor = 999

	# Check that the other combatant and the baseline resource are unaffected
	var baseline_armor = _BASELINE_STAT_BLOCK.get_stat_value(MobaStatBlock.ARMOR)
	var combatant2_armor = combatant2._runtime_stat_block.get_stat_value(MobaStatBlock.ARMOR)

	if combatant2_armor == 999:
		violations.append("duplication: combatant2's stat block was modified")

	if baseline_armor == 999:
		violations.append("duplication: baseline resource was modified")

	return violations


## Test 50 raw PHYSICAL against 50 armor reduces health by 33.33 (within 0.01)
static func _test_physical_armor_mitigation() -> Array[String]:
	var violations: Array[String] = []

	MobaRules.seed_crit_rng(42)  # Seed for deterministic results

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._runtime_stat_block.armor = 50  # Override armor
	combatant._runtime_stat_block.crit_chance = 0.0  # Disable crit for this test

	var initial_health = combatant._current_health

	# 50 raw PHYSICAL damage vs 50 armor should result in 33.33 final damage
	# Formula: 50 * (100 / (100 + 50)) = 50 * 0.6667 = 33.33
	var damage_packet = MobaDamage.new(50.0, MobaDamage.DamageType.PHYSICAL)
	combatant.apply_damage(damage_packet)

	var expected_health = initial_health - 33.33
	if not _approx_equal(combatant._current_health, expected_health, 0.01):
		violations.append(
			(
				"physical_armor_mitigation: expected ~%f, got %f"
				% [expected_health, combatant._current_health]
			)
		)

	return violations


## Test MAGICAL is mitigated by magic_resistance, PHYSICAL by armor
static func _test_damage_type_routing() -> Array[String]:
	var violations: Array[String] = []

	MobaRules.seed_crit_rng(42)  # Seed for deterministic results

	var combatant1 = MobaCombatant.new()
	combatant1.stat_block = _BASELINE_STAT_BLOCK
	combatant1._runtime_stat_block = combatant1.stat_block.duplicate()
	combatant1._current_health = combatant1._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant1._runtime_stat_block.armor = 50
	combatant1._runtime_stat_block.magic_resistance = 0
	combatant1._runtime_stat_block.crit_chance = 0.0

	var combatant2 = MobaCombatant.new()
	combatant2.stat_block = _BASELINE_STAT_BLOCK
	combatant2._runtime_stat_block = combatant2.stat_block.duplicate()
	combatant2._current_health = combatant2._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant2._runtime_stat_block.armor = 0
	combatant2._runtime_stat_block.magic_resistance = 50
	combatant2._runtime_stat_block.crit_chance = 0.0

	var initial_health1 = combatant1._current_health
	var initial_health2 = combatant2._current_health

	# Apply 100 raw PHYSICAL to combatant1 (with armor=50)
	var physical_damage = MobaDamage.new(100.0, MobaDamage.DamageType.PHYSICAL)
	combatant1.apply_damage(physical_damage)

	# Apply 100 raw MAGICAL to combatant2 (with magic_resistance=50)
	var magical_damage = MobaDamage.new(100.0, MobaDamage.DamageType.MAGICAL)
	combatant2.apply_damage(magical_damage)

	# Both should receive 66.67 damage (100 * 100 / (100 + 50))
	var expected_reduction = 66.67

	var actual_reduction1 = initial_health1 - combatant1._current_health
	var actual_reduction2 = initial_health2 - combatant2._current_health

	if not _approx_equal(actual_reduction1, expected_reduction, 0.01):
		violations.append(
			(
				"damage_type_routing: PHYSICAL mitigation expected %f, got %f"
				% [expected_reduction, actual_reduction1]
			)
		)

	if not _approx_equal(actual_reduction2, expected_reduction, 0.01):
		violations.append(
			(
				"damage_type_routing: MAGICAL mitigation expected %f, got %f"
				% [expected_reduction, actual_reduction2]
			)
		)

	return violations


## Test TRUE damage ignores defenses and penetration entirely
static func _test_true_damage_ignores_defenses() -> Array[String]:
	var violations: Array[String] = []

	MobaRules.seed_crit_rng(42)  # Seed for deterministic results

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._runtime_stat_block.armor = 100
	combatant._runtime_stat_block.magic_resistance = 100
	combatant._runtime_stat_block.crit_chance = 0.0

	var initial_health = combatant._current_health

	# Apply 50 raw TRUE damage with non-zero penetration (should have no effect)
	var true_damage_packet = MobaDamage.new(
		50.0, MobaDamage.DamageType.TRUE, null, false, 20.0, 0.3  # flat_pen  # percent_pen
	)
	combatant.apply_damage(true_damage_packet)

	# Health should be reduced by exactly 50 (no mitigation, no penetration calc)
	var expected_health = initial_health - 50.0
	if not is_equal_approx(combatant._current_health, expected_health):
		violations.append(
			(
				"true_damage_ignores_defenses: expected %f, got %f"
				% [expected_health, combatant._current_health]
			)
		)

	return violations


## Test crit multiplier applied before mitigation
static func _test_crit_before_mitigation() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._runtime_stat_block.armor = 30

	# Crit is the attacker's statistic, so the crit stats go on a separate
	# attacker combatant passed as MobaDamage.source. Setting them on the victim
	# would prove nothing: apply_damage() reads them off the source.
	var attacker = MobaCombatant.new()
	attacker.stat_block = _BASELINE_STAT_BLOCK
	attacker._runtime_stat_block = attacker.stat_block.duplicate()
	attacker._runtime_stat_block.crit_chance = 1.0  # Guaranteed crit
	attacker._runtime_stat_block.crit_damage = 2.0

	var initial_health = combatant._current_health

	# Seed RNG for deterministic crit
	MobaRules.seed_crit_rng(42)

	# Apply 50 raw damage from an attacker who always crits
	var damage_packet = MobaDamage.new(50.0, MobaDamage.DamageType.PHYSICAL, attacker)
	combatant.apply_damage(damage_packet)

	# Expected: 50 * 2.0 (crit) * (100 / (100 + 30)) = 100 * 0.7692 = 76.92
	var expected_health = initial_health - 76.92
	if not _approx_equal(combatant._current_health, expected_health, 0.01):
		violations.append(
			(
				"crit_before_mitigation: expected %f, got %f"
				% [expected_health, combatant._current_health]
			)
		)

	return violations


## Test seeded RNG produces deterministic crit results
static func _test_seeded_rng() -> Array[String]:
	var violations: Array[String] = []

	# First run with seed 123
	MobaRules.seed_crit_rng(123)
	var combatant1 = MobaCombatant.new()
	combatant1.stat_block = _BASELINE_STAT_BLOCK
	combatant1._runtime_stat_block = combatant1.stat_block.duplicate()
	combatant1._current_health = combatant1._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	var attacker1 = MobaCombatant.new()
	attacker1.stat_block = _BASELINE_STAT_BLOCK
	attacker1._runtime_stat_block = attacker1.stat_block.duplicate()
	attacker1._runtime_stat_block.crit_chance = 0.5

	var initial_health1 = combatant1._current_health
	var damage1 = MobaDamage.new(100.0, MobaDamage.DamageType.PHYSICAL, attacker1)
	combatant1.apply_damage(damage1)
	var reduction1 = initial_health1 - combatant1._current_health

	# Second run with same seed
	MobaRules.seed_crit_rng(123)
	var combatant2 = MobaCombatant.new()
	combatant2.stat_block = _BASELINE_STAT_BLOCK
	combatant2._runtime_stat_block = combatant2.stat_block.duplicate()
	combatant2._current_health = combatant2._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	var attacker2 = MobaCombatant.new()
	attacker2.stat_block = _BASELINE_STAT_BLOCK
	attacker2._runtime_stat_block = attacker2.stat_block.duplicate()
	attacker2._runtime_stat_block.crit_chance = 0.5

	var initial_health2 = combatant2._current_health
	var damage2 = MobaDamage.new(100.0, MobaDamage.DamageType.PHYSICAL, attacker2)
	combatant2.apply_damage(damage2)
	var reduction2 = initial_health2 - combatant2._current_health

	# Results should be identical
	if not _approx_equal(reduction1, reduction2, 0.0001):
		violations.append(
			(
				"seeded_rng: different results for same seed (run1=%f, run2=%f)"
				% [reduction1, reduction2]
			)
		)

	return violations


## Test loadout is duplicated, not shared
static func _test_loadout_duplicated() -> Array[String]:
	var violations: Array[String] = []

	# Create a weapon and loadout to assign to both combatants
	var weapon := MobaWeapon.new()
	weapon.damage = 10.0
	weapon.attack_range = 5.0
	weapon.wind_up = 0.1
	weapon.recovery = 0.2
	weapon.damage_type = MobaDamage.DamageType.PHYSICAL

	var shared_loadout := MobaLoadout.new()
	shared_loadout.weapon = weapon
	shared_loadout.set_action_slot(1, "test_ability")
	shared_loadout.set_passive_slot("test_passive")

	# Assign the same loadout instance to two combatants
	var combatant1 = MobaCombatant.new()
	combatant1.stat_block = _BASELINE_STAT_BLOCK
	combatant1._runtime_stat_block = combatant1.stat_block.duplicate()
	combatant1._current_health = combatant1._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant1.loadout = shared_loadout

	var combatant2 = MobaCombatant.new()
	combatant2.stat_block = _BASELINE_STAT_BLOCK
	combatant2._runtime_stat_block = combatant2.stat_block.duplicate()
	combatant2._current_health = combatant2._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant2.loadout = shared_loadout

	# Check that the two combatants have different loadout instances
	if combatant1.loadout == combatant2.loadout:
		violations.append("loadout_duplicated: combatants should have different loadout instances")

	# Check that neither is the original shared_loadout
	if combatant1.loadout == shared_loadout:
		violations.append("loadout_duplicated: combatant1's loadout should not be the original")

	if combatant2.loadout == shared_loadout:
		violations.append("loadout_duplicated: combatant2's loadout should not be the original")

	# Action slot mutations through one combatant reach neither the other
	# combatant nor the resource that was assigned to both
	combatant1.loadout.set_action_slot(2, "mutated_ability")
	if combatant2.get_action_slot_ability_id(2) == &"mutated_ability":
		violations.append("loadout_duplicated: action slot mutation leaked to combatant2")

	if shared_loadout.get_action_slot(2) == "mutated_ability":
		violations.append("loadout_duplicated: action slot mutation leaked to original")

	# Passive slot mutations are isolated the same way
	combatant1.loadout.set_passive_slot("mutated_passive")
	if combatant2.get_passive_slot_id() == &"mutated_passive":
		violations.append("loadout_duplicated: passive slot mutation leaked to combatant2")

	if shared_loadout.get_passive_slot() == "mutated_passive":
		violations.append("loadout_duplicated: passive slot mutation leaked to original")

	# The weapon is deliberately shared across the duplicates, not deep-copied
	if combatant1.loadout.get_weapon() != combatant2.loadout.get_weapon():
		violations.append("loadout_duplicated: weapon should be shared across duplicates")

	if combatant1.loadout.get_weapon() != weapon:
		violations.append("loadout_duplicated: weapon should be the assigned instance")

	# Assigning null must not error and must leave the loadout null
	combatant1.loadout = null
	if combatant1.loadout != null:
		violations.append("loadout_duplicated: null assignment should leave loadout null")

	return violations


## Test shield_absorbed on damage_resolved: no shield, full absorption, partial absorption.
##
## shield_absorbed is defined against the post-mitigation "final" amount (see
## MobaCombatant.apply_damage(): pre_shield_final - post_shield_final), so TRUE
## damage is used throughout to keep raw == final and isolate the shield math.
static func _test_shield_absorbed_signal() -> Array[String]:
	var violations: Array[String] = []

	MobaRules.seed_crit_rng(42)  # Seed for deterministic results

	# Case (a): no shield active -- shield_absorbed should be 0.0
	var combatant_no_shield = MobaCombatant.new()
	combatant_no_shield.stat_block = _BASELINE_STAT_BLOCK
	combatant_no_shield._runtime_stat_block = combatant_no_shield.stat_block.duplicate()
	combatant_no_shield._current_health = (combatant_no_shield._runtime_stat_block.get_stat_value(
		MobaStatBlock.HEALTH
	))
	combatant_no_shield._runtime_stat_block.crit_chance = 0.0

	var absorbed_no_shield := -1.0
	combatant_no_shield.damage_resolved.connect(
		func(_raw: float, _final: float, _dtype: int, _crit: bool, _src, absorbed: float):
			absorbed_no_shield = absorbed
	)

	var initial_health_no_shield = combatant_no_shield._current_health
	combatant_no_shield.apply_damage(MobaDamage.new(50.0, MobaDamage.DamageType.TRUE))

	if not is_equal_approx(absorbed_no_shield, 0.0):
		violations.append(
			(
				"shield_absorbed_signal: no shield active should report 0.0, got %f"
				% absorbed_no_shield
			)
		)

	if not is_equal_approx(combatant_no_shield._current_health, initial_health_no_shield - 50.0):
		violations.append("shield_absorbed_signal: no-shield health should drop by the full hit")

	# Case (b): a shield that fully absorbs the hit -- shield_absorbed equals the
	# post-mitigation final damage, and health does not change.
	var combatant_full = MobaCombatant.new()
	combatant_full.stat_block = _BASELINE_STAT_BLOCK
	combatant_full._runtime_stat_block = combatant_full.stat_block.duplicate()
	combatant_full._current_health = combatant_full._runtime_stat_block.get_stat_value(
		MobaStatBlock.HEALTH
	)
	combatant_full._runtime_stat_block.crit_chance = 0.0
	combatant_full.apply_shield(100.0, &"test_shield", 10.0)

	var absorbed_full := -1.0
	combatant_full.damage_resolved.connect(
		func(_raw: float, _final: float, _dtype: int, _crit: bool, _src, absorbed: float):
			absorbed_full = absorbed
	)

	var initial_health_full = combatant_full._current_health
	combatant_full.apply_damage(MobaDamage.new(50.0, MobaDamage.DamageType.TRUE))

	if not is_equal_approx(absorbed_full, 50.0):
		violations.append(
			"shield_absorbed_signal: full absorption should report 50.0, got %f" % absorbed_full
		)

	if not is_equal_approx(combatant_full._current_health, initial_health_full):
		violations.append("shield_absorbed_signal: fully-shielded hit should not reduce health")

	# Case (c): a shield that only partially absorbs -- shield_absorbed equals the
	# shield's remaining capacity, and the remainder reduces health.
	var combatant_partial = MobaCombatant.new()
	combatant_partial.stat_block = _BASELINE_STAT_BLOCK
	combatant_partial._runtime_stat_block = combatant_partial.stat_block.duplicate()
	combatant_partial._current_health = combatant_partial._runtime_stat_block.get_stat_value(
		MobaStatBlock.HEALTH
	)
	combatant_partial._runtime_stat_block.crit_chance = 0.0
	combatant_partial.apply_shield(20.0, &"test_shield", 10.0)

	var absorbed_partial := -1.0
	combatant_partial.damage_resolved.connect(
		func(_raw: float, _final: float, _dtype: int, _crit: bool, _src, absorbed: float):
			absorbed_partial = absorbed
	)

	var initial_health_partial = combatant_partial._current_health
	combatant_partial.apply_damage(MobaDamage.new(50.0, MobaDamage.DamageType.TRUE))

	if not is_equal_approx(absorbed_partial, 20.0):
		violations.append(
			(
				"shield_absorbed_signal: partial absorption should report 20.0, got %f"
				% absorbed_partial
			)
		)

	var expected_health_partial = initial_health_partial - (50.0 - 20.0)
	if not is_equal_approx(combatant_partial._current_health, expected_health_partial):
		violations.append(
			(
				"shield_absorbed_signal: partial absorption should reduce health by the"
				+ " unabsorbed remainder"
			)
		)

	return violations
