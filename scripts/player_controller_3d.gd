# Game-specific player controller for Sword and Planet.
# Controls: W=forward, S=back, Q=strafe left, E=strafe right,
#           A=turn left, D=turn right, Space=jump.
# Extends Bones' Controller contract so the existing ActorBody3D/Actor
# pipeline drives movement and combat unchanged.
class_name PlayerController3D
extends Controller

var _jump_requested := false

func _ready() -> void:
	actor.add_to_group("players")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		_jump_requested = true

# Returns world-space movement direction relative to the player's current
# facing so forward/back/strafe all respect which way the body is pointing.
func get_move_direction() -> Vector3:
	var body := actor.get_node_or_null("Body") as Node3D
	if not body:
		return Vector3.ZERO
	var forward := -body.global_basis.z
	var right := body.global_basis.x
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir += forward
	if Input.is_action_pressed("move_back"):
		dir -= forward
	if Input.is_action_pressed("strafe_left"):
		dir -= right
	if Input.is_action_pressed("strafe_right"):
		dir += right
	return dir.normalized()

# Signed turn input: negative = turn left, positive = turn right.
func get_turn_direction() -> float:
	var turn := 0.0
	if Input.is_action_pressed("turn_left"):
		turn -= 1.0
	if Input.is_action_pressed("turn_right"):
		turn += 1.0
	return turn

# Consumes and returns the buffered jump request.
func consume_jump() -> bool:
	var requested := _jump_requested
	_jump_requested = false
	return requested
