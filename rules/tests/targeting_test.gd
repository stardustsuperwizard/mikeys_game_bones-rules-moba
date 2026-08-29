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
const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaAbilityAction = preload("res://rules/abilities/moba_ability_action.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## Fixture ability for the instant-GROUND producer scenario (Scenario H below):
## cast_time == 0.0, GROUND, area_radius == _TEST_RADIUS.
const _GROUND_ABILITY_FIXTURE := "res://rules/tests/fixtures/abilities/ground_ability.tres"

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


## Build one physics fixture matching the shipped scene layout exactly
## (scenes/enemy/enemy.tscn, scenes/player/player.tscn): Actor(Node) ->
## Body(CharacterBody3D with a CollisionShape3D child), with MobaCombatant as
## a *sibling* of Body -- a direct child of the Actor, not of the collider.
##
## Returns the Actor, which is what production passes as caster
## (MobaAbilityAction.actor) and what a normalised query candidate now is
## (see MobaTargeting._normalize_to_actor()) -- the same node
## MobaAbilityAction._get_combatant() looks up MobaCombatant on.
static func _make_physics_fixture(tree: SceneTree, hostile: bool, position: Vector3) -> Actor:
	var actor := _TestActor.new()
	actor.hostile = hostile

	var body := CharacterBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 1

	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	collision.shape = sphere
	body.add_child(collision)

	actor.add_child(body)
	actor.add_child(_create_combatant())
	tree.root.add_child(actor)

	# global_position requires the node to be inside the tree.
	body.global_position = position
	return actor


## Reposition an Actor fixture built by _make_physics_fixture(). Actor's own
## global_position (the Actor -> Body bridge in actor.gd) is get-only, so a
## move has to land on the Body child, the actual Node3D.
static func _move_physics_fixture(actor: Actor, position: Vector3) -> void:
	(actor.get_node("Body") as Node3D).global_position = position


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


## A caster fixture that is simultaneously a real Actor (for MobaCastContext's
## typed `caster: Actor` field, and for the allegiance filter's `as Actor`
## checks) and a real Node3D inside the tree (so MobaTargeting's physics
## query can find a world through it), but with no "Body" child of its own.
##
## Actor extends Node, not Node3D (see addons/mikeys_game_bones/actors/actor.gd);
## MobaTargeting._get_spatial_anchor() bridges that by falling back to an
## Actor's "Body" child, but this fixture has none, so it has to be Node3D
## itself. Attaching the Actor script to a native Node3D is exactly what
## Godot's set_script() is for -- a script's declared base only has to be an
## ancestor of the object's native class, and Node3D is an ancestor of
## itself. Test-only construction; nothing outside this file relies on it.
## Scenarios A-F use the shipped-scene-shaped _make_physics_fixture() Actor
## (with a real "Body" child) as caster instead; this stand-in exists only
## for G/H, which need MobaCastTracker's re-query and the real activation
## pipeline to reach a physics world through a caster with no Body.
##
## Returns Node (not Node3D): the static analyzer statically proves Node3D and
## Actor incompatible -- they are unrelated native siblings under Node -- and
## refuses to compile a call that binds one where the other is expected, even
## though the set_script() swap above makes it valid at runtime. Declaring the
## return type as their common ancestor is what lets callers hand this to
## MobaCastContext.new()'s `caster: Actor` parameter at all.
static func _make_ground_caster(tree: SceneTree, position: Vector3) -> Node:
	var caster := Node3D.new()
	caster.set_script(_TestActor)
	tree.root.add_child(caster)
	caster.position = position
	return caster


## _make_ground_caster() plus a MobaCombatant and MobaStateMachine child,
## matching the shape MobaAbilityAction.execute() expects
## (get_node_or_null("MobaCombatant") / ("MobaStateMachine")) -- needed to drive
## the instant-GROUND scenario through the real activation pipeline, legality
## checks included, rather than calling MobaCombatant.start_cast() directly the
## way the delayed scenario does.
static func _make_ground_actor_caster(tree: SceneTree, position: Vector3) -> Dictionary:
	var caster := _make_ground_caster(tree, position)
	var combatant := _create_combatant()
	caster.add_child(combatant)
	var state_machine := MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	caster.add_child(state_machine)
	return {"caster": caster, "combatant": combatant}


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
	var origin_delayed := Vector3(_CLUSTER_SPACING * 6.0, 0, 0)
	var origin_instant := Vector3(_CLUSTER_SPACING * 7.0, 0, 0)

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

	# Scenario G -- a delayed GROUND cast (cast_time > 0), driven through the
	# real producer (MobaCombatant.start_cast() / tick()) instead of a direct
	# MobaTargeting.resolve_ground() call. g_caster is the Node3D-backed Actor
	# stand-in from _make_ground_caster() so MobaCastTracker's re-query at
	# resolution time can actually reach a physics world.
	var g_point := origin_delayed + Vector3(20.0, 0, 0)
	var g_caster := _make_ground_caster(tree, origin_delayed)
	var g_target := _make_physics_fixture(tree, false, g_point + Vector3(1.0, 0, 0))

	# Scenario H -- an instant GROUND ability (cast_time == 0.0), driven
	# through MobaAbilityAction.execute() -- the real activation-tick producer
	# -- instead of a direct MobaTargeting.resolve_ground() call.
	var h_point := origin_instant + Vector3(20.0, 0, 0)
	var h_actor := _make_ground_actor_caster(tree, origin_instant)
	var h_target := _make_physics_fixture(tree, false, h_point + Vector3(1.0, 0, 0))

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

	# Scenario G (part 1) -- delayed GROUND cast, driven through
	# MobaCombatant.start_cast(). g_pre_move_targets is captured with a real
	# query, before g_target moves, and handed to start_cast() as its
	# resolved_targets argument -- the exact list a mutation that dropped the
	# GROUND branch in MobaCastTracker.start() would fall back to instead of
	# re-querying. It has to actually contain g_target for that fallback to be
	# observable at resolution below.
	var ground_delayed_ability := _make_ability(
		"ground_delayed",
		MobaAbility.TargetAllegiance.HOSTILE,
		false,
		MobaAbility.TargetingType.GROUND
	)
	ground_delayed_ability.cast_time = 1.0
	ground_delayed_ability.base_damage = 10.0
	ground_delayed_ability.damage_type = MobaAbility.DamageType.PHYSICAL

	var g_pre_move_targets := MobaTargeting.resolve_ground(
		g_caster, g_point, ground_delayed_ability
	)
	if not g_pre_move_targets.has(g_target):
		violations.append("ground_delayed: target was not hittable before it moved")

	var g_context := MobaCastContext.new(g_caster, null, Vector3.ZERO, g_point)
	var g_combatant := _create_combatant()
	var g_target_combatant := g_target.get_node_or_null("MobaCombatant") as MobaCombatant
	var g_health_before: float = (
		g_target_combatant._current_health if g_target_combatant != null else 0.0
	)

	g_combatant.start_cast(
		&"ground_delayed",
		ground_delayed_ability,
		g_pre_move_targets,
		ground_delayed_ability.cast_time,
		g_context
	)
	g_combatant.tick(0.5)
	if not g_combatant.is_casting():
		violations.append("ground_delayed: cast should still be in progress mid-delay")

	# Scenario H -- instant GROUND ability, driven through
	# MobaAbilityAction.execute(). h_target never moves; the point of this
	# scenario is that execute() resolves it without any tick() call, in the
	# same activation tick.
	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")
	MobaAbilityLibrary._load_single_ability(_GROUND_ABILITY_FIXTURE)
	var ground_instant_ability := MobaAbilityLibrary.get_ability(&"ground_ability")
	var h_combatant: MobaCombatant = h_actor["combatant"]
	var h_target_combatant := h_target.get_node_or_null("MobaCombatant") as MobaCombatant
	var h_health_before: float = (
		h_target_combatant._current_health if h_target_combatant != null else 0.0
	)

	if ground_instant_ability == null:
		violations.append("ground_instant: fixture failed to load")
	else:
		h_combatant.register_ability(ground_instant_ability)
		var h_context := MobaCastContext.new(h_actor["caster"], null, Vector3.ZERO, h_point)
		var h_action := MobaAbilityAction.new(h_actor["caster"], &"ground_ability", h_context)
		var h_result := h_action.execute()
		if not h_result.success:
			violations.append(
				"ground_instant: activation should succeed, got: %s" % h_result.reason
			)
		if h_combatant.is_casting():
			violations.append("ground_instant: an instant ability should never enter a cast")
		if h_target_combatant == null or h_target_combatant._current_health >= h_health_before:
			violations.append("ground_instant: target should be hit within the activation tick")
	MobaAbilityLibrary._reset()

	_move_physics_fixture(f_target, f_point + Vector3(50.0, 0, 0))
	_move_physics_fixture(g_target, g_point + Vector3(200.0, 0, 0))

	# Frame 2: let the space observe the new positions.
	await tree.physics_frame

	if MobaTargeting.resolve_ground(f_caster, f_point, ground_ability).has(f_target):
		violations.append("ground_moved: target that left the radius was still hit")

	# Scenario G (part 2) -- resolve the delayed cast now that g_target has
	# left area_radius. A mutation that dropped the GROUND branch in
	# MobaCastTracker.start() would fall back to g_pre_move_targets (asserted
	# above to actually contain g_target) instead of re-querying, and would
	# hit g_target anyway -- that is what actually catches that mutation, not
	# merely "g_target was never hit".
	g_combatant.tick(1.0)
	if g_combatant.is_casting():
		violations.append("ground_delayed: cast should have resolved by now")
	if g_target_combatant != null and g_target_combatant._current_health != g_health_before:
		violations.append("ground_delayed: target that left the radius before resolution was hit")

	var fixtures: Array[Actor] = [
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
		g_target,
		h_target,
	]
	for fixture in fixtures:
		fixture.queue_free()
	g_caster.queue_free()
	(h_actor["caster"] as Node3D).queue_free()

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
