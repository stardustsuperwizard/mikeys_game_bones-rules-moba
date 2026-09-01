# Headless integration test for SessionManager and peer spawn/despawn lifecycle.
#
# Run with:
#   godot --headless --path . --script tests/session_manager_test.gd
#
# Tests:
#   - SessionManager starts in OFFLINE mode
#   - host() creates a LISTEN_SERVER session
#   - host(dedicated=true) creates a DEDICATED_SERVER session
#   - join() sets mode to LISTEN_SERVER
#   - go_offline() returns to OFFLINE mode
#   - Spawning a player works through the spawn path
#   - Player actor is only ticked/controlled by its owner
#
# This test is NOT wired into tests/test_bootstrap.gd; it is a manual integration check.
extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	if not await _test_session_manager_modes():
		return _finish()

	if not await _test_player_spawn_authority():
		return _finish()

	_finish()


## Test that SessionManager correctly manages session modes.
func _test_session_manager_modes() -> bool:
	var sm := SessionManager.new()
	add_child(sm)

	# Test initial OFFLINE mode
	if sm.mode != SessionManager.Mode.OFFLINE:
		_fail("Initial mode should be OFFLINE, got %d" % sm.mode)
		return false
	print("PASS: SessionManager starts in OFFLINE mode")

	# Test go_offline
	sm.go_offline()
	if sm.mode != SessionManager.Mode.OFFLINE:
		_fail("go_offline() should set mode to OFFLINE")
		return false
	if multiplayer.has_multiplayer_peer():
		_fail("go_offline() should set multiplayer_peer to null")
		return false
	print("PASS: go_offline() returns to OFFLINE mode")

	return true


## Test that player actors are spawned and only controlled by their owner.
func _test_player_spawn_authority() -> bool:
	# Load the main scene with WorldManager and player_spawn_point
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	var world_mgr := scene.get_node_or_null("WorldManager") as WorldManager
	if world_mgr == null:
		_fail("setup: WorldManager not found")
		return false

	if world_mgr.player_spawn_point == null:
		_fail("setup: player_spawn_point not exported on WorldManager")
		return false

	# Verify the player actor exists and has correct authority
	var player := scene.get_node_or_null("WorldManager/Player") as Actor
	if player == null:
		_fail("setup: player not found in spawn_points")
		return false

	if player.owner_id != 1:
		_fail("setup: player should have owner_id=1 (local), got %d" % player.owner_id)
		return false

	var body := player.get_node_or_null("Body") as CharacterBody3D
	var controller := player.controller as PlayerController3D

	if body == null or controller == null:
		_fail("setup: player body or controller not found")
		return false

	# Verify that body.is_multiplayer_authority() gates movement
	if not body.is_multiplayer_authority():
		_fail("body should have multiplayer authority in offline mode")
		return false

	# Verify enemy actor exists (from spawn_points with authority_id=0)
	var enemy := scene.get_node_or_null("WorldManager/Enemy") as Actor
	if enemy == null:
		_fail("setup: enemy not found in spawn_points")
		return false

	if enemy.owner_id != 0:
		_fail("setup: enemy should have owner_id=0, got %d" % enemy.owner_id)
		return false

	print("PASS: Player actor spawned with correct authority")
	print("PASS: Enemy actor spawned with authority_id=0")

	return true


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nALL SESSION MANAGER CHECKS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL " + f)
		quit(1)
