## Session manager for multiplayer peer lifecycle.
##
## Handles hosting, joining, and offline modes with ENet transport.
## Exposes readable mode (OFFLINE, LISTEN_SERVER, DEDICATED_SERVER).
class_name SessionManager
extends Node

enum Mode {
	OFFLINE,
	LISTEN_SERVER,
	DEDICATED_SERVER,
}

var mode: Mode = Mode.OFFLINE


func _ready() -> void:
	# Support dedicated server mode via environment variable or command-line
	if _should_start_dedicated_server():
		host(9999, true)


## Start hosting a listen-server session on the given port.
## If dedicated=true, no local player actor is spawned for peer 1.
func host(port: int, dedicated: bool = false) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error != OK:
		return error

	multiplayer.multiplayer_peer = peer
	mode = Mode.DEDICATED_SERVER if dedicated else Mode.LISTEN_SERVER

	# For listen-server (non-dedicated), spawn the host's own player
	if not dedicated:
		var world_mgr := _get_world_manager()
		if world_mgr:
			world_mgr.spawn_player_for_peer(multiplayer.get_unique_id())

	return OK


## Join a session hosted at address:port.
func join(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error

	multiplayer.multiplayer_peer = peer
	mode = Mode.LISTEN_SERVER  # Client connects to a listen-server host

	return OK


## Disconnect and return to offline mode.
func go_offline() -> void:
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE


## Check if a dedicated server should be started at boot.
func _should_start_dedicated_server() -> bool:
	# Check environment variable
	if OS.get_environment("MIKEYS_DEDICATED_SERVER") == "true":
		return true

	# Check command-line arguments for --dedicated-server
	for arg in OS.get_cmdline_args():
		if arg == "--dedicated-server":
			return true

	return false


func _get_world_manager() -> WorldManager:
	var scene := get_tree().root.get_child(0) if get_tree().root.get_child_count() > 0 else null
	if scene:
		return scene.get_node_or_null("WorldManager") as WorldManager
	return null
