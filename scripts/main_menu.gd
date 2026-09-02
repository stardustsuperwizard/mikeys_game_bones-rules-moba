## Main menu: the player's entry point into a session.
##
## Offers the three session choices from Issue #314, none of which needs a
## command-line flag:
## - Play Offline: `SessionManager.go_offline()`, then the world scene
## - Host: `SessionManager.host(port)`, then the world scene
## - Join: `SessionManager.join(address, port)`, then the world scene
##
## Also offers an entry point to character creation (#335) where a player can
## build, name, save, and load characters.
##
## This is a thin wrapper over the #312 API: it validates the text fields,
## calls one of those three methods, and changes scene. No transport logic
## lives here -- `ENetMultiplayerPeer` is created only inside SessionManager.
##
## Ordering matters, and it is deliberate: the session is established *before*
## `scenes/main.tscn` is loaded. `WorldManager._ready()` then sees the finished
## session and takes its own branch -- a server (offline or listen-server)
## spawns the world content plus the local player exactly once, and a pure
## client takes its early return and spawns nothing locally. Loading the world
## first and hosting afterwards would work too (`SessionManager.host()` covers
## that case by looking up the `world_manager` group), but it would spawn the
## host's player through a second, later path for no reason.
extends Control

const _WORLD_SCENE := "res://scenes/main.tscn"
const _CHARACTER_CREATION_SCENE := "res://scenes/ui/character_creation.tscn"

## Highest port number a peer can bind. Ports are 16-bit and 0 means
## "let the OS choose", which a player typing a port never wants.
const _MAX_PORT: int = 65535

# Resolved in _ready() off the one container they all live under, rather than
# with @onready and a full path each: the paths are long enough that spelling
# them out individually runs past the line length gdlint enforces.
var _offline_button: Button
var _character_button: Button
var _host_button: Button
var _host_port_input: LineEdit
var _join_button: Button
var _join_address_input: LineEdit
var _join_port_input: LineEdit
var _status_label: Label


func _ready() -> void:
	var menu := $CenterContainer/VBoxContainer as VBoxContainer
	_offline_button = menu.get_node(^"OfflineButton")
	_character_button = menu.get_node(^"CharacterButton")
	_host_button = menu.get_node(^"HostContainer/HostButton")
	_host_port_input = menu.get_node(^"HostContainer/HBoxContainer/PortInput")
	_join_button = menu.get_node(^"JoinContainer/JoinButton")
	_join_address_input = menu.get_node(^"JoinContainer/HBoxContainer/AddressInput")
	_join_port_input = menu.get_node(^"JoinContainer/HBoxContainer2/JoinPortInput")
	_status_label = menu.get_node(^"StatusLabel")

	_offline_button.pressed.connect(_on_play_offline)
	_character_button.pressed.connect(_on_character_creation)
	_host_button.pressed.connect(_on_host)
	_join_button.pressed.connect(_on_join)

	_host_port_input.text = str(_default_port())
	_join_address_input.text = "localhost"
	_join_port_input.text = str(_default_port())
	_status_label.text = ""


## Offline is the zero-setup path: no peer, no fields, straight into the world.
func _on_play_offline() -> void:
	var session := _session()
	if session != null:
		session.go_offline()

	_enter_world()


## Character creation: open the character creation screen.
func _on_character_creation() -> void:
	get_tree().change_scene_to_file(_CHARACTER_CREATION_SCENE)


func _on_host() -> void:
	var port := _parse_port(_host_port_input.text)
	if port < 0:
		return

	var session := _session()
	if session == null:
		_report("SessionManager autoload is missing; cannot host.")
		return

	var error: Error = session.host(port)
	if error != OK:
		# Almost always "port already in use". Surfaced in the menu rather than
		# only on stderr: the player is the one who has to pick another port,
		# and a button that silently does nothing reads as a broken build.
		_report("Could not host on port %d (error %d)." % [port, error])
		return

	_enter_world()


func _on_join() -> void:
	var address := _join_address_input.text.strip_edges()
	if address.is_empty():
		_report("Enter the address of the host to join.")
		return

	var port := _parse_port(_join_port_input.text)
	if port < 0:
		return

	var session := _session()
	if session == null:
		_report("SessionManager autoload is missing; cannot join.")
		return

	# create_client() only fails here on a malformed address or a socket the OS
	# refuses. A host that is simply not listening still returns OK and fails
	# asynchronously, which is Godot's ENet behavior, not something this menu
	# can detect synchronously.
	var error: Error = session.join(address, port)
	if error != OK:
		_report("Could not join %s:%d (error %d)." % [address, port, error])
		return

	_enter_world()


func _enter_world() -> void:
	get_tree().change_scene_to_file(_WORLD_SCENE)


## Parse and range-check a port field. Returns -1 (and reports) when invalid,
## so callers can bail without a second error path.
func _parse_port(text: String) -> int:
	var trimmed := text.strip_edges()
	if not trimmed.is_valid_int():
		_report("Port must be a number.")
		return -1

	var port := trimmed.to_int()
	if port <= 0 or port > _MAX_PORT:
		_report("Port must be between 1 and %d." % _MAX_PORT)
		return -1

	return port


func _report(message: String) -> void:
	_status_label.text = message
	printerr(message)


## The port pre-filled in both fields, taken from SessionManager so the menu and
## the dedicated-server boot path do not drift apart.
func _default_port() -> int:
	var session := _session()
	if session == null:
		return 9999
	return session.DEFAULT_DEDICATED_PORT


## The SessionManager autoload, resolved by node path rather than by its global
## identifier. `scripts/world_manager.gd` resolves it the same way and for the
## same reason: autoload *identifiers* are not registered when Godot runs a
## `--script` SceneTree (the mode `tests/` integration checks use), so a bare
## `SessionManager` reference makes this script fail to compile there -- and
## since the pause menu ships inside `scenes/main.tscn`, that failure would take
## the script off a node in the world scene every one of those tests loads.
func _session() -> Node:
	return get_node_or_null(^"/root/SessionManager")
