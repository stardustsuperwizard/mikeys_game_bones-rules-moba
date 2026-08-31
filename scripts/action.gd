class_name Action
extends RefCounted

var actor: Actor

func _init(p_actor: Actor) -> void:
	actor = p_actor

func execute() -> ActionResult:
	push_error("Action.execute() not implemented")
	return ActionResult.new(false)

# Empty string means no capability is required. Recorded for future
# enforcement (see docs/20260815T130000 - Game Objects and Rules.md); not
# yet checked by ActionRunner -- no second case exists yet to justify the
# new silent-failure mode a missing/misconfigured ObjectDefinition would add.
func required_capability() -> StringName:
	return &""
