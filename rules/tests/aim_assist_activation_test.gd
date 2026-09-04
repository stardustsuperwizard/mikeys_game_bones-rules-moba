## Integration tests for aim assist wired into SKILLSHOT activation (#272).
##
## rules/tests/aim_assist_test.gd covers MobaAimAssist in isolation (pure
## functions, no scene tree). This suite covers what that one cannot: the real
## MobaAbilityAction.execute() pipeline actually bending a SKILLSHOT's
## context.aim_direction before MobaTargeting.resolve_skillshot() is called --
## the device multiplier read live from a caster's MobaInputScheme, hard_lock
## resolving to MobaCastContext.locked_target (or falling back when it is not
## set), and TARGETED abilities staying untouched by any of it.
class_name AimAssistActivationTest
extends RefCounted

const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaAbilityAction = preload("res://rules/abilities/moba_ability_action.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaInputScheme = preload("res://rules/input/moba_input_scheme.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## Scenario clusters are spaced this far apart so one scenario's fixtures can
## never fall inside another scenario's acquisition_range sphere query. Every
## fixture in this suite shares one physics space, so separation is what keeps
## them independent (see rules/tests/targeting_test.gd for the same pattern).
const _CLUSTER_SPACING := 500.0

const _EPSILON := 0.01


## Actor stand-in whose _ready() is a no-op.
##
## Actor._ready() dereferences character_sheet, which is statically typed to
## the game-side CharacterSheet -- naming that type from rules/ is exactly the
## outward dependency the extraction contract exists to prevent. A physics
## fixture has to be in the tree for MobaTargeting's sphere query to reach a
## physics world through it, so overriding _ready() -- deliberately without
## super() -- lets the fixture live in the tree while still being an Actor.
## Matches rules/tests/targeting_test.gd's and projectile_test.gd's own
## _TestActor.
class _TestActor:
	extends Actor

	func _ready() -> void:
		pass


static func run() -> bool:
	var all_violations: Array[String] = []

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		all_violations.append("aim_assist_activation: no SceneTree available")
		printerr("\n=== Aim Assist Activation Test Violations ===")
		for violation in all_violations:
			printerr("FAIL " + violation)
		return false

	all_violations.append_array(await _test_scheme_change_updates_multiplier_live(tree))
	all_violations.append_array(_test_hard_lock_resolves_to_locked_target(tree))
	all_violations.append_array(_test_hard_lock_falls_back_when_unset(tree))
	all_violations.append_array(_test_targeted_ability_unaffected_by_assist(tree))

	if all_violations.is_empty():
		return true

	printerr("\n=== Aim Assist Activation Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Build one physics fixture matching the shipped scene layout: Actor(Node) ->
## Body(CharacterBody3D with a CollisionShape3D child), with MobaCombatant and
## MobaStateMachine as siblings of Body -- a direct children of the Actor.
## Added straight to the tree, matching targeting_test.gd's
## _make_physics_fixture(), because Actor.global_position bridges to Body's
## Node3D.global_position, which errors when Body is outside the tree.
static func _make_physics_actor(tree: SceneTree, hostile: bool, position: Vector3) -> Actor:
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

	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)
	actor.add_child(combatant)

	var state_machine := MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	tree.root.add_child(actor)
	# global_position requires the node to be inside the tree.
	body.global_position = position
	return actor


static func _direction_approx_equal(a: Vector3, b: Vector3, tolerance: float = _EPSILON) -> bool:
	return (
		absf(a.x - b.x) < tolerance and absf(a.y - b.y) < tolerance and absf(a.z - b.z) < tolerance
	)


## A scheme change mid-session (no restart) changes which device multiplier a
## SOFT_LOCK skillshot's next activation bends by: the read has to happen live
## at activation time, not once and cached. Two activations of the same
## SOFT_LOCK ability against the same in-cone candidate, one on the default
## KEYBOARD_MOUSE scheme (0.23x) and one after switching to GAMEPAD (0.67x) via
## the same MobaInputScheme node, should bend by two different amounts -- the
## higher multiplier bending further toward the candidate.
static func _test_scheme_change_updates_multiplier_live(tree: SceneTree) -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")

	var origin := Vector3(_CLUSTER_SPACING * 0.5, 0.0, 0.0)
	var caster := _make_physics_actor(tree, true, origin)
	# Off-axis from raw_direction (1, 0, 0) by ~16.7 degrees -- inside the 45
	# degree cone below, but far enough off-axis that soft-lock bending by
	# different magnetism amounts produces distinguishably different angles.
	var candidate := _make_physics_actor(tree, false, origin + Vector3(1.0, 0.3, 0.0))

	var scheme := MobaInputScheme.new()
	scheme.name = "MobaInputScheme"
	caster.add_child(scheme)

	var ability := MobaAbility.new()
	ability.id = "assist_scheme_change_test"
	ability.targeting_type = MobaAbility.TargetingType.SKILLSHOT
	ability.aim_assist = MobaAbility.AimAssist.SOFT_LOCK
	ability.aim_cone_degrees = 45.0
	ability.magnetism = 1.0
	ability.acquisition_range = 20.0
	ability.range = 20.0
	ability.resource_cost = 0.0
	ability.cooldown = 0.0
	ability.charges = 99
	MobaAbilityLibrary._cache[StringName(ability.id)] = ability

	var combatant := caster.get_node("MobaCombatant") as MobaCombatant
	combatant.register_ability(ability)

	# Let the space observe the bodies just added.
	await tree.physics_frame

	var raw_direction := Vector3(1.0, 0.0, 0.0).normalized()

	# First activation: default scheme is KEYBOARD_MOUSE (0.23x, per
	# rules/data/aim_assist.json).
	var context_mouse := MobaCastContext.new(caster, null, raw_direction)
	var action_mouse := MobaAbilityAction.new(caster, StringName(ability.id), context_mouse)
	var result_mouse := action_mouse.execute()
	if not result_mouse.success:
		violations.append(
			"scheme_change: mouse-scheme activation should succeed, got %s" % result_mouse.reason
		)
	var mouse_angle := raw_direction.angle_to(context_mouse.aim_direction)

	# Switch to GAMEPAD (0.67x) mid-session -- no restart, same MobaInputScheme
	# node the caster already carries.
	scheme.note_event(InputEventJoypadButton.new())
	if scheme.get_scheme() != MobaInputScheme.Scheme.GAMEPAD:
		violations.append("scheme_change: scheme did not switch to GAMEPAD on a joypad event")

	var context_gamepad := MobaCastContext.new(caster, null, raw_direction)
	var action_gamepad := MobaAbilityAction.new(caster, StringName(ability.id), context_gamepad)
	var result_gamepad := action_gamepad.execute()
	if not result_gamepad.success:
		violations.append(
			(
				"scheme_change: gamepad-scheme activation should succeed, got %s"
				% result_gamepad.reason
			)
		)
	var gamepad_angle := raw_direction.angle_to(context_gamepad.aim_direction)

	# Calculate the expected angles based on the actual candidate position and magnetism.
	# The candidate is at origin + (1.0, 0.3, 0.0), and the raw direction is (1, 0, 0).
	# The angle from raw to candidate is arccos((1, 0, 0) . (1, 0.3, 0).normalized()).
	# With magnetism values of 0.23 (mouse) and 0.67 (gamepad) applied via slerp,
	# the resulting angles should be approximately the candidate angle * magnetism.
	var to_candidate := (candidate.global_position - caster.global_position).normalized()
	var candidate_angle := raw_direction.angle_to(to_candidate)
	var expected_mouse_angle := candidate_angle * 0.23  # magnetism 1.0 * mouse multiplier 0.23
	var expected_gamepad_angle := candidate_angle * 0.67  # magnetism 1.0 * gamepad multiplier 0.67

	# Assert that both angles match their expected values within tolerance, pinning that
	# the multiplier was read live at activation time (not cached).
	if absf(mouse_angle - expected_mouse_angle) > _EPSILON:
		violations.append(
			(
				"scheme_change: mouse angle should be ~%.4f (0.23 * %.4f), got %.4f"
				% [expected_mouse_angle, candidate_angle, mouse_angle]
			)
		)
	if absf(gamepad_angle - expected_gamepad_angle) > _EPSILON:
		violations.append(
			(
				"scheme_change: gamepad angle should be ~%.4f (0.67 * %.4f), got %.4f"
				% [expected_gamepad_angle, candidate_angle, gamepad_angle]
			)
		)

	caster.queue_free()
	candidate.queue_free()
	MobaAbilityLibrary._reset()
	return violations


## hard_lock resolves exactly to context.locked_target's direction (no
## magnetism blend) when it is set and valid, regardless of the raw aim
## direction or any in-cone candidate.
static func _test_hard_lock_resolves_to_locked_target(tree: SceneTree) -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")

	var origin := Vector3(_CLUSTER_SPACING * 1.0, 0.0, 0.0)
	var caster := _make_physics_actor(tree, true, origin)
	# Well off raw_direction (1, 0, 0) -- hard_lock has no cone to respect.
	var locked := _make_physics_actor(tree, false, origin + Vector3(0.0, 5.0, 5.0))

	var ability := MobaAbility.new()
	ability.id = "assist_hard_lock_test"
	ability.targeting_type = MobaAbility.TargetingType.SKILLSHOT
	ability.aim_assist = MobaAbility.AimAssist.HARD_LOCK
	ability.range = 20.0
	ability.resource_cost = 0.0
	ability.cooldown = 0.0
	ability.charges = 99
	MobaAbilityLibrary._cache[StringName(ability.id)] = ability

	var combatant := caster.get_node("MobaCombatant") as MobaCombatant
	combatant.register_ability(ability)

	var raw_direction := Vector3(1.0, 0.0, 0.0).normalized()
	var context := MobaCastContext.new(caster, null, raw_direction)
	context.locked_target = locked

	var action := MobaAbilityAction.new(caster, StringName(ability.id), context)
	var result := action.execute()
	if not result.success:
		violations.append("hard_lock: activation should succeed, got %s" % result.reason)

	var expected_direction := (locked.global_position - caster.global_position).normalized()
	if not _direction_approx_equal(context.aim_direction, expected_direction):
		violations.append(
			(
				"hard_lock: expected direction to locked_target %v, got %v"
				% [expected_direction, context.aim_direction]
			)
		)

	caster.queue_free()
	locked.queue_free()
	MobaAbilityLibrary._reset()
	return violations


## hard_lock falls back to the raw aim direction, unchanged, when
## context.locked_target is unset (the default -- lock-on acquisition is #39,
## and nothing in this task ever populates it).
static func _test_hard_lock_falls_back_when_unset(tree: SceneTree) -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")

	var origin := Vector3(_CLUSTER_SPACING * 2.0, 0.0, 0.0)
	var caster := _make_physics_actor(tree, true, origin)

	var ability := MobaAbility.new()
	ability.id = "assist_hard_lock_unset_test"
	ability.targeting_type = MobaAbility.TargetingType.SKILLSHOT
	ability.aim_assist = MobaAbility.AimAssist.HARD_LOCK
	ability.range = 20.0
	ability.resource_cost = 0.0
	ability.cooldown = 0.0
	ability.charges = 99
	MobaAbilityLibrary._cache[StringName(ability.id)] = ability

	var combatant := caster.get_node("MobaCombatant") as MobaCombatant
	combatant.register_ability(ability)

	var raw_direction := Vector3(0.0, 0.0, -1.0).normalized()
	var context := MobaCastContext.new(caster, null, raw_direction)
	# context.locked_target left at its default (null).

	var action := MobaAbilityAction.new(caster, StringName(ability.id), context)
	var result := action.execute()
	if not result.success:
		violations.append("hard_lock_unset: activation should succeed, got %s" % result.reason)

	if not _direction_approx_equal(context.aim_direction, raw_direction):
		violations.append(
			(
				"hard_lock_unset: expected raw direction %v unchanged, got %v"
				% [raw_direction, context.aim_direction]
			)
		)

	caster.queue_free()
	MobaAbilityLibrary._reset()
	return violations


## A TARGETED ability is unaffected by aim assist even when aim_assist is
## authored as SOFT_LOCK on it: assist only applies inside execute()'s
## SKILLSHOT branch, so context.aim_direction is never touched and no
## candidate query ever runs for a TARGETED activation.
static func _test_targeted_ability_unaffected_by_assist(tree: SceneTree) -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._ensure_loaded("res://rules/data/abilities/")

	var origin := Vector3(_CLUSTER_SPACING * 3.0, 0.0, 0.0)
	var caster := _make_physics_actor(tree, true, origin)
	var target := _make_physics_actor(tree, false, origin + Vector3(1.0, 0.0, 0.0))

	var ability := MobaAbility.new()
	ability.id = "assist_targeted_unaffected_test"
	ability.targeting_type = MobaAbility.TargetingType.TARGETED
	# Deliberately authored as SOFT_LOCK, to prove it is ignored for a
	# targeting type other than SKILLSHOT, not merely unset.
	ability.aim_assist = MobaAbility.AimAssist.SOFT_LOCK
	ability.aim_cone_degrees = 45.0
	ability.magnetism = 1.0
	ability.acquisition_range = 20.0
	ability.range = 20.0
	ability.resource_cost = 0.0
	ability.cooldown = 0.0
	ability.charges = 99
	MobaAbilityLibrary._cache[StringName(ability.id)] = ability

	var combatant := caster.get_node("MobaCombatant") as MobaCombatant
	combatant.register_ability(ability)

	var raw_direction := Vector3(1.0, 0.0, 0.0).normalized()
	var context := MobaCastContext.new(caster, target, raw_direction)

	var action := MobaAbilityAction.new(caster, StringName(ability.id), context)
	var result := action.execute()
	if not result.success:
		violations.append("targeted_unaffected: activation should succeed, got %s" % result.reason)

	if not _direction_approx_equal(context.aim_direction, raw_direction):
		violations.append(
			(
				"targeted_unaffected: aim_direction should be untouched for a TARGETED ability,"
				+ " expected %v, got %v" % [raw_direction, context.aim_direction]
			)
		)

	caster.queue_free()
	target.queue_free()
	MobaAbilityLibrary._reset()
	return violations
