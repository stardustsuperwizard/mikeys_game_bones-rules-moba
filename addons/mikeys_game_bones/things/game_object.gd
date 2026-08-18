class_name GameObject
extends RefCounted

var id: StringName
var definition: ObjectDefinition
var traits: Array[StringName]
var capabilities: Array[StringName]
var state: Dictionary

func _init(p_id: StringName, p_definition: ObjectDefinition) -> void:
	id = p_id
	definition = p_definition
	traits = definition.traits if definition else []
	capabilities = definition.capabilities if definition else []
	state = definition.default_state.duplicate() if definition else {}

func has_trait(trait_name: StringName) -> bool:
	return traits.has(trait_name)

func has_capability(capability: StringName) -> bool:
	return capabilities.has(capability)

func get_state(key: StringName, default_value: Variant = null) -> Variant:
	return state.get(key, default_value)

func set_state(key: StringName, value: Variant) -> void:
	state[key] = value
