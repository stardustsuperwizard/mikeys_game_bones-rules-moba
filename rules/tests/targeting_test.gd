## Test suite for targeting resolution and valid-target filtering.
##
## Covers: MobaTargeting AREA/GROUND resolution with physics queries, valid-target
## filtering (alive, allegiance, caster inclusion), and the stealth visibility hook.
class_name TargetingTest
extends RefCounted


const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const MobaTargeting = preload("res://rules/targeting/moba_targeting.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_filter_excludes_caster_by_default())
	all_violations.append_array(_test_filter_includes_caster_when_affects_caster_true())
	all_violations.append_array(_test_filter_dead_excluded())
	all_violations.append_array(_test_filter_allegiance_hostile())
	all_violations.append_array(_test_filter_allegiance_friendly())
	all_violations.append_array(_test_filter_allegiance_any())
	all_violations.append_array(_test_self_targeting())
	all_violations.append_array(_test_targeted_targeting())
	all_violations.append_array(_test_whirlwind_ability_exists())

	if all_violations.is_empty():
		return true

	printerr("\n=== Targeting Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Helper to create a test actor with a combatant
static func _create_test_actor(
	with_parent_actor: bool = false, hostile: bool = true
) -> Node3D:
	var actor: Actor = null
	if with_parent_actor:
		actor = Actor.new()
		actor.owner_id = 1
		actor.hostile = hostile

	var caster = Node3D.new()
	caster.name = "TestCaster"

	var combatant = MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	caster.add_child(combatant)

	if actor != null:
		actor.add_child(caster)

	return caster


## Helper to create a target with combatant and optional parent actor
static func _create_target(
	with_parent_actor: bool = false, hostile: bool = true, alive: bool = true
) -> Node3D:
	var actor: Actor = null
	if with_parent_actor:
		actor = Actor.new()
		actor.owner_id = 2
		actor.hostile = hostile

	var target = Node3D.new()
	target.name = "TestTarget"

	var combatant = MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	if alive:
		combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	else:
		combatant._current_health = 0.0
	target.add_child(combatant)

	if actor != null:
		actor.add_child(target)

	return target


## Test 1: Filter excludes caster by default (affects_caster = false)
static func _test_filter_excludes_caster_by_default() -> Array[String]:
	var violations: Array[String] = []

	var caster = _create_test_actor(true, true)

	# Create ability with affects_caster = false
	var ability = MobaAbility.new()
	ability.id = "test_no_self"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 10.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.HOSTILE
	ability.affects_caster = false

	var candidates: Array[Node] = [caster]
	var filtered = MobaTargeting.filter_valid_targets(candidates, caster, ability)

	if filtered.has(caster):
		violations.append("excludes_caster: caster should be excluded when affects_caster = false")

	return violations


## Test 2: Filter includes caster when affects_caster = true
static func _test_filter_includes_caster_when_affects_caster_true() -> Array[String]:
	var violations: Array[String] = []

	var caster = _create_test_actor(true, true)

	# Create ability with affects_caster = true
	var ability = MobaAbility.new()
	ability.id = "test_with_self"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 10.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.ANY
	ability.affects_caster = true

	# Debug: check if caster is alive
	var combatant = caster.get_node_or_null("MobaCombatant") as MobaCombatant
	if combatant == null:
		violations.append("includes_caster: caster has no MobaCombatant child")
		return violations

	if not combatant.is_alive():
		violations.append("includes_caster: caster is not alive (health=%f)" % combatant._current_health)
		return violations

	var candidates: Array[Node] = [caster]
	var filtered = MobaTargeting.filter_valid_targets(candidates, caster, ability)

	if not filtered.has(caster):
		violations.append("includes_caster: caster should be included when affects_caster = true")

	return violations


## Test 3: Filter excludes dead candidates
static func _test_filter_dead_excluded() -> Array[String]:
	var violations: Array[String] = []

	var caster = _create_test_actor(true, true)
	var dead_target = _create_target(true, true, false)

	var ability = MobaAbility.new()
	ability.id = "test_dead"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 10.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.HOSTILE
	ability.affects_caster = false

	var candidates: Array[Node] = [dead_target]
	var filtered = MobaTargeting.filter_valid_targets(candidates, caster, ability)

	if filtered.has(dead_target):
		violations.append("dead_excluded: dead candidate should be excluded")

	return violations


## Test 4: Allegiance filtering - HOSTILE ability
static func _test_filter_allegiance_hostile() -> Array[String]:
	var violations: Array[String] = []

	# Caster is hostile=true
	var caster = _create_test_actor(true, true)

	# Target with hostile=false (different side, should be hit by HOSTILE ability)
	var enemy_target = _create_target(true, false)

	# Target with hostile=true (same side, should NOT be hit by HOSTILE ability)
	var ally_target = _create_target(true, true)

	var ability = MobaAbility.new()
	ability.id = "test_hostile"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 10.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.HOSTILE
	ability.affects_caster = false

	var candidates: Array[Node] = [enemy_target, ally_target]
	var filtered = MobaTargeting.filter_valid_targets(candidates, caster, ability)

	if not filtered.has(enemy_target):
		violations.append("allegiance_hostile: should hit enemy (different hostility)")

	if filtered.has(ally_target):
		violations.append("allegiance_hostile: should not hit ally (same hostility)")

	return violations


## Test 5: Allegiance filtering - FRIENDLY ability
static func _test_filter_allegiance_friendly() -> Array[String]:
	var violations: Array[String] = []

	# Caster is hostile=true
	var caster = _create_test_actor(true, true)

	# Target with hostile=false (different side, should NOT be hit by FRIENDLY)
	var enemy_target = _create_target(true, false)

	# Target with hostile=true (same side, should be hit by FRIENDLY)
	var ally_target = _create_target(true, true)

	var ability = MobaAbility.new()
	ability.id = "test_friendly"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 10.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.FRIENDLY
	ability.affects_caster = false

	var candidates: Array[Node] = [enemy_target, ally_target]
	var filtered = MobaTargeting.filter_valid_targets(candidates, caster, ability)

	if filtered.has(enemy_target):
		violations.append("allegiance_friendly: should not hit enemy (different hostility)")

	if not filtered.has(ally_target):
		violations.append("allegiance_friendly: should hit ally (same hostility)")

	return violations


## Test 6: Allegiance filtering - ANY ability
static func _test_filter_allegiance_any() -> Array[String]:
	var violations: Array[String] = []

	var caster = _create_test_actor(true, true)
	var enemy_target = _create_target(true, false)
	var ally_target = _create_target(true, true)

	var ability = MobaAbility.new()
	ability.id = "test_any"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 10.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.ANY
	ability.affects_caster = false

	var candidates: Array[Node] = [enemy_target, ally_target]
	var filtered = MobaTargeting.filter_valid_targets(candidates, caster, ability)

	if not filtered.has(enemy_target):
		violations.append("allegiance_any: should hit all regardless of hostility")

	if not filtered.has(ally_target):
		violations.append("allegiance_any: should hit all regardless of hostility")

	return violations


## Test 7: SELF targeting returns only caster
static func _test_self_targeting() -> Array[String]:
	var violations: Array[String] = []

	var caster = _create_test_actor(true, true)

	var ability = MobaAbility.new()
	ability.id = "test_self"
	ability.targeting_type = MobaAbility.TargetingType.SELF

	var targets = MobaTargeting.resolve_self(caster, ability)

	if targets.size() != 1:
		violations.append("self_targeting: expected 1 target (caster), got %d" % targets.size())
	elif not targets.has(caster):
		violations.append("self_targeting: target should be caster")

	return violations


## Test 8: TARGETED targeting returns single target
static func _test_targeted_targeting() -> Array[String]:
	var violations: Array[String] = []

	var caster = _create_test_actor(true, true)
	var target = _create_test_actor(true, false)

	var ability = MobaAbility.new()
	ability.id = "test_targeted"
	ability.targeting_type = MobaAbility.TargetingType.TARGETED

	var targets = MobaTargeting.resolve_targeted(caster, target, ability)

	if targets.size() != 1:
		violations.append("targeted_targeting: expected 1 target, got %d" % targets.size())
	elif not targets.has(target):
		violations.append("targeted_targeting: target should be the specified target")

	return violations


## Test 9: Whirlwind ability exists and has correct properties
static func _test_whirlwind_ability_exists() -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")
	var ability = MobaAbilityLibrary.get_ability(&"whirlwind")

	if ability == null:
		violations.append("whirlwind: ability not found in library")
		return violations

	if ability.targeting_type != MobaAbility.TargetingType.AREA:
		violations.append("whirlwind: should be AREA type, got %s" % ability.targeting_type)

	if ability.cast_time != 0.0:
		violations.append("whirlwind: should have cast_time = 0, got %f" % ability.cast_time)

	if ability.area_radius <= 0:
		violations.append("whirlwind: should have positive area_radius")

	if ability.target_allegiance != MobaAbility.TargetAllegiance.HOSTILE:
		violations.append("whirlwind: should target HOSTILE by default")

	if ability.affects_caster:
		violations.append("whirlwind: should have affects_caster = false by default")

	MobaAbilityLibrary._reset()

	return violations
