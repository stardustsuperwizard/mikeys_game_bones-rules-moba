class_name Controller
extends Node

@onready var actor: Actor = get_parent() as Actor

func get_move_direction() -> Vector3:
	return Vector3.ZERO

func get_attack_target() -> Actor:
	return null

func get_interact_target() -> Node:
	return null
