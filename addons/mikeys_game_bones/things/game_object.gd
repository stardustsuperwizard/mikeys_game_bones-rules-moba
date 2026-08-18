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
	# Left at their empty defaults when there's no definition -- an untyped
	# `[]` fallback can't be assigned to these typed fields.
	if definition:
		traits = definition.traits
		capabilities = definition.capabilities
		state = definition.default_state.duplicate()

func has_trait(trait_name: StringName) -> bool:
	return traits.has(trait_name)

func has_capability(capability: StringName) -> bool:
	return capabilities.has(capability)

func get_state(key: StringName, default_value: Variant = null) -> Variant:
	return state.get(key, default_value)

func set_state(key: StringName, value: Variant) -> void:
	state[key] = value
