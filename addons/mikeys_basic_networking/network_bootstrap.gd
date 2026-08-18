extends Node
# Transport only: parses --server / --connect=<address>, establishes an
# ENetMultiplayerPeer, and assigns it. Nothing here knows what a "player"
# or an "Actor" is -- spawning/despawning on peer connect/disconnect is the
# consuming game's job, done by connecting to Godot's own native
# multiplayer.peer_connected / peer_disconnected signals (see each game's
# runtime/session_spawner.gd), not something this addon should own.

const PORT := 7777
const MAX_PEERS := 8

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		_start_server()
		return

	var address := _arg_value(args, "--connect=")
	if address != "":
		_start_client(address)

func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PEERS)
	if err != OK:
		push_error("Failed to start server on port %d: %s" % [PORT, err])
		return

	multiplayer.multiplayer_peer = peer
	print("NET: server listening on port %d" % PORT)

func _start_client(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("Failed to connect to %s:%d: %s" % [address, PORT, err])
		return

	multiplayer.multiplayer_peer = peer
	print("NET: connecting to %s:%d" % [address, PORT])

func _arg_value(args: PackedStringArray, prefix: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""
