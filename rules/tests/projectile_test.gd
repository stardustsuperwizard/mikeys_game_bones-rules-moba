## Test suite for MobaProjectile and SKILLSHOT resolution.
##
## Covers projectile travel, collision against combatants and world geometry,
## piercing, the three despawn conditions (hit, maximum range, lifetime cap),
## tunneling through thin geometry, and the hard cap on live projectiles.
##
## Every projectile in this suite is driven by an explicit tick(delta) with
## self_driven turned off, so travel is deterministic and independent of engine
## frame timing. A projectile that self-drove here would advance on the physics
## clock as well and make every distance assertion below a race.
class_name ProjectileTest
extends RefCounted

const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaAbilityAction = preload("res://rules/abilities/moba_ability_action.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaProjectile = preload("res://rules/targeting/moba_projectile.gd")
const MobaTargeting = preload("res://rules/targeting/moba_targeting.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## Scenario clusters are separated along Z, well clear of every other physics
## suite's fixtures, and spaced this far apart from each other -- one
## scenario's bodies can never fall inside another's travel segment. Every
## fixture in the run shares one physics space, so separation is what keeps
## them independent.
##
## Separated along Z specifically, leaving X near the origin: travel and
## position are asserted along X to a millimetre below, and Vector3 is float32,
## whose spacing at a five-digit coordinate is already coarser than that.
const _CLUSTER_ORIGIN_Z := 5000.0
const _CLUSTER_SPACING := 200.0

## Ticking a projectile forever is how a suite hangs the whole run, so every
## drive loop is bounded. Generous: the longest scenario here is 200 m at 10
## m/s in 0.1 s steps.
const _MAX_DRIVE_STEPS := 400

## Bound on the cap scenario's spawn attempts, for the same reason: comfortably
## past any cap the projectile scene could reasonably author, but finite.
const _MAX_SPAWN_ATTEMPTS := 128

## Tolerance for "travelled exactly this far" assertions. Travel is pure
## float accumulation of speed * delta, so this only absorbs representation
## error, not physics jitter.
const _EPSILON := 0.001


## Actor stand-in whose _ready() is a no-op.
##
## Actor._ready() dereferences character_sheet, which is statically typed to
## the game-side CharacterSheet -- naming that type from rules/ is exactly the
## outward dependency the extraction contract exists to prevent. A physics
## fixture has to be in the tree to register with the space, so overriding
## _ready() -- deliberately without super() -- is what lets these fixtures live
## in the tree while still being an Actor to the allegiance filter.
class _TestActor:
	extends Actor

	func _ready() -> void:
		pass


static func run() -> bool:
	var violations: Array[String] = []

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		printerr("\n=== Projectile Test Violations ===")
		printerr("FAIL projectile: no SceneTree available")
		return false

	# Build every fixture up front so the whole suite costs one physics frame.
	# A body added to the tree does not register with the physics space until a
	# frame has been processed, and `godot --headless --quit` only runs a
	# handful of frames -- a suite that awaits more than that stalls forever and
	# silently takes the rest of the run with it.
	var hit_scene := _build_scene(tree, 0, [6.0])
	var miss_scene := _build_scene(tree, 1, [])
	var lifetime_scene := _build_scene(tree, 2, [])
	var wall_scene := _build_scene(tree, 3, [8.0])
	var pierce_scene := _build_scene(tree, 4, [3.0, 5.0, 7.0])
	var tunnel_scene := _build_scene(tree, 5, [])
	var self_drive_scene := _build_scene(tree, 6, [])
	var cap_scene := _build_scene(tree, 7, [])

	_add_wall(wall_scene, 4.0, 0.2)
	_add_wall(tunnel_scene, 50.0, 0.05)

	# Let the space observe every body just added.
	await tree.physics_frame

	violations.append_array(_test_hit(hit_scene))
	violations.append_array(_test_miss_through_activation(miss_scene))
	violations.append_array(_test_lifetime_cap(lifetime_scene))
	violations.append_array(_test_world_geometry(wall_scene))
	violations.append_array(_test_piercing(pierce_scene))
	violations.append_array(_test_no_tunneling(tunnel_scene))
	violations.append_array(_test_self_drive_guard(self_drive_scene))
	violations.append_array(_test_spawn_cap(cap_scene))

	for scene in [
		hit_scene,
		miss_scene,
		lifetime_scene,
		wall_scene,
		pierce_scene,
		tunnel_scene,
		self_drive_scene,
		cap_scene,
	]:
		(scene["container"] as Node).queue_free()

	if violations.is_empty():
		return true

	printerr("\n=== Projectile Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


## A skillshot travels at its declared speed, hits a combatant, applies the
## ability's damage, and despawns on that hit.
static func _test_hit(scene: Dictionary) -> Array[String]:
	var violations: Array[String] = []

	var ability := _make_ability("projectile_hit", 10.0, 20.0, 10.0)
	var projectile := _spawn(ability, scene)
	if projectile == null:
		violations.append("hit: no projectile was spawned")
		return violations

	var enemy: Actor = scene["enemies"][0]
	var enemy_combatant := _combatant_of(enemy)
	var health_before: float = enemy_combatant._current_health
	var origin: Vector3 = scene["origin"]

	# Declared speed: two 0.1 s steps of a 10 m/s projectile is 2 m, no more.
	projectile.tick(0.1)
	projectile.tick(0.1)
	if absf(projectile.distance_traveled - 2.0) > _EPSILON:
		violations.append(
			"hit: 0.2 s at 10 m/s should be 2 m, got %s" % projectile.distance_traveled
		)
	if absf(projectile.global_position.x - (origin.x + 2.0)) > _EPSILON:
		violations.append("hit: projectile position does not match its declared speed")
	if not projectile.is_active():
		violations.append("hit: despawned before reaching the target")

	_drive(projectile, 0.1)

	if projectile.is_active():
		violations.append("hit: never despawned")
	if projectile.despawn_reason != MobaProjectile.DespawnReason.COMBATANT_HIT:
		violations.append("hit: despawn reason should be COMBATANT_HIT")
	if enemy_combatant._current_health >= health_before:
		violations.append("hit: the ability's damage was not applied")
	if projectile.hit_count() != 1:
		violations.append("hit: expected exactly one target hit, got %d" % projectile.hit_count())
	if projectile.distance_traveled >= 6.0:
		violations.append("hit: travelled past the target it hit")

	return violations


## A skillshot aimed at empty space, driven through the real activation
## pipeline: it travels to maximum range, hits nothing, despawns there, and the
## resource and cooldown it committed are never refunded (§1).
static func _test_miss_through_activation(scene: Dictionary) -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")
	var ability := MobaAbilityLibrary.get_ability(&"aimed_shot")
	if ability == null:
		violations.append("miss: aimed_shot.tres did not load")
		MobaAbilityLibrary._reset()
		return violations

	violations.append_array(_assert_authored_skillshot(ability, "aimed_shot", 100.0, 12.0, 6.0))

	var caster: Actor = scene["caster"]
	var combatant := _combatant_of(caster)
	combatant.register_ability(ability)
	var resource_before: float = combatant._current_resource

	var context := MobaCastContext.new(caster, null, Vector3.RIGHT)
	var action := MobaAbilityAction.new(caster, &"aimed_shot", context)
	var result := action.execute()
	if not result.success:
		violations.append("miss: activation should succeed, got: %s" % result.reason)

	var projectile := _find_projectile(scene["container"])
	if projectile == null:
		violations.append("miss: activation spawned no projectile")
		MobaAbilityLibrary._reset()
		return violations
	projectile.self_driven = false

	if absf(combatant._current_resource - (resource_before - 30.0)) > _EPSILON:
		violations.append("miss: the activation should have spent its 30 resource")
	if combatant.get_cooldown_remaining(&"aimed_shot") <= 0.0:
		violations.append("miss: the activation should have started its cooldown")

	_drive(projectile, 0.05)

	if projectile.is_active():
		violations.append("miss: never despawned")
	if projectile.despawn_reason != MobaProjectile.DespawnReason.MAX_RANGE:
		violations.append("miss: despawn reason should be MAX_RANGE")
	if absf(projectile.distance_traveled - 12.0) > _EPSILON:
		violations.append(
			"miss: should stop at its 12 m range, got %s" % projectile.distance_traveled
		)
	if projectile.hit_count() != 0:
		violations.append("miss: a projectile aimed at empty space hit something")
	if combatant.get_cooldown_remaining(&"aimed_shot") <= 0.0:
		violations.append("miss: the cooldown should still be running after the miss")
	if absf(combatant._current_resource - (resource_before - 30.0)) > _EPSILON:
		violations.append("miss: the spent resource should never be refunded")

	MobaAbilityLibrary._reset()
	return violations


## The lifetime cap despawns a projectile independently of range: this one is
## nowhere near its maximum range when its time runs out.
static func _test_lifetime_cap(scene: Dictionary) -> Array[String]:
	var violations: Array[String] = []

	var ability := _make_ability("projectile_lifetime", 1.0, 1000.0, 0.5)
	var projectile := _spawn(ability, scene)
	if projectile == null:
		violations.append("lifetime: no projectile was spawned")
		return violations

	_drive(projectile, 0.1)

	if projectile.is_active():
		violations.append("lifetime: never despawned")
	if projectile.despawn_reason != MobaProjectile.DespawnReason.LIFETIME_CAP:
		violations.append("lifetime: despawn reason should be LIFETIME_CAP")
	if projectile.elapsed_lifetime < 0.5:
		violations.append("lifetime: despawned before its 0.5 s cap")
	if projectile.distance_traveled >= projectile.max_range:
		violations.append("lifetime: should despawn well short of its range, not at it")

	return violations


## A skillshot fired into a wall collides with world geometry, despawns there,
## applies nothing, and never reaches the enemy standing behind the wall.
static func _test_world_geometry(scene: Dictionary) -> Array[String]:
	var violations: Array[String] = []

	var ability := _make_ability("projectile_wall", 10.0, 20.0, 10.0)
	var projectile := _spawn(ability, scene)
	if projectile == null:
		violations.append("wall: no projectile was spawned")
		return violations

	var enemy: Actor = scene["enemies"][0]
	var enemy_combatant := _combatant_of(enemy)
	var health_before: float = enemy_combatant._current_health

	_drive(projectile, 0.1)

	if projectile.is_active():
		violations.append("wall: never despawned")
	if projectile.despawn_reason != MobaProjectile.DespawnReason.WORLD_GEOMETRY:
		violations.append("wall: despawn reason should be WORLD_GEOMETRY")
	if projectile.hit_count() != 0:
		violations.append("wall: world geometry should apply no effect")
	if enemy_combatant._current_health != health_before:
		violations.append("wall: the enemy behind the wall was hit")
	if projectile.distance_traveled >= 5.0:
		violations.append("wall: travelled past the wall at 4 m")

	return violations


## A piercing projectile hits several targets, hits none of them twice even
## while overlapping them across consecutive ticks, and carries on to despawn
## at its maximum range.
static func _test_piercing(scene: Dictionary) -> Array[String]:
	var violations: Array[String] = []

	var ability := _make_ability("projectile_pierce", 10.0, 12.0, 10.0)
	var projectile := _spawn(ability, scene)
	if projectile == null:
		violations.append("pierce: no projectile was spawned")
		return violations
	projectile.piercing = true

	var enemies: Array = scene["enemies"]
	var health: Array[float] = []
	var damage_events: Array[int] = []
	for enemy in enemies:
		health.append(_combatant_of(enemy)._current_health)
		damage_events.append(0)

	# Sample every target after every tick: counting the ticks on which a
	# target's health dropped is what proves "hit exactly once", independently
	# of the projectile's own hit set.
	var steps := 0
	while projectile.is_active() and steps < _MAX_DRIVE_STEPS:
		projectile.tick(0.1)
		steps += 1
		for index in enemies.size():
			var current: float = _combatant_of(enemies[index])._current_health
			if current < health[index]:
				damage_events[index] += 1
				health[index] = current

	for index in enemies.size():
		if damage_events[index] != 1:
			violations.append(
				(
					"pierce: target %d should be damaged exactly once, was damaged %d times"
					% [index, damage_events[index]]
				)
			)

	if projectile.is_active():
		violations.append("pierce: never despawned")
	if projectile.despawn_reason != MobaProjectile.DespawnReason.MAX_RANGE:
		violations.append("pierce: should carry on to its maximum range and despawn there")
	if projectile.hit_count() != enemies.size():
		violations.append(
			"pierce: expected %d distinct hits, got %d" % [enemies.size(), projectile.hit_count()]
		)

	return violations


## A deliberately fast projectile, whose single frame of travel steps clean over
## a thin wall, still collides with it. The travel segment is swept, not
## sampled at its endpoint.
static func _test_no_tunneling(scene: Dictionary) -> Array[String]:
	var violations: Array[String] = []

	# 100 m of travel in one 0.1 s tick, against a wall 0.05 m thick at 50 m.
	var ability := _make_ability("projectile_fast", 1000.0, 200.0, 10.0)
	var projectile := _spawn(ability, scene)
	if projectile == null:
		violations.append("tunneling: no projectile was spawned")
		return violations

	projectile.tick(0.1)

	if projectile.is_active():
		violations.append("tunneling: a fast projectile passed straight through a thin wall")
	if projectile.despawn_reason != MobaProjectile.DespawnReason.WORLD_GEOMETRY:
		violations.append("tunneling: despawn reason should be WORLD_GEOMETRY")
	if projectile.distance_traveled >= 51.0:
		violations.append(
			(
				"tunneling: should stop at the wall 50 m out, recorded %s"
				% projectile.distance_traveled
			)
		)

	return violations


## Self-driving is disableable, and mixing it with an external tick() cannot
## advance a projectile twice in one frame: the external call is refused
## outright rather than stacking on top of the _physics_process-driven one.
##
## The refusal is loud by design, so this scenario prints one MobaProjectile
## error to the log. That error is the assertion passing, not a failure.
static func _test_self_drive_guard(scene: Dictionary) -> Array[String]:
	var violations: Array[String] = []

	var ability := _make_ability("projectile_self_drive", 10.0, 20.0, 10.0)
	var projectile := _spawn(ability, scene)
	if projectile == null:
		violations.append("self_drive: no projectile was spawned")
		return violations

	if projectile.is_physics_processing():
		violations.append(
			"self_drive: self_driven = false should stop the projectile driving itself"
		)

	# Hand it back to self-driving, then try to advance it externally anyway --
	# exactly the mix that would otherwise move it twice in a frame.
	projectile.self_driven = true
	if not projectile.is_physics_processing():
		violations.append("self_drive: self_driven = true should have it drive itself again")

	projectile.tick(0.1)
	if projectile.distance_traveled != 0.0:
		violations.append("self_drive: an external tick() advanced a self-driving projectile")
	if not projectile.is_active():
		violations.append("self_drive: the refused tick() should be a no-op, not a despawn")

	# ... and with self-driving off, the same call advances it normally.
	projectile.self_driven = false
	projectile.tick(0.1)
	if absf(projectile.distance_traveled - 1.0) > _EPSILON:
		violations.append("self_drive: tick() should advance a projectile that is not self-driving")

	return violations


## The hard cap refuses spawns over its limit gracefully -- returning null and
## leaving every projectile already in flight untouched. Nothing is pooled,
## recycled, or freed to make room.
static func _test_spawn_cap(scene: Dictionary) -> Array[String]:
	var violations: Array[String] = []

	var ability := _make_ability("projectile_cap", 10.0, 20.0, 10.0)
	var spawned: Array[MobaProjectile] = []
	var refused := false
	var cap := 0

	for _attempt in _MAX_SPAWN_ATTEMPTS:
		var projectile := _spawn(ability, scene)
		if projectile == null:
			refused = true
			break
		cap = projectile.max_active_projectiles
		spawned.append(projectile)

	if not refused:
		violations.append("cap: spawning never got refused")
	if spawned.size() > cap:
		violations.append("cap: %d projectiles live against a cap of %d" % [spawned.size(), cap])
	if MobaProjectile.active_count() > cap:
		violations.append("cap: the live count exceeded the cap")

	for projectile in spawned:
		if not is_instance_valid(projectile) or not projectile.is_active():
			violations.append("cap: an in-flight projectile was freed to make room for a new one")
			break

	for projectile in spawned:
		if is_instance_valid(projectile):
			projectile.queue_free()

	return violations


## Assert the §19 numbers an authored skillshot resource must carry.
static func _assert_authored_skillshot(
	ability: MobaAbility, id: String, damage: float, ability_range: float, cooldown: float
) -> Array[String]:
	var violations: Array[String] = []

	if ability.targeting_type != MobaAbility.TargetingType.SKILLSHOT:
		violations.append("%s: should be SKILLSHOT" % id)
	if ability.target_allegiance != MobaAbility.TargetAllegiance.HOSTILE:
		violations.append("%s: should be HOSTILE" % id)
	if ability.base_damage != damage:
		violations.append("%s: base_damage should be %s" % [id, damage])
	if ability.range != ability_range:
		violations.append("%s: range should be %s" % [id, ability_range])
	if ability.resource_cost != 30.0:
		violations.append("%s: resource_cost should be 30" % id)
	if ability.cooldown != cooldown:
		violations.append("%s: cooldown should be %s" % [id, cooldown])
	if ability.projectile_speed <= 0.0:
		violations.append("%s: needs a projectile_speed to have any travel time" % id)
	if ability.duration <= ability_range / ability.projectile_speed:
		violations.append("%s: lifetime cap must sit above its own range / speed" % id)

	return violations


## Build one scenario cluster: a container node, a non-hostile caster at its
## origin, and a hostile combatant at each offset along +X.
##
## The container is what makes the caster's parent scenario-local: a skillshot
## parents its projectile to the caster's parent so it outlives the activation,
## and a shared root would put every scenario's projectiles in one bag.
static func _build_scene(tree: SceneTree, cluster: int, offsets: Array) -> Dictionary:
	var origin := Vector3(0.0, 0.0, _CLUSTER_ORIGIN_Z + _CLUSTER_SPACING * cluster)

	var container := Node3D.new()
	tree.root.add_child(container)

	var caster := _make_actor(container, false, origin)
	var state_machine := MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	caster.add_child(state_machine)

	var enemies: Array[Actor] = []
	for offset in offsets:
		enemies.append(_make_actor(container, true, origin + Vector3(offset, 0.0, 0.0)))

	return {"origin": origin, "container": container, "caster": caster, "enemies": enemies}


## Add a thin static wall across the scenario's travel line, `offset` metres
## along +X from its origin.
static func _add_wall(scene: Dictionary, offset: float, thickness: float) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 1

	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(thickness, 4.0, 4.0)
	collision.shape = box
	wall.add_child(collision)

	var container: Node3D = scene["container"]
	container.add_child(wall)
	wall.global_position = (scene["origin"] as Vector3) + Vector3(offset, 0.0, 0.0)
	return wall


## Build one physics fixture matching the shipped scene layout: Actor(Node) ->
## Body(CharacterBody3D with a CollisionShape3D child), with MobaCombatant as a
## sibling of Body rather than a child of the collider.
static func _make_actor(container: Node, hostile: bool, position: Vector3) -> Actor:
	var actor := _TestActor.new()
	actor.hostile = hostile

	var body := CharacterBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 1

	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	collision.shape = sphere
	body.add_child(collision)

	actor.add_child(body)
	actor.add_child(_create_combatant())
	container.add_child(actor)

	# global_position requires the node to be inside the tree.
	body.global_position = position
	return actor


static func _create_combatant() -> MobaCombatant:
	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	return combatant


static func _combatant_of(node: Node) -> MobaCombatant:
	return node.get_node_or_null("MobaCombatant") as MobaCombatant


## A SKILLSHOT ability with the delivery numbers a scenario needs. Damage type
## is TRUE so a target's armour cannot mitigate a hit down to nothing and make
## "was it damaged?" ambiguous.
static func _make_ability(
	id: String, speed: float, ability_range: float, lifetime: float
) -> MobaAbility:
	var ability := MobaAbility.new()
	ability.id = id
	ability.targeting_type = MobaAbility.TargetingType.SKILLSHOT
	ability.target_allegiance = MobaAbility.TargetAllegiance.HOSTILE
	ability.damage_type = MobaAbility.DamageType.TRUE
	ability.base_damage = 25.0
	ability.projectile_speed = speed
	ability.range = ability_range
	ability.duration = lifetime
	ability.targeting_collision_mask = 1
	return ability


## Spawn a projectile down the scenario's +X travel line through the production
## resolver, then take it off self-drive so this suite alone advances it.
static func _spawn(ability: MobaAbility, scene: Dictionary) -> MobaProjectile:
	var caster: Actor = scene["caster"]
	var context := MobaCastContext.new(caster, null, Vector3.RIGHT)
	var projectile := MobaTargeting.resolve_skillshot(ability, context, caster)
	if projectile != null:
		projectile.self_driven = false
	return projectile


## Find the projectile an activation spawned into a scenario's container.
static func _find_projectile(container: Node) -> MobaProjectile:
	for child in container.get_children():
		var projectile := child as MobaProjectile
		if projectile != null and projectile.is_active():
			return projectile
	return null


## Advance a projectile in fixed steps until it despawns, or until the step
## bound trips -- a drive loop that cannot terminate would hang the whole run.
static func _drive(projectile: MobaProjectile, delta: float) -> void:
	var steps := 0
	while projectile.is_active() and steps < _MAX_DRIVE_STEPS:
		projectile.tick(delta)
		steps += 1
