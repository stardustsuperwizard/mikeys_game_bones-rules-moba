class_name ActionResult
extends RefCounted

var success: bool
var reason: StringName

func _init(p_success: bool = true, p_reason: StringName = &"") -> void:
	success = p_success
	reason = p_reason
