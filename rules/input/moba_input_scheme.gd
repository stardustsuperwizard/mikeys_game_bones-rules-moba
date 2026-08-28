## Tracks which input device is in use and hot-swaps between schemes (§5.4).
##
## One of only two files under rules/ permitted to reference Input or InputMap
## (the other is moba_input_router.gd).
##
## §5.4 requires schemes to hot-swap: receiving gamepad input while keyboard is
## active switches immediately, with no restart and no menu. This node emits the
## signal that makes that possible; swapping prompt glyphs on it comes later.
##
## Detection reads the *class* of each InputEvent, never a keycode, so it needs
## no binding of its own and stays correct when bindings are remapped.
class_name MobaInputScheme
extends Node

## Emitted when the active scheme changes. Not emitted for input from the scheme
## already active, nor while the hysteresis window is open.
signal scheme_changed(scheme: Scheme)

## Active input scheme.
##
## TOUCH is present from the start although nothing produces it yet: the touch
## HUD lands in a later batch, and having the value here means neither that work
## nor the consumer task needs an enum migration.
enum Scheme {
	GAMEPAD,
	KEYBOARD_MOUSE,
	TOUCH,
}

## The movement-axis deadzone configured in project.godot, recorded here only
## so the relationship below is checkable. This node never applies it and must
## not change it.
const MOVEMENT_DEADZONE: float = 0.2

## Minimum analog magnitude that counts as a deliberate device change.
##
## Deliberately greater than MOVEMENT_DEADZONE. The deadzone's job is to decide
## when a stick is being pushed at all; this threshold's job is to decide when
## the player has switched hands to the pad. Setting them equal would let a
## resting stick's drift past the deadzone yank the scheme away from a keyboard
## the player is still using, so it sits well clear of that noise floor.
@export var scheme_change_threshold: float = 0.5

## How long after a swap to ignore further swaps.
##
## Without this, input alternating between two devices across consecutive frames
## re-fires scheme_changed every frame and any consumer redrawing prompts on the
## signal thrashes. One swap per window is enough to track a real device change,
## which happens on a human timescale.
@export var hysteresis_seconds: float = 0.25

var _current_scheme: Scheme = Scheme.KEYBOARD_MOUSE
var _hysteresis_remaining: float = 0.0


## The scheme currently driving the game.
func get_scheme() -> Scheme:
	return _current_scheme


func _process(delta: float) -> void:
	advance(delta)


func _input(event: InputEvent) -> void:
	note_event(event)


## Age the hysteresis window. Public so a consumer or the test suite can drive
## this node without depending on the SceneTree's process loop.
func advance(delta: float) -> void:
	if _hysteresis_remaining > 0.0:
		_hysteresis_remaining = maxf(0.0, _hysteresis_remaining - delta)


## Offer one input event to scheme detection, switching if it comes from a
## different device and clears the threshold.
##
## Public for the same reason as advance(): rules/tests/ may not read the device
## singletons, so the suite feeds synthetic InputEvent objects straight in, with
## no device attached and nothing to poll.
##
## Classification is by event class, never by keycode, so remapping a binding
## cannot change which device an event is attributed to. Analog stick motion has
## to clear scheme_change_threshold; buttons, keys, mouse and touch are
## unambiguous and count on their own.
func note_event(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) > scheme_change_threshold:
			_adopt(Scheme.GAMEPAD)
		return

	if event is InputEventJoypadButton:
		_adopt(Scheme.GAMEPAD)
		return

	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_adopt(Scheme.TOUCH)
		return

	if event is InputEventKey or event is InputEventMouse:
		_adopt(Scheme.KEYBOARD_MOUSE)


func _adopt(scheme: Scheme) -> void:
	if scheme == _current_scheme:
		return

	if _hysteresis_remaining > 0.0:
		return

	_current_scheme = scheme
	_hysteresis_remaining = hysteresis_seconds
	scheme_changed.emit(_current_scheme)
