## Test suite for targeting resolution and valid-target filtering.
##
## Covers AREA and GROUND resolution through real PhysicsDirectSpaceState3D
## shape queries, the shared valid-target filter (alive, allegiance, caster
## inclusion), and graceful degradation when no physics world exists.
class_name TargetingTest
extends RefCounted

const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const MobaTargeting = preload("res://rules/targeting/moba_targeting.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## Scenario clusters are spaced this far apart so one scenario's bodies can
## never fall inside another scenario's query radius. Every fixture in the
## suite shares one physics space, so separation is what keeps them independent.
const _CLUSTER_SPACING := 1000.0

## Radius shared by every area/ground ability built here.
const _TEST_RADIUS := 3.0


## Actor stand-in whose _ready() is a no-op.
##
## Actor._ready() dereferences character_sheet, which is statically typed to the
## game-side CharacterSheet -- naming that type from rules/ is exactly the
## outward dependency the extraction contract exists to prevent, and a
## duck-typed stand-in is a parse error (see the note in target_frame_test.gd).
## Other suites dodge this by never adding their Actor to the tree, but a
## physics fixture has to be in the tree to register with the space. Overriding
## _ready() -- deliberately without super() -- lets the fixture live in the tree
## while still being an Actor to get_parent() as Actor, and so to the allegiance
## filter, without rules/ ever naming CharacterSheet.
class _TestActor:
	extends Actor

	func _ready() -> void:
		pass


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(await _test_physics_resolution())
	all_violations.append_array(_test_whirlwind_instant_area_contract())
	all_violations.append_array(_test_graceful_degradation_no_world())

	if all_violations.is_empty():
		return true

	printerr("\n=== Targeting Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


static func _create_combatant() -> MobaCombatant:
	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	return combatant


## Build one physics fixture: an Actor carrying a StaticBody3D that has a
## collision shape and a MobaCombatant. Returns the body, which is what a shape
## query reports as the collider and what the filter sees as a candidate.
static func _make_physics_fixture(tree: SceneTree, hostile: bool, position: Vector3) -> Node3D:
	var actor := _TestActor.new()
	actor.hostile = hostile

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1

	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	collision.shape = sphere
	body.add_child(collision)

	body.add_child(_create_combatant())

	actor.add_child(body)
	tree.root.add_child(actor)

	# global_position requires the node to be inside the tree.
	body.global_position = position
	return body


static func _make_ability(
	id: String, allegiance: int, affects_caster: bool, targeting: int
) -> MobaAbility:
	var ability := MobaAbility.new()
	ability.id = id
	ability.targeting_type = targeting
	ability.area_radius = _TEST_RADIUS
	ability.target_allegiance = allegiance
	ability.affects_caster = affects_caster
	return ability


## Every physics-backed scenario, built and asserted together.
##
## A body added to the tree does not register with the physics space until a
## frame has been processed, so each scenario would otherwise need its own
## await. `godot --headless --quit` only runs a handful of frames before the
## process exits, and a suite that awaits more frames than that stalls forever
## and silently takes the rest of the run with it. Building every fixture up
## front means the whole suite costs two frames: one to register the bodies,
## and one more after the moved-target scenario repositions a body.
static func _test_physics_resolution() -> Array[String]:
	var violations: Array[String] = []

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		violations.append("physics: no SceneTree available")
		return violations

	# The bootstrap autoload's _ready() runs while the scene root is still
	# setting up its children, and add_child() refuses to run during that
	# window ("Parent node is busy setting up children"). Yield once first so
	# the fixtures below actually enter the tree.
	await tree.physics_frame

	var origin_area := Vector3.ZERO
	var origin_caster := Vector3(_CLUSTER_SPACING, 0, 0)
	var origin_affects := Vector3(_CLUSTER_SPACING * 2.0, 0, 0)
	var origin_friendly := Vector3(_CLUSTER_SPACING * 3.0, 0, 0)
	var origin_ground := Vector3(_CLUSTER_SPACING * 4.0, 0, 0)
	var origin_moved := Vector3(_CLUSTER_SPACING * 5.0, 0, 0)

	# Scenario A -- an area ability hits what is inside its radius, not outside.
	var a_caster := _make_physics_fixture(tree, true, origin_area)
	var a_inside := _make_physics_fixture(tree, false, origin_area + Vector3(1.0, 0, 0))
	var a_outside := _make_physics_fixture(tree, false, origin_area + Vector3(10.0, 0, 0))

	# Scenario B -- the caster is excluded by default.
	var b_caster := _make_physics_fixture(tree, true, origin_caster)
	var b_other := _make_physics_fixture(tree, false, origin_caster + Vector3(1.0, 0, 0))

	# Scenario C -- the caster is included when affects_caster is true.
	var c_caster := _make_physics_fixture(tree, true, origin_affects)
	var c_other := _make_physics_fixture(tree, false, origin_affects + Vector3(1.0, 0, 0))

	# Scenario D -- allegiance across all three TargetAllegiance values.
	var d_caster := _make_physics_fixture(tree, true, origin_friendly)
	var d_friend := _make_physics_fixture(tree, true, origin_friendly + Vector3(1.0, 0, 0))
	var d_enemy := _make_physics_fixture(tree, false, origin_friendly + Vector3(1.5, 0, 0))

	# Scenario E -- ground resolution lands at the aimed point, not on the caster.
	var e_point := origin_ground + Vector3(20.0, 0, 0)
	var e_caster := _make_physics_fixture(tree, true, origin_ground)
	var e_near_caster := _make_physics_fixture(tree, false, origin_ground + Vector3(1.0, 0, 0))
	var e_at_point := _make_physics_fixture(tree, false, e_point + Vector3(1.0, 0, 0))

	# Scenario F -- a target that leaves the radius before resolution is missed.
	var f_point := origin_moved + Vector3(20.0, 0, 0)
	var f_caster := _make_physics_fixture(tree, true, origin_moved)
	var f_target := _make_physics_fixture(tree, false, f_point + Vector3(1.0, 0, 0))

	# Let the space observe the bodies just added.
	await tree.physics_frame

	var hostile_area := _make_ability(
		"area_hostile", MobaAbility.TargetAllegiance.HOSTILE, false, MobaAbility.TargetingType.AREA
	)

	var a_targets := MobaTargeting.resolve_area(a_caster, hostile_area)
	if not a_targets.has(a_inside):
		violations.append("area_inside: body inside area_radius was not hit")
	if a_targets.has(a_outside):
		violations.append("area_outside: body beyond area_radius was hit")

	var b_targets := MobaTargeting.resolve_area(b_caster, hostile_area)
	if b_targets.has(b_caster):
		violations.append("area_caster: caster hit with affects_caster = false")
	if not b_targets.has(b_other):
		violations.append("area_caster: the non-caster target was not hit")

	var affects_area := _make_ability(
		"area_affects_caster",
		MobaAbility.TargetAllegiance.ANY,
		true,
		MobaAbility.TargetingType.AREA
	)
	var c_targets := MobaTargeting.resolve_area(c_caster, affects_area)
	if not c_targets.has(c_caster):
		violations.append("area_affects_caster: caster missed with affects_caster = true")
	if not c_targets.has(c_other):
		violations.append("area_affects_caster: the other target was not hit")

	var d_targets := MobaTargeting.resolve_area(d_caster, hostile_area)
	if d_targets.has(d_friend):
		violations.append("area_allegiance: HOSTILE ability hit a friendly bystander")
	if not d_targets.has(d_enemy):
		violations.append("area_allegiance: HOSTILE ability missed a hostile target")

	var friendly_area := _make_ability(
		"area_friendly",
		MobaAbility.TargetAllegiance.FRIENDLY,
		false,
		MobaAbility.TargetingType.AREA
	)
	var d_friendly := MobaTargeting.resolve_area(d_caster, friendly_area)
	if not d_friendly.has(d_friend):
		violations.append("area_allegiance: FRIENDLY ability missed a same-side combatant")
	if d_friendly.has(d_enemy):
		violations.append("area_allegiance: FRIENDLY ability hit a hostile combatant")

	var any_area := _make_ability(
		"area_any", MobaAbility.TargetAllegiance.ANY, false, MobaAbility.TargetingType.AREA
	)
	var d_any := MobaTargeting.resolve_area(d_caster, any_area)
	if not d_any.has(d_friend) or not d_any.has(d_enemy):
		violations.append("area_allegiance: ANY ability did not hit both sides")

	var ground_ability := _make_ability(
		"ground_hostile",
		MobaAbility.TargetAllegiance.HOSTILE,
		false,
		MobaAbility.TargetingType.GROUND
	)
	var e_targets := MobaTargeting.resolve_ground(e_caster, e_point, ground_ability)
	if not e_targets.has(e_at_point):
		violations.append("ground_point: target at the aimed point was not hit")
	if e_targets.has(e_near_caster):
		violations.append("ground_point: target near the caster was hit instead")

	# A dead candidate is filtered out even though the shape query still finds it.
	var e_combatant := e_at_point.get_node_or_null("MobaCombatant") as MobaCombatant
	if e_combatant == null:
		violations.append("filter_alive: fixture combatant missing")
	else:
		e_combatant._current_health = 0.0
		if MobaTargeting.resolve_ground(e_caster, e_point, ground_ability).has(e_at_point):
			violations.append("filter_alive: a dead candidate was returned")

	# The moved-target scenario, asserted before and after the move so the
	# "not hit" half cannot pass merely because the query never worked.
	if not MobaTargeting.resolve_ground(f_caster, f_point, ground_ability).has(f_target):
		violations.append("ground_moved: target was not hit before it moved")

	f_target.global_position = f_point + Vector3(50.0, 0, 0)

	# Frame 2: let the space observe the new position.
	await tree.physics_frame

	if MobaTargeting.resolve_ground(f_caster, f_point, ground_ability).has(f_target):
		violations.append("ground_moved: target that left the radius was still hit")

	var fixtures: Array[Node3D] = [
		a_caster,
		a_inside,
		a_outside,
		b_caster,
		b_other,
		c_caster,
		c_other,
		d_caster,
		d_friend,
		d_enemy,
		e_caster,
		e_near_caster,
		e_at_point,
		f_caster,
		f_target,
	]
	for body in fixtures:
		body.get_parent().queue_free()

	return violations


## Whirlwind ships instant (cast_time == 0), so activating it resolves in the
## activation tick rather than through MobaCastTracker's delayed branch.
static func _test_whirlwind_instant_area_contract() -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")
	var ability := MobaAbilityLibrary.get_ability(&"whirlwind")

	if ability == null:
		violations.append("whirlwind: not loaded")
		MobaAbilityLibrary._reset()
		return violations

	if ability.cast_time != 0.0:
		violations.append("whirlwind: should be instant")
	if ability.targeting_type != MobaAbility.TargetingType.AREA:
		violations.append("whirlwind: should be AREA")
	if ability.area_radius != 3.0:
		violations.append("whirlwind: radius should be 3.0")
	if ability.affects_caster:
		violations.append("whirlwind: should not affect the caster")
	if ability.target_allegiance != MobaAbility.TargetAllegiance.HOSTILE:
		violations.append("whirlwind: should be HOSTILE")

	MobaAbilityLibrary._reset()
	return violations


## No physics world means an empty list, not a crash.
static func _test_graceful_degradation_no_world() -> Array[String]:
	var violations: Array[String] = []

	var bare_node := Node3D.new()
	bare_node.add_child(_create_combatant())

	var ability := _make_ability(
		"graceful", MobaAbility.TargetAllegiance.ANY, false, MobaAbility.TargetingType.AREA
	)

	if not MobaTargeting.resolve_area(bare_node, ability).is_empty():
		violations.append("graceful_degrade: expected an empty list outside the tree")

	bare_node.free()
	return violations
