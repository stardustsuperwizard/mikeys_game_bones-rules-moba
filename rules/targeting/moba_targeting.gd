## MOBA ability targeting resolver.
##
## MobaTargeting provides the canonical strategies for resolving ability targets
## based on targeting type (SELF, TARGETED, SKILLSHOT, AREA, GROUND). It is the sole place
## in the codebase that reads Actor.hostile for ability targeting, centralizing
## the logic so future changes to hostility mechanics require only one-function
## changes rather than sweeping modifications.
##
## Each targeting type has its own resolution function returning either a single
## target (SELF, TARGETED) or a list (AREA, GROUND after filtering). All
## multi-target strategies pass through the shared filter_valid_targets() to
## apply allegiance, alive status, caster-inclusion, and stealth checks.
##
## SKILLSHOT is the one resolver that returns no targets: it spawns a
## MobaProjectile instead, which applies the same filter to whatever it hits
## later. See resolve_skillshot().
class_name MobaTargeting
extends RefCounted

## The projectile scene SKILLSHOT resolution spawns.
const PROJECTILE_SCENE_PATH := "res://rules/targeting/moba_projectile.tscn"

## Loaded on first skillshot rather than preloaded: moba_projectile.gd names
## MobaTargeting itself, and a preload here would make that a load-time cycle.
static var _projectile_scene: PackedScene = null


## Resolve a SELF targeting ability: target is always the caster.
static func resolve_self(caster: Node, _ability: MobaAbility) -> Array[Node]:
	if caster == null:
		return []
	return [caster]


## Resolve a TARGETED ability: target is the explicitly provided target.
static func resolve_targeted(_caster: Node, target: Node, _ability: MobaAbility) -> Array[Node]:
	if target == null or not is_instance_valid(target):
		return []
	return [target]


## Resolve a CHANNELED ability: target is the explicitly provided target.
static func resolve_channeled(_caster: Node, target: Node, _ability: MobaAbility) -> Array[Node]:
	if target == null or not is_instance_valid(target):
		return []
	return [target]


## Resolve a SKILLSHOT ability: spawn a MobaProjectile at the caster, aimed
## along context.aim_direction, and hand it the ability whose effects it will
## apply when it eventually collides.
##
## Unlike every other resolver here, this one returns no targets: a skillshot
## has none at activation time. Spawning the projectile *is* the resolution;
## its damage and effects land later, asynchronously, on collision.
##
## The aim direction is consumed raw. No cone narrowing, no magnetism, no
## lock-on -- aim assist is its own concern and does not belong in delivery.
##
## The projectile is parented to the caster's parent, not to the caster, so it
## outlives the activation call and does not inherit the caster's movement.
##
## Args:
##   ability: The MobaAbility being resolved
##   context: The activation context supplying aim_direction
##   caster: The ability caster
##
## Returns: The spawned MobaProjectile, or null when it could not be spawned --
##   including when the live-projectile cap refuses it. A refused spawn is not
##   a failed activation: the resource and cooldown were already committed, and
##   §1 charges full price for a miss.
static func resolve_skillshot(
	ability: MobaAbility, context: MobaCastContext, caster: Node
) -> MobaProjectile:
	if ability == null or context == null or caster == null:
		return null

	if context.aim_direction.length_squared() <= 0.0:
		return null

	var parent := caster.get_parent()
	if parent == null:
		return null

	var scene := _get_projectile_scene()
	if scene == null:
		return null

	var projectile := scene.instantiate() as MobaProjectile
	if projectile == null:
		return null

	# Hard cap, not a pool: a spawn over the limit is refused outright rather
	# than paid for by freeing something already in flight.
	if not projectile.try_reserve_slot():
		projectile.free()
		return null

	parent.add_child(projectile)
	projectile.global_position = _get_position(caster)
	projectile.configure(ability, caster, context.aim_direction)
	return projectile


## Resolve an AREA targeting ability: gather all combatants within area_radius
## of the caster's position, then filter through the valid-target filter.
##
## Args:
##   caster: The ability caster
##   ability: The MobaAbility being resolved
##   origin: Optional origin position (defaults to caster's position when unset)
##
## Returns: Array of valid targets within the area radius, filtered by allegiance,
##   alive status, and caster inclusion rules.
static func resolve_area(
	caster: Node,
	ability: MobaAbility,
	origin: Variant = null,
) -> Array[Node]:
	if caster == null:
		return []

	# Use caster position when no origin was provided. `origin` is a Variant
	# defaulting to null rather than Vector3.ZERO so an explicit query at the
	# world origin is distinguishable from "unset" -- Vector3.ZERO is a
	# legitimate coordinate, not a sentinel.
	var query_origin: Vector3 = origin if origin is Vector3 else _get_position(caster)

	# Query physics space for bodies in the area. Collision mask comes from the
	# ability (an @export, not a shared const) so different abilities can
	# target different physics layers.
	var candidates := _query_area(
		query_origin, ability.area_radius, ability.targeting_collision_mask, caster
	)

	# Filter through the shared valid-target filter
	return filter_valid_targets(candidates, caster, ability)


## Resolve a GROUND targeting ability: gather all combatants within area_radius
## of the ground point, then filter through the valid-target filter.
##
## Args:
##   caster: The ability caster
##   ground_point: The targeted ground location
##   ability: The MobaAbility being resolved
##
## Returns: Array of valid targets within the area radius, filtered by allegiance,
##   alive status, and caster inclusion rules.
static func resolve_ground(
	caster: Node,
	ground_point: Vector3,
	ability: MobaAbility,
) -> Array[Node]:
	if caster == null:
		return []

	# Query physics space for bodies at the ground point. Collision mask comes
	# from the ability (an @export, not a shared const) so different abilities
	# can target different physics layers.
	var candidates := _query_area(
		ground_point, ability.area_radius, ability.targeting_collision_mask, caster
	)

	# Filter through the shared valid-target filter
	return filter_valid_targets(candidates, caster, ability)


## The shared valid-target filter applied to all multi-target strategies.
##
## Filters candidates based on:
##   - Alive: keep only candidates whose MobaCombatant.is_alive() is true
##   - Allegiance: read Actor.hostile to determine friend/foe, honor ability's target_allegiance
##   - Caster inclusion: exclude caster unless ability.affects_caster is true
##   - Stealth: route through a single named hook (currently always visible)
##
## This is the ONLY place in the codebase that reads Actor.hostile for ability targeting.
##
## Args:
##   candidates: Array of potential targets
##   caster: The ability caster
##   ability: The MobaAbility being resolved
##
## Returns: Filtered array of valid targets
static func filter_valid_targets(
	candidates: Array[Node], caster: Node, ability: MobaAbility
) -> Array[Node]:
	var valid: Array[Node] = []

	for candidate in candidates:
		if candidate == null or not is_instance_valid(candidate):
			continue

		# Check: candidate must be alive
		if not _is_candidate_alive(candidate):
			continue

		# Check: caster inclusion (exclude caster unless ability.affects_caster)
		if candidate == caster and not ability.affects_caster:
			continue

		# Check: allegiance matches ability's target_allegiance
		if not _matches_allegiance(candidate, caster, ability.target_allegiance):
			continue

		# Check: stealth hook (currently always visible)
		if not _is_candidate_visible(candidate):
			continue

		valid.append(candidate)

	return valid


## Load (once) and return the projectile scene resolve_skillshot() instances.
static func _get_projectile_scene() -> PackedScene:
	if _projectile_scene == null:
		_projectile_scene = load(PROJECTILE_SCENE_PATH) as PackedScene
	return _projectile_scene


## Query physics space for bodies within a sphere at the given position.
## Colliders are normalised to their owning Actor (see _normalize_to_actor())
## before being checked for a MobaCombatant child, since production scenes
## put MobaCombatant on the Actor, not on the collider body itself.
##
## Fails gracefully (returns empty array) if no physics world is available.
## Requires a reference node to get the physics world from.
static func _query_area(
	position: Vector3, radius: float, collision_mask: int, reference_node: Node
) -> Array[Node]:
	var candidates: Array[Node] = []

	# Get the physics space state through the reference node's spatial anchor.
	# Fail gracefully if it doesn't exist. get_world_3d() likewise logs an
	# engine error when the node is not in a world yet, so the tree check has
	# to come first.
	var space_state: PhysicsDirectSpaceState3D = null
	var anchor := _get_spatial_anchor(reference_node)
	if anchor != null and anchor.is_inside_tree():
		var world := anchor.get_world_3d()
		if world != null:
			space_state = world.direct_space_state
	if space_state == null:
		return candidates

	# Create a sphere shape for the query
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = radius

	# Perform the shape query
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere_shape
	query.transform.origin = position
	query.collision_mask = collision_mask

	var results: Array[Dictionary] = space_state.intersect_shape(query)
	for result in results:
		if result is Dictionary and "collider" in result:
			var body: Node = result["collider"] as Node
			if body == null:
				continue
			var candidate := _normalize_to_actor(body)
			if candidate.get_node_or_null("MobaCombatant") != null:
				candidates.append(candidate)

	return candidates


## Normalise a physics collider to the node the rest of targeting (and
## MobaAbilityAction._get_combatant()) expects a candidate to be.
##
## Production scenes are Actor(Node) -> Body(CharacterBody3D/2D), with
## MobaCombatant as a sibling of Body under the Actor -- so the collider
## itself never carries MobaCombatant, only its parent Actor does. Fall back
## to the collider itself when it has no Actor parent so a bare headless
## fixture (a collider with MobaCombatant attached directly, no Actor) still
## resolves.
static func _normalize_to_actor(collider: Node) -> Node:
	var actor := collider.get_parent() as Actor
	if actor != null:
		return actor
	return collider


## Check if a candidate is alive.
static func _is_candidate_alive(candidate: Node) -> bool:
	var combatant := candidate.get_node_or_null("MobaCombatant") as MobaCombatant
	if combatant == null:
		return false
	return combatant.is_alive()


## Check if a candidate matches the ability's target allegiance.
##
## When either the candidate or caster is not itself an Actor, treat the
## candidate as hostile (allows headless test fixtures without full scenes
## to resolve).
static func _matches_allegiance(candidate: Node, caster: Node, target_allegiance: int) -> bool:
	match target_allegiance:
		MobaAbility.TargetAllegiance.ANY:
			# ANY targets everyone
			return true

		MobaAbility.TargetAllegiance.HOSTILE:
			# HOSTILE targets enemies (different hostility)
			return _is_hostile_to(candidate, caster)

		MobaAbility.TargetAllegiance.FRIENDLY:
			# FRIENDLY targets allies (same hostility)
			return _is_friendly_to(candidate, caster)

		_:
			# Unknown allegiance, treat as hostile
			return true


## Check if a candidate is hostile to the caster.
##
## Candidates are already normalised to their Actor by _query_area() (see
## _normalize_to_actor()), and production always passes the Actor itself as
## caster -- so both sides are read directly, not via get_parent(). Returns
## true if their Actor.hostile values differ, treating headless fixtures
## (either side not an Actor) as hostile.
static func _is_hostile_to(candidate: Node, caster: Node) -> bool:
	var candidate_actor := candidate as Actor
	var caster_actor := caster as Actor

	# If either side is not an Actor, treat candidate as hostile
	if candidate_actor == null or caster_actor == null:
		return true

	# Hostile when their hostility values differ
	return candidate_actor.hostile != caster_actor.hostile


## Check if a candidate is friendly to the caster.
##
## Candidates are already normalised to their Actor by _query_area() (see
## _normalize_to_actor()), and production always passes the Actor itself as
## caster -- so both sides are read directly, not via get_parent(). Returns
## true if their Actor.hostile values match, treating headless fixtures
## (either side not an Actor) as hostile.
static func _is_friendly_to(candidate: Node, caster: Node) -> bool:
	var candidate_actor := candidate as Actor
	var caster_actor := caster as Actor

	# If either side is not an Actor, treat candidate as hostile (not friendly)
	if candidate_actor == null or caster_actor == null:
		return false

	# Friendly when their hostility values match
	return candidate_actor.hostile == caster_actor.hostile


## Check if a candidate is visible (stealth hook).
##
## Currently always returns true. This is a single named hook so a future
## stealth mechanic has exactly one place to change.
static func _is_candidate_visible(_candidate: Node) -> bool:
	# TODO: implement stealth check when vanish mechanic is added
	return true


## Resolve a spatial anchor (a Node3D) for a caster/reference node.
##
## Production always passes the Actor itself (Actor extends Node, not
## Node3D -- see addons/mikeys_game_bones/actors/actor.gd), whose actual
## Node3D presentation lives on its "Body" child. If the node is already a
## Node3D, use it directly (covers headless test fixtures that pass a body
## or a Node3D-scripted stand-in). Otherwise fall back to its Body child,
## null if neither exists.
static func _get_spatial_anchor(node: Node) -> Node3D:
	if node == null:
		return null

	var node_3d := node as Node3D
	if node_3d != null:
		return node_3d

	return node.get_node_or_null("Body") as Node3D


## Get world position of a node, with a default fallback.
##
## global_position is only readable once a Node3D is inside the tree -- reading
## it earlier still returns a value but logs an engine error, which turns the
## documented "no physics world" path into pages of error spam. Guard on the
## tree instead of relying on that.
##
## Prefers the Actor.global_position bridge (which already knows how to read
## a CharacterBody3D or CharacterBody2D "Body" child) over re-implementing
## the 2D/3D handling here, so that logic stays in the one place Actor owns.
static func _get_position(node: Node) -> Vector3:
	var anchor := _get_spatial_anchor(node)
	if anchor == null or not anchor.is_inside_tree():
		return Vector3.ZERO

	var actor := node as Actor
	if actor != null:
		return actor.global_position

	return anchor.global_position
