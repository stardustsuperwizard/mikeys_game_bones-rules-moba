## Binds the target frame to the player's current attack target.
##
## The player's target concept lives in PlayerController3D and changes as the
## player issues click orders. This binder polls the controller once per frame
## and calls bind_target() / unbind_target() on the target frame when the target
## changes, becomes null, or the previously-bound target dies.
##
## All scene-tree searching lives here, on the game side: rules/ui/ is bound by
## assignment through the frame's public bind() API and never looks for a player.
class_name TargetFrameBinder
extends Node

## How many frames the lookups are retried before giving up.
const MAX_LOOKUP_FRAMES := 120

## The MobaTargetFrame instance to bind.
@export var target_frame_path: NodePath

## The player's PlayerController3D node.
@export var controller_path: NodePath

var _frames_remaining: int = MAX_LOOKUP_FRAMES
var _current_target: MobaCombatant = null
var _found_nodes: bool = false


func _ready() -> void:
	set_process(not _try_lookup())


func _process(_delta: float) -> void:
	# Phase 1: Try to find the nodes
	if not _found_nodes:
		_frames_remaining -= 1
		if _try_lookup():
			_found_nodes = true
		elif _frames_remaining <= 0:
			set_process(false)
			return

	# Phase 2: Poll the target
	var frame := get_node_or_null(target_frame_path) as MobaTargetFrame
	var controller := get_node_or_null(controller_path) as PlayerController3D

	if frame == null or controller == null:
		return

	_poll_and_bind(frame, controller)


## Returns true once the frame and controller have been found and primed.
func _try_lookup() -> bool:
	var frame := get_node_or_null(target_frame_path) as MobaTargetFrame
	if frame == null:
		return false

	var controller := get_node_or_null(controller_path) as PlayerController3D
	if controller == null:
		return false

	# Found both; prime the binding with the current target
	_poll_and_bind(frame, controller)
	return true


## Poll the controller's current target and bind or unbind the frame accordingly.
## Also checks if the previously-bound target has died and unbinds in that case.
func _poll_and_bind(frame: MobaTargetFrame, controller: PlayerController3D) -> void:
	var new_target := controller.get_current_target_combatant()

	# If target hasn't changed and the currently bound target is still valid,
	# nothing to do.
	if new_target == _current_target:
		# But do check if the bound target has died
		if _current_target != null and not _current_target.is_alive():
			frame.unbind()
			_current_target = null
		return

	# Target has changed
	_current_target = new_target
	if _current_target == null:
		frame.unbind()
	else:
		frame.bind(_current_target)
