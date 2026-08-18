class_name PlayerController
extends Controller

# Exported (not const) so a differently-scaled presentation can retune them
# per instance -- same pattern SimpleAIController already uses for aggro_range/
# attack_range. The 2D room is pixel-scale, not small-unit like 3D, so its
# Player overrides these; 3D's default here is unchanged.
@export var attack_range := 2.0
@export var interact_range := 2.0

var _attack_requested := false
var _interact_requested := false

func _ready() -> void:
	actor.add_to_group("players")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_attack_requested = true
	if event.is_action_pressed("interact"):
		_interact_requested = true

func get_move_direction() -> Vector3:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return Vector3(input_dir.x, 0, input_dir.y).normalized()

func get_attack_target() -> Actor:
	if not _attack_requested:
		return null
	_attack_requested = false

	var nearest: Actor = null
	var nearest_dist := attack_range
	for node in actor.get_tree().get_nodes_in_group("nonplayers"):
		var nonplayer := node as Actor
		if not nonplayer or not nonplayer.hostile:
			continue
		var dist := actor.global_position.distance_to(nonplayer.global_position)
		if dist <= nearest_dist:
			nearest = nonplayer
			nearest_dist = dist
	return nearest

func get_interact_target() -> Node:
	if not _interact_requested:
		return null
	_interact_requested = false
	return get_nearby_interactable()

# Same search as get_interact_target(), but non-consuming and independent of
# whether interact was actually pressed -- for UI (an on-screen "Press E to
# interact" prompt) that needs to know what's in range every frame.
func get_nearby_interactable() -> Node:
	var nearest: Node = null
	var nearest_dist := interact_range
	for node in actor.get_tree().get_nodes_in_group("interactables"):
		var interactable := node as Node3D
		if not interactable:
			continue
		var dist := actor.global_position.distance_to(interactable.global_position)
		if dist <= nearest_dist:
			nearest = interactable
			nearest_dist = dist
	return nearest
