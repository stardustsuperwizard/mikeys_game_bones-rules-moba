class_name WorldManager
extends Node3D

@export var spawn_points: Array[SpawnPoint] = []
@export var player_spawn_point: SpawnPoint

# Map of peer_id -> the player actor spawned for it, so a disconnect can find
# and free the right one.
var _peer_actors: Dictionary[int, Actor] = {}

@onready var _spawner: MultiplayerSpawner = get_node_or_null("MultiplayerSpawner")


func _ready() -> void:
	add_to_group("world_manager")
	if _spawner:
		_spawner.spawn_function = _spawn_actor

	# A pure client (connected, not the server) gets its world content from
	# replication instead -- spawning it locally too would double it up.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# World/bot content: always-present, authority-0 entries, spawned
	# unconditionally on server/offline exactly as before.
	for spawn_point in spawn_points:
		spawn(spawn_point, spawn_point.authority_id)

	# Connected unconditionally, not just when a peer already exists. A session
	# hosted after boot (the offline -> host transition) leaves _ready() long
	# past, and a signal only wired when has_multiplayer_peer() was already true
	# would never fire for the peers that later join.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# The local machine's own player, through the same function peer_connected
	# uses and with this peer's real id -- 1 both offline and as the server.
	# Dedicated-server is the only mode that never gets a local player, and this
	# is the only place session mode decides anything.
	if not _is_dedicated_server():
		spawn_player_for_peer(multiplayer.get_unique_id())


# The one spawn path for "this peer has a player", shared by the local-start
# case and by every remote peer that connects. Idempotent per peer id, so the
# offline-then-host transition re-requesting peer 1 keeps the existing actor
# rather than spawning a second one.
func spawn_player_for_peer(peer_id: int) -> void:
	if player_spawn_point == null:
		return
	if _peer_actors.has(peer_id) and is_instance_valid(_peer_actors[peer_id]):
		return

	_peer_actors[peer_id] = spawn(player_spawn_point, peer_id)


# Read off the SessionManager autoload, which has already run its own _ready()
# by the time any scene node does. Absent in tests that build a WorldManager
# without the autoload, where offline (a local player) is the right default.
func _is_dedicated_server() -> bool:
	var session := get_node_or_null(^"/root/SessionManager")
	return session != null and session.mode == session.Mode.DEDICATED_SERVER


# Assumes WorldManager stays attached to the room's own root node (identity
# transform, direct children) so spawn_point.transform reproduces the old
# hardcoded per-instance transforms as-is.
#
# Routed through MultiplayerSpawner.spawn() (custom spawn_function) rather
# than instantiating and add_child()-ing directly, even offline: the spawn
# function receives identical data on every peer, which is what lets a
# networked spawn reconstruct the same character_sheet/color/authority
# everywhere instead of only on the spawning peer.
func spawn(spawn_point: SpawnPoint, authority_id: int = 1) -> Actor:
	var data := {
		"scene_path": spawn_point.actor_scene.resource_path,
		"character_sheet_path": spawn_point.character_sheet.resource_path,
		"color": spawn_point.color,
		"transform": spawn_point.transform,
		"authority_id": authority_id,
	}
	if _spawner:
		return _spawner.spawn(data) as Actor
	return _spawn_actor(data)


func _spawn_actor(data: Dictionary) -> Actor:
	var actor := (load(data["scene_path"]) as PackedScene).instantiate() as Actor
	actor.character_sheet = load(data["character_sheet_path"]) as CharacterSheet
	actor.color = data["color"]
	(actor.get_node("Body") as Node3D).transform = data["transform"]
	actor.owner_id = data["authority_id"]

	# Set multiplayer authority for the actor and its movement body
	# (connecting peer stays authoritative for movement).
	actor.set_multiplayer_authority(data["authority_id"])

	# Combat state is always server-authoritative (peer 1), regardless of which
	# peer owns the actor. This is required so clients can never broadcast their
	# own claimed health to other peers.
	var combatant := actor.get_node_or_null("MobaCombatant") as Node
	if combatant != null:
		combatant.set_multiplayer_authority(1)

	var state_machine := actor.get_node_or_null("MobaStateMachine") as Node
	if state_machine != null:
		state_machine.set_multiplayer_authority(1)

	return actor


## Called when a peer connects to the session.
func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	spawn_player_for_peer(peer_id)


## Called when a peer disconnects from the session.
func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var actor: Actor = _peer_actors.get(peer_id)
	if is_instance_valid(actor):
		actor.queue_free()
	_peer_actors.erase(peer_id)
