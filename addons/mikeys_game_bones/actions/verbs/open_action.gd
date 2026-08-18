class_name OpenAction
extends Action

var target: Door

func _init(p_actor: Actor, p_target: Door) -> void:
	super._init(p_actor)
	target = p_target

func required_capability() -> StringName:
	return &"interact"

func execute() -> ActionResult:
	return Rules.open(actor, target)
