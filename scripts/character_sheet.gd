class_name CharacterSheet
extends Resource

@export var character_name: String = ""
@export var max_hp: int = 100
# current_hp is runtime state, not saved in the resource file. Actor._ready()
# always resets it to max_hp after duplicating the resource, so the default
# here is never observed in play.
var current_hp: int = 0
