class_name ActorBody3D
extends CharacterBody3D

const SPEED = 5.0

# The placeholder appearance renderer this body owns (#377). Created in _ready()
# rather than authored into every actor scene so one component covers player,
# enemy and lobby avatar, and so a body that never wears anything still has the
# same structure as one that does.
var appearance_renderer: ActorAppearance3D

@onready var actor: Actor = get_parent() as Actor
@onready var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")


func _ready() -> void:
	if mesh and not _has_own_material(mesh):
		var material := StandardMaterial3D.new()
		material.albedo_color = actor.color
		mesh.material_override = material

	# Dress the body from the appearance its spawn data carried. Spawn assigns
	# Actor.appearance before the actor enters the tree, so it is already set by
	# the time this runs. An actor with no appearance is left untouched -- see
	# ActorAppearance3D.apply().
	appearance_renderer = ActorAppearance3D.new()
	appearance_renderer.name = ActorAppearance3D.NODE_NAME
	add_child(appearance_renderer)
	appearance_renderer.apply(actor)


# Placeholder actors (bare primitive meshes, no material of their own) rely
# on `color` for visibility. A real imported model already brings its own
# materials/textures and shouldn't have them stomped by a flat color.
func _has_own_material(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance.get_surface_override_material(0):
		return true
	var mesh_resource := mesh_instance.mesh
	return (
		mesh_resource
		and mesh_resource.get_surface_count() > 0
		and mesh_resource.surface_get_material(0) != null
	)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	var move_direction := (
		actor.controller.get_move_direction() if actor.controller else Vector3.ZERO
	)
	if move_direction:
		velocity.x = move_direction.x * SPEED
		velocity.z = move_direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

	# Poll the controller's attack seam once the body has moved for the frame,
	# and deliberately discard what it returns.
	#
	# This looks like a dead call and is not. The flat Actor.try_attack() path
	# that used to consume the return value is gone, but get_attack_target() was
	# never a pure query: it is where PlayerController3D and EnemyAIController3D
	# arm the pending basic-attack cycle (_basic_attack_pending /
	# _pending_attack_target) and apply taunt re-pointing. Their own
	# _physics_process resolves that cycle through MobaCombatant.basic_attack().
	# Nothing else calls it, so dropping this line silently disables every basic
	# attack in the game -- player and enemy alike -- while still compiling and
	# still passing a scene-load check.
	#
	# The interact seam had no such second life: Door was its only consumer and
	# nothing remains in the "interactables" group, so that poll is gone.
	if actor.controller:
		actor.controller.get_attack_target()
