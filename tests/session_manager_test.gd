# Headless integration test for SessionManager and the peer player spawn path.
#
# Run with:
#   godot --headless --path . --script tests/session_manager_test.gd
#
# Covers, in order:
#   - SessionManager starts in OFFLINE mode, and go_offline() leaves no peer;
#   - the offline boot still spawns the local player (peer id 1) from
#     player_spawn_point, i.e. today's single-player-vs-bots behavior survives
#     the move of the player out of spawn_points;
#   - the authority-0 enemy still spawns unconditionally from spawn_points;
#   - the local player's Body holds multiplayer authority, which is the check
#     PlayerController3D's input and combat tick are now gated on;
#   - DEDICATED_SERVER mode spawns the world content but no local player, which
#     is the one thing session mode is allowed to decide.
#
# host()/join() are not exercised: both bind a real ENet socket and join() needs
# a second Godot instance, which a single headless process cannot provide. Those
# are the Issue's human-validation criteria.
#
# SessionManager is loaded by path rather than by class_name: it is an autoload,
# and a global class sharing an autoload's name is a parse error in Godot 4.
#
# Every check appends its name to _completed and the run is only green when all
# of _EXPECTED_CHECKS are present. A GDScript runtime error aborts the enclosing
# function silently and returns null, which a plain "no failures recorded" exit
# would report as success -- the same trap tests/test_bootstrap.gd guards with
# its _expected_suites count.
#
# This test is NOT wired into tests/test_bootstrap.gd; it is a manual integration
# check matching tests/input_intent_controller_test.gd's own precedent.
extends SceneTree

const _MAIN_SCENE := preload("res://scenes/main.tscn")

const _EXPECTED_CHECKS: Array[String] = [
	"starts offline",
	"go_offline leaves no network peer",
	"offline spawns local player",
	"local player body holds authority",
	"enemy spawns unowned",
	"dedicated server spawns no local player",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# The tree is not live yet inside _initialize(); Node.multiplayer is still
	# null until it has processed a frame, and go_offline() writes through it.
	await process_frame

	_test_session_manager_modes()
	await _test_offline_spawn()
	await _test_dedicated_server_spawn()

	_finish()


## SessionManager's mode starts offline and go_offline() creates no peer.
func _test_session_manager_modes() -> void:
	var session := _session()
	if session == null:
		_fail("setup: SessionManager autoload not found at /root/SessionManager")
		return

	if session.mode != session.Mode.OFFLINE:
		_fail("initial mode should be OFFLINE, got %d" % session.mode)
	else:
		_pass("starts offline")

	# "No multiplayer peer created" means no *network* peer. Offline still holds
	# an OfflineMultiplayerPeer -- Godot's own default -- which is what keeps
	# unique_id 1, is_server() true, and MultiplayerSpawner spawning at all.
	session.go_offline()
	if session.mode != session.Mode.OFFLINE:
		_fail("go_offline() should leave mode OFFLINE, got %d" % session.mode)
	elif session.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_fail("go_offline() should leave no ENet peer")
	elif not (session.multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		_fail("go_offline() should restore an OfflineMultiplayerPeer")
	elif session.multiplayer.get_unique_id() != 1:
		_fail("offline unique id should be 1, got %d" % session.multiplayer.get_unique_id())
	else:
		_pass("go_offline leaves no network peer")


## The offline boot spawns the local player and the unowned enemy.
func _test_offline_spawn() -> void:
	var scene := _MAIN_SCENE.instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	var world_manager := scene.get_node_or_null("WorldManager") as WorldManager
	if world_manager == null:
		_fail("setup: WorldManager not found")
		return

	if world_manager.player_spawn_point == null:
		_fail("setup: player_spawn_point not exported on WorldManager")
		return

	# The local player now comes from player_spawn_point via
	# spawn_player_for_peer(), not from spawn_points. Its absence is the
	# regression this check exists to catch: offline must still have a player.
	var player := scene.get_node_or_null("WorldManager/Player") as Actor
	if player == null:
		_fail("offline boot spawned no local player from player_spawn_point")
		return

	if player.owner_id != 1:
		_fail("local player should have owner_id 1, got %d" % player.owner_id)
	else:
		_pass("offline spawns local player")

	var body := player.get_node_or_null("Body") as ActorBody3D
	if body == null:
		_fail("setup: player Body not found")
	elif not body.is_multiplayer_authority():
		_fail("local player's Body should hold multiplayer authority offline")
	else:
		_pass("local player body holds authority")

	# spawn_points keeps the always-present, authority-0 world content, and it
	# still spawns unconditionally -- bot parity must not regress.
	var enemy := scene.get_node_or_null("WorldManager/Enemy") as Actor
	if enemy == null:
		_fail("enemy not spawned from spawn_points")
	elif enemy.owner_id != 0:
		_fail("enemy should have owner_id 0, got %d" % enemy.owner_id)
	else:
		_pass("enemy spawns unowned")


## The SessionManager autoload. Autoloads are instantiated under --script too,
## and it is this node -- not a locally constructed one -- that WorldManager
## reads its mode off, so a second instance would be renamed and ignored.
func _session() -> Node:
	return root.get_node_or_null(^"/root/SessionManager")


## Dedicated-server mode spawns world content but no player for peer 1.
func _test_dedicated_server_spawn() -> void:
	var session := _session()
	if session == null:
		_fail("setup: SessionManager autoload not found")
		return

	session.mode = session.Mode.DEDICATED_SERVER
	var scene := _MAIN_SCENE.instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	var world_manager := scene.get_node_or_null("WorldManager") as WorldManager
	if world_manager == null:
		_fail("setup: WorldManager not found in dedicated scene")
	elif scene.get_node_or_null("WorldManager/Player") != null:
		_fail("dedicated server spawned a local player for peer 1")
	elif scene.get_node_or_null("WorldManager/Enemy") == null:
		_fail("dedicated server did not spawn world content from spawn_points")
	else:
		_pass("dedicated server spawns no local player")

	session.mode = session.Mode.OFFLINE


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
		print("\nAll %d session manager checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
