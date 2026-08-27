# Headless integration test for issue #240's camera criterion.
#
# Run with:
#   godot --headless --path . --script tests/death_respawn_camera_test.gd
#
# Loads the real main scene, kills the real player through MobaCombatant, and
# respawns it, then confirms ThirdPersonCamera3D's `_target` is still the same
# valid Body node throughout. Nothing in this test drives the camera to
# "reacquire" anything -- per #240's architecture constraints, no camera code
# changed, so there is nothing to reacquire; this only proves the Actor/Body
# node the camera resolved once in _ready() survives the whole death/respawn
# cycle instead of being freed and replaced.
extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var refs := await _setup()
	if refs.is_empty():
		return _finish()

	if not await _verify_death(refs):
		return _finish()

	if not await _verify_respawn(refs):
		return _finish()

	_finish()


## Loads the main scene, neutralizes the enemy, and resolves the player/camera
## references the rest of the test needs. Returns an empty Dictionary (and
## records a failure) if any expected node is missing.
func _setup() -> Dictionary:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	# Neutralize the spawned enemy so it doesn't interfere with the player's
	# scripted death below.
	var enemy := scene.get_node_or_null("WorldManager/Enemy")
	if enemy != null:
		enemy.queue_free()
	await physics_frame

	var player := scene.get_node_or_null("WorldManager/Player") as Actor
	var camera := scene.get_node_or_null("ThirdPersonCamera") as ThirdPersonCamera3D
	if player == null or camera == null:
		_fail("setup: player=%s camera=%s" % [player, camera])
		return {}

	var body := player.get_node_or_null("Body") as Node3D
	var combatant := player.get_node_or_null("MobaCombatant") as MobaCombatant
	var state_machine := player.get_node_or_null("MobaStateMachine") as MobaStateMachine
	if body == null or combatant == null or state_machine == null:
		_fail("setup: body=%s combatant=%s state_machine=%s" % [body, combatant, state_machine])
		return {}

	if camera._target != body:
		_fail("setup: camera did not resolve target_path to the player's Body")
		return {}

	return {
		"player": player,
		"camera": camera,
		"body": body,
		"combatant": combatant,
		"state_machine": state_machine,
	}


## Kills the player through the real damage pipeline and confirms the Actor/
## Body node survives and the camera keeps its target reference across death.
func _verify_death(refs: Dictionary) -> bool:
	var player := refs["player"] as Actor
	var camera := refs["camera"] as ThirdPersonCamera3D
	var body := refs["body"] as Node3D
	var combatant := refs["combatant"] as MobaCombatant
	var state_machine := refs["state_machine"] as MobaStateMachine

	var lethal := MobaDamage.new(
		999999.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(lethal)
	await physics_frame

	if state_machine.current_state != MobaState.DEAD:
		_fail("death: expected state DEAD, got %d" % state_machine.current_state)
		return false

	if not is_instance_valid(body) or not is_instance_valid(player):
		_fail("death: Actor/Body node was freed on death")
		return false

	if camera._target != body:
		_fail("death: camera lost its target reference across death")
		return false

	print("PASS death -> Actor/Body stays in the tree, camera target unchanged")
	return true


## Waits out the configured auto-respawn delay and confirms the Actor/Body
## node survives and the camera keeps tracking and framing it across respawn.
func _verify_respawn(refs: Dictionary) -> bool:
	var player := refs["player"] as Actor
	var camera := refs["camera"] as ThirdPersonCamera3D
	var body := refs["body"] as Node3D
	var state_machine := refs["state_machine"] as MobaStateMachine

	var respawned := await _wait_until(
		func() -> bool: return state_machine.current_state == MobaState.IDLE, 600
	)

	if not respawned:
		_fail("respawn: player never returned to IDLE within the wait window")
		return false

	if not is_instance_valid(body) or not is_instance_valid(player):
		_fail("respawn: Actor/Body node was freed on respawn")
		return false

	if camera._target != body:
		_fail("respawn: camera lost its target reference across respawn")
		return false

	# Confirm the camera is still actively tracking (not just holding a stale
	# but coincidentally-valid pointer): its pivot should track the body's
	# post-respawn position on the very next frame.
	await physics_frame
	var pivot := camera._target.global_position + Vector3(0, camera.target_height_offset, 0)
	var camera_to_pivot := (pivot - camera.global_position).length()
	if camera_to_pivot > camera.max_distance + 1.0:
		_fail(
			"respawn: camera is not framing the respawned target (distance=%.2f)" % camera_to_pivot
		)
		return false

	print("PASS respawn -> camera target survives and keeps framing the player")
	return true


func _wait_until(predicate: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if predicate.call():
			return true
		await physics_frame
	return predicate.call()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nALL DEATH/RESPAWN CAMERA CHECKS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL " + f)
		quit(1)
