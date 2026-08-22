# Game-specific player controller for Sword and Planet.
#
# Keyboard: W=forward, S=back, Q=strafe left, E=strafe right,
#           A=turn left, D=turn right, Space=jump.
#
# Mouse: left click is the contextual action button. What it does depends on
# what was clicked -- ground walks there, a wall walks up to it and stops, a
# hostile actor closes to melee range and attacks, an interactable closes and
# uses it. Each click issues a single order that the controller then carries
# out over the following frames; a new click, or any keyboard movement,
# replaces or cancels it.
#
# Extends Bones' Controller contract so the existing ActorBody3D/Actor
# pipeline drives movement and combat unchanged -- the mouse only decides
# *what* to ask for, never how it resolves.
class_name PlayerController3D
extends Controller

# A surface at least this upright counts as ground the player can stand on;
# anything steeper is a wall, which is walked up to rather than onto.
const WALKABLE_NORMAL_Y := 0.7

# How head-on a wall contact must be to count as "blocked" rather than
# "brushing past": the dot of the wall normal with the direction of travel,
# so this is roughly 60 degrees either side of straight into the surface.
# A glancing contact keeps walking and slides along instead, which is what
# lets a click far along a wall you are already leaning on still get there.
const WALL_BLOCK_DOT := -0.5

## How close the player must get to a clicked ground point to have arrived.
@export var arrival_distance: float = 0.4

## How close the player must get to a clicked actor before attacking it.
@export var attack_range: float = 2.0

## How close the player must get to a clicked interactable before using it.
@export var interact_range: float = 2.0

## Yaw error, in degrees, at which the auto-turn toward an order runs at full
## turn speed. Smaller errors turn proportionally slower so the facing eases
## in instead of oscillating around the target heading.
@export var turn_ease_degrees: float = 15.0

## How far the click raycast reaches into the world, in meters.
@export var max_click_distance: float = 100.0

## Physics layers the click raycast can select.
@export_flags_3d_physics var click_collision_mask: int = 1

## How long the player may fail to close on an order before it is abandoned.
## There is no pathfinding yet, so an order behind an obstacle would
## otherwise leave the player shoving into it forever.
@export var stall_timeout: float = 0.75

## Distance, in meters, that counts as real progress toward an order.
@export var stall_progress: float = 0.05

var _jump_requested := false

# The current click order -- at most one of these three is ever live.
var _destination := Vector3.ZERO
var _has_destination := false
var _destination_is_wall := false
var _attack_target: Actor = null
var _interact_target: Node = null

# Stall bookkeeping for the live order.
var _closest_distance := INF
var _stall_timer := 0.0


func _ready() -> void:
	actor.add_to_group("players")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		_jump_requested = true
	elif event.is_action_pressed("action_primary"):
		# The camera captures the mouse while right-drag look is active, which
		# parks the cursor at screen center -- a click then would pick whatever
		# happens to be under the crosshair rather than what the player aimed at.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_issue_order_from_click(get_viewport().get_mouse_position())


# Returns world-space movement direction. Keyboard input is relative to the
# player's current facing so forward/back/strafe respect which way the body
# is pointing, and takes precedence over -- and cancels -- any click order.
func get_move_direction() -> Vector3:
	var body := _body()
	if not body:
		return Vector3.ZERO

	var keyboard := _keyboard_move_direction(body)
	if keyboard != Vector3.ZERO:
		cancel_order()
		return keyboard

	return _order_move_direction(body)


# Signed turn input: negative = turn left, positive = turn right. Falls back
# to turning toward the current order when the player isn't steering.
func get_turn_direction() -> float:
	var turn := 0.0
	if Input.is_action_pressed("turn_left"):
		turn -= 1.0
	if Input.is_action_pressed("turn_right"):
		turn += 1.0
	if turn != 0.0:
		return turn
	return _order_turn_direction()


# Consumes and returns the buffered jump request.
func consume_jump() -> bool:
	var requested := _jump_requested
	_jump_requested = false
	return requested


# Bones polls these once the body has moved for the frame, so an order that
# arrived this frame resolves on the same frame it arrived.
func get_attack_target() -> Actor:
	if _attack_target == null or not _in_range_of(_attack_target, attack_range):
		return null
	var target := _attack_target
	cancel_order()
	return target


func get_interact_target() -> Node:
	if _interact_target == null or not _in_range_of(_interact_target, interact_range):
		return null
	var target := _interact_target
	cancel_order()
	return target


# Drops the live order, whatever kind it is, and resets its stall tracking.
func cancel_order() -> void:
	_has_destination = false
	_destination_is_wall = false
	_attack_target = null
	_interact_target = null
	_closest_distance = INF
	_stall_timer = 0.0


# Raycasts from the camera through the clicked pixel and turns whatever it
# hits into an order. A click that hits nothing at all just clears the
# current order.
func _issue_order_from_click(screen_position: Vector2) -> void:
	var body := _body()
	var camera := get_viewport().get_camera_3d()
	if not body or not camera:
		return

	var from := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + camera.project_ray_normal(screen_position) * max_click_distance
	)
	query.collision_mask = click_collision_mask
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)

	cancel_order()
	if hit.is_empty():
		return

	var collider := hit["collider"] as Node
	var hit_actor := _actor_of(collider)
	if hit_actor and hit_actor != actor and hit_actor.hostile:
		_attack_target = hit_actor
	elif collider and collider.is_in_group("interactables"):
		_interact_target = collider
	else:
		# Walls included: the destination sits on the clicked surface itself,
		# and the body's own collision is what stops the walk flush against
		# it. Since the approach is measured on the ground plane, a click
		# high up a wall still walks to the wall's base.
		_destination = hit["position"]
		_destination_is_wall = (hit["normal"] as Vector3).y < WALKABLE_NORMAL_Y
		_has_destination = true


func _keyboard_move_direction(body: Node3D) -> Vector3:
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


# Walks toward the live order until inside the distance at which it resolves.
# Also where stall detection is metered, since Bones calls this exactly once
# per physics frame.
func _order_move_direction(body: CharacterBody3D) -> Vector3:
	if not _refresh_order():
		return Vector3.ZERO

	var to_goal := _order_goal() - body.global_position
	to_goal.y = 0.0
	var distance := to_goal.length()
	if distance <= _order_stop_distance():
		return Vector3.ZERO

	var direction := to_goal / distance

	# A wall destination is reached as soon as the body is up against
	# something blocking the way to it: the walk can never close the last
	# body-radius of distance, so waiting on arrival_distance would leave the
	# player grinding into the wall until the stall guard eventually fired.
	# Only walls the body is pushing *into* count, so brushing along one on
	# the way somewhere else doesn't read as arrival.
	if (
		_destination_is_wall
		and body.is_on_wall()
		and body.get_wall_normal().dot(direction) < WALL_BLOCK_DOT
	):
		cancel_order()
		return Vector3.ZERO

	if distance < _closest_distance - stall_progress:
		_closest_distance = distance
		_stall_timer = 0.0
	else:
		_stall_timer += actor.get_physics_process_delta_time()
		if _stall_timer >= stall_timeout:
			cancel_order()
			return Vector3.ZERO

	return direction


func _order_turn_direction() -> float:
	var body := _body()
	if not body or not _refresh_order():
		return 0.0

	var to_goal := _order_goal() - body.global_position
	to_goal.y = 0.0
	if to_goal.length() < arrival_distance:
		return 0.0

	# The body's forward is -Z, so this is the yaw that would point it at the
	# goal. PlayerBody3D rotates by -turn, so a left turn is a negative value.
	var desired_yaw := atan2(-to_goal.x, -to_goal.z)
	var error := wrapf(desired_yaw - body.global_rotation.y, -PI, PI)
	return -clampf(rad_to_deg(error) / turn_ease_degrees, -1.0, 1.0)


# True while an order is live. Drops orders whose target has been freed --
# a killed enemy, a despawned prop -- so the player stops walking at a ghost.
func _refresh_order() -> bool:
	if _attack_target and not is_instance_valid(_attack_target):
		cancel_order()
	if _interact_target and not is_instance_valid(_interact_target):
		cancel_order()
	return _has_destination or _attack_target != null or _interact_target != null


func _order_goal() -> Vector3:
	if _attack_target:
		return _attack_target.global_position
	if _interact_target:
		return (_interact_target as Node3D).global_position
	return _destination


func _order_stop_distance() -> float:
	if _attack_target:
		return attack_range
	if _interact_target:
		return interact_range
	return arrival_distance


# Range is measured on the ground plane, matching how the approach in
# _order_move_direction decides it has arrived. Measuring in 3D instead would
# deadlock on a target whose origin sits above the floor -- a door's does --
# by stopping the walk at a distance the range check still calls too far.
func _in_range_of(target: Node, range_limit: float) -> bool:
	if not is_instance_valid(target):
		return false
	var target_position := (
		(target as Actor).global_position if target is Actor else (target as Node3D).global_position
	)
	return _ground_distance(target_position - actor.global_position) <= range_limit


func _ground_distance(offset: Vector3) -> float:
	return Vector2(offset.x, offset.z).length()


func _actor_of(collider: Node) -> Actor:
	if collider == null:
		return null
	return collider.get_parent() as Actor


func _body() -> CharacterBody3D:
	return actor.get_node_or_null("Body") as CharacterBody3D
