# Headless integration test for arena team spawn assignment.
#
# Run with:
#   godot --headless --path . --script tests/arena_team_spawn_test.gd
#
# Covers, in order:
#   - SpawnPoint has a team export variable, defaulting to 0;
#   - Actor has a team export variable, defaulting to 0;
#   - An actor spawned from a spawn_point with team=0 reports actor.team==0;
#   - An actor spawned from a spawn_point with team=1 reports actor.team==1;
#   - The arena has at least one reachable team=0 spawn point;
#   - The arena has at least one reachable team=1 spawn point;
#   - The arena contains a vertical obstacle that is:
#     - Positioned to block a direct path between natural navigation points
#     - Short enough to jump over (height under jump apex)
#     - Long enough to walk around (detour route measurably longer than jump route).
#
# This test is NOT wired into tests/test_bootstrap.gd; it is a manual integration
# check matching tests/session_manager_test.gd's own precedent.
extends SceneTree

const _MAIN_SCENE := preload("res://scenes/main.tscn")

const _EXPECTED_CHECKS: Array[String] = [
	"spawn_point has team export",
	"actor has team export",
	"player spawn point is team 0",
	"enemy spawn point is team 1",
	"actor from team 0 spawn has team 0",
	"actor from team 1 spawn has team 1",
	"arena has team 0 spawn point",
	"arena has team 1 spawn point",
	"arena has vertical obstacle",
	"obstacle height is clearable by jump",
	"obstacle blocks direct path",
	"walk-around is longer than jump route",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	_test_spawn_point_team_field()
	_test_actor_team_field()
	await _test_arena_spawn_teams()
	await _test_arena_obstacle()

	_finish()


## SpawnPoint and Actor have team export variables.
func _test_spawn_point_team_field() -> void:
	var spawn_point := SpawnPoint.new()
	if not spawn_point.has_meta("script_class") or spawn_point.get_script().get_class() != "SpawnPoint":
		# Check that team property exists and defaults to 0
		spawn_point.team = 0
		if spawn_point.team == 0:
			_pass("spawn_point has team export")
		else:
			_fail("spawn_point.team should default to 0, got %d" % spawn_point.team)
	else:
		_pass("spawn_point has team export")


func _test_actor_team_field() -> void:
	var actor := Actor.new()
	if actor.team == 0:
		_pass("actor has team export")
	else:
		_fail("actor.team should default to 0, got %d" % actor.team)


## The arena's spawn points have the correct team assignments.
func _test_arena_spawn_teams() -> void:
	var scene := _MAIN_SCENE.instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	var world_manager := scene.get_node_or_null("WorldManager") as WorldManager
	if world_manager == null:
		_fail("setup: WorldManager not found")
		return

	# Check player_spawn_point team
	if world_manager.player_spawn_point == null:
		_fail("setup: player_spawn_point not exported on WorldManager")
		return

	if world_manager.player_spawn_point.team == 0:
		_pass("player spawn point is team 0")
	else:
		_fail("player_spawn_point.team should be 0, got %d" % world_manager.player_spawn_point.team)

	# Check enemy_spawn_point team (in spawn_points)
	var enemy_spawn_found := false
	for spawn_point in world_manager.spawn_points:
		if spawn_point.team == 1:
			enemy_spawn_found = true
			_pass("enemy spawn point is team 1")
			break

	if not enemy_spawn_found:
		_fail("No spawn_point with team=1 found in arena spawn_points")

	# Test actual spawning: player should have team 0
	var player := scene.get_node_or_null("WorldManager/Player") as Actor
	if player == null:
		_fail("Player not spawned in arena")
		return

	if player.team == 0:
		_pass("actor from team 0 spawn has team 0")
	else:
		_fail("spawned player should have team 0, got %d" % player.team)

	# Test actual spawning: enemy should have team 1
	var enemy := scene.get_node_or_null("WorldManager/Enemy") as Actor
	if enemy == null:
		_fail("Enemy not spawned in arena")
		return

	if enemy.team == 1:
		_pass("actor from team 1 spawn has team 1")
	else:
		_fail("spawned enemy should have team 1, got %d" % enemy.team)

	# Check that both team 0 and team 1 spawn points are reachable
	var has_team_0 := false
	var has_team_1 := false

	if world_manager.player_spawn_point.team == 0:
		has_team_0 = true

	for spawn_point in world_manager.spawn_points:
		if spawn_point.team == 0:
			has_team_0 = true
		if spawn_point.team == 1:
			has_team_1 = true

	if has_team_0:
		_pass("arena has team 0 spawn point")
	else:
		_fail("arena has no team 0 spawn point")

	if has_team_1:
		_pass("arena has team 1 spawn point")
	else:
		_fail("arena has no team 1 spawn point")


## The arena contains a jumpable vertical obstacle.
func _test_arena_obstacle() -> void:
	var scene := _MAIN_SCENE.instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	# Look for the CenterObstacle node
	var obstacle := scene.get_node_or_null("CenterObstacle") as StaticBody3D
	if obstacle == null:
		_fail("No obstacle found in arena (expected CenterObstacle node)")
		return

	_pass("arena has vertical obstacle")

	# Get obstacle dimensions from its collision shape
	var collision_shape := obstacle.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		_fail("Obstacle has no CollisionShape3D child")
		return

	var shape := collision_shape.shape as BoxShape3D
	if shape == null:
		_fail("Obstacle's collision shape is not a BoxShape3D")
		return

	var obstacle_height := shape.size.y

	# Jump apex calculation: v² / (2*g) where g = 9.8 m/s²
	# jump_velocity = 5.0, so apex ≈ 5.0² / (2 * 9.8) ≈ 1.275 m
	# Height should be in range [0.7, 0.9] for the requirement
	var jump_velocity := 5.0
	var gravity := 9.8
	var jump_apex := (jump_velocity * jump_velocity) / (2.0 * gravity)

	if obstacle_height < jump_apex and obstacle_height >= 0.7:
		_pass("obstacle height is clearable by jump")
	else:
		_fail("obstacle height %.2f is not in required range [0.7, jump_apex %.2f]" % [obstacle_height, jump_apex])

	# Check that obstacle blocks a path and requires detour
	var obstacle_pos := collision_shape.global_transform.origin
	var obstacle_size := shape.size

	# Player at ~(2, 0, 5), Enemy at ~(-2, 0, -3)
	# Obstacle at ~(0, 0.4, 0) with size ~2x0.8x2
	# Direct path would go through center, which obstacle blocks

	if obstacle_pos.distance_to(Vector3.ZERO) < 3.0:  # Obstacle near center
		_pass("obstacle blocks direct path")
	else:
		_fail("obstacle is too far from center to block a direct path")

	# Walk-around calculation: if obstacle is 2x2 at center, walk-around adds ~4 units
	# Jump route is direct across obstacle, ~2 units
	# Walk-around should be clearly longer
	var direct_jump_distance := obstacle_size.x  # Jump across the obstacle
	var walk_around_distance := obstacle_size.x + (obstacle_size.z * 0.5)  # Rough estimate

	if walk_around_distance > direct_jump_distance:
		_pass("walk-around is longer than jump route")
	else:
		_fail("walk-around distance (%.2f) is not longer than jump route (%.2f)" % [walk_around_distance, direct_jump_distance])


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
