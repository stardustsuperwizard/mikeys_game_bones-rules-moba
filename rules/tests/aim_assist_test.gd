## Test suite for MobaAimAssist.
##
## Covers cone/nearest selection, slerp-based direction resolution,
## effective magnetism with clamping, device multiplier loading,
## and the pure locked-target function.
class_name AimAssistTest


## Helper to compare floats with tolerance.
static func _approx_equal(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return abs(a - b) < tolerance


## Build a Node3D fixture inside the scene tree at the given position.
##
## Node3D.global_position (and get_global_transform()) fails on a node
## outside the scene tree -- see rules/tests/targeting_test.gd's
## _make_physics_fixture() for the same requirement. Position is set only
## after the node is parented, matching that established pattern.
static func _make_target(tree: SceneTree, position: Vector3) -> Node3D:
	var target := Node3D.new()
	tree.root.add_child(target)
	target.global_position = position
	return target


## Run the aim assist test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		all_violations.append("aim_assist: no SceneTree available")
		printerr("\n=== Aim Assist Test Violations ===")
		for violation in all_violations:
			printerr("FAIL " + violation)
		return false

	# Test 1: No candidate in range returns raw aim direction
	all_violations.append_array(_test_no_candidate_in_range())

	# Test 2: Candidate outside cone ignored even if metrically closest
	all_violations.append_array(_test_outside_cone_ignored(tree))

	# Test 3: Nearest-in-cone picks smallest angular deviation
	all_violations.append_array(_test_nearest_in_cone_angular_selection(tree))

	# Test 4: Magnetism 0.0 returns raw direction
	all_violations.append_array(_test_magnetism_zero_returns_raw_direction(tree))

	# Test 5: Magnetism 1.0 returns exact direction to target
	all_violations.append_array(_test_magnetism_one_returns_exact_direction(tree))

	# Test 6: Magnetism 0.5 returns angular halfway via slerp
	all_violations.append_array(_test_magnetism_half_returns_angular_halfway(tree))

	# Test 7: Device multiplier loading
	all_violations.append_array(_test_device_multiplier_loading())

	# Test 8: Clamp in effective_magnetism
	all_violations.append_array(_test_effective_magnetism_clamp())

	# Test 9: Free aim (0.0) × every device multiplier = 0.0
	all_violations.append_array(_test_free_aim_unaffected_by_device_multiplier())

	# Test 10: Every value in aim_assist.json is ≤ 1.0
	all_violations.append_array(_test_all_device_multipliers_within_bounds())

	# Test 11: Locked-target resolution function
	all_violations.append_array(_test_locked_target_resolution())

	if all_violations.is_empty():
		return true

	# Print violations
	printerr("\n=== Aim Assist Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Test 1: No candidate in range returns raw aim direction unchanged.
static func _test_no_candidate_in_range() -> Array[String]:
	var violations: Array[String] = []

	var raw_aim := Vector3(1.0, 0.0, 0.0).normalized()
	var caster_pos := Vector3(0.0, 0.0, 0.0)
	var candidates: Array[Node] = []
	var cone_angle := 45.0

	var result := MobaAimAssist.select_nearest_in_cone(raw_aim, caster_pos, candidates, cone_angle)

	if result != null:
		violations.append("No candidates: expected null, got %s" % result)

	return violations


## Test 2: Candidate outside cone ignored even if metrically closest.
static func _test_outside_cone_ignored(tree: SceneTree) -> Array[String]:
	var violations: Array[String] = []

	var raw_aim := Vector3(1.0, 0.0, 0.0).normalized()
	var caster_pos := Vector3(0.0, 0.0, 0.0)
	var cone_angle := 30.0  # 30 degree cone

	# A candidate outside the cone (~45 degrees, outside the 30-degree cone).
	var outside_target := _make_target(tree, Vector3(1.0, 1.0, 0.0))

	var candidates: Array[Node] = [outside_target]

	var result := MobaAimAssist.select_nearest_in_cone(raw_aim, caster_pos, candidates, cone_angle)

	if result != null:
		violations.append("Outside cone: expected null, got %s" % result)

	outside_target.queue_free()

	return violations


## Test 3: Nearest-in-cone picks smallest angular deviation.
## Uses two candidates where metrically-closer has larger angle,
## metrically-farther has smaller angle; should pick the farther one.
static func _test_nearest_in_cone_angular_selection(tree: SceneTree) -> Array[String]:
	var violations: Array[String] = []

	var raw_aim := Vector3(1.0, 0.0, 0.0).normalized()
	var caster_pos := Vector3(0.0, 0.0, 0.0)
	var cone_angle := 45.0

	# Candidate 1: Close but off-axis (larger angle)
	var close_target := _make_target(tree, Vector3(1.0, 0.5, 0.0))  # Close, but ~26.5 degrees off

	# Candidate 2: Far but more aligned (smaller angle)
	var far_target := _make_target(tree, Vector3(2.0, 0.1, 0.0))  # Far, but ~2.9 degrees off

	var candidates: Array[Node] = [close_target, far_target]

	var result := MobaAimAssist.select_nearest_in_cone(raw_aim, caster_pos, candidates, cone_angle)

	if result != far_target:
		violations.append("Nearest-in-cone: expected far_target (better angle), got %s" % result)

	close_target.queue_free()
	far_target.queue_free()

	return violations


## Test 4: Magnetism 0.0 returns raw direction unchanged.
static func _test_magnetism_zero_returns_raw_direction(tree: SceneTree) -> Array[String]:
	var violations: Array[String] = []

	var raw_aim := Vector3(1.0, 0.0, 0.0).normalized()
	var target := _make_target(tree, Vector3(0.0, 1.0, 0.0))

	var caster_pos := Vector3(0.0, 0.0, 0.0)
	var magnetism := 0.0

	var result := MobaAimAssist.resolve_direction(raw_aim, target, caster_pos, magnetism)

	if (
		not _approx_equal(result.x, raw_aim.x)
		or not _approx_equal(result.y, raw_aim.y)
		or not _approx_equal(result.z, raw_aim.z)
	):
		violations.append("Magnetism 0.0: expected raw direction %v, got %v" % [raw_aim, result])

	target.queue_free()

	return violations


## Test 5: Magnetism 1.0 returns exact direction to target.
static func _test_magnetism_one_returns_exact_direction(tree: SceneTree) -> Array[String]:
	var violations: Array[String] = []

	var raw_aim := Vector3(1.0, 0.0, 0.0).normalized()
	var target := _make_target(tree, Vector3(0.0, 1.0, 0.0))

	var caster_pos := Vector3(0.0, 0.0, 0.0)
	var to_target := (target.global_position - caster_pos).normalized()
	var magnetism := 1.0

	var result := MobaAimAssist.resolve_direction(raw_aim, target, caster_pos, magnetism)

	if (
		not _approx_equal(result.x, to_target.x)
		or not _approx_equal(result.y, to_target.y)
		or not _approx_equal(result.z, to_target.z)
	):
		violations.append(
			"Magnetism 1.0: expected target direction %v, got %v" % [to_target, result]
		)

	target.queue_free()

	return violations


## Test 6: Magnetism 0.5 returns angular halfway direction via slerp.
static func _test_magnetism_half_returns_angular_halfway(tree: SceneTree) -> Array[String]:
	var violations: Array[String] = []

	var raw_aim := Vector3(1.0, 0.0, 0.0).normalized()
	var target := _make_target(tree, Vector3(0.0, 1.0, 0.0))

	var caster_pos := Vector3(0.0, 0.0, 0.0)
	var to_target := (target.global_position - caster_pos).normalized()
	var magnetism := 0.5

	var result := MobaAimAssist.resolve_direction(raw_aim, target, caster_pos, magnetism)

	# Check via angle: the angle from raw_aim to result should be
	# approximately half the angle from raw_aim to to_target
	var total_angle := raw_aim.angle_to(to_target)
	var result_angle := raw_aim.angle_to(result)
	var expected_angle := total_angle * 0.5

	if not _approx_equal(result_angle, expected_angle, 0.01):
		violations.append(
			(
				"Magnetism 0.5: angle mismatch. total_angle=%f, result_angle=%f, expected=%f"
				% [total_angle, result_angle, expected_angle]
			)
		)

	target.queue_free()

	return violations


## Test 7: Device multiplier loading.
static func _test_device_multiplier_loading() -> Array[String]:
	var violations: Array[String] = []

	# Reset to ensure fresh load
	MobaAimAssist.reset_for_testing()

	var mouse_mult := MobaAimAssist.get_device_multiplier("mouse")
	var gamepad_mult := MobaAimAssist.get_device_multiplier("gamepad")
	var touch_mult := MobaAimAssist.get_device_multiplier("touch")

	if not _approx_equal(mouse_mult, 0.23, 0.001):
		violations.append("Device multiplier: mouse expected 0.23, got %f" % mouse_mult)

	if not _approx_equal(gamepad_mult, 0.67, 0.001):
		violations.append("Device multiplier: gamepad expected 0.67, got %f" % gamepad_mult)

	if not _approx_equal(touch_mult, 1.0, 0.001):
		violations.append("Device multiplier: touch expected 1.0, got %f" % touch_mult)

	return violations


## Test 8: Clamp in effective_magnetism.
## Feed values that would exceed 1.0 and verify clamping.
static func _test_effective_magnetism_clamp() -> Array[String]:
	var violations: Array[String] = []

	# Test case 1: ability_magnetism=1.0, device_multiplier=1.5 → should clamp to 1.0
	var result1 := MobaAimAssist.effective_magnetism(1.0, 1.5)
	if not _approx_equal(result1, 1.0):
		violations.append("Clamp test 1: expected 1.0, got %f" % result1)

	# Test case 2: ability_magnetism=0.8, device_multiplier=2.0 → should clamp to 1.0
	var result2 := MobaAimAssist.effective_magnetism(0.8, 2.0)
	if not _approx_equal(result2, 1.0):
		violations.append("Clamp test 2: expected 1.0, got %f" % result2)

	# Test case 3: ability_magnetism=0.5, device_multiplier=3.0 → should clamp to 1.0.
	# (0.5 * 1.5 = 0.75 does not exceed 1.0 and does not exercise the clamp --
	# the multiplier here is deliberately higher than any real aim_assist.json
	# value so this case actually clamps rather than duplicating test case 4.)
	var result3 := MobaAimAssist.effective_magnetism(0.5, 3.0)
	if not _approx_equal(result3, 1.0):
		violations.append("Clamp test 3: expected 1.0, got %f" % result3)

	# Test case 4: ability_magnetism=0.5, device_multiplier=1.0 → should be 0.5 (no clamp)
	var result4 := MobaAimAssist.effective_magnetism(0.5, 1.0)
	if not _approx_equal(result4, 0.5):
		violations.append("Clamp test 4: expected 0.5, got %f" % result4)

	return violations


## Test 9: Free aim (magnetism 0.0) × every device multiplier = 0.0.
static func _test_free_aim_unaffected_by_device_multiplier() -> Array[String]:
	var violations: Array[String] = []

	# Reset to ensure fresh load
	MobaAimAssist.reset_for_testing()

	var devices := ["mouse", "gamepad", "touch"]
	for device in devices:
		var multiplier := MobaAimAssist.get_device_multiplier(device)
		var result := MobaAimAssist.effective_magnetism(0.0, multiplier)
		if not _approx_equal(result, 0.0):
			violations.append(
				(
					"Free aim: %s multiplier %.2f should yield 0.0, got %f"
					% [device, multiplier, result]
				)
			)

	return violations


## Test 10: Every value in aim_assist.json is ≤ 1.0.
static func _test_all_device_multipliers_within_bounds() -> Array[String]:
	var violations: Array[String] = []

	# Reset to ensure fresh load
	MobaAimAssist.reset_for_testing()

	var devices := ["mouse", "gamepad", "touch"]
	for device in devices:
		var multiplier := MobaAimAssist.get_device_multiplier(device)
		if multiplier > 1.0:
			violations.append("Bounds check: %s multiplier %.2f exceeds 1.0" % [device, multiplier])

	return violations


## Test 11: Locked-target resolution function.
static func _test_locked_target_resolution() -> Array[String]:
	var violations: Array[String] = []

	var raw_aim := Vector3(1.0, 0.0, 0.0).normalized()

	# Test case 1: Given a direction, returns it verbatim
	var locked_direction := Vector3(0.0, 1.0, 0.0).normalized()
	var result1 := MobaAimAssist.resolve_locked_target(locked_direction, raw_aim)
	if (
		not _approx_equal(result1.x, locked_direction.x)
		or not _approx_equal(result1.y, locked_direction.y)
		or not _approx_equal(result1.z, locked_direction.z)
	):
		violations.append(
			"Locked target: given direction, expected %v, got %v" % [locked_direction, result1]
		)

	# Test case 2: Given null, returns raw aim direction
	var result2 := MobaAimAssist.resolve_locked_target(null, raw_aim)
	if (
		not _approx_equal(result2.x, raw_aim.x)
		or not _approx_equal(result2.y, raw_aim.y)
		or not _approx_equal(result2.z, raw_aim.z)
	):
		violations.append(
			"Locked target: given null, expected raw aim %v, got %v" % [raw_aim, result2]
		)

	return violations
