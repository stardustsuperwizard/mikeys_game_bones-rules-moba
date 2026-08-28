## Binds the main scene's MobaTargetFrame to the player's current target.
##
## The player is spawned by WorldManager rather than authored into the scene, so
## the controller may not exist yet when this node is ready. The lookup is
## retried for a bounded number of frames and then given up on, so a scene
## without a player runs silently instead of searching every frame forever.
##
## Unlike CombatHUDBinder, which binds once and stops, the target changes over
## the session: once both nodes are found this node keeps polling the
## controller's target every frame and rebinds the frame when it changes,
## becomes null, or dies. Polling matches the placeholder target it reads --
## PlayerController3D exposes no target-changed signal, and #39 will replace
## what feeds this without the frame or this binder's contract changing.
##
## All scene-tree searching lives here, on the game side: rules/ui/ is bound by
## assignment through the frame's public bind_target() API and never looks for a
## target itself.
class_name TargetFrameBinder
extends Node

## How many frames the node lookup is retried before giving up.
const MAX_LOOKUP_FRAMES := 120

## The MobaCombatHUD that contains the target frame.
@export var hud_path: NodePath

## The player's PlayerController3D node.
@export var controller_path: NodePath

var _frames_remaining: int = MAX_LOOKUP_FRAMES
var _hud: MobaCombatHUD = null
var _controller: PlayerController3D = null
var _bound_target: MobaCombatant = null

## Whether the frame currently holds a binding from this node. A reference to a
## freed Object compares equal to null in GDScript, so _bound_target alone
## cannot tell "no target" apart from "a target that has since been freed".
var _has_binding: bool = false


func _ready() -> void:
	_try_lookup()


func _process(_delta: float) -> void:
	if not _resolved():
		_frames_remaining -= 1
		if not _try_lookup() and _frames_remaining <= 0:
			set_process(false)
		return

	_poll_and_bind()


## True once both nodes have been found and are still alive. A resolved pair can
## go stale if the player is despawned, which drops this back to searching.
func _resolved() -> bool:
	return is_instance_valid(_hud) and is_instance_valid(_controller)


## Returns true once both the HUD and the controller have been found.
func _try_lookup() -> bool:
	_hud = get_node_or_null(hud_path) as MobaCombatHUD
	_controller = get_node_or_null(controller_path) as PlayerController3D
	if not _resolved():
		return false
	_poll_and_bind()
	return true


## Push the controller's current target at the HUD's target frame, rebinding
## only when it actually changed. A bound target dying or being freed counts as
## a change: the frame is unbound, and a later target rebinds normally.
func _poll_and_bind() -> void:
	var target := _controller.get_current_target_combatant()
	if not is_instance_valid(target) or not target.is_alive():
		target = null

	if target != null:
		if _has_binding and is_instance_valid(_bound_target) and target == _bound_target:
			return
		_bound_target = target
		_has_binding = true
		_hud.bind_target(target)
		return

	if not _has_binding:
		return
	_bound_target = null
	_has_binding = false
	_hud.unbind_target()
