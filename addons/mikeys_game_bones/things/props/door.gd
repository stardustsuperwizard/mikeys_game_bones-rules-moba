class_name Door
extends StaticBody3D

@export var object_definition: ObjectDefinition
@export var locked: bool = false
@export var open: bool = false:
	set(value):
		open = value
		_update_presentation()

var game_object: GameObject

@onready var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var collision: CollisionShape3D = get_node_or_null("CollisionShape3D")

func _ready() -> void:
	add_to_group("interactables")
	game_object = GameObject.new(StringName(name), object_definition)
	_update_presentation()

func is_open() -> bool:
	return open

func is_locked() -> bool:
	return locked

func set_open(value: bool) -> void:
	open = value

# An opened door hides its mesh and disables its collision, so a door
# placed in an actual wall gap lets the player through -- not just a color
# change like the placeholder capsules elsewhere in the game.
func _update_presentation() -> void:
	if mesh:
		mesh.visible = not open
	if collision:
		collision.disabled = open
