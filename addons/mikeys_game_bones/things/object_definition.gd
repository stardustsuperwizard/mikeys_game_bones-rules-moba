class_name ObjectDefinition
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var traits: Array[StringName] = []
@export var capabilities: Array[StringName] = []

# Not read by any GameObject-hosting node yet (Actor/Door use typed fields
# for their real state today). Kept here because it's what lets a future
# object with no dedicated typed resource -- a Chest, say -- get a working
# GameObject without inventing a new Resource subclass first.
@export var default_state: Dictionary = {}
