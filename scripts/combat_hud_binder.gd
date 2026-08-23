## Binds the main scene's MobaCombatHUD to the player's MobaCombatant.
##
## The player is spawned by WorldManager rather than authored into the scene,
## so the combatant may not exist yet when this node is ready. The lookup is
## retried for a bounded number of frames and then given up on, so a scene
## without a player runs silently instead of searching every frame forever.
##
## All scene-tree searching lives here, on the game side: rules/ui/ is bound by
## assignment through the HUD's public bind() API and never looks for a player.
class_name CombatHUDBinder
extends Node

## How many frames the combatant lookup is retried before giving up.
const MAX_LOOKUP_FRAMES := 120

## The MobaCombatHUD instance to bind.
@export var hud_path: NodePath

## The player's MobaCombatant node.
@export var combatant_path: NodePath

var _frames_remaining: int = MAX_LOOKUP_FRAMES


func _ready() -> void:
	set_process(not _try_bind())


func _process(_delta: float) -> void:
	_frames_remaining -= 1
	if _try_bind() or _frames_remaining <= 0:
		set_process(false)


## Returns true once the HUD has been bound to a live combatant.
func _try_bind() -> bool:
	var hud := get_node_or_null(hud_path) as MobaCombatHUD
	if hud == null:
		return false
	var combatant := get_node_or_null(combatant_path) as MobaCombatant
	if combatant == null:
		return false
	hud.bind(combatant)
	return true
