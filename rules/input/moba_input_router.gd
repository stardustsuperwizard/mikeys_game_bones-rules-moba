## Translates Godot InputMap actions into device-agnostic intents (ruleset §5.4).
##
## One of only two files under rules/ permitted to reference Input or InputMap
## (the other is moba_input_scheme.gd). Everything downstream sees intents.
##
## This is a translation layer, not a second place where control decisions are
## made: it reads action names already defined in project.godot and never a
## keycode. Anything expressible as a binding belongs in project.godot instead.
##
## Emits for exactly the §5.4 mapping-table rows that produce a combat or
## movement intent. action_primary (a game-side mouse convenience) and
## camera_recenter (camera, not combat) are listed there as non-combat and
## produce nothing here.
class_name MobaInputRouter
extends Node

## Emitted once per intent produced. A single signal keeps consumers free to
## match on type rather than subscribing to seven separate channels.
signal intent_emitted(intent: RefCounted)

## Number of ability slots, matching MobaLoadout's positional slots.
const _ABILITY_SLOTS: int = 4

## Reads the current strength of an action, 0.0 to 1.0.
##
## Indirected through a Callable so the layer stays testable with no device
## attached: rules/tests/ may not reference Input at all, so the suite injects
## a substitute here and drives the router with synthetic values. In the game
## this is never reassigned and reads Godot's Input singleton.
var action_strength_source: Callable = func(action: StringName) -> float:
	return Input.get_action_strength(action)

## Held state from the previous poll, per action, for edge detection.
##
## The router derives its own edges rather than calling Input.is_action_just_*,
## whose answers are tied to the engine's frame counter. Deriving them makes a
## poll self-consistent however it is driven, which is what lets the suite step
## a full PRESS -> AIM -> RELEASE gesture synchronously.
var _was_pressed: Dictionary = {}

## Slots with a gesture currently in flight, so AIM only follows a real PRESS.
var _ability_active: Dictionary = {}


func _process(_delta: float) -> void:
	poll()


## Read every mapped action once and emit the intents they produce.
##
## Public so a consumer can drive the layer from its own loop, and so the test
## suite can step it deterministically.
func poll() -> void:
	_poll_movement()
	_poll_jump()
	_poll_basic_attack()
	_poll_abilities()
	_poll_lock_on()
	_poll_defend()


func _strength(action: StringName) -> float:
	return action_strength_source.call(action)


func _axis(negative: StringName, positive: StringName) -> float:
	return _strength(positive) - _strength(negative)


## True on the poll an action goes down; updates the remembered state.
## Call at most once per action per poll -- it consumes the edge.
func _just_pressed(action: StringName) -> bool:
	var down := _strength(action) > 0.0
	var before: bool = _was_pressed.get(action, false)
	_was_pressed[action] = down
	return down and not before


## True on the poll an action comes up; updates the remembered state.
func _just_released(action: StringName) -> bool:
	var down := _strength(action) > 0.0
	var before: bool = _was_pressed.get(action, false)
	_was_pressed[action] = down
	return before and not down


func _is_down(action: StringName) -> bool:
	return _strength(action) > 0.0


## Emit movement. Translation and rotation go out as separate intents so the
## MoveIntent invariant holds: exactly one of direction or turn is non-zero.
func _poll_movement() -> void:
	var direction := Vector3.ZERO
	direction.x = _axis(&"strafe_left", &"strafe_right")
	direction.z = _axis(&"move_back", &"move_forward") * -1.0

	var turn := _axis(&"turn_left", &"turn_right")

	if not direction.is_zero_approx():
		var move := MobaIntent.MoveIntent.new()
		move.direction = direction
		intent_emitted.emit(move)

	if not is_zero_approx(turn):
		var facing := MobaIntent.MoveIntent.new()
		facing.turn = turn
		intent_emitted.emit(facing)


func _poll_jump() -> void:
	if _just_pressed(&"jump"):
		intent_emitted.emit(MobaIntent.JumpIntent.new())


func _poll_basic_attack() -> void:
	var down := _is_down(&"basic_attack")
	var before: bool = _was_pressed.get(&"basic_attack", false)
	_was_pressed[&"basic_attack"] = down

	if down and not before:
		var pressed := MobaIntent.BasicAttackIntent.new()
		pressed.held = true
		intent_emitted.emit(pressed)
	elif before and not down:
		var released := MobaIntent.BasicAttackIntent.new()
		released.held = false
		intent_emitted.emit(released)


## Emit the ability gesture lifecycle: PRESS on the way down, AIM every poll
## while held, RELEASE on the way up.
##
## Repeating AIM each poll is correct, not something to optimize away -- it is
## what drag-to-aim on touch and stick-aim on gamepad both consume.
func _poll_abilities() -> void:
	for slot in range(1, _ABILITY_SLOTS + 1):
		var action := StringName("ability_%d" % slot)
		var down := _is_down(action)
		var before: bool = _was_pressed.get(action, false)
		_was_pressed[action] = down

		if down and not before:
			_ability_active[slot] = true
			intent_emitted.emit(_ability(slot, MobaIntent.AbilityIntent.Phase.PRESS))
		elif before and not down:
			if _ability_active.get(slot, false):
				_ability_active[slot] = false
				intent_emitted.emit(_ability(slot, MobaIntent.AbilityIntent.Phase.RELEASE))
		elif down and _ability_active.get(slot, false):
			intent_emitted.emit(_ability(slot, MobaIntent.AbilityIntent.Phase.AIM))


func _ability(slot: int, phase: MobaIntent.AbilityIntent.Phase) -> MobaIntent.AbilityIntent:
	var intent := MobaIntent.AbilityIntent.new()
	intent.slot = slot
	intent.phase = phase
	return intent


## Emit lock-on press and release. CYCLE stays unproducible: the single bound
## lock_on action has no cycling semantics defined yet.
func _poll_lock_on() -> void:
	var down := _is_down(&"lock_on")
	var before: bool = _was_pressed.get(&"lock_on", false)
	_was_pressed[&"lock_on"] = down

	if down and not before:
		var pressed := MobaIntent.LockOnIntent.new()
		pressed.phase = MobaIntent.LockOnIntent.Phase.PRESS
		intent_emitted.emit(pressed)
	elif before and not down:
		var released := MobaIntent.LockOnIntent.new()
		released.phase = MobaIntent.LockOnIntent.Phase.RELEASE
		intent_emitted.emit(released)


func _poll_defend() -> void:
	if _just_pressed(&"defend"):
		var intent := MobaIntent.UtilityIntent.new()
		intent.id = &"defend"
		intent_emitted.emit(intent)
