# Headless integration test for #342's match controller.
#
# Run with:
#   godot --headless --path . --script tests/match_controller_test.gd
#
# Covers, in order:
#   - the offline process is authoritative, registers both rosters and starts
#     the round, so MobaMatchState advances on it;
#   - rosters follow actor.team rather than "players" vs "nonplayers" group
#     membership, so an AI-controlled actor authored onto Team A lands there;
#   - a pure client is NOT authoritative: its own MatchController never calls
#     tick() and never starts a round, so its copy of the state stays at the
#     values replication gives it;
#   - MatchStateSynchronizer replicates exactly the four match-state properties
#     on-change, the way CombatStateSynchronizer replicates combat state.
#
# The gating check is the one with teeth. MobaMatchState deliberately never
# reads `multiplayer` and never decides whether it should be running, so
# MatchController is the only thing standing between a client and a second,
# divergent authority over the same match. A gate that quietly widened to
# "everyone" would still look correct in a single-process run; this test is
# what catches that, by asserting the condition directly AND by showing the
# client's own state never leaves its initial values.
#
# The client peer is created with create_client() against a port nothing is
# listening on. That is deliberate: ENet reports a unique id other than 1
# immediately, so `multiplayer.is_server()` is already false before any
# handshake, and the gate can be tested without standing up a real session.
#
# This test is NOT wired into tests/test_bootstrap.gd: it loads game scenes,
# matching the precedent set by tests/session_manager_test.gd and
# tests/replication_authority_test.gd.
extends SceneTree

# A port nothing is listening on. The client peer never connects; it only has
# to report a non-server unique id.
const _DEAD_PORT := 27321

# Physics frames to let _physics_process run on an instanced scene.
const _TICK_FRAMES := 10

# The four properties #342 requires on the wire, relative to the synchronizer's
# root_path (MatchController).
const _REPLICATED := [
	"MobaMatchState:team_a_score",
	"MobaMatchState:team_b_score",
	"MobaMatchState:winning_team",
	"MobaMatchState:round_in_progress",
]

const _EXPECTED_CHECKS: Array[String] = [
	"offline process is authoritative and starts the round",
	"rosters follow actor.team, not group membership",
	"client process is not authoritative",
	"client match state never advances on its own",
	"match state replicates the four properties on-change",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	await _test_offline_authority()
	await _test_client_gating()
	_test_replication_config()

	_finish()


## Offline: the controller owns the match. It registers both rosters from
## actor.team and starts the round, so the state is live on this process.
func _test_offline_authority() -> void:
	var session := _session()
	if session != null:
		session.mode = session.Mode.OFFLINE

	var world := _instance_main()
	if world == null:
		return
	root.add_child(world)
	await process_frame

	var controller := world.get_node_or_null(^"MatchController") as MatchController
	var state := world.get_node_or_null(^"MatchController/MobaMatchState") as MobaMatchState
	if controller == null or state == null:
		_fail("setup: MatchController/MobaMatchState missing from scenes/main.tscn")
		world.queue_free()
		await process_frame
		return

	if not controller._is_authoritative():
		_fail("offline process reports itself non-authoritative")
	elif not state.round_in_progress:
		_fail("offline process did not start the round")
	else:
		_pass("offline process is authoritative and starts the round")

	_check_rosters_follow_team(state)

	world.queue_free()
	await process_frame


## Every actor's combatant must sit in the roster its actor.team names --
## never in the one its group membership would suggest.
func _check_rosters_follow_team(state: MobaMatchState) -> void:
	var rosters: Array = state._rosters
	if rosters[MobaMatchState.TEAM_A].is_empty() or rosters[MobaMatchState.TEAM_B].is_empty():
		_fail(
			(
				"setup: a roster is empty (A=%d, B=%d); the arena must author both sides"
				% [rosters[MobaMatchState.TEAM_A].size(), rosters[MobaMatchState.TEAM_B].size()]
			)
		)
		return

	var checked := 0
	for group in [&"players", &"nonplayers"]:
		for node in get_nodes_in_group(group):
			var actor := node as Actor
			if actor == null:
				continue
			var combatant := actor.get_node_or_null(^"MobaCombatant") as MobaCombatant
			if combatant == null:
				continue
			checked += 1
			if not rosters[actor.team].has(combatant):
				_fail(
					(
						"%s is in group %s with team %d but is not on that team's roster"
						% [actor.name, group, actor.team]
					)
				)
				return

	if checked == 0:
		_fail("setup: no actors with a MobaCombatant were found in either group")
		return

	_pass("rosters follow actor.team, not group membership")


## A pure client must never tick or start its own copy of the match.
func _test_client_gating() -> void:
	var session := _session()
	if session != null:
		# What SessionManager.join() leaves behind on a joining peer.
		session.mode = session.Mode.LISTEN_SERVER

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client("127.0.0.1", _DEAD_PORT)
	if err != OK:
		_fail("setup: create_client failed with error %d" % err)
		_restore_offline(session)
		return
	multiplayer.multiplayer_peer = peer

	if multiplayer.is_server():
		_fail("setup: client peer still reports is_server()")
		_restore_offline(session)
		return

	var world := _instance_main()
	if world == null:
		_restore_offline(session)
		return
	root.add_child(world)
	await process_frame

	var controller := world.get_node_or_null(^"MatchController") as MatchController
	var state := world.get_node_or_null(^"MatchController/MobaMatchState") as MobaMatchState
	if controller == null or state == null:
		_fail("setup: MatchController/MobaMatchState missing on the client instance")
	else:
		if controller._is_authoritative():
			_fail("client process reports itself authoritative")
		else:
			_pass("client process is not authoritative")

		for _i in _TICK_FRAMES:
			await physics_frame

		if state.round_in_progress:
			_fail("client started a round on its own")
		elif state.team_a_score != 0 or state.team_b_score != 0:
			_fail(
				"client advanced its own score to %d-%d" % [state.team_a_score, state.team_b_score]
			)
		elif state.winning_team != MobaMatchState.NO_WINNER:
			_fail("client decided a winner on its own: %d" % state.winning_team)
		else:
			_pass("client match state never advances on its own")

	world.queue_free()
	await process_frame
	_restore_offline(session)


## The synchronizer must carry exactly the four match-state properties, each
## on-change (replication_mode 2), matching CombatStateSynchronizer.
##
## Read off an instanced-but-detached scene: _ready() never runs, so this
## asserts what the scene authors rather than what any code path built.
func _test_replication_config() -> void:
	var world := _instance_main()
	if world == null:
		return

	var path := ^"MatchController/MobaMatchState/MatchStateSynchronizer"
	var sync := world.get_node_or_null(path) as MultiplayerSynchronizer
	if sync == null:
		_fail("MatchStateSynchronizer not found at %s" % path)
		world.free()
		return

	var config := sync.replication_config
	if config == null:
		_fail("MatchStateSynchronizer has no replication_config")
		world.free()
		return

	var found: Array[String] = []
	var ok := true
	for property: NodePath in config.get_properties():
		found.append(String(property))
		var mode := config.property_get_replication_mode(property)
		if mode != SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE:
			_fail("%s replicates in mode %d, expected on-change (2)" % [property, mode])
			ok = false

	for expected in _REPLICATED:
		if expected not in found:
			_fail("%s is not replicated by MatchStateSynchronizer" % expected)
			ok = false

	for property in found:
		if property not in _REPLICATED:
			_fail("MatchStateSynchronizer replicates unexpected property %s" % property)
			ok = false

	if ok:
		_pass("match state replicates the four properties on-change")

	world.free()


## scenes/main.tscn, instantiated but not parented.
func _instance_main() -> Node:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("setup: res://scenes/main.tscn did not load")
		return null
	return packed.instantiate()


## The SessionManager autoload. Autoloads are instantiated under --script too,
## so this is normally present; reached by path rather than by its global name.
func _session() -> Node:
	return root.get_node_or_null(^"SessionManager")


func _restore_offline(session: Node) -> void:
	multiplayer.multiplayer_peer = null
	if session != null:
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
		print("\nAll %d match controller checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
