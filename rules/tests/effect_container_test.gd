## Test suite for MobaEffectContainer and the modifier layer in MobaCombatant.get_stat().
##
## Covers: pinned (base + flat) * (1 + percent) ordering, the four §60 stacking
## policies, shared-duration stacking past the cap, independent source ability
## ids, duration expiry through MobaCombatant.tick(), permanent modifiers,
## lifecycle signals, cache invalidation, invalid-stat rejection, and the
## attack_speed floor.
class_name EffectContainerTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")


static func _approx_equal(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return abs(a - b) < tolerance


## Build a standalone combatant fixture that never enters the scene tree.
static func _make_combatant() -> MobaCombatant:
	var combatant := MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	return combatant


static func _make_modifier(
	stat: String,
	amount: float,
	is_percentage: bool = false,
	duration: float = 0.0,
	stacking: int = MobaStatModifier.Stacking.REFRESH,
	max_stacks: int = 1
) -> MobaStatModifier:
	var modifier := MobaStatModifier.new()
	modifier.stat = stat
	modifier.amount = amount
	modifier.is_percentage = is_percentage
	modifier.duration = duration
	modifier.stacking = stacking
	modifier.max_stacks = max_stacks
	return modifier


## Run the effect container test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_modifier_order())
	all_violations.append_array(_test_refresh())
	all_violations.append_array(_test_stack())
	all_violations.append_array(_test_stack_past_cap_refreshes_duration())
	all_violations.append_array(_test_ignore())
	all_violations.append_array(_test_replace_if_stronger())
	all_violations.append_array(_test_independent_sources())
	all_violations.append_array(_test_expiry())
	all_violations.append_array(_test_permanent_modifier())
	all_violations.append_array(_test_signals())
	all_violations.append_array(_test_cache_invalidation())
	all_violations.append_array(_test_invalid_stat_rejected())
	all_violations.append_array(_test_attack_speed_floor())
	all_violations.append_array(_test_is_debuff_polarity())
	all_violations.append_array(_test_replace_if_stronger_preserves_is_debuff())

	if all_violations.is_empty():
		return true

	printerr("\n=== Effect Container Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Flat applies before percentage: (50 + 20) * 1.5 == 105, not 50 * 1.5 + 20 == 95.
## get_base_stat() keeps returning the unmodified base in the same situation.
static func _test_modifier_order() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()
	container.apply_modifier(_make_modifier("attack_damage", 20.0), &"flat_source")
	container.apply_modifier(_make_modifier("attack_damage", 0.5, true), &"percent_source")

	var value := combatant.get_stat(MobaStatBlock.ATTACK_DAMAGE)
	if not _approx_equal(value, 105.0):
		violations.append("modifier_order: expected 105.0, got %f" % value)

	var base := combatant.get_base_stat(MobaStatBlock.ATTACK_DAMAGE)
	if not _approx_equal(base, 50.0):
		violations.append("modifier_order: get_base_stat expected 50.0, got %f" % base)

	if _approx_equal(base, value):
		violations.append("modifier_order: get_stat and get_base_stat should differ here")

	return violations


## A combatant with no modifiers applied, and REFRESH semantics.
static func _test_refresh() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	if not _approx_equal(combatant.get_stat(MobaStatBlock.ARMOR), 30.0):
		violations.append("refresh: unmodified combatant should return the base value")

	var modifier := _make_modifier("armor", 15.0, false, 5.0, MobaStatModifier.Stacking.REFRESH)
	container.apply_modifier(modifier, &"buff")
	container.tick(2.0)

	if not _approx_equal(container.get_remaining_duration(&"buff", MobaStatBlock.ARMOR), 3.0):
		violations.append("refresh: expected 3.0 remaining before reapplication")

	container.apply_modifier(modifier, &"buff")

	if not _approx_equal(container.get_remaining_duration(&"buff", MobaStatBlock.ARMOR), 5.0):
		violations.append("refresh: duration should reset to 5.0")

	if not _approx_equal(container.get_flat_bonus(MobaStatBlock.ARMOR), 15.0):
		violations.append("refresh: magnitude should be unchanged at 15.0")

	if container.get_stacks(&"buff", MobaStatBlock.ARMOR) != 1:
		violations.append("refresh: exactly one instance should be active")

	return violations


## STACK sums magnitude but never past max_stacks.
static func _test_stack() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()
	var modifier := _make_modifier(
		"attack_speed", 0.02, true, 4.0, MobaStatModifier.Stacking.STACK, 5
	)

	for i in range(7):
		container.apply_modifier(modifier, &"rally")

	var bonus := container.get_percent_bonus(MobaStatBlock.ATTACK_SPEED)
	if not _approx_equal(bonus, 0.10):
		violations.append("stack: expected effective bonus 0.10, got %f" % bonus)

	var stacks := container.get_stacks(&"rally", MobaStatBlock.ATTACK_SPEED)
	if stacks != 5:
		violations.append("stack: expected 5 stacks, got %d" % stacks)

	return violations


## Applications past max_stacks still refresh the single shared duration.
static func _test_stack_past_cap_refreshes_duration() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()
	var modifier := _make_modifier("armor", 2.0, false, 4.0, MobaStatModifier.Stacking.STACK, 2)

	container.apply_modifier(modifier, &"grit")
	container.apply_modifier(modifier, &"grit")
	container.tick(3.0)

	if not _approx_equal(container.get_remaining_duration(&"grit", MobaStatBlock.ARMOR), 1.0):
		violations.append("stack_past_cap: expected 1.0 remaining before the capped reapply")

	# Third application is past the cap: magnitude holds, duration refreshes.
	container.apply_modifier(modifier, &"grit")

	if not _approx_equal(container.get_remaining_duration(&"grit", MobaStatBlock.ARMOR), 4.0):
		violations.append("stack_past_cap: capped application should still refresh duration")

	if not _approx_equal(container.get_flat_bonus(MobaStatBlock.ARMOR), 4.0):
		violations.append("stack_past_cap: magnitude should stay capped at 4.0")

	return violations


## IGNORE makes a second application a no-op while one is active.
static func _test_ignore() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	container.apply_modifier(
		_make_modifier("armor", 10.0, false, 6.0, MobaStatModifier.Stacking.IGNORE), &"ward"
	)
	container.tick(2.0)
	var applied := container.apply_modifier(
		_make_modifier("armor", 99.0, false, 60.0, MobaStatModifier.Stacking.IGNORE), &"ward"
	)

	if applied:
		violations.append("ignore: second application should report false")

	if not _approx_equal(container.get_flat_bonus(MobaStatBlock.ARMOR), 10.0):
		violations.append("ignore: magnitude should be unchanged at 10.0")

	if not _approx_equal(container.get_remaining_duration(&"ward", MobaStatBlock.ARMOR), 4.0):
		violations.append("ignore: duration should be unchanged at 4.0")

	return violations


## REPLACE_IF_STRONGER keeps the greater absolute magnitude and its duration.
static func _test_replace_if_stronger() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()
	var policy := MobaStatModifier.Stacking.REPLACE_IF_STRONGER

	container.apply_modifier(_make_modifier("armor", 10.0, false, 3.0, policy), &"hex")
	container.apply_modifier(_make_modifier("armor", 25.0, false, 8.0, policy), &"hex")

	if not _approx_equal(container.get_flat_bonus(MobaStatBlock.ARMOR), 25.0):
		violations.append("replace_if_stronger: stronger instance should be kept")

	if not _approx_equal(container.get_remaining_duration(&"hex", MobaStatBlock.ARMOR), 8.0):
		violations.append("replace_if_stronger: stronger instance's duration should be taken")

	var applied := container.apply_modifier(
		_make_modifier("armor", 5.0, false, 60.0, policy), &"hex"
	)

	if applied:
		violations.append("replace_if_stronger: weaker application should report false")

	if not _approx_equal(container.get_flat_bonus(MobaStatBlock.ARMOR), 25.0):
		violations.append("replace_if_stronger: weaker application should change nothing")

	if not _approx_equal(container.get_remaining_duration(&"hex", MobaStatBlock.ARMOR), 8.0):
		violations.append("replace_if_stronger: weaker application should not extend duration")

	return violations


## Two different source ability ids on one stat coexist and sum.
static func _test_independent_sources() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	container.apply_modifier(_make_modifier("armor", 10.0), &"brace")
	container.apply_modifier(_make_modifier("armor", 12.0), &"aegis")

	if not container.has_modifier(&"brace", MobaStatBlock.ARMOR):
		violations.append("independent_sources: brace entry missing")

	if not container.has_modifier(&"aegis", MobaStatBlock.ARMOR):
		violations.append("independent_sources: aegis entry missing")

	var value := combatant.get_stat(MobaStatBlock.ARMOR)
	if not _approx_equal(value, 52.0):
		violations.append("independent_sources: expected 52.0, got %f" % value)

	return violations


## Time advances through MobaCombatant.tick(); an expired modifier is removed.
static func _test_expiry() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()
	container.apply_modifier(_make_modifier("attack_damage", 20.0, false, 2.0), &"surge")

	combatant.tick(1.0)
	if not container.has_modifier(&"surge", MobaStatBlock.ATTACK_DAMAGE):
		violations.append("expiry: modifier removed too early")

	combatant.tick(1.5)
	if container.has_modifier(&"surge", MobaStatBlock.ATTACK_DAMAGE):
		violations.append("expiry: modifier should have expired")

	var value := combatant.get_stat(MobaStatBlock.ATTACK_DAMAGE)
	if not _approx_equal(value, 50.0):
		violations.append("expiry: expected base 50.0 after expiry, got %f" % value)

	return violations


## duration == 0.0 is permanent until explicitly removed.
static func _test_permanent_modifier() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()
	container.apply_modifier(_make_modifier("armor", 10.0, false, 0.0), &"sigil")

	for i in range(20):
		combatant.tick(5.0)

	if not container.has_modifier(&"sigil", MobaStatBlock.ARMOR):
		violations.append("permanent_modifier: permanent modifier should still be active")

	if not _approx_equal(combatant.get_stat(MobaStatBlock.ARMOR), 40.0):
		violations.append("permanent_modifier: expected 40.0 armor")

	container.remove_modifiers_from(&"sigil")
	if container.has_modifier(&"sigil", MobaStatBlock.ARMOR):
		violations.append("permanent_modifier: remove_modifiers_from should have removed it")

	return violations


## Each lifecycle signal fires in its own situation.
static func _test_signals() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	var seen := {"applied": false, "refreshed": false, "stacks": false, "expired": false}
	container.effect_applied.connect(
		func(_source: StringName, _stat: StringName): seen["applied"] = true
	)
	container.effect_refreshed.connect(
		func(_source: StringName, _stat: StringName): seen["refreshed"] = true
	)
	container.effect_stacks_changed.connect(
		func(_source: StringName, _stat: StringName, _stacks: int): seen["stacks"] = true
	)
	container.effect_expired.connect(
		func(_source: StringName, _stat: StringName): seen["expired"] = true
	)

	var refresh_modifier := _make_modifier(
		"armor", 10.0, false, 2.0, MobaStatModifier.Stacking.REFRESH
	)
	container.apply_modifier(refresh_modifier, &"buff")
	container.apply_modifier(refresh_modifier, &"buff")

	var stack_modifier := _make_modifier(
		"attack_damage", 5.0, false, 2.0, MobaStatModifier.Stacking.STACK, 3
	)
	container.apply_modifier(stack_modifier, &"rally")
	container.apply_modifier(stack_modifier, &"rally")

	combatant.tick(3.0)

	for key in ["applied", "refreshed", "stacks", "expired"]:
		if not seen[key]:
			violations.append("signals: effect_%s was never emitted" % key)

	return violations


## A cached stat value is invalidated by application and by expiry.
static func _test_cache_invalidation() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	if not _approx_equal(combatant.get_stat(MobaStatBlock.ARMOR), 30.0):
		violations.append("cache_invalidation: expected base armor 30.0 on first read")

	container.apply_modifier(_make_modifier("armor", 10.0, false, 2.0), &"buff")

	if not _approx_equal(combatant.get_stat(MobaStatBlock.ARMOR), 40.0):
		violations.append("cache_invalidation: read after apply should be 40.0")

	combatant.tick(3.0)

	if not _approx_equal(combatant.get_stat(MobaStatBlock.ARMOR), 30.0):
		violations.append("cache_invalidation: read after expiry should be back to 30.0")

	return violations


## An unknown stat name is rejected loudly and stores nothing.
static func _test_invalid_stat_rejected() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	var applied := container.apply_modifier(_make_modifier("attak_damage", 20.0), &"typo_source")

	if applied:
		violations.append("invalid_stat: apply_modifier should return false")

	if container.has_modifier(&"typo_source", &"attak_damage"):
		violations.append("invalid_stat: nothing should have been stored")

	if not _approx_equal(combatant.get_stat(MobaStatBlock.ATTACK_DAMAGE), 50.0):
		violations.append("invalid_stat: get_stat should stay at base 50.0")

	# apply_modifier() calls push_error() on this exact reject path (see
	# moba_effect_container.gd), but GDScript has no supported hook to
	# intercept push_error() from a test script -- there is no signal or
	# override point the engine calls through, only a stderr/log side
	# effect. invalid_stat_message() is the same string apply_modifier()
	# passes to push_error(), so asserting it here is the closest available
	# proxy for "the error names the offending stat and source ability";
	# it does not prove push_error() itself was called.
	var message := MobaEffectContainer.invalid_stat_message(&"attak_damage", &"typo_source")
	if not message.contains("attak_damage") or not message.contains("typo_source"):
		violations.append("invalid_stat: error message must name the stat and the source ability")

	return violations


## attack_speed never drops below the 0.01 floor.
static func _test_attack_speed_floor() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()
	container.apply_modifier(_make_modifier("attack_speed", -5.0), &"cripple")

	var value := combatant.get_stat(MobaStatBlock.ATTACK_SPEED)
	if not _approx_equal(value, 0.01):
		violations.append("attack_speed_floor: expected 0.01, got %f" % value)

	return violations


## is_debuff() correctly tracks and reports buff/debuff polarity.
static func _test_is_debuff_polarity() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	# Apply a buff (is_debuff = false)
	var buff_modifier := _make_modifier("armor", 10.0)
	container.apply_modifier(buff_modifier, &"armor_buff", false)

	# Apply a debuff (is_debuff = true)
	var debuff_modifier := _make_modifier("armor", -5.0)
	container.apply_modifier(debuff_modifier, &"armor_debuff", true)

	# Check buff polarity
	if container.is_debuff(&"armor_buff", MobaStatBlock.ARMOR):
		violations.append("is_debuff_polarity: buff should report is_debuff = false")

	# Check debuff polarity
	if not container.is_debuff(&"armor_debuff", MobaStatBlock.ARMOR):
		violations.append("is_debuff_polarity: debuff should report is_debuff = true")

	# Check absent entry returns false
	if container.is_debuff(&"nonexistent", MobaStatBlock.ARMOR):
		violations.append("is_debuff_polarity: absent entry should return false")

	return violations


## REPLACE_IF_STRONGER preserves is_debuff polarity when replacing an entry.
static func _test_replace_if_stronger_preserves_is_debuff() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()
	var policy := MobaStatModifier.Stacking.REPLACE_IF_STRONGER

	# Test 1: Debuff entry under REPLACE_IF_STRONGER with is_debuff = true
	# Should preserve is_debuff = true after replacement
	var debuff_modifier_weak := _make_modifier("armor", -10.0, false, 3.0, policy)
	container.apply_modifier(debuff_modifier_weak, &"debuff_hex", true)

	if not container.is_debuff(&"debuff_hex", MobaStatBlock.ARMOR):
		violations.append("replace_if_stronger_is_debuff: initial debuff should report is_debuff = true")

	# Apply a stronger debuff with is_debuff = true
	var debuff_modifier_strong := _make_modifier("armor", -25.0, false, 8.0, policy)
	container.apply_modifier(debuff_modifier_strong, &"debuff_hex", true)

	if not container.is_debuff(&"debuff_hex", MobaStatBlock.ARMOR):
		violations.append("replace_if_stronger_is_debuff: replaced debuff should preserve is_debuff = true")

	if not _approx_equal(container.get_flat_bonus(MobaStatBlock.ARMOR), -25.0):
		violations.append("replace_if_stronger_is_debuff: replaced debuff magnitude should be -25.0")

	# Test 2: Buff entry under REPLACE_IF_STRONGER with is_debuff = false
	# Should preserve is_debuff = false after replacement
	var buff_modifier_weak := _make_modifier("attack_damage", 5.0, false, 3.0, policy)
	container.apply_modifier(buff_modifier_weak, &"buff_surge", false)

	if container.is_debuff(&"buff_surge", MobaStatBlock.ATTACK_DAMAGE):
		violations.append("replace_if_stronger_is_debuff: initial buff should report is_debuff = false")

	# Apply a stronger buff with is_debuff = false
	var buff_modifier_strong := _make_modifier("attack_damage", 20.0, false, 8.0, policy)
	container.apply_modifier(buff_modifier_strong, &"buff_surge", false)

	if container.is_debuff(&"buff_surge", MobaStatBlock.ATTACK_DAMAGE):
		violations.append("replace_if_stronger_is_debuff: replaced buff should preserve is_debuff = false")

	# Test 3: Weaker application is rejected and doesn't change is_debuff
	var buff_modifier_weaker := _make_modifier("attack_damage", 3.0, false, 60.0, policy)
	var applied := container.apply_modifier(buff_modifier_weaker, &"buff_surge", false)

	if applied:
		violations.append("replace_if_stronger_is_debuff: weaker application should return false")

	if container.is_debuff(&"buff_surge", MobaStatBlock.ATTACK_DAMAGE):
		violations.append("replace_if_stronger_is_debuff: weaker rejected application should not change is_debuff")

	return violations
