## MOBA aim-assist algorithm implementing nearest-in-cone selection,
## slerp-based direction interpolation, and device-specific magnetism multipliers.
##
## This module is pure: all functions are static, deterministic, and touch
## no node or scene tree. It accepts pre-filtered arrays of candidates
## and pre-known direction inputs, returning interpolated directions and
## clamp-guarded magnetism values.
##
## Integration into ability activation (reading the active device,
## gathering/filtering candidates, applying the locked target) is out
## of scope and handled elsewhere (see #272).
class_name MobaAimAssist
extends RefCounted


## Path to the device-multiplier data table.
const _DATA_PATH := "res://rules/data/aim_assist.json"

## Cached device multiplier table, loaded once.
static var _multiplier_table: Dictionary = {}

## Whether the multiplier table has been loaded.
static var _table_loaded: bool = false


## Select the nearest in-cone candidate by smallest angular deviation
## from the aim direction.
##
## Args:
##   aim_direction: The raw aim direction (must be normalized or near-unit length)
##   caster_position: The caster's world position
##   candidates: Array[Node] of already-filtered candidate targets
##   cone_half_angle_degrees: The cone half-angle in degrees
##
## Returns: The candidate with the smallest angular deviation from aim_direction,
##   or null if no candidates fall within the cone.
static func select_nearest_in_cone(
	aim_direction: Vector3,
	caster_position: Vector3,
	candidates: Array[Node],
	cone_half_angle_degrees: float
) -> Node:
	if candidates.is_empty():
		return null

	var cone_half_angle_radians := deg_to_rad(cone_half_angle_degrees)
	var best_candidate: Node = null
	var best_angle: float = cone_half_angle_radians + 0.1  # Initialize above threshold

	for candidate in candidates:
		if candidate == null or not is_instance_valid(candidate):
			continue

		var candidate_pos := _get_position(candidate)
		var to_candidate := candidate_pos - caster_position
		if to_candidate.length_squared() <= 0.0:
			continue

		to_candidate = to_candidate.normalized()
		var angle := aim_direction.angle_to(to_candidate)

		# Check if in cone
		if angle > cone_half_angle_radians:
			continue

		# Check if this is the best so far
		if angle < best_angle:
			best_angle = angle
			best_candidate = candidate

	return best_candidate


## Resolve the aim direction given a raw direction, an optional target,
## and an effective magnetism value.
##
## When target is null, returns raw_aim_direction unchanged.
## When target is present, uses slerp to interpolate between the raw aim
## direction and the direction to the target, with magnetism as the blend factor
## (0.0 = raw direction, 1.0 = exact direction to target).
##
## Args:
##   raw_aim_direction: The unaided aim direction (normalized)
##   target: The resolved target (Node), or null
##   caster_position: The caster's world position
##   magnetism: Effective magnetism in [0.0, 1.0]
##
## Returns: The slerp-interpolated direction toward the target, or the raw direction.
static func resolve_direction(
	raw_aim_direction: Vector3,
	target: Node,
	caster_position: Vector3,
	magnetism: float
) -> Vector3:
	if target == null or not is_instance_valid(target):
		return raw_aim_direction

	var target_pos := _get_position(target)
	var to_target := target_pos - caster_position
	if to_target.length_squared() <= 0.0:
		return raw_aim_direction

	to_target = to_target.normalized()

	# Slerp from raw aim direction to target direction, with magnetism as blend factor.
	# magnetism 0.0 returns raw_aim_direction (slerp(from, to, 0.0) = from)
	# magnetism 1.0 returns to_target (slerp(from, to, 1.0) = to)
	# magnetism 0.5 returns the angular halfway point
	return raw_aim_direction.slerp(to_target, magnetism)


## Calculate the effective magnetism clamped to [0.0, 1.0].
##
## Args:
##   ability_magnetism: Magnetism value authored on the ability [0.0, 1.0]
##   device_multiplier: Device-specific multiplier from aim_assist.json
##
## Returns: clamp(ability_magnetism * device_multiplier, 0.0, 1.0)
static func effective_magnetism(ability_magnetism: float, device_multiplier: float) -> float:
	return clamp(ability_magnetism * device_multiplier, 0.0, 1.0)


## Return the locked target direction if present, or the raw aim direction.
##
## This is the pure half of hard_lock consumption: it does not read or
## search for a lock, but returns the supplied direction verbatim when
## present, or falls back to the raw aim direction.
##
## Args:
##   locked_target_direction: A locked target direction (Vector3), or null
##   raw_aim_direction: The unaided aim direction
##
## Returns: locked_target_direction if present and valid, else raw_aim_direction
static func resolve_locked_target(
	locked_target_direction: Variant,
	raw_aim_direction: Vector3
) -> Vector3:
	if locked_target_direction is Vector3:
		return locked_target_direction
	return raw_aim_direction


## Load (once, cached) and return the device multiplier for the given device key.
##
## Args:
##   device_key: One of "mouse", "gamepad", or "touch"
##
## Returns: The multiplier value from aim_assist.json, or 0.0 if not found.
static func get_device_multiplier(device_key: String) -> float:
	_ensure_table_loaded()
	if device_key in _multiplier_table:
		return _multiplier_table[device_key]
	return 0.0


## Ensure the multiplier table is loaded. Called lazily before each query.
static func _ensure_table_loaded() -> void:
	if _table_loaded:
		return
	_load_multiplier_table()
	_table_loaded = true


## Load the device multiplier table from aim_assist.json.
static func _load_multiplier_table() -> void:
	_multiplier_table = {}

	var file := FileAccess.open(_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to load aim_assist.json at %s" % _DATA_PATH)
		return

	var content := file.get_as_text()
	var json := JSON.new()
	var error := json.parse(content)
	if error != OK:
		push_error("Failed to parse aim_assist.json: %s" % json.get_error_message())
		return

	var data: Variant = json.data
	if data is Dictionary:
		# Extract device multipliers, skipping the comment key
		if "mouse" in data:
			_multiplier_table["mouse"] = data["mouse"]
		if "gamepad" in data:
			_multiplier_table["gamepad"] = data["gamepad"]
		if "touch" in data:
			_multiplier_table["touch"] = data["touch"]


## Get the world position of a node.
##
## Tries multiple strategies to get a consistent position:
## 1. If the node is a Node3D, use its global_position
## 2. If the node has an Actor parent, use Actor.global_position
## 3. If the node has a Body child (CharacterBody3D/CharacterBody2D), use its position
## 4. Default to Vector3.ZERO
static func _get_position(node: Node) -> Vector3:
	if node == null:
		return Vector3.ZERO

	# Try Node3D directly
	var node_3d := node as Node3D
	if node_3d != null:
		return node_3d.global_position

	# Try as Actor
	var actor := node as Actor
	if actor != null:
		return actor.global_position

	# Try Body child
	var body := node.get_node_or_null("Body") as Node3D
	if body != null:
		return body.global_position

	return Vector3.ZERO


## Reset the multiplier table for testing.
## Clears cached data so re-loading can be tested.
static func reset_for_testing() -> void:
	_multiplier_table = {}
	_table_loaded = false
