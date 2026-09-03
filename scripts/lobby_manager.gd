class_name LobbyManager
extends Node3D

## Emitted when match_starting is assigned a value different from its current one.
signal match_starting_changed(value: bool)

## Emitted on the requesting peer when an inspected build arrives. Carries
## _encode_build_for_inspection()'s payload, or an empty Dictionary when the
## target peer has no spawned lobby avatar.
##
## The one delivery point for both routes: a client emits it on the server's
## reply, and the host emits it on its own local resolve. A panel connects here
## and never has to know which of the two it is running on.
signal build_inspection_received(encoded_build: Dictionary)

## Where a started match sends every present peer. The same scene
## scripts/match_controller.gd returns from in the other direction.
const ARENA_SCENE_PATH := "res://scenes/main.tscn"

@export var avatar_spawn_point: SpawnPoint

## True once the server has decided the present peers are entering a match.
##
## The same settable / on-change / signal-emitting shape MobaMatchState's
## round_in_progress keeps, and for the same reason: a MultiplayerSynchronizer
## replicating this on-change assigns the property on each client, which runs
## this setter there and emits locally. A one-shot RPC broadcast would carry the
## event but leave late arrivals with no state to read.
var match_starting: bool:
	get:
		return _match_starting
	set(value):
		if value == _match_starting:
			return
		_match_starting = value
		match_starting_changed.emit(value)

# Map of peer_id -> the avatar actor spawned for it, so a disconnect can find
# and free the right one.
var _peer_avatars: Dictionary[int, Actor] = {}

var _match_starting: bool = false

@onready var _spawner: MultiplayerSpawner = get_node_or_null("MultiplayerSpawner")


func _ready() -> void:
	if _spawner:
		_spawner.spawn_function = _spawn_avatar

	# Every peer observes match_starting to know when to transition to the arena.
	match_starting_changed.connect(_on_match_starting_changed)

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


## Request to start a match. Any peer in the lobby can call this; the server
## validates that the requester has a spawned avatar before starting the match.
##
## Matches the try_*() / request_*() / _resolve_*() pattern from Actor:
## - For offline or server, resolves locally.
## - For client, sends an RPC to the server.
func try_start_match() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_start_match.rpc_id(1)
		return

	_resolve_start_match(multiplayer.get_unique_id())


## The server's inbox for a client's match-start request.
@rpc("any_peer", "call_remote", "reliable")
func request_start_match() -> void:
	var requester_id := multiplayer.get_remote_sender_id()
	_resolve_start_match(requester_id)


## Resolve a match-start request from a peer. Validates that the peer has
## a spawned avatar in the lobby, then sets match_starting = true.
func _resolve_start_match(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var avatar: Actor = _peer_avatars.get(peer_id)
	if avatar == null or not is_instance_valid(avatar):
		return

	match_starting = true


## Request to inspect another peer's build. Any peer present in the lobby can
## call this for any other present peer; the answer arrives on
## build_inspection_received rather than as a return value, because a client
## cannot know it synchronously.
##
## Matches the try_*() / request_*() / _resolve_*() pattern from Actor:
## - For offline or server, resolves locally.
## - For client, sends an RPC to the server.
func try_inspect_build(target_peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_inspect_build.rpc_id(1, target_peer_id)
		return

	# Offline or host: there is no reply RPC to wait for, because a peer does not
	# send itself one. Emitting the resolved payload here is what keeps the host's
	# own panel from waiting forever for a message that is never addressed to it.
	build_inspection_received.emit(_resolve_inspect_build(target_peer_id))


## The server's inbox for a client's build-inspection request.
##
## The target arrives as a peer id and is re-checked against the server's own
## presence tracking, never trusted as a claim about who is present.
@rpc("any_peer", "call_remote", "reliable")
func request_inspect_build(target_peer_id: int) -> void:
	var requester_id := multiplayer.get_remote_sender_id()

	# Addressed with rpc_id to the one peer that asked, never broadcast with
	# rpc(). A build breakdown is pull, not push: no other present peer learns
	# anything from this exchange, which is the constraint that keeps build data
	# off the continuous replication path entirely.
	_reply_inspect_build.rpc_id(requester_id, _resolve_inspect_build(target_peer_id))


## Resolve a build-inspection request, returning the encoded build for a peer
## that currently has a spawned lobby avatar.
##
## An absent target -- disconnected, or never connected -- resolves to an empty
## Dictionary rather than an error or a silent drop, so the requester always gets
## an answer it can render as "not present" instead of waiting on one forever.
##
## Takes no requester id: this is a read query with nothing to gate. Any present
## peer may inspect any other present peer, so there is no ownership question and
## no reason to route it through Authority.can_perform(). Keeping it separate from
## request_inspect_build() is also what makes the reply's addressing checkable:
## the payload is computed here, and the single rpc_id() above is the only thing
## that decides who receives it.
func _resolve_inspect_build(target_peer_id: int) -> Dictionary:
	if not multiplayer.is_server():
		return {}

	var avatar: Actor = _peer_avatars.get(target_peer_id)
	if avatar == null or not is_instance_valid(avatar):
		return {}

	var registry := _identity_registry()
	if registry == null:
		return {}

	var build: MobaCharacterBuild = registry.get_peer_build(target_peer_id)
	if build == null:
		return {}

	return _encode_build_for_inspection(build)


## Encode a build's display-relevant fields into plain Variant data, following
## the same "no Resource crosses the wire" discipline WorldManager._encode_build()
## already establishes: the weapon travels as its authored resource path, and the
## disciplines as their enum ints, because a Resource put in an RPC payload is
## dropped on the wire and silently arrives as null.
##
## stat_allocation is duplicated rather than passed by reference. Inspection is a
## read: the reply must not hand the caller a live alias of the registry's own
## stored allocation, or rendering a panel could edit authoritative state.
##
## The appearance travels as its three plain String ids for the same "no Resource
## crosses the wire" reason, and reading them off the build is already a copy:
## a String read out of a StringName field is a new value, not an alias of the
## stored MobaAppearance.
func _encode_build_for_inspection(build: MobaCharacterBuild) -> Dictionary:
	var appearance := build.appearance
	var loadout := build.loadout
	return {
		"character_name": build.character_name,
		"primary_discipline": int(build.primary_discipline),
		"secondary_discipline": int(build.secondary_discipline),
		"stat_allocation": build.stat_allocation.duplicate(),
		"helm_id": "" if appearance == null else String(appearance.helm_id),
		"chest_id": "" if appearance == null else String(appearance.chest_id),
		"color_scheme_id": "" if appearance == null else String(appearance.color_scheme_id),
		"weapon_path":
		"" if loadout == null or loadout.weapon == null else loadout.weapon.resource_path,
		"action_slots":
		PackedStringArray(
			(
				[]
				if loadout == null
				else [
					loadout.action_slot_1,
					loadout.action_slot_2,
					loadout.action_slot_3,
					loadout.action_slot_4,
				]
			)
		),
		"passive_slot": "" if loadout == null else loadout.passive_slot,
	}


## The requesting client's inbox for the server's reply. Reached only through the
## rpc_id() above, so it runs on the one peer that asked and on no other.
@rpc("authority", "call_remote", "reliable")
func _reply_inspect_build(encoded_build: Dictionary) -> void:
	build_inspection_received.emit(encoded_build)


## Every peer reacts to the start by entering the arena together: the server
## because it set the property, each client because replication assigned it and
## the setter emitted there too.
##
## The awaited frame is the same one scripts/match_controller.gd waits for in
## _on_match_ended, and for the same reason -- on the server, match_starting has
## to leave through LobbyStateSynchronizer before the scene holding that
## synchronizer is torn down. Changing the scene in the same frame the property
## is set destroys the synchronizer with the change still unsent, and no client
## ever learns the match began. The wait is harmless on a client, which is
## already reacting to the replicated value.
func _on_match_starting_changed(value: bool) -> void:
	if not value:
		return

	await get_tree().process_frame
	get_tree().change_scene_to_file(ARENA_SCENE_PATH)


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
	# The peer's registered appearance, as three plain String ids and never as the
	# MobaAppearance itself -- object decoding is off, so a Resource in spawn data
	# is dropped on the wire and every remote peer would see the lobby's default
	# instead of the character standing there. The same discipline
	# WorldManager._encode_build() keeps, read here the way character_name already
	# is: the lobby carries a peer's identity, not a whole build.
	var appearance_ids := _peer_appearance_ids(authority_id)

	var data := {
		"scene_path": spawn_point.actor_scene.resource_path,
		"character_sheet_path": spawn_point.character_sheet.resource_path,
		"color": _peer_color(authority_id),
		"transform": spawn_point.transform,
		"authority_id": authority_id,
		"team": spawn_point.team,
		"character_name": _get_peer_name(authority_id),
		"helm_id": appearance_ids["helm_id"],
		"chest_id": appearance_ids["chest_id"],
		"color_scheme_id": appearance_ids["color_scheme_id"],
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

	# The same assignment WorldManager._spawn_actor() makes for a match actor, so
	# the character in the lobby is the character that walks into the arena.
	actor.appearance = _decode_appearance(data)

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


# The peer's registered appearance, flattened into the three plain String ids the
# spawn payload carries. A peer with no accepted build, or no appearance on the
# build it did have, gets three empty ids -- the same "none" value
# MobaAppearanceCatalog treats as legal in every category.
func _peer_appearance_ids(peer_id: int) -> Dictionary:
	var ids := {"helm_id": "", "chest_id": "", "color_scheme_id": ""}

	var registry := _identity_registry()
	if registry == null:
		return ids

	var build: MobaCharacterBuild = registry.get_peer_build(peer_id)
	if build == null or build.appearance == null:
		return ids

	ids["helm_id"] = String(build.appearance.helm_id)
	ids["chest_id"] = String(build.appearance.chest_id)
	ids["color_scheme_id"] = String(build.appearance.color_scheme_id)
	return ids


# Rebuild a MobaAppearance from a spawn payload's ids, or null when it carries
# none -- the same rule, and the same reasoning, as
# WorldManager._decode_appearance().
func _decode_appearance(data: Dictionary) -> MobaAppearance:
	var helm_id: String = data.get("helm_id", "")
	var chest_id: String = data.get("chest_id", "")
	var color_scheme_id: String = data.get("color_scheme_id", "")
	if helm_id == "" and chest_id == "" and color_scheme_id == "":
		return null

	var appearance := MobaAppearance.new()
	appearance.helm_id = StringName(helm_id)
	appearance.chest_id = StringName(chest_id)
	appearance.color_scheme_id = StringName(color_scheme_id)
	return appearance


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
