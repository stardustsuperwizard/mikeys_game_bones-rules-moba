class_name ItemPickup3D
extends StaticBody3D
## A world item that can be picked up by interacting with it (same
## click-then-walk-into-range flow as Door). What item_base actually is is
## up to the game -- the framework only carries the reference and hands it
## to Rules.pickup() to interpret.

@export var item_base: Resource

func _ready() -> void:
	add_to_group("interactables")
