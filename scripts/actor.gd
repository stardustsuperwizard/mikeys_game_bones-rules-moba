class_name Actor
extends Node

@export var character_sheet: CharacterSheet
@export var color: Color = Color.WHITE

# Whether player input may target this actor for attack. Defaults to true so
# existing hostile content (the Goblin) needs no data change; a friendly
# NPC sets this false. Deliberately just a flag, not a faction/relationship
# system -- nothing today needs more than "attackable or not."
@export var hostile: bool = true

# 0 means unowned/AI-controlled; a connected LAN client's peer id otherwise.
# Checked by Authority.can_perform() before an Action is honored.
var owner_id: int = 0

# Bridges whichever presentation body this Actor has (see
# scripts/actor_body_3d.gd) into a single presentation-neutral position, so
# Controller/PlayerController/SimpleAIController never need to know or care
# whether they're driving a 3D or a 2D actor.
# 2D's XY plane maps onto 3D's XZ ground plane (Y stays up).
#
# Deliberately not cached via @onready: Godot readies children before their
# parent, and SimpleAIController._ready() (a child of this Actor) reads
# global_position to set its home position -- that would run before this
# Actor's own @onready vars were assigned.
var global_position: Vector3:
	get:
		var body := get_node_or_null("Body")
		if body is CharacterBody3D:
			return (body as CharacterBody3D).global_position
		if body is CharacterBody2D:
			var position_2d := (body as CharacterBody2D).global_position
			return Vector3(position_2d.x, 0, position_2d.y)
		return Vector3.ZERO

@onready var controller: Controller = get_node_or_null("Controller")


func _ready() -> void:
	character_sheet = character_sheet.duplicate()
	character_sheet.current_hp = character_sheet.max_hp
