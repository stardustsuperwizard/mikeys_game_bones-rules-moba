## Session manager for multiplayer peer lifecycle.
##
## Handles hosting, joining, and offline modes with ENet transport, and exposes
## a readable `mode` so other code can branch on the session without
## re-deriving it from `multiplayer.has_multiplayer_peer()`/`is_server()`.
##
## Registered as the `SessionManager` autoload, so this script deliberately
## carries no `class_name`: a global class sharing an autoload's name is a
## parse error in Godot 4 ("hides an autoload singleton"). `tests/test_bootstrap.gd`
## is the existing autoload following the same rule.
extends Node

enum Mode {
	OFFLINE,
	LISTEN_SERVER,
	DEDICATED_SERVER,
}

## Port used when a dedicated server is started from the boot flag/environment,
## where there is no operator to choose one. Overridable with MIKEYS_SERVER_PORT.
const DEFAULT_DEDICATED_PORT: int = 9999

var mode: Mode = Mode.OFFLINE


# A dedicated server has no local operator to click a menu, so the dedicated
# path is reachable at boot from a command-line flag or environment variable in
# addition to the host() API. This runs before the main scene is instantiated,
# which is what lets WorldManager see DEDICATED_SERVER and skip its local
# player -- the one place session mode is allowed to decide anything.
func _ready() -> void:
	if _should_start_dedicated_server():
		host(_dedicated_port(), true)


## Start a server session on the given port.
## When `dedicated` is true the session runs with no local player actor.
func host(port: int, dedicated: bool = false) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error != OK:
		return error

	multiplayer.multiplayer_peer = peer
	mode = Mode.DEDICATED_SERVER if dedicated else Mode.LISTEN_SERVER

	# Hosting from an already-running scene: WorldManager._ready() has been and
	# gone, so the host's own player is spawned here instead. Same function and
	# same peer id the peer_connected path uses; spawn_player_for_peer() is
	# idempotent per peer, so the offline-then-host case does not double up.
	if not dedicated:
		var world_manager := _get_world_manager()
		if world_manager:
			world_manager.spawn_player_for_peer(multiplayer.get_unique_id())

	return OK


## Join a session hosted at address:port.
##
## A client cannot tell whether its host is playing, so the joined session is
## reported as LISTEN_SERVER: the distinction that matters to a client is
## "networked" versus OFFLINE, and DEDICATED_SERVER means "this process is a
## server with no local player," which a client never is.
func join(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error

	multiplayer.multiplayer_peer = peer
	mode = Mode.LISTEN_SERVER

	return OK


## Drop any network peer and return to offline single-player.
##
## Restores an OfflineMultiplayerPeer rather than assigning null. Godot 4's
## default multiplayer_peer is already an OfflineMultiplayerPeer -- not null --
## and that is what reports unique_id 1, is_server() true and
## has_multiplayer_peer() true with nothing networked. Assigning null instead
## leaves the MultiplayerAPI with no peer at all, and MultiplayerSpawner.spawn()
## refuses to spawn without one: offline then produces neither a player nor the
## bots. Task #312 asks for "today's single-player-vs-bots behavior exactly",
## and this is the assignment that reproduces it.
func go_offline() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE


## True when this process was launched to be a dedicated server.
func _should_start_dedicated_server() -> bool:
	if OS.get_environment("MIKEYS_DEDICATED_SERVER") == "true":
		return true

	return "--dedicated-server" in OS.get_cmdline_args()


func _dedicated_port() -> int:
	var configured := OS.get_environment("MIKEYS_SERVER_PORT")
	if configured.is_valid_int():
		return configured.to_int()
	return DEFAULT_DEDICATED_PORT


# Resolved through the "world_manager" group rather than a scene path: autoloads
# are children of root and are added before the main scene, so root.get_child(0)
# is an autoload, not the running world. WorldManager joins the group in its own
# _ready(), which is the lookup the rest of the codebase already uses.
func _get_world_manager() -> WorldManager:
	return get_tree().get_first_node_in_group("world_manager") as WorldManager
