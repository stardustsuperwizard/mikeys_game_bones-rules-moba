# Headless integration test for the left-click contextual action.
#
# Run with:
#   godot --headless --path . --script tests/mouse_action_test.gd
#
# Loads the real main scene and drives PlayerController3D through the real
# ActorBody3D/Actor/Rules pipeline -- clicks are issued by projecting a world
# point back to screen space, so the raycast, the approach, and the resulting
# Action all get exercised. Exits non-zero on the first failed expectation.
#
# It reaches into a couple of the controller's private members (issuing a
# click, seeding an unreachable order); there is no public seam for either,
# and inventing one just for the test would be more machinery than the
# coverage is worth.
extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	var player := scene.get_node_or_null("WorldManager/Player") as Actor
	var camera := scene.get_node_or_null("ThirdPersonCamera") as Camera3D
	if player == null or camera == null:
		_fail("setup: player=%s camera=%s" % [player, camera])
		return _finish()

	var controller := player.controller as PlayerController3D
	var body := player.get_node("Body") as CharacterBody3D
	if controller == null:
		_fail("setup: controller is not PlayerController3D")
		return _finish()

	# --- click the ground -> walk there and settle ---------------------
	var goal := Vector3(2, 0, 2)
	await _click_world_point(controller, camera, goal + Vector3(0, 0.01, 0))
	var arrived := await _wait_until(
		func() -> bool:
			return _flat_distance(body.global_position, goal) <= controller.arrival_distance,
		240
	)
	for i in 40:
		await physics_frame
	var settled := _flat_distance(body.global_position, goal)
	if not arrived or settled > controller.arrival_distance + 0.15:
		_fail(
			(
				"ground click: player settled %.2fm from %v (arrival_distance %.2f)"
				% [settled, goal, controller.arrival_distance]
			)
		)
	else:
		print(
			(
				"PASS ground click -> walked to %v and stopped (%.2fm off)"
				% [body.global_position, settled]
			)
		)

	# --- click behind the player -> body turns to face the walk --------
	var behind := Vector3(-4, 0, 6)
	await _click_world_point(controller, camera, behind + Vector3(0, 0.01, 0))
	var faced := await _wait_until(
		func() -> bool:
			var to_goal := behind - body.global_position
			var want := atan2(-to_goal.x, -to_goal.z)
			return absf(rad_to_deg(wrapf(want - body.global_rotation.y, -PI, PI))) <= 15.0,
		180
	)
	if not faced:
		_fail(
			(
				"turn toward order: yaw %.1f deg never lined up with the goal"
				% rad_to_deg(body.global_rotation.y)
			)
		)
	else:
		print("PASS click behind -> body turned to face the destination")
	await _wait_until(
		func() -> bool: return _flat_distance(body.global_position, behind) <= 0.5, 240
	)

	# --- click a wall -> walk up to it and stop flush ------------------
	# The north wall's inner face is at z = -9.9. Clicking high up the wall
	# should still walk to its base, settle with the 0.4-radius capsule
	# touching it, and drop the order on contact rather than grinding into
	# the wall until the stall guard eventually gives up.
	const WALL_FACE_Z := -9.9
	const BODY_RADIUS := 0.4
	await _click_world_point(controller, camera, Vector3(1, 3, WALL_FACE_Z))
	var touched := await _wait_until(func() -> bool: return body.is_on_wall(), 600)
	var frames_to_stop := 0
	while controller._has_destination and frames_to_stop < 120:
		frames_to_stop += 1
		await physics_frame
	var wall_resting := body.global_position
	for i in 60:
		await physics_frame

	var gap := body.global_position.z - WALL_FACE_Z
	if not touched:
		_fail("wall click: player never reached the wall (at %v)" % body.global_position)
	elif absf(gap - BODY_RADIUS) > 0.05:
		_fail(
			(
				"wall click: player settled %.2fm from the wall face, wanted flush at %.2f"
				% [gap, BODY_RADIUS]
			)
		)
	elif frames_to_stop > 5:
		_fail(
			(
				"wall click: order held for %d frames after contact -- stopped by the stall guard, not by the wall"
				% frames_to_stop
			)
		)
	elif _flat_distance(wall_resting, body.global_position) > 0.02:
		_fail(
			(
				"wall click: player kept moving after the order cleared (%v -> %v)"
				% [wall_resting, body.global_position]
			)
		)
	else:
		print(
			(
				"PASS wall click -> walked to the wall, stopped flush (%.2fm from face) %d frames after contact"
				% [gap, frames_to_stop]
			)
		)

	# --- click along a wall you are already against -> slide, don't stall
	# Standing flush on the north wall, clicking it far to the west is a
	# glancing contact, not a blocked one: the player should slide along the
	# wall rather than read the wall it is already touching as "arrived".
	# The contact turns head-on again over the last stride, so the walk ends
	# within roughly a body-width of the clicked spot rather than exactly on
	# it -- close enough for an order that just means "over there by the wall".
	var slide_start := body.global_position
	var slide_goal_x := -6.0
	await _click_world_point(controller, camera, Vector3(slide_goal_x, 3, WALL_FACE_Z))
	var slid := await _wait_until(func() -> bool: return not controller._has_destination, 600)
	var slide_miss := absf(body.global_position.x - slide_goal_x)
	if not slid or slide_miss > 0.8:
		_fail(
			(
				"wall slide: player stopped at x=%.2f (from x=%.2f), wanted within 0.8m of x=%.1f"
				% [body.global_position.x, slide_start.x, slide_goal_x]
			)
		)
	elif absf(body.global_position.z - (WALL_FACE_Z + BODY_RADIUS)) > 0.05:
		_fail("wall slide: player came off the wall, z=%.2f" % body.global_position.z)
	else:
		print(
			(
				"PASS click along the touched wall -> slid to %.2fm of the spot, still flush"
				% slide_miss
			)
		)

	# --- click a hostile actor -> approach and attack ------------------
	var dummy := _make_dummy(scene, Vector3(2, 0, -3))
	await physics_frame
	await _click_world_point(controller, camera, dummy.global_position + Vector3(0, 1, 0))
	var hurt := await _wait_until(
		func() -> bool:
			return (
				not is_instance_valid(dummy)
				or dummy.character_sheet.current_hp < dummy.character_sheet.max_hp
			),
		360
	)
	if not hurt:
		_fail(
			(
				"attack click: dummy never took damage (player at %v, dummy at %v)"
				% [body.global_position, dummy.global_position]
			)
		)
	else:
		print("PASS attack click -> closed to melee and dealt damage")

	# --- click a door -> approach and open -----------------------------
	var door := _make_door(scene, Vector3(-2, 1, 2))
	await physics_frame
	await _click_world_point(controller, camera, door.global_position)
	var opened := await _wait_until(func() -> bool: return door.is_open(), 360)
	if not opened:
		_fail(
			(
				"door click: door never opened (player at %v, door at %v)"
				% [body.global_position, door.global_position]
			)
		)
	else:
		print("PASS door click -> closed and opened the door")

	# --- keyboard movement cancels a live click order ------------------
	await _click_world_point(controller, camera, Vector3(6, 0.01, 6))
	await physics_frame
	Input.action_press("move_forward")
	for i in 20:
		await physics_frame
	Input.action_release("move_forward")
	var resting := body.global_position
	for i in 40:
		await physics_frame
	if _flat_distance(resting, body.global_position) > 0.3:
		_fail("keyboard cancel: player resumed walking to the click order after WASD input")
	else:
		print("PASS keyboard input cancels the click order")

	# --- unreachable order gives up instead of shoving forever ---------
	controller.cancel_order()
	controller._destination = Vector3(body.global_position.x, 0, -40)  # through the north wall
	controller._has_destination = true
	var gave_up := await _wait_until(func() -> bool: return not controller._has_destination, 600)
	if not gave_up:
		_fail("stall guard: player never abandoned an unreachable order")
	else:
		print("PASS unreachable order abandoned by the stall guard")

	_finish()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _click_world_point(
	controller: PlayerController3D, camera: Camera3D, world_point: Vector3
) -> void:
	await physics_frame
	controller._issue_order_from_click(camera.unproject_position(world_point))


func _wait_until(predicate: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if predicate.call():
			return true
		await physics_frame
	return predicate.call()


func _make_dummy(parent: Node, position: Vector3) -> Actor:
	var dummy := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Actor
	dummy.name = "Dummy"
	dummy.hostile = true
	dummy.get_node("Controller").free()  # inert target: no controller, no decisions
	(dummy.get_node("Body") as Node3D).position = position
	parent.add_child(dummy)
	return dummy


func _make_door(parent: Node, position: Vector3) -> Door:
	var door := Door.new()
	door.name = "TestDoor"
	door.set_script(load("res://addons/mikeys_game_bones/things/props/door.gd"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2, 0.3)
	shape.shape = box
	door.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1, 2, 0.3)
	mesh.mesh = box_mesh
	door.add_child(mesh)
	parent.add_child(door)
	door.global_position = position
	return door


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nALL MOUSE ACTION CHECKS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL " + f)
		quit(1)
