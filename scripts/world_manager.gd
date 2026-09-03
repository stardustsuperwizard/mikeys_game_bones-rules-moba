class_name WorldManager
extends Node3D

# The baseline a build's stat allocation is added on top of. Preloaded rather
# than load()-ed per spawn: it is authored single-instance data, and a parse-time
# failure here is a louder, earlier signal than a null at spawn.
const _BASELINE_STAT_BLOCK := preload("res://rules/data/stat_blocks/baseline.tres")

# Reported when the PeerIdentityRegistry autoload is missing, which means the
# project is misconfigured rather than that a submission was illegal.
const _FAILURE_NO_REGISTRY := "PeerIdentityRegistry autoload not found"

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

	# The build is passed in here rather than looked up inside spawn(), because
	# spawn() is also the path for world and bot content. Only a peer has a build.
	_peer_actors[peer_id] = spawn(player_spawn_point, peer_id, get_peer_build(peer_id))


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
#
# `build` is the character build the spawned actor should be equipped with, and
# is deliberately a parameter rather than something this function looks up.
# spawn() is the single path for every spawn point, world and bot content
# included, and those are not peers: an actor spawned without a build keeps the
# loadout and stats its scene authored. Defaulting to a lookup here handed the
# per-peer fallback build to enemies as well, quietly restatting them.
func spawn(
	spawn_point: SpawnPoint, authority_id: int = 1, build: MobaCharacterBuild = null
) -> Actor:
	var data := {
		"scene_path": spawn_point.actor_scene.resource_path,
		"character_sheet_path": spawn_point.character_sheet.resource_path,
		"color": spawn_point.color,
		"transform": spawn_point.transform,
		"authority_id": authority_id,
		"team": spawn_point.team,
	}

	# Absent, not null, when there is no build: _spawn_actor() runs on every peer
	# off this payload, and "no key" is the one state that cannot be confused with
	# a build that failed to encode.
	if build != null:
		data["build"] = _encode_build(build)
	if _spawner:
		return _spawner.spawn(data) as Actor
	return _spawn_actor(data)


func _spawn_actor(data: Dictionary) -> Actor:
	var actor := (load(data["scene_path"]) as PackedScene).instantiate() as Actor
	actor.character_sheet = load(data["character_sheet_path"]) as CharacterSheet
	actor.color = data["color"]
	(actor.get_node("Body") as Node3D).transform = data["transform"]
	actor.owner_id = data["authority_id"]
	actor.team = data["team"]

	# Equip the build the server accepted for this peer, replacing whatever
	# loadout the actor scene baked in at design time. Plain property assignment,
	# matching character_sheet/color above -- spawn initialization, not a
	# mutator-method call, so command_mutator_contract_test.gd stays satisfied.
	#
	# stat_block is assigned before the actor enters the tree, which is what makes
	# it stick: MobaCombatant seeds its runtime stat block from this property, so
	# an effective block set here is the one health and resource are sized from.
	#
	# Only when the payload carries a build. World and bot actors are spawned
	# without one and are left exactly as their scene authored them -- equipping
	# them from the per-peer fallback would be a silent balance change to actors
	# that have no build to submit in the first place.
	var combatant := actor.get_node_or_null("MobaCombatant") as MobaCombatant
	if combatant != null and data.has("build"):
		var build := _decode_build(data["build"])
		combatant.stat_block = build.get_effective_stat_block(_BASELINE_STAT_BLOCK)
		combatant.loadout = build.loadout

	# Set multiplayer authority for the actor and its movement body
	# (connecting peer stays authoritative for movement).
	actor.set_multiplayer_authority(data["authority_id"])

	# Combat state is always server-authoritative (peer 1), regardless of which
	# peer owns the actor. This is required so clients can never broadcast their
	# own claimed health to other peers.
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

	var registry := _identity_registry()
	if registry != null:
		registry.clear_peer(peer_id)


## Submit a character build on behalf of a peer, and store it if the server
## accepts it. Returns the ActionResult so a caller can surface the refusal.
##
## This is a thin delegator to PeerIdentityRegistry for the storage part.
## The submission goes through ActionRunner via the registry, which applies
## Authority.can_perform(): `requester_id` is the peer that asked, `actor.owner_id`
## is who it asked for, and a mismatch is refused without either this function or
## the Action containing an ownership check of its own.
func submit_build(peer_id: int, build: MobaCharacterBuild, requester_id: int = -1) -> ActionResult:
	var actor: Actor = _peer_actors.get(peer_id)
	if actor == null:
		return ActionResult.new(false, MobaSubmitBuildAction.FAILURE_NO_ACTOR)

	var registry := _identity_registry()
	if registry == null:
		return ActionResult.new(false, _FAILURE_NO_REGISTRY)

	return registry.submit_build(peer_id, actor, build, requester_id)


## The build a peer's actor should spawn with: the last one the server accepted,
## or the shipped fallback if that peer has never had one accepted.
## This is a thin delegator to PeerIdentityRegistry.
func get_peer_build(peer_id: int) -> MobaCharacterBuild:
	var registry := _identity_registry()
	if registry == null:
		push_error(_FAILURE_NO_REGISTRY)
		return null
	return registry.get_peer_build(peer_id)


# The PeerIdentityRegistry autoload, resolved by node path rather than by its
# global name for the same reason _is_dedicated_server() resolves SessionManager
# that way: a bare global reference makes this script fail to compile wherever
# the autoload is absent, and returning null lets the caller say so instead.
#
# Deliberately the only place this script knows where peer builds live. The
# shipped fallback for a peer with no accepted build is the registry's to define,
# not this node's -- a second copy of that constant here is exactly the
# duplication moving the storage out was meant to remove.
func _identity_registry() -> Node:
	return get_node_or_null(^"/root/PeerIdentityRegistry")


# Flatten a build into plain Variant data for MultiplayerSpawner.spawn().
#
# Resources cannot go in this dictionary. Spawn data is encoded with
# var_to_bytes and object decoding is off (SceneMultiplayer.allow_object_decoding
# defaults false and this project never enables it), so a MobaLoadout or
# MobaStatBlock placed here survives an offline spawn -- which never serializes
# -- and is dropped on the wire, giving every remote peer the scene's baked
# loadout instead of the player's. That is precisely the bug this task exists to
# fix, and it would be invisible in single-player. Hence plain fields, mirroring
# how character_sheet already travels as a path rather than as a CharacterSheet.
#
# The weapon travels as a resource path for the same reason. Weapons are authored
# files picked in the creation screen, never built at runtime, so a path always
# resolves on the far side.
func _encode_build(build: MobaCharacterBuild) -> Dictionary:
	var loadout := build.loadout
	return {
		"character_name": build.character_name,
		"primary_discipline": int(build.primary_discipline),
		"secondary_discipline": int(build.secondary_discipline),
		"stat_allocation": build.stat_allocation.duplicate(),
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


# Rebuild a MobaCharacterBuild from _encode_build()'s output. Runs on every peer,
# including the one that spawned, so the server and its clients construct the
# combatant from the same bytes rather than the server taking a shortcut the
# clients cannot.
func _decode_build(data: Dictionary) -> MobaCharacterBuild:
	var loadout := MobaLoadout.new()
	var action_slots: PackedStringArray = data["action_slots"]
	for i in range(action_slots.size()):
		loadout.set_action_slot(i + 1, action_slots[i])
	loadout.passive_slot = data["passive_slot"]

	var weapon_path: String = data["weapon_path"]
	if weapon_path != "":
		loadout.weapon = load(weapon_path) as MobaWeapon

	var build := MobaCharacterBuild.new()
	build.character_name = data["character_name"]
	build.primary_discipline = data["primary_discipline"]
	build.secondary_discipline = data["secondary_discipline"]
	build.stat_allocation.assign(data["stat_allocation"])
	build.loadout = loadout

	return build
