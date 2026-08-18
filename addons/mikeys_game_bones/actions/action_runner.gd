class_name ActionRunner
extends RefCounted

static func run(action: Action, requester_id: int = 1) -> ActionResult:
	if not Authority.can_perform(action, requester_id):
		return ActionResult.new(false)
	return action.execute()
