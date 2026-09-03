# Headless integration test for #350's lobby entry and match-return wiring.
#
# Run with:
#   godot --headless --path . --script tests/lobby_match_transition_test.gd
#
# Covers, in order:
#   - main_menu.gd's post-Play Offline / Host / Join destination is the lobby,
#     not the arena, so all three entry paths land in the shared space;
#   - match_controller.gd's return destination is the lobby, not the bare
#     main menu;
#   - match_starting follows the settable / on-change / signal-emitting shape
#     MobaMatchState's round_in_progress establishes: an unchanged assignment
#     is a no-op, any other assignment emits;
#   - a peer alone in the lobby resolves its own start request locally, with no
#     RPC round trip, and flips match_starting;
#   - a start request naming a peer with no spawned avatar is refused;
#   - a non-server peer cannot decide match_starting, even calling the resolve
#     path directly;
#   - LobbyStateSynchronizer carries match_starting on-change AND its configured
#     path actually resolves against the synchronizer's own root, which is what
#     makes the second peer observe the flip.
#
# On the two-peer criterion. The repository does not open real sockets in tests
# (see tests/match_controller_test.gd's own note), so "both peers observe it" is
# proven in the two halves it actually decomposes into, rather than asserted by
# a comment:
#
#   1. the wire carries it -- the synchronizer config lists match_starting
#      on-change and its NodePath resolves to a real node and a real property;
#   2. arrival is observable -- assigning the property on a second, independent
#      LobbyManager (which is precisely what a MultiplayerSynchronizer does to
#      the receiving peer's copy) emits match_starting_changed there.
#
# Half 1 has teeth: a synchronizer whose path silently resolves to nothing looks
# perfectly correct in the scene file and replicates nothing at runtime.
#
# This test is NOT wired into tests/test_bootstrap.gd: it loads game scenes,
# matching the precedent set by tests/session_manager_test.gd and
# tests/match_controller_test.gd.
extends SceneTree

const _LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"
const _ARENA_SCENE := "res://scenes/main.tscn"

# A port nothing is listening on. The client peer never connects; it only has to
# report a non-server unique id, exactly as tests/match_controller_test.gd does.
const _DEAD_PORT := 27322

# A peer id that is never spawned an avatar in these checks.
const _PEER_WITHOUT_AVATAR := 4321

const _EXPECTED_CHECKS: Array[String] = [
	"main menu enters the lobby, not the arena",
	"a decided match returns to the lobby, not the main menu",
	"match_starting is settable on-change and emits",
	"a lone offline peer starts the match locally",
	"a request from a peer with no avatar is refused",
	"a non-server peer cannot decide match_starting",
	"match_starting replicates on-change over a path that resolves",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	_test_menu_enters_lobby()
	_test_match_returns_to_lobby()
	await _test_match_starting_is_on_change()
	await _test_lone_offline_peer_starts_match()
	await _test_request_without_avatar_refused()
	await _test_replication_config()
	await _test_non_server_cannot_decide()

	_finish()


## Play Offline, Host and Join all funnel through main_menu.gd's _enter_world(),
## so the one scene constant that function changes to is the whole criterion for
## all three. Read off the script's constant map rather than by calling it: the
## call would tear this test's own tree down.
func _test_menu_enters_lobby() -> void:
	var script := load("res://scripts/main_menu.gd") as GDScript
	if script == null:
		_fail("setup: scripts/main_menu.gd did not load")
		return

	var constants := script.get_script_constant_map()
	var destinations: Array = []
	for value in constants.values():
		if value is String and (value as String).ends_with(".tscn"):
			destinations.append(value)

	if _ARENA_SCENE in destinations:
		_fail("main_menu.gd still names %s as a destination" % _ARENA_SCENE)
		return

	if _LOBBY_SCENE not in destinations:
		_fail("main_menu.gd does not name %s as a destination" % _LOBBY_SCENE)
		return

	_pass("main menu enters the lobby, not the arena")


## The end-of-match return trip lands in the shared lobby rather than the
## disconnected main menu screen.
func _test_match_returns_to_lobby() -> void:
	var script := load("res://scripts/match_controller.gd") as GDScript
	if script == null:
		_fail("setup: scripts/match_controller.gd did not load")
		return

	var destination: Variant = script.get_script_constant_map().get("LOBBY_SCENE_PATH")
	if destination != _LOBBY_SCENE:
		_fail("MatchController.LOBBY_SCENE_PATH is %s, expected %s" % [destination, _LOBBY_SCENE])
		return

	_pass("a decided match returns to the lobby, not the main menu")


## The same contract round_in_progress already keeps: assigning the value it
## already holds emits nothing, any other assignment emits once.
func _test_match_starting_is_on_change() -> void:
	var manager := await _spawn_lobby_manager()
	if manager == null:
		return

	var emitted: Array[bool] = []
	manager.match_starting_changed.connect(func(value: bool) -> void: emitted.append(value))

	manager.match_starting = false
	if not emitted.is_empty():
		_fail("assigning the unchanged value false emitted %d time(s)" % emitted.size())
		_teardown(manager)
		return

	manager.match_starting = true
	if emitted != [true]:
		_fail("assigning true emitted %s, expected [true]" % [emitted])
		_teardown(manager)
		return

	manager.match_starting = true
	if emitted != [true]:
		_fail("re-assigning true emitted again: %s" % [emitted])
		_teardown(manager)
		return

	if not manager.match_starting:
		_fail("match_starting did not read back true after being set")
		_teardown(manager)
		return

	_pass("match_starting is settable on-change and emits")
	_teardown(manager)
	await process_frame


## Offline, the lone peer's own request is resolved in-process. The criterion is
## that it needs no server round trip and that it flips the property that drives
## everyone present into the arena.
func _test_lone_offline_peer_starts_match() -> void:
	var manager := await _spawn_lobby_manager()
	if manager == null:
		return

	# _ready() already spawned the local peer's avatar offline; that lone avatar
	# is what makes this peer a present occupant.
	var local_id := manager.multiplayer.get_unique_id()
	if not manager._peer_avatars.has(local_id):
		_fail("offline lobby did not spawn an avatar for the local peer")
		_teardown(manager)
		return

	manager.try_start_match()

	if not manager.match_starting:
		_fail("a lone offline peer's try_start_match() did not set match_starting")
		_teardown(manager)
		return

	# The arena it is sent to is a real, loadable scene -- the same one the
	# existing single-player-vs-bots match already runs in.
	if manager.ARENA_SCENE_PATH != _ARENA_SCENE:
		_fail(
			(
				"LobbyManager.ARENA_SCENE_PATH is %s, expected %s"
				% [manager.ARENA_SCENE_PATH, _ARENA_SCENE]
			)
		)
		_teardown(manager)
		return

	if load(_ARENA_SCENE) == null:
		_fail("setup: %s did not load" % _ARENA_SCENE)
		_teardown(manager)
		return

	_pass("a lone offline peer starts the match locally")
	_teardown(manager)
	await process_frame


## Presence is the gate: a peer id with no spawned avatar is not in the lobby,
## and its request must not flip the property.
func _test_request_without_avatar_refused() -> void:
	var manager := await _spawn_lobby_manager()
	if manager == null:
		return

	if manager._peer_avatars.has(_PEER_WITHOUT_AVATAR):
		_fail("setup: peer %d unexpectedly has an avatar" % _PEER_WITHOUT_AVATAR)
		_teardown(manager)
		return

	manager._resolve_start_match(_PEER_WITHOUT_AVATAR)

	if manager.match_starting:
		_fail("a peer with no spawned avatar flipped match_starting")
		_teardown(manager)
		return

	_pass("a request from a peer with no avatar is refused")
	_teardown(manager)
	await process_frame


## The synchronizer must carry match_starting on-change, and -- the half that
## actually bites -- the configured path must resolve against the synchronizer's
## own root_path to a real node holding a real property. A path that resolves to
## nothing replicates nothing while looking correct in the scene file.
func _test_replication_config() -> void:
	var lobby := await _instance_lobby()
	if lobby == null:
		return

	var problem := _replication_problem(lobby)
	if problem != "":
		_fail(problem)
		_free_lobby(lobby)
		return

	# Arrival is observable on the receiving side: assigning the property on a
	# second, independent LobbyManager -- which is exactly what the synchronizer
	# does to a client's own copy -- emits there too. Together with the resolving
	# path above, that is both peers observing the flip.
	var receiver := await _spawn_lobby_manager()
	if receiver == null:
		_free_lobby(lobby)
		return

	var observed: Array[bool] = []
	receiver.match_starting_changed.connect(func(value: bool) -> void: observed.append(value))
	receiver.match_starting = true

	if observed != [true]:
		_fail("a second peer did not observe match_starting on assignment: %s" % [observed])
	else:
		_pass("match_starting replicates on-change over a path that resolves")

	_teardown(receiver)
	_free_lobby(lobby)
	await process_frame


## Returns "" when the lobby's synchronizer is authored correctly, or the reason
## it is not. Split out from the check above, and split again below, to keep each
## condition a separately named failure without piling early returns into one
## function.
func _replication_problem(lobby: Node) -> String:
	var sync := (
		lobby.get_node_or_null("LobbyManager/LobbyStateSynchronizer") as MultiplayerSynchronizer
	)
	if sync == null:
		return "lobby.tscn has no LobbyManager/LobbyStateSynchronizer"

	var config := sync.replication_config
	if config == null:
		return "LobbyStateSynchronizer has no replication_config"

	var root_node := sync.get_node_or_null(sync.root_path)
	if root_node == null:
		return "LobbyStateSynchronizer.root_path %s resolves to nothing" % sync.root_path

	var properties := config.get_properties()
	if properties.size() != 1:
		return (
			"LobbyStateSynchronizer replicates %d properties, expected exactly 1"
			% properties.size()
		)

	return _property_problem(config, root_node, properties[0])


## The half with teeth: the configured path has to name a node that exists under
## the synchronizer's root and a property that exists on it, replicated
## on-change. A path resolving to nothing replicates nothing, silently.
func _property_problem(config: SceneReplicationConfig, root_node: Node, path: NodePath) -> String:
	var target := root_node.get_node_or_null(NodePath(String(path).get_slice(":", 0)))
	if target == null:
		return "replicated path %s resolves to no node under %s" % [path, root_node.name]

	var subname := path.get_subname(0)
	if subname != "match_starting":
		return "replicated property is %s, expected match_starting" % subname

	if not (subname in target):
		return "%s has no property named %s" % [target.name, subname]

	# On-change, not always -- the same mode MatchStateSynchronizer uses.
	if (
		config.property_get_replication_mode(path)
		!= SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
	):
		return "%s is not replicated on-change" % path

	return ""


## Only the server decides. A peer whose multiplayer id is not 1 must not be
## able to flip the property even by calling the resolve path directly.
##
## The client peer is created against a port nothing is listening on: ENet
## reports a non-server unique id immediately, so is_server() is already false
## before any handshake, and the gate is testable without a real session.
func _test_non_server_cannot_decide() -> void:
	var lobby := await _instance_lobby()
	if lobby == null:
		return

	var manager := lobby.get_node_or_null("LobbyManager") as LobbyManager
	if manager == null:
		_fail("setup: LobbyManager missing")
		_free_lobby(lobby)
		return

	# Give the manager an avatar for the id it is about to be asked about, so the
	# refusal below can only come from the authority gate and not from presence.
	manager.spawn_avatar_for_peer(_PEER_WITHOUT_AVATAR)
	_disconnect_transition(manager)

	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", _DEAD_PORT) != OK:
		_fail("setup: create_client failed")
		_free_lobby(lobby)
		return

	var previous := root.multiplayer.multiplayer_peer
	root.multiplayer.multiplayer_peer = peer
	await process_frame

	if manager.multiplayer.is_server():
		_fail("setup: the client peer still reports itself as the server")
	else:
		manager._resolve_start_match(_PEER_WITHOUT_AVATAR)
		if manager.match_starting:
			_fail("a non-server peer flipped match_starting")
		else:
			_pass("a non-server peer cannot decide match_starting")

	root.multiplayer.multiplayer_peer = previous
	peer.close()
	_free_lobby(lobby)
	await process_frame


## scenes/lobby/lobby.tscn, instanced into the tree so _ready() has run.
func _instance_lobby() -> Node:
	var packed := load(_LOBBY_SCENE) as PackedScene
	if packed == null:
		_fail("setup: %s did not load" % _LOBBY_SCENE)
		return null

	var lobby := packed.instantiate()
	root.add_child(lobby)
	await process_frame
	return lobby


## A readied LobbyManager with its auto-transition detached.
func _spawn_lobby_manager() -> LobbyManager:
	var lobby := await _instance_lobby()
	if lobby == null:
		return null

	var manager := lobby.get_node_or_null("LobbyManager") as LobbyManager
	if manager == null:
		_fail("setup: lobby.tscn has no LobbyManager")
		_free_lobby(lobby)
		return null

	_disconnect_transition(manager)
	return manager


## Detach the handler that changes scene on match_starting. These checks are
## about the state that drives the transition; letting the transition itself run
## would swap the scene this test is standing in out from under it.
func _disconnect_transition(manager: LobbyManager) -> void:
	if manager.match_starting_changed.is_connected(manager._on_match_starting_changed):
		manager.match_starting_changed.disconnect(manager._on_match_starting_changed)


func _teardown(manager: LobbyManager) -> void:
	_free_lobby(manager.get_parent())


func _free_lobby(lobby: Node) -> void:
	if is_instance_valid(lobby):
		lobby.queue_free()


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
		print("\nAll %d lobby match transition checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
