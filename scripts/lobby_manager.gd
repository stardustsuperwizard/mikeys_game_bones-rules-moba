class_name LobbyManager
extends Node3D

@export var avatar_spawn_point: SpawnPoint

# Map of peer_id -> the avatar actor spawned for it, so a disconnect can find
# and free the right one.
var _peer_avatars: Dictionary[int, Actor] = {}

@onready var _spawner: MultiplayerSpawner = get_node_or_null("MultiplayerSpawner")


func _ready() -> void:
	if _spawner:
		_spawner.spawn_function = _spawn_avatar

	# A pure client (connected, not the server) gets avatars from
	# replication instead -- spawning them locally too would double them up.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Connected unconditionally, not just when a peer already exists.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Spawn the local player's avatar if offline or as the server.
	if not _is_dedicated_server():
		spawn_avatar_for_peer(multiplayer.get_unique_id())


# Check if this is a dedicated server (no local player).
func _is_dedicated_server() -> bool:
	var session := get_node_or_null(^"/root/SessionManager")
	return session != null and session.mode == session.Mode.DEDICATED_SERVER


# Spawn an avatar for a peer, matching how WorldManager spawns a player.
func spawn_avatar_for_peer(peer_id: int) -> void:
	if _peer_avatars.has(peer_id) and is_instance_valid(_peer_avatars[peer_id]):
		return

	if avatar_spawn_point == null:
		return

	# The authored SpawnPoint is shared, single-instance data: read from it,
	# never write to it. authority_id travels as spawn()'s own parameter.
	_peer_avatars[peer_id] = spawn(avatar_spawn_point, peer_id)


# Spawn through the MultiplayerSpawner or directly if none exists.
func spawn(spawn_point: SpawnPoint, authority_id: int) -> Actor:
	var data := {
		"scene_path": spawn_point.actor_scene.resource_path,
		"character_sheet_path": spawn_point.character_sheet.resource_path,
		"color": _peer_color(authority_id),
		"transform": spawn_point.transform,
		"authority_id": authority_id,
		"team": spawn_point.team,
		"character_name": _get_peer_name(authority_id),
	}

	if _spawner:
		return _spawner.spawn(data) as Actor
	return _spawn_avatar(data)


func _spawn_avatar(data: Dictionary) -> Actor:
	var actor := (load(data["scene_path"]) as PackedScene).instantiate() as Actor
	var sheet: CharacterSheet = (load(data["character_sheet_path"]) as CharacterSheet).duplicate()
	sheet.character_name = data.get("character_name", sheet.character_name)
	actor.character_sheet = sheet
	actor.color = data["color"]
	(actor.get_node("Body") as Node3D).transform = data["transform"]
	actor.owner_id = data["authority_id"]
	actor.team = data["team"]

	# Update the name display label
	var name_display := actor.get_node_or_null("Body/NameDisplay") as Label3D
	if name_display != null:
		name_display.text = sheet.character_name

	# Set multiplayer authority for the actor and its movement body
	actor.set_multiplayer_authority(data["authority_id"])

	return actor


# Called when a peer connects to the session.
func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	spawn_avatar_for_peer(peer_id)


# Called when a peer disconnects from the session.
func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var actor: Actor = _peer_avatars.get(peer_id)
	if is_instance_valid(actor):
		actor.queue_free()
	_peer_avatars.erase(peer_id)


# Look up the peer's registered character name. Returns the fallback if the peer
# has no accepted build, or a placeholder if the registry is unavailable.
func _get_peer_name(peer_id: int) -> String:
	var registry := _identity_registry()
	if registry == null:
		return "Peer %d" % peer_id

	var build: MobaCharacterBuild = registry.get_peer_build(peer_id)
	if build == null:
		return "Peer %d" % peer_id

	return build.character_name


# Source the avatar's color. For now, returns a fixed default for every peer.
# A future appearance system can replace only this lookup.
func _peer_color(_peer_id: int) -> Color:
	# Every peer gets the lobby's own authored default, read off the spawn point
	# rather than restated as a literal here: a second copy of the colour is free
	# to drift from the one an author edits. There is no per-character colour
	# field to read yet (#283); when there is, only this function changes.
	if avatar_spawn_point != null:
		return avatar_spawn_point.color
	return Color(0.5, 0.7, 1.0, 1.0)


# The PeerIdentityRegistry autoload, resolved by node path for the same reason
# WorldManager does: a bare global reference makes this script fail to compile
# wherever the autoload is absent.
func _identity_registry() -> Node:
	return get_node_or_null(^"/root/PeerIdentityRegistry")
