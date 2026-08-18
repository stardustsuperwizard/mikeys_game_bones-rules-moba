class_name AttackAction
extends Action

var target: Actor

func _init(p_actor: Actor, p_target: Actor) -> void:
	super._init(p_actor)
	target = p_target

func required_capability() -> StringName:
	return &"attack"

func execute() -> ActionResult:
	return Rules.attack(actor, target)
