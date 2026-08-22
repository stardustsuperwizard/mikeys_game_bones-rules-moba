# Game-specific 3D player body for Sword and Planet.
# Extends ActorBody3D to add turning (A/D) and jumping (Space) on top of
# the base movement/gravity handled by the framework body.
class_name PlayerBody3D
extends ActorBody3D

@export var turn_speed: float = 2.0
@export var jump_velocity: float = 5.0


func _physics_process(delta: float) -> void:
	var player_ctrl := actor.controller as PlayerController3D
	if player_ctrl:
		# Rotate the body around Y before calling super() so
		# get_move_direction() already reflects the new facing this frame.
		rotate_y(-player_ctrl.get_turn_direction() * turn_speed * delta)
		# Set upward velocity before super() applies gravity; the grounded
		# check ensures jump is only available while on the floor.
		if player_ctrl.consume_jump() and is_on_floor():
			velocity.y = jump_velocity
	super(delta)
