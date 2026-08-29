## Skillshot projectile: a capped Area3D that travels along a fixed aim
## direction, resolves what it passes through, and despawns on hit, at maximum
## range, or at its lifetime cap.
##
## Spawned and configured by MobaTargeting.resolve_skillshot(); nothing else
## constructs one. Its effect application is deliberately asynchronous -- a
## skillshot commits its resource and cooldown at activation and only lands
## damage later, when the projectile actually reaches something.
##
## Time convention. `.github/instructions/rules.instructions.md` requires
## systems to advance on an explicit tick(delta) from their owner. tick() here
## is public, complete, and callable with no engine frame driving it: movement,
## range bookkeeping, lifetime bookkeeping, collision resolution, and every
## despawn decision live inside it and nowhere else. _physics_process() is a
## live-game *driver* for that tick, not a second code path -- it exists
## because a projectile in a running game has to advance on the physics clock
## for its collision sweep to query a settled physics space, the same way
## rules/ui/ and rules/input/ already drive themselves from _process. Do not
## put movement, collision bookkeeping, or despawn decisions anywhere tick()
## cannot reach.
##
## Self-driving is disableable and cannot double-advance. A projectile that
## self-drives while its owner (or a test) also calls tick() would move twice
## in a frame, silently and only when the two are mixed. `self_driven` gates
## _physics_process, and tick() rejects -- loudly -- an external call made
## while self-driving is still on.
##
## Collision. The sweep is a shapecast along the frame's whole travel segment,
## not a point sample at its end, so `speed * delta` cannot skip thin geometry.
## Area3D's own body_entered/area_entered are deliberately not connected: they
## fire only from the engine's physics step, which would put collision handling
## outside tick() and outside any headless caller's control, and they sample
## overlap rather than the segment, which is exactly the tunneling hazard.
## The Area3D is still the projectile's volume -- the shapecast sweeps that
## same CollisionShape3D shape and that same collision_mask.
##
## Hit decisions route through MobaTargeting.filter_valid_targets(). This file
## never reads Actor.hostile, never re-checks aliveness, and never
## re-implements caster exclusion; that filter is their single reader.
class_name MobaProjectile
extends Area3D

## Why a projectile stopped existing. Exposed so a caller (and the test suite)
## can tell "hit something" from "ran out of range" from "ran out of time".
enum DespawnReason {
	NONE,
	COMBATANT_HIT,
	WORLD_GEOMETRY,
	MAX_RANGE,
	LIFETIME_CAP,
}

## Multiplier applied to range / speed when an ability authors no explicit
## lifetime (see configure()). A safety net, not a balance number: it only
## decides how long a projectile that somehow never reaches its own maximum
## range is allowed to keep existing.
const _LIFETIME_FALLBACK_FACTOR := 2.0

## Number of live projectiles holding a slot against max_active_projectiles.
static var _active_count: int = 0

## Set when a refusal has already been logged, cleared when a slot frees up, so
## a saturated cap logs once per episode rather than once per attempted spawn.
static var _cap_refusal_logged: bool = false

# Collision layer and mask are Area3D's own exported properties, authored on
# moba_projectile.tscn and (for the mask) re-read from the ability's
# targeting_collision_mask in configure(). They are deliberately not
# re-declared here: GDScript cannot shadow a parent member, and a parallel
# @export applied back onto the real one would be a second source of truth for
# the same value. No integer layer or mask is written in this file.

## Travel speed in world units per second.
@export var speed: float = 20.0

## Maximum distance travelled before despawning, in world units.
@export var max_range: float = 10.0

## Despawn safety net measured in seconds of flight, independent of range: a
## projectile that misses everything and somehow never trips max_range cannot
## live forever. 0 disables it.
@export var lifetime_cap: float = 3.0

## When true, a valid target is hit and the projectile keeps going instead of
## despawning. Never applies to world geometry.
@export var piercing: bool = false

## Hard cap on simultaneously live projectiles. A spawn that would exceed it is
## refused (see try_reserve_slot()); no in-flight projectile is ever recycled or
## freed to make room, and there is no pool.
@export var max_active_projectiles: int = 16

## Whether this projectile drives its own tick() from _physics_process. Turn it
## off to advance the projectile explicitly, which is what the headless tests
## and the conformance suite do.
@export var self_driven: bool = true:
	set = _set_self_driven

## The ability whose effects this projectile applies on hit.
var ability: MobaAbility = null

## The node that fired this projectile (production: the caster Actor). Handed
## to filter_valid_targets() unchanged; never inspected here.
var caster: Node = null

## The caster's MobaCombatant, the damage/effect source passed to
## MobaAbilityAction.resolve().
var caster_combatant: MobaCombatant = null

## Normalised direction of travel. Raw aim: no cone narrowing, no magnetism.
var direction: Vector3 = Vector3.FORWARD

## World units travelled so far, against max_range.
var distance_traveled: float = 0.0

## Seconds of flight so far, against lifetime_cap.
var elapsed_lifetime: float = 0.0

## Why this projectile despawned, DespawnReason.NONE while it is still flying.
var despawn_reason: DespawnReason = DespawnReason.NONE

## Per-instance hit set, keyed by instance id, so a piercing projectile never
## hits the same target twice -- including when a sweep re-clips the edge of a
## body it already passed through. Instance ids rather than node references so
## a target freed mid-flight cannot resurrect as a second hit.
var _hit_ids: Dictionary = {}

## False once this projectile has despawned. It may outlive the flag by a frame
## (queue_free() is deferred), so every entry point checks this, not liveness.
var _active: bool = true

## Whether this instance currently holds a slot against max_active_projectiles.
var _reserved: bool = false

## Set only for the duration of the _physics_process-driven tick() call, so
## tick() can tell a self-drive from an external call. Not logic: the
## re-entrancy marker that makes double-advancing detectable.
var _driving: bool = false

@onready var _volume: CollisionShape3D = $CollisionShape3D
@onready var _sweep: ShapeCast3D = $ShapeCast3D


func _ready() -> void:
	_sync_sweep()
	set_physics_process(self_driven and _active)


## Live-game driver for tick(). Does nothing but call it; the marker around the
## call is the double-advance guard described in the header, not behavior.
func _physics_process(delta: float) -> void:
	_driving = true
	tick(delta)
	_driving = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# A projectile freed without despawning (scene teardown, a test's own
		# cleanup) must still give its slot back, or the cap leaks downward.
		_release_slot()


## Advance the projectile by `delta` seconds: sweep the travel segment, resolve
## whatever it meets, move, and despawn when the hit / range / lifetime rules
## say to. The single implementation of all of that.
func tick(delta: float) -> void:
	if not _active:
		return

	if self_driven and not _driving:
		push_error(
			(
				"MobaProjectile.tick() called externally while self_driven is true. "
				+ "Set self_driven = false before driving a projectile yourself, or "
				+ "it advances twice in a frame."
			)
		)
		return

	if delta <= 0.0:
		return

	elapsed_lifetime += delta

	# Clamp the frame's step to whatever range is left, so a hit found by the
	# sweep is always a hit that happened inside the ability's range.
	var step := speed * delta
	var remaining := maxf(max_range - distance_traveled, 0.0)
	var range_exhausted := false
	if step >= remaining:
		step = remaining
		range_exhausted = true

	if step > 0.0:
		if not _sweep_and_resolve(direction * step):
			return
		global_position += direction * step
		distance_traveled += step

	if range_exhausted:
		_despawn(DespawnReason.MAX_RANGE)
		return

	if lifetime_cap > 0.0 and elapsed_lifetime >= lifetime_cap:
		_despawn(DespawnReason.LIFETIME_CAP)


## Apply an ability's authored delivery numbers to this instance and bind it to
## its caster. Called by MobaTargeting.resolve_skillshot() after the projectile
## is in the tree.
##
## lifetime_cap reads ability.duration, the same field MobaAbility already
## lends to shield duration ("uses ability's duration field for shield
## duration"). An ability that authors none falls back to a multiple of its own
## range / speed, so the safety net exists whether or not it was authored.
func configure(p_ability: MobaAbility, p_caster: Node, p_direction: Vector3) -> void:
	ability = p_ability
	caster = p_caster
	caster_combatant = null
	if p_caster != null:
		caster_combatant = p_caster.get_node_or_null("MobaCombatant") as MobaCombatant

	if p_direction.length_squared() > 0.0:
		direction = p_direction.normalized()

	if ability == null:
		return

	if ability.projectile_speed > 0.0:
		speed = ability.projectile_speed
	if ability.range > 0.0:
		max_range = ability.range
	if ability.targeting_collision_mask > 0:
		collision_mask = ability.targeting_collision_mask

	if ability.duration > 0.0:
		lifetime_cap = ability.duration
	elif speed > 0.0:
		lifetime_cap = (max_range / speed) * _LIFETIME_FALLBACK_FACTOR

	_sync_sweep()


## Reserve one of the max_active_projectiles slots for this instance.
##
## Returns false when the cap is already saturated; the caller must free the
## instance and give up on the spawn. This is a hard cap, not a pool: nothing
## in flight is ever freed or recycled to make room for a newer projectile.
func try_reserve_slot() -> bool:
	if _reserved:
		return true

	if _active_count >= max_active_projectiles:
		if not _cap_refusal_logged:
			_cap_refusal_logged = true
			push_warning(
				(
					"MobaProjectile: %d live projectiles is the cap; refusing the spawn."
					% max_active_projectiles
				)
			)
		return false

	_reserved = true
	_active_count += 1
	return true


## Whether this projectile is still flying. Stays false after a despawn even
## for the frame the node survives queue_free().
func is_active() -> bool:
	return _active


## How many distinct targets this projectile has hit.
func hit_count() -> int:
	return _hit_ids.size()


## Whether this projectile has already hit `target`.
func has_hit(target: Node) -> bool:
	if target == null:
		return false
	return _hit_ids.has(target.get_instance_id())


## Live projectiles currently holding a slot against the cap.
static func active_count() -> int:
	return _active_count


func _set_self_driven(value: bool) -> void:
	self_driven = value
	if is_inside_tree():
		set_physics_process(value and _active)


## Keep the sweep sampling exactly the Area3D's own volume and mask, so the
## collision shape and layer/mask authored on the scene stay the single source
## of truth for both.
func _sync_sweep() -> void:
	if _sweep == null:
		return
	if _volume != null:
		_sweep.shape = _volume.shape
	_sweep.collision_mask = collision_mask


## Shapecast the frame's travel segment and resolve every collider along it in
## order of distance, nearest first -- a wall in front of an enemy has to stop
## the projectile before the enemy behind it is ever considered.
##
## Returns true when the projectile survived the sweep. When a collider
## despawned it, the projectile is moved to that contact point rather than to
## the end of the segment: a fast projectile must not record travel past the
## thing that stopped it.
func _sweep_and_resolve(motion: Vector3) -> bool:
	var start := global_position

	for hit in _cast_segment(motion):
		var collider := hit["collider"] as Node
		if collider == null or not is_instance_valid(collider):
			continue

		if _resolve_collider(collider):
			continue

		var travelled: float = clampf(hit["distance"], 0.0, motion.length())
		global_position = start + direction * travelled
		distance_traveled += travelled
		return false

	return true


## Sweep the projectile's own shape along `motion` and return every collider it
## meets as {"collider": Node, "distance": float}, sorted nearest first.
func _cast_segment(motion: Vector3) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if _sweep == null or not is_inside_tree():
		return hits

	# target_position is ShapeCast3D-local; to_local() converts the segment's
	# world-space endpoint without assuming the projectile is unrotated.
	_sweep.target_position = _sweep.to_local(global_position + motion)
	_sweep.force_shapecast_update()

	var origin := global_position
	for index in _sweep.get_collision_count():
		var collider := _sweep.get_collider(index) as Node
		if collider == null:
			continue
		(
			hits
			. append(
				{
					"collider": collider,
					"distance": origin.distance_to(_sweep.get_collision_point(index)),
				}
			)
		)

	hits.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"]
	)
	return hits


## Resolve one collider met by the sweep. Returns true when the projectile
## should keep going, false when this collider despawned it.
func _resolve_collider(collider: Node) -> bool:
	# Colliders are normalised to their owning Actor exactly as
	# MobaTargeting._query_area() does, because production scenes put
	# MobaCombatant on the Actor rather than on the collider body itself.
	var candidate := MobaTargeting._normalize_to_actor(collider)
	if candidate.get_node_or_null("MobaCombatant") == null:
		# World geometry: stop dead, apply nothing, and never pierce through it.
		_despawn(DespawnReason.WORLD_GEOMETRY)
		return false

	if ability == null:
		return true

	# Already hit: a piercing projectile overlapping the same body across
	# consecutive frames, or re-clipping its edge, must not hit it twice.
	if _hit_ids.has(candidate.get_instance_id()):
		return true

	# Every hit decision -- allegiance, aliveness, caster exclusion, stealth --
	# belongs to the shared filter. Nothing here duplicates any of it.
	var candidates: Array[Node] = [candidate]
	if MobaTargeting.filter_valid_targets(candidates, caster, ability).is_empty():
		return true

	_hit_ids[candidate.get_instance_id()] = true
	MobaAbilityAction.resolve(ability, candidate, caster_combatant)

	if piercing:
		return true

	_despawn(DespawnReason.COMBATANT_HIT)
	return false


## Stop flying, give the cap slot back, and leave the scene.
func _despawn(reason: DespawnReason) -> void:
	if not _active:
		return

	_active = false
	despawn_reason = reason
	set_physics_process(false)
	_release_slot()
	queue_free()


## Return this instance's slot to the cap. Idempotent: _despawn() and
## NOTIFICATION_PREDELETE both call it.
func _release_slot() -> void:
	if not _reserved:
		return

	_reserved = false
	_active_count = maxi(_active_count - 1, 0)
	_cap_refusal_logged = false
