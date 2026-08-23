## Data carrier for ability activation context.
##
## MobaCastContext holds all input data needed to activate an ability:
## - caster: the Actor performing the ability
## - explicit_target: the intended target (for targeted abilities), or null for self-targeting
## - aim_direction: direction vector for skillshot/area abilities (unused for self/targeted)
## - ground_point: world position for ground-placed abilities (unused for self/targeted)
class_name MobaCastContext
extends RefCounted

var caster: Actor
var explicit_target: Node = null
var aim_direction: Vector3 = Vector3.ZERO
var ground_point: Vector3 = Vector3.ZERO


func _init(
	p_caster: Actor,
	p_explicit_target: Node = null,
	p_aim_direction: Vector3 = Vector3.ZERO,
	p_ground_point: Vector3 = Vector3.ZERO
) -> void:
	caster = p_caster
	explicit_target = p_explicit_target
	aim_direction = p_aim_direction
	ground_point = p_ground_point
