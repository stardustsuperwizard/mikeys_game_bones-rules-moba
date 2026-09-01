class_name WorldManager
extends Node3D

@export var spawn_points: Array[SpawnPoint] = []
@export var player_spawn_point: SpawnPoint

@onready var _spawner: MultiplayerSpawner = get_node_or_null("MultiplayerSpawner")

# Map of peer_id -> spawned actor for peer-specific player actors
var _peer_actors: Dictionary[int, Actor] = {}


func _ready() -> void:
	add_to_group("world_manager")
	if _spawner:
		_spawner.spawn_function = _spawn_actor

	# A pure client (connected, not the server) gets its world content from
	# replication instead -- spawning it locally too would double it up.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Spawn world/bot content from spawn_points (non-player spawns)
	for spawn_point in spawn_points:
		spawn(spawn_point, spawn_point.authority_id)

	# Connect peer lifecycle signals for per-peer player spawn/despawn
	if multiplayer.has_multiplayer_peer():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# Spawn a player actor for a connecting peer.
# Uses the same spawn code path as offline/listen-server bootstrap.
func spawn_player_for_peer(peer_id: int) -> void:
	if not player_spawn_point:
		return

	var actor := spawn(player_spawn_point, peer_id)
	_peer_actors[peer_id] = actor


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
	actor.set_multiplayer_authority(data["authority_id"])
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

	var actor := _peer_actors.get(peer_id)
	if actor:
		actor.queue_free()
		_peer_actors.erase(peer_id)
