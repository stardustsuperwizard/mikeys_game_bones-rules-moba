class_name ActorBody2D
extends CharacterBody2D

# Pixel-scale, unlike ActorBody3D's small-unit SPEED -- ranges/aggro on
# PlayerController/SimpleAIController are @export, not const, specifically so a
# differently-scaled presentation like this one can retune them per instance
# instead of forcing every presentation onto one shared coordinate scale.
const SPEED = 220.0

@onready var actor: Actor = get_parent() as Actor
@onready var polygon: Polygon2D = get_node_or_null("Polygon2D")

func _ready() -> void:
	if polygon:
		polygon.color = actor.color

# No gravity/is_on_floor() here -- a top-down 2D room has no vertical axis
# to fall along, unlike ActorBody3D's ground-based movement.
func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var move_direction := actor.controller.get_move_direction() if actor.controller else Vector3.ZERO
	var move_direction_2d := Vector2(move_direction.x, move_direction.z)
	if move_direction_2d:
		velocity = move_direction_2d * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)

	move_and_slide()

	var target := actor.controller.get_attack_target() if actor.controller else null
	if target:
		actor.try_attack(target)

	var interact_target := actor.controller.get_interact_target() if actor.controller else null
	if interact_target:
		actor.try_interact(interact_target)
