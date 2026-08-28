## Test suite for targeting resolution and valid-target filtering.
class_name TargetingTest
extends RefCounted

const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const MobaTargeting = preload("res://rules/targeting/moba_targeting.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")


## Minimal CharacterSheet mock for testing (avoids extraction contract violation)
class _TestCharacterSheet:
	extends Resource
	var character_name: String = "Test"
	var max_hp: int = 100
	var current_hp: int = 100

static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(await _test_area_hits_hostile_in_radius())
	all_violations.append_array(await _test_area_excludes_caster_by_default())
	all_violations.append_array(await _test_area_includes_caster_when_affects_caster_true())
	all_violations.append_array(await _test_area_excludes_friendly_bystander())
	all_violations.append_array(await _test_ground_resolves_at_aimed_point())
	all_violations.append_array(await _test_ground_target_moved_away_not_hit())
	all_violations.append_array(_test_ground_instant_resolves_same_as_delayed())
	all_violations.append_array(_test_graceful_degradation_no_world())

	if all_violations.is_empty():
		return true

	printerr("\n=== Targeting Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


static func _create_combatant() -> MobaCombatant:
	var combatant = MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	return combatant


## Create a StaticBody3D fixture with Actor parent for physics testing.
## Returns the body (StaticBody3D) node; caller must queue_free() the actor (body.owner).
static func _make_physics_fixture(tree: SceneTree, hostile: bool) -> Node3D:
	# Create the Actor
	var actor = Actor.new()
	actor.owner_id = randi() % 1000
	actor.hostile = hostile
	# Set character_sheet before adding to tree (required by Actor._ready)
	actor.character_sheet = _TestCharacterSheet.new()

	# Create the physics body (StaticBody3D for tests)
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1

	# Add collision shape to body
	var collision = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.5
	collision.shape = sphere
	body.add_child(collision)

	# Add combatant to body
	var combatant = _create_combatant()
	body.add_child(combatant)

	# Attach body to actor, actor to tree
	actor.add_child(body)
	tree.root.add_child(actor)

	return body


static func _test_area_hits_hostile_in_radius() -> Array[String]:
	var violations: Array[String] = []
	var tree = Engine.get_main_loop()

	var caster = _make_physics_fixture(tree, true)
	caster.position = Vector3.ZERO

	var inside = _make_physics_fixture(tree, false)
	inside.position = Vector3(1.0, 0, 0)

	var outside = _make_physics_fixture(tree, false)
	outside.position = Vector3(10.0, 0, 0)

	await tree.physics_frame

	var ability = MobaAbility.new()
	ability.id = "area_test_1"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 3.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.HOSTILE
	ability.affects_caster = false

	var targets = MobaTargeting.resolve_area(caster, ability)

	if targets.size() != 1:
		violations.append("area_inside: expected 1, got %d" % targets.size())
	elif not targets.has(inside):
		violations.append("area_inside: inside should be hit")

	if targets.has(outside):
		violations.append("area_inside: outside should not be hit")

	caster.owner.queue_free()
	inside.owner.queue_free()
	outside.owner.queue_free()
	return violations


static func _test_area_excludes_caster_by_default() -> Array[String]:
	var violations: Array[String] = []
	var tree = Engine.get_main_loop()

	var caster = _make_physics_fixture(tree, true)
	caster.position = Vector3.ZERO

	await tree.physics_frame

	var ability = MobaAbility.new()
	ability.id = "area_test_2"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 5.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.ANY
	ability.affects_caster = false

	var targets = MobaTargeting.resolve_area(caster, ability)

	if targets.has(caster):
		violations.append("area_exclude_caster: caster excluded by default")

	caster.owner.queue_free()
	return violations


static func _test_area_includes_caster_when_affects_caster_true() -> Array[String]:
	var violations: Array[String] = []
	var tree = Engine.get_main_loop()

	var caster = _make_physics_fixture(tree, true)
	caster.position = Vector3.ZERO

	await tree.physics_frame

	var ability = MobaAbility.new()
	ability.id = "area_test_3"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 5.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.ANY
	ability.affects_caster = true

	var targets = MobaTargeting.resolve_area(caster, ability)

	if not targets.has(caster):
		violations.append("area_include_caster: caster included when affects_caster=true")

	caster.owner.queue_free()
	return violations


static func _test_area_excludes_friendly_bystander() -> Array[String]:
	var violations: Array[String] = []
	var tree = Engine.get_main_loop()

	var caster = _make_physics_fixture(tree, true)
	caster.position = Vector3.ZERO

	var friendly = _make_physics_fixture(tree, true)
	friendly.position = Vector3(1.0, 0, 0)

	await tree.physics_frame

	var ability = MobaAbility.new()
	ability.id = "area_test_4"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 5.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.HOSTILE
	ability.affects_caster = false

	var targets = MobaTargeting.resolve_area(caster, ability)

	if targets.has(friendly):
		violations.append("area_exclude_friendly: friendly excluded from HOSTILE")

	caster.owner.queue_free()
	friendly.owner.queue_free()
	return violations


static func _test_ground_resolves_at_aimed_point() -> Array[String]:
	var violations: Array[String] = []
	var tree = Engine.get_main_loop()

	var caster = _make_physics_fixture(tree, true)
	caster.position = Vector3.ZERO

	var ground_point = Vector3(5.0, 0, 0)

	var at_point = _make_physics_fixture(tree, false)
	at_point.position = ground_point

	var near_caster = _make_physics_fixture(tree, false)
	near_caster.position = Vector3(0.5, 0, 0)

	await tree.physics_frame

	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")
	var ability = MobaAbilityLibrary.get_ability(&"whirlwind")

	if ability == null:
		violations.append("ground_at_point: whirlwind not loaded")
		caster.owner.queue_free()
		at_point.owner.queue_free()
		near_caster.owner.queue_free()
		MobaAbilityLibrary._reset()
		return violations

	var targets = MobaTargeting.resolve_ground(caster, ground_point, ability)

	if targets.size() == 0:
		violations.append("ground_at_point: expected targets at point, got 0")
	elif not targets.has(at_point):
		violations.append("ground_at_point: should hit at point")

	if targets.has(near_caster):
		violations.append("ground_at_point: should not hit near caster")

	caster.owner.queue_free()
	at_point.owner.queue_free()
	near_caster.owner.queue_free()
	MobaAbilityLibrary._reset()
	return violations


static func _test_ground_target_moved_away_not_hit() -> Array[String]:
	var violations: Array[String] = []
	var tree = Engine.get_main_loop()

	var caster = _make_physics_fixture(tree, true)
	caster.position = Vector3.ZERO

	var ground_point = Vector3(5.0, 0, 0)

	var target = _make_physics_fixture(tree, false)
	target.position = ground_point

	await tree.physics_frame

	# Move away
	target.position = Vector3(10.0, 0, 0)
	await tree.physics_frame

	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")
	var ability = MobaAbilityLibrary.get_ability(&"whirlwind")

	if ability == null:
		violations.append("ground_moved: whirlwind not loaded")
		caster.owner.queue_free()
		target.owner.queue_free()
		MobaAbilityLibrary._reset()
		return violations

	var targets = MobaTargeting.resolve_ground(caster, ground_point, ability)

	if targets.has(target):
		violations.append("ground_moved: moved target not hit")

	caster.owner.queue_free()
	target.owner.queue_free()
	MobaAbilityLibrary._reset()
	return violations


static func _test_ground_instant_resolves_same_as_delayed() -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")
	var ability = MobaAbilityLibrary.get_ability(&"whirlwind")

	if ability == null:
		violations.append("ground_instant: whirlwind not loaded")
		return violations

	if ability.cast_time != 0.0:
		violations.append("ground_instant: cast_time should be 0")

	if ability.targeting_type != MobaAbility.TargetingType.AREA and ability.targeting_type != MobaAbility.TargetingType.GROUND:
		violations.append("ground_instant: should be AREA or GROUND")

	MobaAbilityLibrary._reset()
	return violations


static func _test_graceful_degradation_no_world() -> Array[String]:
	var violations: Array[String] = []

	var bare_node = Node3D.new()
	var combatant = _create_combatant()
	bare_node.add_child(combatant)

	var ability = MobaAbility.new()
	ability.id = "graceful_test"
	ability.targeting_type = MobaAbility.TargetingType.AREA
	ability.area_radius = 5.0
	ability.target_allegiance = MobaAbility.TargetAllegiance.ANY
	ability.affects_caster = false

	var targets = MobaTargeting.resolve_area(bare_node, ability)

	if targets.size() != 0:
		violations.append("graceful_degrade: should return empty")

	return violations
