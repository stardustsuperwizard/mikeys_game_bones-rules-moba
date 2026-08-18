# Modular isometric-style camera for Sword and Planet.
# Attach to a Camera3D node. Configure the target and offsets via exports.
# The camera follows a target node at a fixed isometric offset.
class_name IsometricCamera3D
extends Camera3D

## Node path to the target this camera tracks.
@export var target_path: NodePath = NodePath("")

## Horizontal distance from the target.
@export var distance: float = 12.0

## Vertical height above the target.
@export var height: float = 10.0

## Horizontal angle around the target in degrees (0 = positive-Z axis).
@export var angle_degrees: float = 45.0

## Smoothing factor (0 = instant, higher = slower follow).
@export var smoothing: float = 0.0

var _target: Node3D = null

func _ready() -> void:
	if target_path != NodePath(""):
		_target = get_node(target_path) as Node3D
	_update_transform()

func _process(delta: float) -> void:
	_update_transform()

func _update_transform() -> void:
	var origin: Vector3 = Vector3.ZERO
	if _target != null:
		origin = _target.global_position

	var angle_rad := deg_to_rad(angle_degrees)
	var offset := Vector3(
		sin(angle_rad) * distance,
		height,
		cos(angle_rad) * distance
	)

	var desired_pos := origin + offset
	if smoothing > 0.0:
		global_position = global_position.lerp(desired_pos, 1.0 - exp(-smoothing * get_process_delta_time()))
	else:
		global_position = desired_pos

	look_at(origin, Vector3.UP)
