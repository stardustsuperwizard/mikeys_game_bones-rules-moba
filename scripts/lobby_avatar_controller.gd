class_name LobbyAvatarController
extends Controller


func get_move_direction() -> Vector3:
	if actor == null:
		return Vector3.ZERO

	var body := actor.get_node_or_null("Body") as Node3D
	if body == null:
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
