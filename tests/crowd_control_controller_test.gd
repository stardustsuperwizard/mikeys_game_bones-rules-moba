# Headless integration test for crowd control gating of Controller intent.
#
# Run with:
#   godot --headless --path . --script tests/crowd_control_controller_test.gd
#
# Loads the real main scene and drives PlayerController3D through the real
# ActorBody3D/Actor/MobaCombatant pipeline, testing that crowd control effects
# properly gate movement and attack intent at the Controller seam. Exits non-zero
# on the first failed expectation.
#
# This test is NOT wired into tests/test_bootstrap.gd; it is a manual integration
# check matching tests/mouse_action_test.gd's own precedent.
extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	# Neutralize the spawned enemy so it doesn't kill the player during test scenarios
	var enemy := scene.get_node_or_null("WorldManager/Enemy")
	if enemy != null:
		enemy.queue_free()
	await physics_frame

	var player := scene.get_node_or_null("WorldManager/Player") as Actor
	if player == null:
		_fail("setup: player not found")
		return _finish()

	var controller := player.controller as PlayerController3D
	var combatant := player.get_node_or_null("MobaCombatant") as MobaCombatant
	var body := player.get_node("Body") as CharacterBody3D
	if controller == null or combatant == null or body == null:
		_fail("setup: controller=%s combatant=%s body=%s" % [controller, combatant, body])
		return _finish()

	if not await _run_stun_scenarios(controller, combatant, body, player):
		return _finish()

	_finish()


# Test: a stunned player's held movement input produces no movement.
# Test: once the stun expires, the same held input produces movement again.
func _run_stun_scenarios(
	controller: PlayerController3D,
	combatant: MobaCombatant,
	body: CharacterBody3D,
	player: Actor
) -> bool:
	# --- stunned player with held movement input produces Vector3.ZERO ----
	if _actors_lost("stun movement gate", [body, controller, combatant]):
		return false

	# Apply a short stun effect to the player
	var stun_spec := MobaCrowdControlSpec.new()
	stun_spec.type = MobaCrowdControlSpec.CCType.STUN
	stun_spec.duration = 0.5  # 500ms stun
	stun_spec.affected_by_tenacity = false  # Don't scale by stats for simplicity

	# Hold move_forward
	Input.action_press("move_forward")
	await physics_frame

	# Initial state: should have movement
	var initial_move := controller.get_move_direction()
	if initial_move == Vector3.ZERO:
		_fail("stun movement: held move_forward produced no movement before stun")
		Input.action_release("move_forward")
		return false

	print("Initial held movement: %v" % initial_move)

	# Apply stun to the combatant (self-applied for simplicity)
	combatant.apply_crowd_control(stun_spec, combatant)
	await physics_frame

	# Verify: movement should be blocked while stunned
	var stunned_move := controller.get_move_direction()
	if stunned_move != Vector3.ZERO:
		_fail(
			"stun movement: held move_forward produced movement while stunned: %v" % stunned_move
		)
		Input.action_release("move_forward")
		return false

	print("PASS stunned movement blocked: get_move_direction() == Vector3.ZERO")

	# Wait for stun to expire (0.5s + a frame of buffer)
	for i in 50:
		await physics_frame
		if not combatant.has_crowd_control(MobaCrowdControlSpec.CCType.STUN):
			break

	# Verify: movement should resume once stun expires
	var resumed_move := controller.get_move_direction()
	if resumed_move == Vector3.ZERO:
		_fail(
			"stun movement: held move_forward produced no movement after stun expired"
		)
		Input.action_release("move_forward")
		return false

	print("PASS stun expiration resumes movement: get_move_direction() != Vector3.ZERO")

	Input.action_release("move_forward")
	return true


# Stops the run when an actor a scenario needs has been freed.
func _actors_lost(scenario: String, nodes: Array) -> bool:
	for node in nodes:
		if not is_instance_valid(node):
			_fail("%s: an actor this scenario needs was freed mid-run" % scenario)
			return true
	return false


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nALL CROWD CONTROL CONTROLLER CHECKS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL " + f)
		quit(1)
