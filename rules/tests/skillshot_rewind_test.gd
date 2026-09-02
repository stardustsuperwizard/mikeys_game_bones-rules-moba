## Test suite for rewind-based skillshot hit resolution (#329).
##
## Covers what the rewound path changes and, just as importantly, what it must
## leave alone: a target whose live position has left the shot's path is still
## hit from its rewound position; world geometry still blocks at its real
## current position; a forged, far-too-old client timestamp is clamped to the
## window edge rather than honoured; damage lands on current health rather than
## on anything read out of position history; and a target that died before the
## tick resolves takes nothing, rewound position notwithstanding.
##
## Physics fixtures follow ProjectileTest's layout exactly -- Actor(Node) ->
## Body(CharacterBody3D + CollisionShape3D), MobaCombatant a sibling of Body --
## because MobaTargeting normalises a collider to its owning Actor and looks for
## MobaCombatant there. Clusters are separated along Z, far from every other
## suite's fixtures, since the whole run shares one physics space.
class_name SkillshotRewindTest

const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaDamage = preload("res://rules/core/moba_damage.gd")
const MobaPositionHistory = preload("res://rules/net/moba_position_history.gd")
const MobaProjectile = preload("res://rules/targeting/moba_projectile.gd")
const MobaRewindClock = preload("res://rules/net/moba_rewind_clock.gd")
const MobaStateMachine = preload("res://rules/state/moba_state_machine.gd")
const MobaTargeting = preload("res://rules/targeting/moba_targeting.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## Cluster separation, same reasoning as ProjectileTest's: one shared physics
## space, so scenarios have to be far enough apart that one's bodies can never
## fall inside another's travel segment or candidate query. Offset well clear of
## ProjectileTest's own origin so the two suites cannot reach each other either.
const _CLUSTER_ORIGIN_Z := 9000.0
const _CLUSTER_SPACING := 200.0

## Bound on every drive loop: a loop that cannot terminate hangs the whole run.
const _MAX_DRIVE_STEPS := 400

## How far along +X the target sits, both in history and now. Only its Z changes
## between the two, so "did the rewind apply?" is the only variable.
const _TARGET_RANGE_M := 10.0

## How far off the +X travel line the target's *live* position is pushed.
##
## Bounded on both sides. It must exceed the live sweep's reach -- the
## projectile's 0.25 m shape plus the target body's 0.5 m sphere, 0.75 m in
## total -- by enough that no tolerance lets the live sweep touch it, which
## _test_live_miss_without_rewind() asserts directly rather than assuming.
##
## It must also stay inside MobaProjectile._REWIND_CANDIDATE_MARGIN_M (6 m),
## because that margin is what the rewound candidate query reaches by, and a
## fixture that teleported the target further than any combatant could actually
## move in the 120 ms window would be testing an impossible scenario. 3 m is
## four times the live reach and half the margin.
const _OFF_PATH_OFFSET_M := 3.0

## How far in the past the forged-timestamp scenario's claim points, in ms.
##
## Far outside DEFAULT_REWIND_WINDOW_MS so the clamp is unambiguous, and
## expressed as a clock *offset* rather than a claimed tick count: engine uptime
## at test time is around a second, so "5 seconds ago" cannot be written as a
## positive Time.get_ticks_msec() value, and resolve_skillshot() only rewinds a
## claim greater than zero.
const _STALE_CLAIM_AGE_MS := 5000

## The claimed client tick count the forged-timestamp scenario sends. Any
## positive value works: the clock's per-peer offset, seeded alongside it, is
## what places it _STALE_CLAIM_AGE_MS in the server's past.
const _STALE_CLAIM_TICKS_MS := 1

## Half-width of the on-path bracket around the window edge in that scenario.
##
## The suite stamps its fixtures from one `rewind_ms` captured before any of
## them run, while the resolver stamps the projectile from the clock at the
## moment it fires -- several tests later. This is the slack between the two,
## wide enough that the drift cannot walk the query off the bracket, and still
## far newer than the oldest retained sample the unclamped read would find.
const _CLAMP_BRACKET_MS := 2000

## Damage the scenario abilities deal. TRUE damage, so armour cannot mitigate a
## hit down to nothing and make "was it damaged?" ambiguous.
const _ABILITY_DAMAGE := 25.0

## Tolerance for float health comparisons -- representation error only.
const _EPSILON := 0.001


## Actor stand-in whose _ready() is a no-op, for the same reason ProjectileTest
## needs one: Actor._ready() dereferences the game-side CharacterSheet, which
## rules/ may not name, but a physics fixture has to be in the tree to register
## with the space.
class _TestActor:
	extends Actor

	func _ready() -> void:
		pass


## Run the skillshot rewind test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var violations: Array[String] = []

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		printerr("\n=== Skillshot Rewind Test Violations ===")
		printerr("FAIL skillshot_rewind: no SceneTree available")
		return false

	# Build and arrange every fixture up front so the whole suite costs one
	# physics frame, exactly as ProjectileTest does and for the same reason: a
	# body does not register with the physics space until a frame has been
	# processed, and `godot --headless --quit` runs only a handful of frames --
	# a suite that awaits more than that stalls forever and silently takes the
	# rest of the run down with it.
	var rewind_ms := Time.get_ticks_msec()

	var hit_scene := _build_scene(tree, 0)
	var control_scene := _build_scene(tree, 1)
	var wall_scene := _build_scene(tree, 2)
	var clamp_scene := _build_scene(tree, 3)
	var health_scene := _build_scene(tree, 4)
	var dead_scene := _build_scene(tree, 5)
	var unticked_scene := _build_scene(tree, 6)

	# Every scenario but the clamping one puts the target on the path at
	# `rewind_ms` and off it now.
	for scene in [hit_scene, control_scene, wall_scene, health_scene, dead_scene]:
		_record_on_path_history(scene, rewind_ms)

	_arrange_clamp_history(clamp_scene, rewind_ms)
	_add_wall(wall_scene, 5.0)

	# Let the space observe every body just added.
	await tree.physics_frame

	violations.append_array(_test_rewound_target_is_hit(hit_scene, rewind_ms))
	violations.append_array(_test_live_miss_without_rewind(control_scene))
	violations.append_array(_test_world_geometry_still_blocks(wall_scene, rewind_ms))
	violations.append_array(_test_stale_timestamp_clamps_to_window(clamp_scene))
	violations.append_array(_test_damage_uses_current_health(health_scene, rewind_ms))
	violations.append_array(_test_dead_target_takes_nothing(dead_scene, rewind_ms))
	violations.append_array(_test_unticked_candidate_is_not_phantom_hit(unticked_scene, rewind_ms))

	for scene in [
		hit_scene,
		control_scene,
		wall_scene,
		clamp_scene,
		health_scene,
		dead_scene,
		unticked_scene,
	]:
		(scene["container"] as Node).queue_free()

	if violations.is_empty():
		return true

	printerr("\n=== Skillshot Rewind Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


## A high-latency client fires at a target that has since moved off the path.
## The live sweep cannot see it there; the rewound position puts it squarely on
## the line, and the hit registers.
static func _test_rewound_target_is_hit(scene: Dictionary, rewind_ms: int) -> Array[String]:
	var violations: Array[String] = []
	var combatant := _combatant_of(scene["enemy"])
	var health_before: float = combatant._current_health

	var projectile := _spawn(scene, rewind_ms)
	if projectile == null:
		violations.append("rewound hit: projectile did not spawn")
		return violations

	_drive(projectile)

	if combatant._current_health >= health_before:
		violations.append(
			(
				"rewound hit: a target that had moved off the live path took no damage "
				+ (
					"(health %.2f, expected below %.2f) -- its rewound position was not tested"
					% [combatant._current_health, health_before]
				)
			)
		)

	return violations


## The control for the case above: the identical fixture with no rewind stamp
## misses. Without this, a rewound "hit" proves nothing -- the live sweep might
## simply have been reaching the target all along.
static func _test_live_miss_without_rewind(scene: Dictionary) -> Array[String]:
	var violations: Array[String] = []
	var combatant := _combatant_of(scene["enemy"])
	var health_before: float = combatant._current_health

	# rewind_timestamp_ms left at 0: the live path, exactly as before #329.
	var projectile := _spawn(scene, 0)
	if projectile == null:
		violations.append("live miss: projectile did not spawn")
		return violations

	_drive(projectile)

	if combatant._current_health != health_before:
		violations.append(
			(
				(
					"live miss: a target %.1f m off the path took damage with no rewind stamp "
					% _OFF_PATH_OFFSET_M
				)
				+ "-- the rewound-hit case proves nothing while the live sweep reaches it"
			)
		)

	return violations


## World geometry is resolved live and still blocks. A wall between the caster
## and the target's rewound position stops the shot at the wall: rewinding
## positions must not let a projectile shoot through a wall.
static func _test_world_geometry_still_blocks(scene: Dictionary, rewind_ms: int) -> Array[String]:
	var violations: Array[String] = []
	var combatant := _combatant_of(scene["enemy"])
	var health_before: float = combatant._current_health

	var projectile := _spawn(scene, rewind_ms)
	if projectile == null:
		violations.append("world geometry: projectile did not spawn")
		return violations

	_drive(projectile)

	if projectile.despawn_reason != MobaProjectile.DespawnReason.WORLD_GEOMETRY:
		violations.append(
			(
				(
					"world geometry: expected despawn reason WORLD_GEOMETRY, got %d -- "
					% projectile.despawn_reason
				)
				+ "the live wall sweep was bypassed by rewound resolution"
			)
		)

	if combatant._current_health != health_before:
		violations.append(
			"world geometry: a target behind the wall was hit from its rewound position"
		)

	return violations


## A claimed timestamp far older than the window is clamped to the window edge
## by MobaRewindClock, so the position tested is the one the target held
## DEFAULT_REWIND_WINDOW_MS ago -- not the fully-stale one the claim asked for.
##
## This is the one scenario that goes through MobaRewindClock end to end rather
## than stamping the projectile directly, because the clamp under test lives in
## the clock. Its fixture distinguishes the two answers: at the window edge the
## target is on the path (hit), at the ancient claimed instant it is far off it
## (miss). An unclamped implementation reads the oldest retained sample, finds
## the off-path position, and misses.
static func _test_stale_timestamp_clamps_to_window(scene: Dictionary) -> Array[String]:
	var violations: Array[String] = []
	var combatant := _combatant_of(scene["enemy"])
	var window: int = MobaPositionHistory.DEFAULT_REWIND_WINDOW_MS
	var health_before: float = combatant._current_health

	# The forged claim, which the seeded offset places _STALE_CLAIM_AGE_MS in the
	# server's past -- far outside the 120 ms window.
	var caster: Actor = scene["caster"]
	var context := MobaCastContext.new(
		caster, null, Vector3.RIGHT, Vector3.ZERO, scene["peer_id"], _STALE_CLAIM_TICKS_MS
	)
	var projectile := MobaTargeting.resolve_skillshot(scene["ability"], context, caster)
	if projectile == null:
		violations.append("stale timestamp: projectile did not spawn")
		return violations
	projectile.self_driven = false

	# The clamp itself, asserted on the stamp the resolver actually applied.
	var stamped_delay := Time.get_ticks_msec() - projectile.rewind_timestamp_ms
	if stamped_delay > window:
		violations.append(
			(
				"stale timestamp: rewound %d ms, past the %d ms window -- not clamped"
				% [stamped_delay, window]
			)
		)

	_drive(projectile)

	if combatant._current_health >= health_before:
		violations.append(
			(
				"stale timestamp: no damage -- the window-edge position (on the path) "
				+ "should have been tested, not the fully-stale one (off the path)"
			)
		)

	return violations


## Damage from a rewind-confirmed hit is computed against the target's health at
## the moment the hit resolves. Position history carries positions and nothing
## else; it must never become a source of stale health.
static func _test_damage_uses_current_health(scene: Dictionary, rewind_ms: int) -> Array[String]:
	var violations: Array[String] = []
	var combatant := _combatant_of(scene["enemy"])

	# Wound the target AFTER the rewound instant was recorded. A hit resolved
	# against anything historical would land on the full-health value instead.
	combatant.apply_damage(MobaDamage.new(40.0, MobaAbility.DamageType.TRUE))

	var health_before: float = combatant._current_health
	var projectile := _spawn(scene, rewind_ms)
	if projectile == null:
		violations.append("current health: projectile did not spawn")
		return violations

	_drive(projectile)

	var expected := health_before - _ABILITY_DAMAGE
	if absf(combatant._current_health - expected) > _EPSILON:
		violations.append(
			(
				"current health: expected %.2f (current %.2f less %.2f), got %.2f"
				% [expected, health_before, _ABILITY_DAMAGE, combatant._current_health]
			)
		)

	return violations


## Validity is read live even though position is rewound. A target that died
## before the projectile's tick resolves takes nothing, however squarely its
## rewound position sits on the segment.
static func _test_dead_target_takes_nothing(scene: Dictionary, rewind_ms: int) -> Array[String]:
	var violations: Array[String] = []
	var combatant := _combatant_of(scene["enemy"])

	# Kill it outright before the shot resolves.
	combatant.apply_damage(
		MobaDamage.new(combatant._current_health + 1000.0, MobaAbility.DamageType.TRUE)
	)

	if combatant.is_alive():
		violations.append("dead target: fixture failed to kill the target before the shot")
		return violations

	var health_before: float = combatant._current_health
	var projectile := _spawn(scene, rewind_ms)
	if projectile == null:
		violations.append("dead target: projectile did not spawn")
		return violations

	_drive(projectile)

	if combatant._current_health != health_before:
		violations.append(
			(
				(
					"dead target: health moved from %.2f to %.2f -- a corpse was hit from its "
					% [health_before, combatant._current_health]
				)
				+ "rewound position; aliveness must still be read live"
			)
		)

	if projectile.despawn_reason == MobaProjectile.DespawnReason.COMBATANT_HIT:
		violations.append("dead target: projectile despawned as COMBATANT_HIT on a dead target")

	return violations


## A candidate the server has never ticked has an empty position history. It
## must resolve at its own live position -- off the path here, so it is missed --
## and never at some substitute the projectile invented.
##
## The specific regression: Actor is a plain Node, not a Node3D, so a
## `candidate as Node3D` cast misses every production candidate. A fallback
## written that way silently returns the *projectile's* own position, which puts
## the candidate at distance 0 along the segment -- an unconditional hit, ahead
## of any wall, on a target that was never in the path.
static func _test_unticked_candidate_is_not_phantom_hit(
	scene: Dictionary, rewind_ms: int
) -> Array[String]:
	var violations: Array[String] = []
	var combatant := _combatant_of(scene["enemy"])

	# Deliberately no _record_on_path_history() for this scenario: the whole
	# point is a combatant whose history is empty.
	if combatant.get_position_history().has_samples():
		violations.append(
			"unticked candidate: fixture recorded history it was meant to leave empty"
		)
		return violations

	var health_before: float = combatant._current_health
	var projectile := _spawn(scene, rewind_ms)
	if projectile == null:
		violations.append("unticked candidate: projectile did not spawn")
		return violations

	_drive(projectile)

	if combatant._current_health != health_before:
		violations.append(
			(
				(
					"unticked candidate: a combatant %.1f m off the path with no recorded "
					% _OFF_PATH_OFFSET_M
				)
				+ "history took damage -- its position was substituted, not resolved"
			)
		)

	if projectile.despawn_reason == MobaProjectile.DespawnReason.COMBATANT_HIT:
		(
			violations
			. append(
				"unticked candidate: projectile despawned as COMBATANT_HIT on a target never in its path"
			)
		)

	return violations


## Build one scenario cluster: a container, a non-hostile caster at its origin,
## and one hostile enemy already standing at its *live* position, off the travel
## line. The container makes the caster's parent scenario-local, since a
## skillshot parents its projectile there.
static func _build_scene(tree: SceneTree, cluster: int) -> Dictionary:
	var origin := Vector3(0.0, 0.0, _CLUSTER_ORIGIN_Z + _CLUSTER_SPACING * cluster)

	var container := Node3D.new()
	tree.root.add_child(container)

	var caster := _make_actor(container, false, origin)
	var state_machine := MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	caster.add_child(state_machine)

	var enemy := _make_actor(container, true, origin + _off_path_offset())

	return {
		"origin": origin,
		"container": container,
		"caster": caster,
		"enemy": enemy,
		"peer_id": 43290 + cluster,
		"ability": _make_ability("rewind_shot_%d" % cluster),
	}


## Where a target stands on the shot's path, relative to a cluster's origin.
static func _on_path_offset() -> Vector3:
	return Vector3(_TARGET_RANGE_M, 0.0, 0.0)


## Where a target stands after moving off the shot's path, relative to origin.
static func _off_path_offset() -> Vector3:
	return Vector3(_TARGET_RANGE_M, 0.0, _OFF_PATH_OFFSET_M)


## Record a history in which the target was on the path at `rewind_ms`.
##
## Bracketed by samples holding the same position, so a query at or near that
## instant resolves to it rather than clamping to an end of the buffer or
## interpolating toward somewhere else.
static func _record_on_path_history(scene: Dictionary, rewind_ms: int) -> void:
	var on_path := (scene["origin"] as Vector3) + _on_path_offset()
	var history := _combatant_of(scene["enemy"]).get_position_history()

	history.record(rewind_ms - 1000, on_path)
	history.record(rewind_ms, on_path)
	history.record(rewind_ms + 100000, on_path)


## Arrange the clamping scenario: a history whose window-edge position is on the
## path but whose oldest retained sample is not, plus a shared-clock offset for
## this peer so the forged timestamp translates to itself on the server.
static func _arrange_clamp_history(scene: Dictionary, rewind_ms: int) -> void:
	var origin: Vector3 = scene["origin"]
	var on_path := origin + _on_path_offset()
	var off_path := origin + _off_path_offset()
	var window: int = MobaPositionHistory.DEFAULT_REWIND_WINDOW_MS
	var history := _combatant_of(scene["enemy"]).get_position_history()

	# The oldest retained sample, at the very instant the forged claim points to:
	# what an UNCLAMPED read returns. Off the path, so honouring the forgery
	# misses.
	history.record(rewind_ms - _STALE_CLAIM_AGE_MS, off_path)

	# The window edge, bracketed by a pair both on the path, so the instant
	# resolve_skillshot() actually stamps still resolves to an on-path point
	# however far the clock has drifted since rewind_ms was captured.
	history.record(rewind_ms - window - _CLAMP_BRACKET_MS, on_path)
	history.record(rewind_ms - window + _CLAMP_BRACKET_MS, on_path)

	# A far-future sample, so a window-edge query interpolates inside the pair
	# above rather than clamping forward to the newest sample.
	history.record(rewind_ms + 100000, off_path)

	# Seed the shared clock so this peer's claim translates to exactly
	# _STALE_CLAIM_AGE_MS before rewind_ms. record_sample() stores
	# `arrival - sent` as the offset, and get_rewind_delay_ms() adds it back to
	# the claim, so this pair places _STALE_CLAIM_TICKS_MS there.
	#
	# This is the one place the suite touches process-wide state, and it is
	# unavoidable: resolve_skillshot() reads MobaRewindClock.shared(), so an
	# end-to-end assertion on the clamp has to seed the instance it reads. It is
	# bounded by peer id -- _build_scene() hands every cluster its own, so this
	# entry cannot collide with another scenario's or with a real peer's, and
	# the write only ever adds one integer under an id nothing else uses. Every
	# other scenario stamps its projectile directly and touches no shared state.
	MobaRewindClock.shared().record_sample(
		scene["peer_id"], _STALE_CLAIM_TICKS_MS, rewind_ms - _STALE_CLAIM_AGE_MS
	)


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


## Add a thin static wall across the travel line, `offset` metres along +X.
static func _add_wall(scene: Dictionary, offset: float) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 1

	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 4.0, 4.0)
	collision.shape = box
	wall.add_child(collision)

	var container: Node3D = scene["container"]
	container.add_child(wall)
	wall.global_position = (scene["origin"] as Vector3) + Vector3(offset, 0.0, 0.0)
	return wall


## A SKILLSHOT ability with the delivery numbers these scenarios need. TRUE
## damage, so armour cannot mitigate a hit down to nothing.
static func _make_ability(id: String) -> MobaAbility:
	var ability := MobaAbility.new()
	ability.id = id
	ability.targeting_type = MobaAbility.TargetingType.SKILLSHOT
	ability.target_allegiance = MobaAbility.TargetAllegiance.HOSTILE
	ability.damage_type = MobaAbility.DamageType.TRUE
	ability.base_damage = _ABILITY_DAMAGE
	ability.projectile_speed = 20.0
	ability.range = 30.0
	ability.duration = 5.0
	ability.targeting_collision_mask = 1
	return ability


## Spawn a projectile down the +X line through the production resolver, stamp it
## with `rewind_ms`, and take it off self-drive so this suite alone advances it.
##
## The stamp is applied directly rather than through MobaRewindClock so that
## every scenario but the clamping one tests the projectile's rewound resolution
## at an instant it controls exactly, with no dependence on how far the process
## clock has advanced between arranging the fixture and firing.
static func _spawn(scene: Dictionary, rewind_ms: int) -> MobaProjectile:
	var caster: Actor = scene["caster"]
	var context := MobaCastContext.new(caster, null, Vector3.RIGHT)
	var projectile := MobaTargeting.resolve_skillshot(scene["ability"], context, caster)
	if projectile == null:
		return null
	projectile.self_driven = false
	projectile.set_rewind_timestamp_ms(rewind_ms)
	return projectile


## Advance a projectile in fixed steps until it despawns, or until the step
## bound trips -- a drive loop that cannot terminate would hang the whole run.
static func _drive(projectile: MobaProjectile) -> void:
	var steps := 0
	while projectile.is_active() and steps < _MAX_DRIVE_STEPS:
		projectile.tick(0.05)
		steps += 1
