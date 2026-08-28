## Pooled floating combat text that displays damage, healing, critical hits,
## and shield absorption near the point of impact for any combatant.
##
## The pool pre-instantiates a fixed set of label nodes at startup, sized by
## max_concurrent, and recycles them. Requests beyond max_concurrent concurrently
## active numbers are silently dropped, not queued.
##
## Signals in, nothing out: the pool exposes spawn methods called explicitly by
## the game-side binder. It never mutates a MobaCombatant.
##
## World-to-screen projection uses the active Camera3D from the viewport.
## Numbers are positioned once at spawn time and do not track a moving target.
class_name MobaFloatingText
extends CanvasLayer

## Colors for different damage types and events.
##
## Keyed by MobaDamage.DamageType rather than by the bare ints it happens to
## resolve to, so reordering that enum cannot silently remap the colors.
## MobaDamage lives in rules/core/, which rules/ui/ may reference -- only
## res://scripts/, res://scenes/, and res://resources/ are off limits here.
const DAMAGE_COLORS := {
	MobaDamage.DamageType.PHYSICAL: Color(0.8, 0.8, 0.8, 1.0),  # neutral white
	MobaDamage.DamageType.MAGICAL: Color(0.6, 0.4, 1.0, 1.0),  # purple
	MobaDamage.DamageType.TRUE: Color(1.0, 0.8, 0.0, 1.0),  # gold
}

const HEAL_COLOR := Color(0.2, 0.8, 0.3, 1.0)  # green
const CRIT_COLOR := Color(1.0, 0.2, 0.2, 1.0)  # red
const SHIELD_COLOR := Color(0.3, 0.7, 1.0, 1.0)  # blue

## Duration each floating number is displayed (in seconds).
const DISPLAY_DURATION := 1.0

## Movement distance per display duration (in pixels).
const MOVEMENT_DISTANCE := 40.0

## Maximum concurrent floating numbers the pool can display.
## Requests beyond this are silently dropped.
@export var max_concurrent: int = 20

## Base vertical offset (in screen pixels) to shift numbers upward from the
## world-space impact point.
@export var base_offset_y: float = 30.0


## A single floating text entry in the pool.
class _FloatingLabel:
	var label: Label
	var time_remaining: float = 0.0
	var start_position: Vector2
	var end_position: Vector2

	func _init(new_label: Label) -> void:
		label = new_label

	func is_active() -> bool:
		return time_remaining > 0.0

	func reset() -> void:
		time_remaining = 0.0
		label.visible = false


var _pool: Array[_FloatingLabel] = []
var _active_count: int = 0


func _ready() -> void:
	_initialize_pool()


func _process(delta: float) -> void:
	_update_pool(delta)


## Initialize the pool with max_concurrent pre-instantiated labels.
func _initialize_pool() -> void:
	_pool.clear()
	_active_count = 0

	for i in range(max_concurrent):
		var label := Label.new()
		label.name = "FloatingText%d" % i
		label.visible = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = false
		# Use a monospace font for consistent width
		label.add_theme_font_size_override(&"font_size", 24)
		add_child(label)

		var entry := _FloatingLabel.new(label)
		_pool.append(entry)


## Update all active floating numbers: advance timers and animate positions.
func _update_pool(delta: float) -> void:
	for entry in _pool:
		if not entry.is_active():
			continue

		entry.time_remaining -= delta

		if entry.time_remaining <= 0.0:
			entry.reset()
			_active_count -= 1
		else:
			# Animate upward
			var progress: float = 1.0 - (entry.time_remaining / DISPLAY_DURATION)
			var current_position: Vector2 = entry.start_position.lerp(entry.end_position, progress)
			entry.label.position = current_position


## Get the next available inactive label from the pool, or null if all are in use.
func _get_next_available() -> _FloatingLabel:
	for entry in _pool:
		if not entry.is_active():
			return entry
	return null


## Project a 3D world position to a 2D screen position.
##
## Falls back to the screen origin when there is no viewport or no active
## Camera3D to project through. Both are absent in headless tests, which
## exercise the pool without ever adding it to a tree, so this is a normal
## path rather than an error worth reporting.
func _world_to_screen(world_pos: Vector3) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO

	var camera := viewport.get_camera_3d()
	if camera == null:
		return Vector2.ZERO

	return camera.unproject_position(world_pos)


## Spawn a floating damage number.
##
## Position is read from world_position (in 3D world space).
## damage_type is one of MobaDamage.DamageType: PHYSICAL (0), MAGICAL (1), TRUE (2).
## was_crit indicates a critical hit, which gets special color/styling.
func spawn_damage(world_position: Vector3, amount: float, damage_type: int, was_crit: bool) -> void:
	var entry := _get_next_available()
	if entry == null:
		return  # Pool exhausted, silently drop

	_active_count += 1
	entry.time_remaining = DISPLAY_DURATION

	# Determine text and color
	var text: String = "%d" % int(amount)
	var color: Color = (
		CRIT_COLOR
		if was_crit
		else DAMAGE_COLORS.get(damage_type, DAMAGE_COLORS[MobaDamage.DamageType.PHYSICAL])
	)

	# Add crit indicator
	if was_crit:
		text += "!"

	_setup_label(entry, text, color, world_position)


## Spawn a floating healing number.
func spawn_heal(world_position: Vector3, amount: float) -> void:
	var entry := _get_next_available()
	if entry == null:
		return  # Pool exhausted, silently drop

	_active_count += 1
	entry.time_remaining = DISPLAY_DURATION

	var text: String = "+%d" % int(amount)
	_setup_label(entry, text, HEAL_COLOR, world_position)


## Spawn a floating shield absorption number.
func spawn_shield_absorbed(world_position: Vector3, amount: float) -> void:
	var entry := _get_next_available()
	if entry == null:
		return  # Pool exhausted, silently drop

	_active_count += 1
	entry.time_remaining = DISPLAY_DURATION

	var text: String = "S%d" % int(amount)
	_setup_label(entry, text, SHIELD_COLOR, world_position)


## Set up a label entry: text, color, and position animation.
func _setup_label(entry: _FloatingLabel, text: String, color: Color, world_pos: Vector3) -> void:
	entry.label.text = text
	entry.label.add_theme_color_override(&"font_color", color)
	entry.label.visible = true

	# Project to screen space and add a small randomized offset to prevent perfect overlap
	var screen_pos := _world_to_screen(world_pos)
	var random_offset_x := randf_range(-10.0, 10.0)
	var random_offset_y := randf_range(-5.0, 5.0)
	entry.start_position = screen_pos + Vector2(random_offset_x, -base_offset_y + random_offset_y)
	entry.end_position = entry.start_position + Vector2(0, -MOVEMENT_DISTANCE)

	entry.label.position = entry.start_position


## Return the number of currently active floating numbers.
func get_active_count() -> int:
	return _active_count
