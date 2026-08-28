## MOBA ability targeting resolver.
##
## MobaTargeting provides the canonical strategies for resolving ability targets
## based on targeting type (SELF, TARGETED, AREA, GROUND). It is the sole place
## in the codebase that reads Actor.hostile for ability targeting, centralizing
## the logic so future changes to hostility mechanics require only one-function
## changes rather than sweeping modifications.
##
## Each targeting type has its own resolution function returning either a single
## target (SELF, TARGETED) or a list (AREA, GROUND after filtering). All
## multi-target strategies pass through the shared filter_valid_targets() to
## apply allegiance, alive status, caster-inclusion, and stealth checks.
class_name MobaTargeting
extends RefCounted


## Resolve a SELF targeting ability: target is always the caster.
static func resolve_self(caster: Node, _ability: MobaAbility) -> Array[Node]:
	if caster == null:
		return []
	return [caster]


## Resolve a TARGETED ability: target is the explicitly provided target.
static func resolve_targeted(caster: Node, target: Node, _ability: MobaAbility) -> Array[Node]:
	if target == null or not is_instance_valid(target):
		return []
	return [target]


## Resolve a CHANNELED ability: target is the explicitly provided target.
static func resolve_channeled(caster: Node, target: Node, _ability: MobaAbility) -> Array[Node]:
	if target == null or not is_instance_valid(target):
		return []
	return [target]


## Resolve an AREA targeting ability: gather all combatants within area_radius
## of the caster's position, then filter through the valid-target filter.
##
## Args:
##   caster: The ability caster
##   ability: The MobaAbility being resolved
##   origin: Optional origin position (defaults to caster's position)
##   collision_layer_mask: Which collision layers to query
##   collision_mask: Which collision bodies to hit
##
## Returns: Array of valid targets within the area radius, filtered by allegiance,
##   alive status, and caster inclusion rules.
static func resolve_area(
	caster: Node,
	ability: MobaAbility,
	origin: Vector3 = Vector3.ZERO,
	collision_layer_mask: int = 1,
	collision_mask: int = 1,
) -> Array[Node]:
	if caster == null:
		return []

	# Use caster position if no origin provided
	var query_origin: Vector3 = origin
	if origin == Vector3.ZERO:
		query_origin = _get_position(caster)

	# Query physics space for bodies in the area
	var candidates := _query_area(query_origin, ability.area_radius, collision_layer_mask, collision_mask, caster)

	# Filter through the shared valid-target filter
	return filter_valid_targets(candidates, caster, ability)


## Resolve a GROUND targeting ability: gather all combatants within area_radius
## of the ground point, then filter through the valid-target filter.
##
## Args:
##   caster: The ability caster
##   ground_point: The targeted ground location
##   ability: The MobaAbility being resolved
##   collision_layer_mask: Which collision layers to query
##   collision_mask: Which collision bodies to hit
##
## Returns: Array of valid targets within the area radius, filtered by allegiance,
##   alive status, and caster inclusion rules.
static func resolve_ground(
	caster: Node,
	ground_point: Vector3,
	ability: MobaAbility,
	collision_layer_mask: int = 1,
	collision_mask: int = 1,
) -> Array[Node]:
	if caster == null:
		return []

	# Query physics space for bodies at the ground point
	var candidates := _query_area(ground_point, ability.area_radius, collision_layer_mask, collision_mask, caster)

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


## Query physics space for bodies within a sphere at the given position.
## Returns the bodies themselves (typically CharacterBody3D, StaticBody3D, Area3D, etc.)
## that have a MobaCombatant child.
##
## Fails gracefully (returns empty array) if no physics world is available.
## Requires a reference node to get the physics world from.
static func _query_area(
	position: Vector3, radius: float, collision_layer_mask: int, collision_mask: int, reference_node: Node
) -> Array[Node]:
	var candidates: Array[Node] = []

	# Get the physics space state from the reference node's world. Fail gracefully if it doesn't exist.
	var space_state: PhysicsDirectSpaceState3D = null
	if reference_node is Node3D:
		var world = (reference_node as Node3D).get_world_3d()
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

	var results = space_state.intersect_shape(query)
	for result in results:
		if result is Dictionary and "collider" in result:
			var body = result["collider"] as Node
			if body != null and body.get_node_or_null("MobaCombatant") != null:
				candidates.append(body)

	return candidates


## Check if a candidate is alive.
static func _is_candidate_alive(candidate: Node) -> bool:
	var combatant := candidate.get_node_or_null("MobaCombatant") as MobaCombatant
	if combatant == null:
		return false
	return combatant.is_alive()


## Check if a candidate matches the ability's target allegiance.
##
## When either the candidate or caster has no parent Actor, treat the candidate
## as hostile (allows headless test fixtures without full scenes to resolve).
static func _matches_allegiance(
	candidate: Node, caster: Node, target_allegiance: int
) -> bool:
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
## Returns true if their Actor.hostile values differ, treating headless
## fixtures (no parent Actor) as hostile.
static func _is_hostile_to(candidate: Node, caster: Node) -> bool:
	var candidate_actor := candidate.get_parent() as Actor
	var caster_actor := caster.get_parent() as Actor

	# If either has no parent Actor, treat candidate as hostile
	if candidate_actor == null or caster_actor == null:
		return true

	# Hostile when their hostility values differ
	return candidate_actor.hostile != caster_actor.hostile


## Check if a candidate is friendly to the caster.
##
## Returns true if their Actor.hostile values match, treating headless
## fixtures (no parent Actor) as hostile.
static func _is_friendly_to(candidate: Node, caster: Node) -> bool:
	var candidate_actor := candidate.get_parent() as Actor
	var caster_actor := caster.get_parent() as Actor

	# If either has no parent Actor, treat candidate as hostile (not friendly)
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


## Get world position of a node, with a default fallback.
static func _get_position(node: Node) -> Vector3:
	if node == null:
		return Vector3.ZERO

	# Try to access global_position (works for Node3D)
	if node.get("global_position") != null:
		return node.global_position as Vector3

	# Fallback to zero
	return Vector3.ZERO
