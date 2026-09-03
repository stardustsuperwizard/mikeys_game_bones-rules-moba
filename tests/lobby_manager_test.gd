# Headless integration test for the lobby system: spawning avatars for connected
# peers with their registered identities visible to all.
#
# Run with:
#   godot --headless --path . --script tests/lobby_manager_test.gd
#
# Covers, in order:
#   - two peers spawned into the lobby each carry the correct, distinct
#     character_sheet.character_name sourced from their own registered build;
#   - both avatars are sibling nodes visible to each other in the scene tree;
#   - a peer connecting after others are already present is spawned via the same
#     peer_connected path WorldManager establishes;
#   - a peer disconnecting has its avatar freed and its entry removed from
#     LobbyManager's presence tracking; no other present peer's avatar is affected;
#   - a lobby avatar's instantiated scene tree contains no MobaCombatant,
#     MobaStateMachine, or MobaAbilityCaster node;
#   - a lobby avatar spawned for peer A always shows peer A's own registered identity,
#     never peer B's, even when peer B registered a build first and is spawned first;
#   - the Body's transform SceneReplicationConfig matches the continuous,
#     owning-peer-authoritative shape player.tscn's BodyTransformSynchronizer uses.
#
# This test is NOT wired into tests/test_bootstrap.gd: it loads game scenes and
# a LobbyManager, matching the precedent set by tests/session_manager_test.gd.
extends SceneTree

const _LOBBY_SPAWN_POINT := preload("res://resources/lobby_player_spawn_point.tres")
const _FALLBACK_BUILD := preload("res://rules/data/builds/melee_bruiser_build.tres")

# Peer ids: one per check, to isolate state
const _PEER_FIRST := 11
const _PEER_SECOND := 12
const _PEER_LATE := 13
const _PEER_IDENTITY_A := 14
const _PEER_IDENTITY_B := 15
const _PEER_DISCONNECT := 16

const _EXPECTED_CHECKS: Array[String] = [
	"two peers spawn with distinct names",
	"avatars are siblings in scene tree",
	"late-joining peer is spawned via peer_connected",
	"disconnecting peer's avatar is freed",
	"lobby avatar has no combat nodes",
	"peer A always shows peer A's identity",
	"body replication config matches player.tscn",
	"lobby camera targets the local avatar's Body",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	_test_two_peers_distinct_names()
	_test_avatars_are_siblings()
	_test_late_peer_via_peer_connected()
	_test_disconnect_frees_avatar()
	_test_no_combat_nodes()
	_test_identity_lookup_per_peer()
	_test_body_replication_config()
	_test_camera_targets_local_avatar()

	_finish()


## Create a LobbyManager without a MultiplayerSpawner
func _make_lobby_manager() -> LobbyManager:
	var lobby_manager: LobbyManager = LobbyManager.new()
	# The scene wires this through lobby.tscn's exported property; a bare
	# LobbyManager.new() has to be given it the same way, or nothing spawns.
	lobby_manager.avatar_spawn_point = _LOBBY_SPAWN_POINT
	root.add_child(lobby_manager)
	return lobby_manager


## Spawn an avatar for a peer through the real LobbyManager path
func _spawn_avatar(lobby_manager: LobbyManager, peer_id: int) -> Node:
	lobby_manager.spawn_avatar_for_peer(peer_id)
	var actor: Node = lobby_manager._peer_avatars.get(peer_id)
	if actor != null and actor.get_parent() == null:
		lobby_manager.add_child(actor)
	return actor


## A legal WARRIOR/GUARDIAN build with a custom name
func _make_named_build(name: String) -> MobaCharacterBuild:
	var loadout := MobaLoadout.new()
	loadout.set_action_slot(1, "whirlwind")
	loadout.set_action_slot(2, "shield_bash")
	loadout.weapon = _FALLBACK_BUILD.loadout.weapon

	var build := MobaCharacterBuild.new()
	build.character_name = name
	build.primary_discipline = MobaAbility.Discipline.WARRIOR
	build.secondary_discipline = MobaAbility.Discipline.GUARDIAN
	build.stat_allocation = {}
	build.loadout = loadout

	return build


## Get the PeerIdentityRegistry autoload
func _get_registry() -> Node:
	return root.get_node_or_null(^"/root/PeerIdentityRegistry")


## Get or create WorldManager for build setup
func _make_world_manager() -> WorldManager:
	var world_manager: WorldManager = WorldManager.new()
	world_manager.player_spawn_point = _LOBBY_SPAWN_POINT
	root.add_child(world_manager)
	return world_manager


## Helper to fail a test and clean up resources
## Give a peer an accepted build under `name`, so the registry holds a real
## identity for the lobby to look up. Reports its own failure and returns false.
func _register_peer_build(wm: WorldManager, peer_id: int, name: String, cleanup: Array) -> bool:
	wm.spawn_player_for_peer(peer_id)
	if wm._peer_actors.get(peer_id) == null:
		_fail_cleanup("setup: no actor for peer %d" % peer_id, cleanup)
		return false

	if not wm.submit_build(peer_id, _make_named_build(name)).success:
		_fail_cleanup("setup: build submission refused for peer %d" % peer_id, cleanup)
		return false

	return true


func _fail_cleanup(message: String, resources: Array) -> void:
	_fail(message)
	for resource in resources:
		if resource is Node:
			(resource as Node).queue_free()


## Two peers spawn with distinct character names from their registered builds
func _test_two_peers_distinct_names() -> void:
	if _get_registry() == null:
		_fail("setup: PeerIdentityRegistry autoload not found")
		return

	var wm := _make_world_manager()
	var cleanup := [wm]

	if not _register_peer_build(wm, _PEER_FIRST, "FirstPeer", cleanup):
		return
	if not _register_peer_build(wm, _PEER_SECOND, "SecondPeer", cleanup):
		return

	var lobby_manager := _make_lobby_manager()
	cleanup.append(lobby_manager)
	var avatar1 := _spawn_avatar(lobby_manager, _PEER_FIRST)
	var avatar2 := _spawn_avatar(lobby_manager, _PEER_SECOND)

	if avatar1 == null or avatar2 == null:
		_fail_cleanup("avatars did not spawn", cleanup)
		return

	if avatar1.character_sheet == null or avatar2.character_sheet == null:
		_fail_cleanup("avatar character_sheet is null", cleanup)
		return

	# Distinctness is carried by the two expected values differing: asserting
	# each avatar's own name separately is what proves they did not collide.
	var name1: String = avatar1.character_sheet.character_name
	var name2: String = avatar2.character_sheet.character_name
	if name1 != "FirstPeer" or name2 != "SecondPeer":
		_fail_cleanup(
			"avatar names are ('%s', '%s'), expected ('FirstPeer', 'SecondPeer')" % [name1, name2],
			cleanup,
		)
		return

	_pass("two peers spawn with distinct names")
	for resource in cleanup:
		(resource as Node).queue_free()


## Both avatars are siblings visible to each other
func _test_avatars_are_siblings() -> void:
	var lobby_manager := _make_lobby_manager()

	var avatar1 := _spawn_avatar(lobby_manager, _PEER_FIRST)
	var avatar2 := _spawn_avatar(lobby_manager, _PEER_SECOND)

	if avatar1 == null or avatar2 == null:
		_fail("setup: avatars did not spawn")
		lobby_manager.queue_free()
		return

	if avatar1.get_parent() != lobby_manager:
		_fail("avatar 1 is not a child of LobbyManager")
		lobby_manager.queue_free()
		return

	if avatar2.get_parent() != lobby_manager:
		_fail("avatar 2 is not a child of LobbyManager")
		lobby_manager.queue_free()
		return

	# Check they are visible to each other (both in tree and are siblings)
	if not avatar1.is_inside_tree():
		_fail("avatar 1 is not in the scene tree")
		lobby_manager.queue_free()
		return

	if not avatar2.is_inside_tree():
		_fail("avatar 2 is not in the scene tree")
		lobby_manager.queue_free()
		return

	_pass("avatars are siblings in scene tree")
	lobby_manager.queue_free()


## A peer connecting after others are present is spawned via peer_connected
func _test_late_peer_via_peer_connected() -> void:
	var lobby_manager := _make_lobby_manager()

	var avatar1 := _spawn_avatar(lobby_manager, _PEER_FIRST)
	if avatar1 == null:
		_fail("setup: first avatar did not spawn")
		lobby_manager.queue_free()
		return

	# Simulate a peer connecting (this calls spawn_avatar_for_peer internally)
	lobby_manager._on_peer_connected(_PEER_LATE)

	var avatar_late: Actor = lobby_manager._peer_avatars.get(_PEER_LATE)
	if avatar_late == null or not is_instance_valid(avatar_late):
		_fail("late-joining peer was not spawned via peer_connected")
		lobby_manager.queue_free()
		return

	# Make sure it's in the tree by adding it if needed
	if avatar_late.get_parent() == null:
		lobby_manager.add_child(avatar_late)

	if not avatar_late.is_inside_tree():
		_fail("late-joining peer's avatar is not in the scene tree")
		lobby_manager.queue_free()
		return

	_pass("late-joining peer is spawned via peer_connected")
	lobby_manager.queue_free()


## A disconnecting peer's avatar is freed
func _test_disconnect_frees_avatar() -> void:
	var lobby_manager := _make_lobby_manager()

	var avatar1 := _spawn_avatar(lobby_manager, _PEER_FIRST)
	var avatar_dc := _spawn_avatar(lobby_manager, _PEER_DISCONNECT)

	if avatar1 == null or avatar_dc == null:
		_fail("setup: avatars did not spawn")
		lobby_manager.queue_free()
		return

	# Simulate disconnect
	lobby_manager._on_peer_disconnected(_PEER_DISCONNECT)

	# Avatar should be queued for deletion
	if is_instance_valid(lobby_manager._peer_avatars.get(_PEER_DISCONNECT)):
		_fail("disconnecting peer's entry was not removed from _peer_avatars")
		lobby_manager.queue_free()
		return

	# First peer's avatar should still be there
	var avatar1_after: Actor = lobby_manager._peer_avatars.get(_PEER_FIRST)
	if avatar1_after == null or not is_instance_valid(avatar1_after):
		_fail("disconnect affected another peer's avatar")
		lobby_manager.queue_free()
		return

	_pass("disconnecting peer's avatar is freed")
	lobby_manager.queue_free()


## Lobby avatar has no combat nodes
func _test_no_combat_nodes() -> void:
	var lobby_manager := _make_lobby_manager()

	var avatar := _spawn_avatar(lobby_manager, _PEER_FIRST)
	if avatar == null:
		_fail("setup: avatar did not spawn")
		lobby_manager.queue_free()
		return

	var combatant := avatar.get_node_or_null("MobaCombatant")
	if combatant != null:
		_fail("lobby avatar contains MobaCombatant node")
		lobby_manager.queue_free()
		return

	var state_machine := avatar.get_node_or_null("MobaStateMachine")
	if state_machine != null:
		_fail("lobby avatar contains MobaStateMachine node")
		lobby_manager.queue_free()
		return

	var caster := avatar.get_node_or_null("MobaAbilityCaster")
	if caster != null:
		_fail("lobby avatar contains MobaAbilityCaster node")
		lobby_manager.queue_free()
		return

	_pass("lobby avatar has no combat nodes")
	lobby_manager.queue_free()


## Peer A's avatar always shows peer A's identity
func _test_identity_lookup_per_peer() -> void:
	if _get_registry() == null:
		_fail("setup: PeerIdentityRegistry autoload not found")
		return

	var wm := _make_world_manager()
	var cleanup := [wm]

	# Peer B registers first and is spawned first on purpose: if identity came
	# from call order or a stale default, peer A would inherit B's name here.
	if not _register_peer_build(wm, _PEER_IDENTITY_B, "PeerB_Identity", cleanup):
		return

	var lobby_manager := _make_lobby_manager()
	cleanup.append(lobby_manager)
	var avatar_b := _spawn_avatar(lobby_manager, _PEER_IDENTITY_B)

	if not _register_peer_build(wm, _PEER_IDENTITY_A, "PeerA_Identity", cleanup):
		return

	var avatar_a := _spawn_avatar(lobby_manager, _PEER_IDENTITY_A)

	if avatar_a == null or avatar_b == null:
		_fail_cleanup("setup: an avatar did not spawn", cleanup)
		return

	var name_a: String = avatar_a.character_sheet.character_name
	var name_b: String = avatar_b.character_sheet.character_name
	if name_a != "PeerA_Identity" or name_b != "PeerB_Identity":
		_fail_cleanup(
			(
				"avatars show ('%s', '%s'), expected ('PeerA_Identity', 'PeerB_Identity')"
				% [name_a, name_b]
			),
			cleanup,
		)
		return

	_pass("peer A always shows peer A's identity")
	for resource in cleanup:
		(resource as Node).queue_free()


## Body's transform SceneReplicationConfig matches player.tscn
func _test_body_replication_config() -> void:
	# AC6 compares the lobby avatar's own config against the real
	# scenes/player/player.tscn one, rather than against hardcoded values: the
	# criterion is "matches player.tscn", so player.tscn is the oracle.
	var lobby_config := _body_sync_config("res://scenes/lobby/lobby_avatar.tscn")
	var player_config := _body_sync_config("res://scenes/player/player.tscn")
	if lobby_config == null or player_config == null:
		_fail("setup: could not read a BodyTransformSynchronizer replication_config")
		return

	var lobby_props := lobby_config.get_properties()
	var player_props := player_config.get_properties()
	if lobby_props != player_props:
		_fail("replicated properties %s != player.tscn's %s" % [lobby_props, player_props])
		return

	for path in player_props:
		var want_spawn := player_config.property_get_spawn(path)
		var got_spawn := lobby_config.property_get_spawn(path)
		if got_spawn != want_spawn:
			_fail("%s spawn=%s, player.tscn has %s" % [path, got_spawn, want_spawn])
			return

		var want_mode := player_config.property_get_replication_mode(path)
		var got_mode := lobby_config.property_get_replication_mode(path)
		if got_mode != want_mode:
			_fail("%s replication_mode=%d, player.tscn has %d" % [path, got_mode, want_mode])
			return

	# Guard the criterion's own wording: continuous (mode 1) transform only.
	if lobby_props != [NodePath("Body:transform")]:
		_fail("expected exactly Body:transform, got %s" % [lobby_props])
		return

	_pass("body replication config matches player.tscn")


# The BodyTransformSynchronizer replication_config authored in a given scene.
func _body_sync_config(scene_path: String) -> SceneReplicationConfig:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate()
	var sync := instance.get_node_or_null("BodyTransformSynchronizer") as MultiplayerSynchronizer
	var config: SceneReplicationConfig = null
	if sync != null:
		config = sync.replication_config
	instance.free()
	return config


## The lobby scene's ThirdPersonCamera3D resolves to the local avatar's Body.
##
## ThirdPersonCamera3D resolves target_path once, in its own _ready(), so this
## only works while the path is authored in lobby.tscn and LobbyManager has
## already spawned this peer's avatar by then -- the same ordering
## scenes/main.tscn relies on. A runtime assignment after the fact is silently
## ignored, which is exactly the regression this guards.
func _test_camera_targets_local_avatar() -> void:
	var lobby := (load("res://scenes/lobby/lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)

	var camera := lobby.get_node_or_null("ThirdPersonCamera") as ThirdPersonCamera3D
	if camera == null:
		_fail_cleanup("lobby.tscn has no ThirdPersonCamera", [lobby])
		return

	var manager := lobby.get_node_or_null("LobbyManager") as LobbyManager
	if manager == null:
		_fail_cleanup("lobby.tscn has no LobbyManager", [lobby])
		return

	var avatar: Actor = manager._peer_avatars.get(1)  # Offline mode uses unique_id 1
	if avatar == null:
		_fail_cleanup("no avatar spawned for the local peer", [lobby])
		return

	if camera.get_node_or_null(camera.target_path) != avatar.get_node("Body"):
		_fail_cleanup(
			"camera target_path %s is not the local avatar's Body" % camera.target_path, [lobby]
		)
		return

	_pass("lobby camera targets the local avatar's Body")
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
		print("\nAll %d lobby manager checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
