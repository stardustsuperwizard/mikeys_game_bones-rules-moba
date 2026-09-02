# Headless integration test for arena team spawn assignment and the arena's
# jumpable vertical feature.
#
# Run with:
#   godot --headless --path . --script tests/arena_team_spawn_test.gd
#
# Covers, in order:
#   - SpawnPoint.team and Actor.team exist and default to 0;
#   - an actor spawned through WorldManager from a team=0 spawn point reports
#     team 0, and one from a team=1 spawn point reports team 1;
#   - the shipped arena exposes at least one team=0 and one team=1 spawn point
#     through WorldManager;
#   - the arena's obstacle blocks the direct ground path between the two
#     marked route points (real raycast against the shipped scene);
#   - a CharacterBody3D matching the player's capsule and movement constants
#     CANNOT cross the obstacle by walking, and CAN cross it by jumping
#     (real physics simulation, not arithmetic about the shape);
#   - the obstacle sits below the jump apex implied by the project's own
#     gravity setting, and the walk-around route is measurably longer than
#     the direct jump route.
#
# This test is NOT wired into tests/test_bootstrap.gd; it is a manual
# integration check matching tests/session_manager_test.gd's own precedent.
extends SceneTree

const _MAIN_SCENE := preload("res://scenes/main.tscn")

# Mirrors of the shipped constants this test measures against. If either of
# these changes, the arena's obstacle has to be re-checked against it -- which
# is the whole point of asserting them here rather than hardcoding an apex.
const _JUMP_VELOCITY := 5.0  # PlayerBody3D.jump_velocity
const _CAPSULE_HEIGHT := 2.0  # scenes/player/player.tscn body capsule
const _CAPSULE_RADIUS := 0.4

const _EXPECTED_CHECKS: Array[String] = [
	"spawn_point.team defaults to 0",
	"actor.team defaults to 0",
	"player spawn point is team 0",
	"enemy spawn point is team 1",
	"actor from team 0 spawn has team 0",
	"actor from team 1 spawn has team 1",
	"arena has team 0 spawn point",
	"arena has team 1 spawn point",
	"arena has vertical obstacle",
	"obstacle height is below jump apex",
	"obstacle blocks the direct ground path",
	"walking alone cannot cross the obstacle",
	"jumping crosses the obstacle",
	"walk-around route is longer than the jump route",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


# A CharacterBody3D driven by the same constants PlayerBody3D/ActorBody3D use.
# The acceptance criterion is about what a body can and cannot do against the
# shipped geometry, so this simulates one rather than reasoning about the box.
class TestBody:
	extends CharacterBody3D

	# An inner class cannot see the outer script's constants, so these repeat
	# PlayerBody3D.jump_velocity and ActorBody3D.SPEED. Keep them in step.
	const JUMP_VELOCITY := 5.0
	const SPEED := 5.0

	var move_direction := Vector3.ZERO
	var jump_queued := false

	func _physics_process(delta: float) -> void:
		# Jump before gravity, only while grounded -- the same order
		# PlayerBody3D uses before delegating to ActorBody3D.
		if jump_queued and is_on_floor():
			velocity.y = JUMP_VELOCITY
			jump_queued = false
		if not is_on_floor():
			velocity += get_gravity() * delta
		velocity.x = move_direction.x * SPEED
		velocity.z = move_direction.z * SPEED
		move_and_slide()


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	_test_team_defaults()
	await _test_arena_spawn_teams()
	await _test_arena_obstacle()

	_finish()


## Actor.team and SpawnPoint.team exist and default to 0.
##
## Read the defaults off a freshly constructed instance -- assigning 0 first
## and then asserting it reads back as 0 would pass no matter what the
## declared default is.
func _test_team_defaults() -> void:
	var spawn_point := SpawnPoint.new()
	if spawn_point.team == 0:
		_pass("spawn_point.team defaults to 0")
	else:
		_fail("SpawnPoint.team should default to 0, got %d" % spawn_point.team)

	var actor := Actor.new()
	if actor.team == 0:
		_pass("actor.team defaults to 0")
	else:
		_fail("Actor.team should default to 0, got %d" % actor.team)
	actor.free()


## Team flows from the SpawnPoint resource through WorldManager onto the Actor.
func _test_arena_spawn_teams() -> void:
	var scene := _MAIN_SCENE.instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	var world_manager := scene.get_node_or_null("WorldManager") as WorldManager
	if world_manager == null:
		_fail("setup: WorldManager not found in scenes/main.tscn")
		scene.queue_free()
		return

	if world_manager.player_spawn_point == null:
		_fail("setup: WorldManager.player_spawn_point is not set")
		scene.queue_free()
		return

	if world_manager.player_spawn_point.team == 0:
		_pass("player spawn point is team 0")
	else:
		_fail("player_spawn_point.team should be 0, got %d" % world_manager.player_spawn_point.team)

	var enemy_spawn_point: SpawnPoint = null
	for spawn_point in world_manager.spawn_points:
		if spawn_point.team == 1:
			enemy_spawn_point = spawn_point
			break

	if enemy_spawn_point != null:
		_pass("enemy spawn point is team 1")
	else:
		_fail("no SpawnPoint with team=1 found in WorldManager.spawn_points")

	# Both team indices must be reachable through WorldManager, not merely
	# present somewhere in resources/.
	var has_team_0 := world_manager.player_spawn_point.team == 0
	var has_team_1 := false
	for spawn_point in world_manager.spawn_points:
		if spawn_point.team == 0:
			has_team_0 = true
		if spawn_point.team == 1:
			has_team_1 = true

	if has_team_0:
		_pass("arena has team 0 spawn point")
	else:
		_fail("arena exposes no team=0 spawn point through WorldManager")

	if has_team_1:
		_pass("arena has team 1 spawn point")
	else:
		_fail("arena exposes no team=1 spawn point through WorldManager")

	# The spawned actors, not just the resources, must carry the team through.
	var spawned_by_team := {}
	for child in world_manager.get_children():
		var actor := child as Actor
		if actor != null:
			spawned_by_team[actor.team] = actor

	if spawned_by_team.has(0):
		_pass("actor from team 0 spawn has team 0")
	else:
		_fail("no spawned Actor reported team 0")

	if spawned_by_team.has(1):
		_pass("actor from team 1 spawn has team 1")
	else:
		_fail("no spawned Actor reported team 1")

	scene.queue_free()
	await process_frame


## The arena's obstacle blocks a walking route and is crossable by jumping.
func _test_arena_obstacle() -> void:
	var scene := _MAIN_SCENE.instantiate()

	# Drop WorldManager before _ready() runs so no actor spawns: the player and
	# the enemy AI would otherwise wander through the same physics space and
	# make the body simulation below flaky. The floor, walls, markers and
	# obstacle -- the geometry actually under test -- are all siblings of it.
	var world_manager := scene.get_node_or_null("WorldManager")
	if world_manager == null:
		_fail("setup: WorldManager not found in scenes/main.tscn")
		scene.queue_free()
		return
	scene.remove_child(world_manager)
	world_manager.free()

	root.add_child(scene)
	await physics_frame
	await physics_frame

	var obstacle := scene.get_node_or_null("LowWall") as StaticBody3D
	if obstacle == null:
		_fail("no obstacle found in the arena (expected a LowWall node)")
		scene.queue_free()
		return
	_pass("arena has vertical obstacle")

	var collision_shape := obstacle.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		_fail("LowWall has no CollisionShape3D child")
		scene.queue_free()
		return

	var box := collision_shape.shape as BoxShape3D
	if box == null:
		_fail("LowWall's collision shape is not a BoxShape3D")
		scene.queue_free()
		return

	# The two marked points the obstacle sits between.
	var marker_a := scene.get_node_or_null("RouteMarkerA") as Marker3D
	var marker_b := scene.get_node_or_null("RouteMarkerB") as Marker3D
	if marker_a == null or marker_b == null:
		_fail("arena is missing RouteMarkerA/RouteMarkerB")
		scene.queue_free()
		return

	var point_a := marker_a.global_position
	var point_b := marker_b.global_position
	var obstacle_height := box.size.y
	var obstacle_centre := collision_shape.global_transform.origin

	# Apex of a jump launched at jump_velocity under the project's own gravity,
	# rather than a hardcoded 1.2 m: v^2 / 2g.
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var jump_apex := (_JUMP_VELOCITY * _JUMP_VELOCITY) / (2.0 * gravity)

	if obstacle_height < jump_apex:
		_pass("obstacle height is below jump apex")
		print(
			(
				"     obstacle %.2f m vs jump apex %.2f m (%.0f%% headroom)"
				% [obstacle_height, jump_apex, (jump_apex / obstacle_height - 1.0) * 100.0]
			)
		)
	else:
		_fail(
			(
				"obstacle height %.2f m is not below the jump apex %.2f m"
				% [obstacle_height, jump_apex]
			)
		)

	var space_state: PhysicsDirectSpaceState3D = obstacle.get_world_3d().direct_space_state
	var ray_height := obstacle_centre.y

	var hit: Dictionary = _cast(space_state, point_a, point_b, ray_height)
	if not hit.is_empty() and hit["collider"] == obstacle:
		_pass("obstacle blocks the direct ground path")
	else:
		var what: String = "nothing" if hit.is_empty() else str(hit["collider"])
		_fail(
			(
				"the direct path from %v to %v is not blocked by LowWall (hit %s)"
				% [point_a, point_b, what]
			)
		)

	# Walk from marker A toward marker B: the body must be stopped on the near
	# side of the obstacle.
	var near_face := obstacle_centre.z + box.size.z * 0.5
	var far_face := obstacle_centre.z - box.size.z * 0.5
	var start := Vector3(point_a.x, _CAPSULE_HEIGHT * 0.5 + 0.05, point_a.z)

	var walk_end := await _simulate(scene, start, -INF)
	if walk_end.z > near_face:
		_pass("walking alone cannot cross the obstacle")
	else:
		_fail(
			(
				"a walking body crossed the obstacle: ended at z=%.2f, near face z=%.2f"
				% [walk_end.z, near_face]
			)
		)

	# Same body, same route, one jump. Launch 2 m short of the near face: early
	# enough to be above the obstacle before contact, late enough to still be
	# above it when clearing the far side. A body that jumps on contact clips
	# the near face instead.
	var jump_end := await _simulate(scene, start, near_face + 2.0)
	if jump_end.z < far_face - _CAPSULE_RADIUS:
		_pass("jumping crosses the obstacle")
	else:
		_fail(
			(
				"a jumping body did not clear the obstacle: ended at z=%.2f, needed z<%.2f"
				% [jump_end.z, far_face - _CAPSULE_RADIUS]
			)
		)

	# Route lengths between the same two marked points. The walk-around passes
	# whichever end of the obstacle is actually reachable -- an end buried in a
	# perimeter wall is not a route, so each candidate is raycast before it
	# counts.
	var direct := _flat(point_a).distance_to(_flat(point_b))
	var floor_extent := _floor_extent(scene)
	var detour := INF
	for side in [-1.0, 1.0]:
		var corner := Vector3(
			obstacle_centre.x + side * (box.size.x * 0.5 + _CAPSULE_RADIUS + 0.1),
			0.0,
			obstacle_centre.z
		)
		# An end is only a route if a body can stand at it: on the floor, and
		# clear of geometry. The obstacle runs into the east perimeter wall, so
		# rounding that end means leaving the arena -- not a walk-around.
		if absf(corner.x) > floor_extent.x or absf(corner.z) > floor_extent.y:
			continue
		if not _standable(space_state, corner):
			continue
		detour = minf(
			detour, _flat(point_a).distance_to(corner) + corner.distance_to(_flat(point_b))
		)

	if detour < INF and detour > direct:
		_pass("walk-around route is longer than the jump route")
		print(
			(
				"     walk-around %.2f m vs direct %.2f m (+%.0f%%)"
				% [detour, direct, (detour / direct - 1.0) * 100.0]
			)
		)
	elif detour == INF:
		_fail("no reachable walk-around route exists between the marked points")
	else:
		_fail(
			"walk-around route %.2f m is not longer than the direct route %.2f m" % [detour, direct]
		)

	scene.queue_free()
	await process_frame


func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)


## Half-extents of the arena floor on X/Z, read from the shipped Floor node.
func _floor_extent(scene: Node) -> Vector2:
	var shape_node := scene.get_node_or_null("Floor/CollisionShape3D") as CollisionShape3D
	var floor_box := shape_node.shape as BoxShape3D if shape_node else null
	if floor_box == null:
		_fail("setup: arena Floor has no BoxShape3D to bound the walk-around by")
		return Vector2.ZERO
	return Vector2(floor_box.size.x, floor_box.size.z) * 0.5


## Whether a player-sized capsule fits at `point` without overlapping anything.
func _standable(space_state: PhysicsDirectSpaceState3D, point: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.height = _CAPSULE_HEIGHT
	capsule.radius = _CAPSULE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(
		Basis.IDENTITY, Vector3(point.x, _CAPSULE_HEIGHT * 0.5 + 0.05, point.z)
	)
	return space_state.intersect_shape(query, 1).is_empty()


func _cast(
	space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, height: float
) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(from.x, height, from.z), Vector3(to.x, height, to.z)
	)
	return space_state.intersect_ray(query)


## Drive a fresh body from `start` toward -Z, jumping once it reaches
## `jump_at_z` (pass -INF to never jump), and return where it ended up.
func _simulate(scene: Node, start: Vector3, jump_at_z: float) -> Vector3:
	var body := TestBody.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = _CAPSULE_HEIGHT
	capsule.radius = _CAPSULE_RADIUS
	var shape_node := CollisionShape3D.new()
	shape_node.shape = capsule
	body.add_child(shape_node)
	scene.add_child(body)
	body.global_position = start

	# Let it settle onto the floor before it starts moving, so the first
	# is_on_floor() check means something.
	for _i in 10:
		await physics_frame

	body.move_direction = Vector3(0.0, 0.0, -1.0)

	var jumped := false

	# 2 seconds at 60 Hz: long enough to walk the run-up and either stop
	# against the obstacle or land well clear of it.
	for _i in 120:
		if not jumped and body.global_position.z <= jump_at_z:
			body.jump_queued = true
			jumped = true
		await physics_frame

	var ended := body.global_position
	body.queue_free()
	await process_frame
	return ended


func _pass(check: String) -> void:
	_completed.append(check)
	print("PASS %s" % check)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	for check in _EXPECTED_CHECKS:
		if check not in _completed:
			_failures.append("check never ran: %s" % check)

	if _failures.is_empty():
		print("\nAll %d arena team spawn checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
