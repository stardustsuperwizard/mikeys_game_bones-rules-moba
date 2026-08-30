# Headless integration test for TargetFrameBinder's wiring in scenes/main.tscn.
#
# Run with:
#   godot --headless --path . --script tests/target_frame_binder_test.gd
#
# Loads the real main scene and checks that the binder's two NodePath exports
# actually resolve against the spawned tree, then drives the controller's
# placeholder target and checks what the frame shows. Exits non-zero on the
# first failed expectation.
#
# This exists because the unit suite cannot see the failure it catches. Every
# case in rules/tests/target_frame_test.gd binds the frame by hand, so a
# controller_path naming a node that does not exist passes all of them and
# still ships a frame that never appears: the binder simply exhausts its retry
# budget and stops, silently. The path is data in a .tscn, and only the real
# scene can say whether it points at anything.
#
# It sets the controller's private _attack_target directly rather than clicking.
# The click path is already covered by tests/mouse_action_test.gd; what is under
# test here is the wiring between a target existing and the frame showing it.
#
# This test is NOT wired into tests/test_bootstrap.gd; it is a manual
# integration check matching tests/floating_text_binder_test.gd's,
# tests/crowd_control_controller_test.gd's and tests/mouse_action_test.gd's own
# precedent. The frame's own behaviour is unit-tested in
# rules/tests/target_frame_test.gd, which does run under the bootstrap.
extends SceneTree

## Frames allowed for a bind to land. The binder polls in _process, so one frame
## is enough; the margin absorbs spawn ordering.
const SETTLE_FRAMES := 5

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	var frame := scene.get_node_or_null("MobaTargetFrame") as MobaTargetFrame
	var binder := scene.get_node_or_null("TargetFrameBinder") as TargetFrameBinder
	if frame == null:
		_fail("setup: scenes/main.tscn has no MobaTargetFrame")
	if binder == null:
		_fail("setup: scenes/main.tscn has no TargetFrameBinder")
	if not _failures.is_empty():
		return _finish()

	# The exports must resolve against the spawned tree, not just parse.
	var frame_target := binder.get_node_or_null(binder.target_frame_path)
	if frame_target != frame:
		_fail(
			(
				"wiring: target_frame_path %s does not resolve to the MobaTargetFrame"
				% binder.target_frame_path
			)
		)
	var controller := binder.get_node_or_null(binder.controller_path) as PlayerController3D
	if controller == null:
		_fail(
			(
				"wiring: controller_path %s does not resolve to a PlayerController3D"
				% binder.controller_path
			)
		)
	if not _failures.is_empty():
		return _finish()

	var enemy := scene.get_node_or_null("WorldManager/Enemy") as Actor
	if enemy == null:
		_fail("setup: no enemy actor spawned")
		return _finish()
	var enemy_combatant := enemy.get_node_or_null("MobaCombatant") as MobaCombatant
	if enemy_combatant == null:
		_fail("setup: the enemy actor has no MobaCombatant")
		return _finish()

	if frame.visible:
		_fail("no target: the frame should start hidden")

	# --- a target appears ---
	controller._attack_target = enemy
	await _settle()

	if not frame.visible:
		_fail("target acquired: the frame should be visible within the polling cadence")
	if frame.get_combatant() != enemy_combatant:
		_fail("target acquired: the frame should be bound to the enemy's combatant")

	# --- the target is dropped ---
	controller._attack_target = null
	await _settle()

	if frame.visible:
		_fail("target lost: the frame should hide once the target is gone")
	if frame.get_combatant() != null:
		_fail("target lost: the frame should drop its binding")

	# --- the target dies while bound ---
	controller._attack_target = enemy
	await _settle()
	if not frame.visible:
		_fail("rebind: the frame should show the target again")

	enemy_combatant.apply_damage(MobaDamage.new(99999.0, MobaDamage.DamageType.TRUE, null, false))
	await _settle()

	if frame.visible:
		_fail("target died: the frame should hide when the bound target dies")

	_finish()


func _settle() -> void:
	for _i in range(SETTLE_FRAMES):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Target Frame Binder Test PASSED")
		quit(0)
		return

	printerr("\n=== Target Frame Binder Test Violations ===")
	for failure in _failures:
		printerr("FAIL " + failure)
	quit(1)
