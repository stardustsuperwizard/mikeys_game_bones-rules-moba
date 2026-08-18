class_name WorldManager
extends Node3D

@export var spawn_points: Array[SpawnPoint] = []

@onready var _spawner: MultiplayerSpawner = get_node_or_null("MultiplayerSpawner")

func _ready() -> void:
	add_to_group("world_manager")
	if _spawner:
		_spawner.spawn_function = _spawn_actor

	# A pure client (connected, not the server) gets its world content from
	# replication instead -- spawning it locally too would double it up.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	for spawn_point in spawn_points:
		spawn(spawn_point)

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
	actor.set_multiplayer_authority(data["authority_id"])
	return actor
