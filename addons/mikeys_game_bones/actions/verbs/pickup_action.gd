class_name PickupAction
extends Action

var target: Node

func _init(p_actor: Actor, p_target: Node) -> void:
	super._init(p_actor)
	target = p_target

func required_capability() -> StringName:
	return &"interact"

func execute() -> ActionResult:
	return Rules.pickup(actor, target)
