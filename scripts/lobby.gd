## Lobby scene controller: wires up the UI to the LobbyManager.
class_name Lobby
extends Node

@onready var lobby_manager: LobbyManager = $LobbyManager
@onready var start_button: Button = $CanvasLayer/StartMatchButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_match_pressed)


func _on_start_match_pressed() -> void:
	lobby_manager.try_start_match()
