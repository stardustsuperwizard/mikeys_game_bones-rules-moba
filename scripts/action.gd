class_name Action
extends RefCounted

var actor: Actor


func _init(p_actor: Actor) -> void:
	actor = p_actor


func execute() -> ActionResult:
	push_error("Action.execute() not implemented")
	return ActionResult.new(false)
