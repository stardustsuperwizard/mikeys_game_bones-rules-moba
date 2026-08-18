# A reference/default animation driver for Bones actors -- reads the same
# Controller intent ActorBody3D/ActorBody2D already poll (move direction,
# attack target, interact target) and plays whichever clip name is mapped
# to that state. Deliberately generic: it knows nothing about any specific
# asset pack's clip names, only exported slots a game wires up to whatever
# animation library its character model actually has (see
# scenes/characters/base_character_3d.tscn in misadventures_rpg for a
# concrete Quaternius-clip wiring). Same role for animation that
# SimpleAIController plays for decision-making: a working reference, not
# the only way to drive an Actor's presentation -- swap it for a state
# machine or AnimationTree blend space by writing a different node against
# the same Actor/Controller contract.
class_name ActorAnimator
extends AnimationPlayer

@export var idle_animation: StringName = &"Idle"
@export var move_animation: StringName = &"Walk"
@export var attack_animation: StringName = &"Attack"
@export var interact_animation: StringName = &"Interact"

var _actor: Actor

func _ready() -> void:
	_actor = _find_actor(self)

func _process(_delta: float) -> void:
	if not _actor or not _actor.controller:
		return

	var next_animation := idle_animation
	if _actor.controller.get_attack_target():
		next_animation = attack_animation
	elif _actor.controller.get_interact_target():
		next_animation = interact_animation
	elif _actor.controller.get_move_direction() != Vector3.ZERO:
		next_animation = move_animation

	if has_animation(next_animation) and current_animation != next_animation:
		play(next_animation)

func _find_actor(node: Node) -> Actor:
	var current := node.get_parent()
	while current:
		if current is Actor:
			return current
		current = current.get_parent()
	return null
