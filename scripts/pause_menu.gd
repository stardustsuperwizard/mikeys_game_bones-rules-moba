## Pause overlay: Resume and Quit during play, opened by the `pause` action.
##
## Ships inside `scenes/main.tscn` so it is reachable whenever the world scene
## is running -- including when that scene is run directly from the editor,
## without the main menu ever loading.
##
## **Quit behavior, chosen deliberately (Issue #314 asks for one and asks that
## it be documented):** Quit returns to the main menu rather than exiting the
## application. It drops the session through `SessionManager.go_offline()` and
## loads `scenes/ui/main_menu.tscn`, so a player who quits a session can start
## or join another one without relaunching the game. Exiting the process would
## have been equally acceptable per the Issue; returning to the menu is the
## choice that keeps the menu's own three entry points reachable.
##
## Two properties are set on the root in `scenes/ui/pause_menu.tscn`, and their
## reasons are recorded here rather than beside them: a `.tscn` can carry `;`
## comments, but the Godot editor drops them on the next resave, so a rationale
## written there does not survive anyone opening the scene.
##
## - `layer = 10`. The combat HUD (`rules/ui/moba_combat_hud.tscn`) is itself a
##   CanvasLayer and leaves `layer` at its default 1. A plain Control would draw
##   on layer 0, underneath it; the overlay has to cover the HUD, so it takes a
##   higher layer of its own. This is also why the root is a CanvasLayer at all.
## - `process_mode = 3` (PROCESS_MODE_ALWAYS). With the tree paused only ALWAYS
##   nodes still receive `_input()`, so without it Escape could open the overlay
##   but never close it again.
##
## `tests/menu_pause_test.gd` asserts both, so a resave that drops them fails
## there rather than silently shipping an unclosable overlay behind the HUD.
extends CanvasLayer

const _MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var _resume_button: Button = $Overlay/Center/Panel/Margin/Buttons/ResumeButton
@onready var _quit_button: Button = $Overlay/Center/Panel/Margin/Buttons/QuitButton


func _ready() -> void:
	_resume_button.pressed.connect(_on_resume)
	_quit_button.pressed.connect(_on_quit)


# _input rather than _unhandled_input: the overlay's own Buttons consume input
# while it is open, so an unhandled-input handler would never see the second
# Escape press and the overlay could be opened but not closed.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return

	if get_tree().paused:
		_on_resume()
	else:
		_open()

	get_viewport().set_input_as_handled()


func _open() -> void:
	get_tree().paused = true
	visible = true


func _on_resume() -> void:
	get_tree().paused = false
	visible = false


func _on_quit() -> void:
	# Unpause before changing scene: `paused` is a property of the tree, not of
	# the scene in it, so leaving it true would carry the pause into the main
	# menu and freeze its buttons.
	get_tree().paused = false
	visible = false

	# Drop the session through the #312 API rather than touching
	# `multiplayer_peer` here -- transport belongs in SessionManager.
	var session := get_node_or_null(^"/root/SessionManager")
	if session != null:
		session.go_offline()

	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)
