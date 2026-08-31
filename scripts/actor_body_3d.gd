class_name ActorBody3D
extends CharacterBody3D

const SPEED = 5.0

@onready var actor: Actor = get_parent() as Actor
@onready var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")

func _ready() -> void:
	if mesh and not _has_own_material(mesh):
		var material := StandardMaterial3D.new()
		material.albedo_color = actor.color
		mesh.material_override = material

# Placeholder actors (bare primitive meshes, no material of their own) rely
# on `color` for visibility. A real imported model already brings its own
# materials/textures and shouldn't have them stomped by a flat color.
func _has_own_material(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance.get_surface_override_material(0):
		return true
	var mesh_resource := mesh_instance.mesh
	return mesh_resource and mesh_resource.get_surface_count() > 0 and mesh_resource.surface_get_material(0) != null

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	var move_direction := actor.controller.get_move_direction() if actor.controller else Vector3.ZERO
	if move_direction:
		velocity.x = move_direction.x * SPEED
		velocity.z = move_direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

	var target := actor.controller.get_attack_target() if actor.controller else null
	if target:
		actor.try_attack(target)

	var interact_target := actor.controller.get_interact_target() if actor.controller else null
	if interact_target:
		actor.try_interact(interact_target)
