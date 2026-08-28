## Test suite for the pooled MobaFloatingText system.
##
## Covers that the pool pre-allocates labels at startup and recycles them, that
## requests beyond max_concurrent are silently dropped rather than queued or
## force-evicting an active number, that damage types and events are visually
## distinguishable, and that multiple simultaneous hits produce visible
## non-overlapping numbers.
##
## The pool is exercised without ever entering the scene tree, so there is no
## viewport and no Camera3D to project through and every number lands at the
## screen origin plus its own offset. That is deliberate: these cases are about
## the pool's capping and recycling rules, not about projection.
##
## The cross-combatant wiring around the pool -- one number per basic attack, a
## fully absorbed hit, and a freed combatant leaving no watch behind -- belongs
## to scripts/floating_text_binder.gd, which rules/ may not reference. Those
## cases live in tests/floating_text_binder_test.gd on the game side.
class_name FloatingTextTest

const FLOATING_TEXT_SCENE = preload("res://rules/ui/moba_floating_text.tscn")
const MobaDamage = preload("res://rules/core/moba_damage.gd")


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_pool_pre_allocates_labels())
	all_violations.append_array(_test_pool_never_instantiates_at_spawn_time())
	all_violations.append_array(_test_requests_beyond_max_concurrent_are_dropped())
	all_violations.append_array(_test_damage_types_are_visually_distinct())
	all_violations.append_array(_test_crit_is_visually_distinct())
	all_violations.append_array(_test_healing_is_visually_distinct())
	all_violations.append_array(_test_shield_absorption_is_visually_distinct())
	all_violations.append_array(_test_multiple_spawns_produce_offset_numbers())

	if all_violations.is_empty():
		return true

	printerr("\n=== Floating Text Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Test that the pool pre-allocates exactly max_concurrent labels at startup.
static func _test_pool_pre_allocates_labels() -> Array[String]:
	var violations: Array[String] = []

	var pool: MobaFloatingText = FLOATING_TEXT_SCENE.instantiate()
	pool.max_concurrent = 10

	# Check the pool is ready
	pool._ready()

	# Count child labels
	var label_count := 0
	for child in pool.get_children():
		if child is Label:
			label_count += 1

	if label_count != 10:
		violations.append("pool_allocation: expected 10 pre-allocated labels, got %d" % label_count)

	pool.free()
	return violations


## Test that spawning does not create new Label nodes, only reuses existing ones.
static func _test_pool_never_instantiates_at_spawn_time() -> Array[String]:
	var violations: Array[String] = []

	var pool: MobaFloatingText = FLOATING_TEXT_SCENE.instantiate()
	pool.max_concurrent = 5
	pool._ready()

	# Count initial child nodes
	var initial_child_count := pool.get_child_count()

	# Spawn more than max_concurrent damage numbers
	for i in range(10):
		pool.spawn_damage(Vector3(0, 0, 0), 10.0 + i, MobaDamage.DamageType.PHYSICAL, false)

	# Check that no new nodes were created
	var final_child_count := pool.get_child_count()
	if final_child_count != initial_child_count:
		violations.append(
			(
				"instantiation: spawn() should not create new nodes. started with %d, ended with %d"
				% [initial_child_count, final_child_count]
			)
		)

	pool.free()
	return violations


## Test that requests beyond max_concurrent are silently dropped.
static func _test_requests_beyond_max_concurrent_are_dropped() -> Array[String]:
	var violations: Array[String] = []

	var pool: MobaFloatingText = FLOATING_TEXT_SCENE.instantiate()
	pool.max_concurrent = 3
	pool._ready()

	# Spawn exactly max_concurrent numbers
	pool.spawn_damage(Vector3(0, 0, 0), 10.0, MobaDamage.DamageType.PHYSICAL, false)
	pool.spawn_damage(Vector3(1, 0, 0), 11.0, MobaDamage.DamageType.PHYSICAL, false)
	pool.spawn_damage(Vector3(2, 0, 0), 12.0, MobaDamage.DamageType.PHYSICAL, false)

	if pool.get_active_count() != 3:
		violations.append(
			"max_concurrent: should have 3 active numbers, got %d" % pool.get_active_count()
		)

	# Try to spawn one more (should be dropped)
	pool.spawn_damage(Vector3(3, 0, 0), 13.0, MobaDamage.DamageType.PHYSICAL, false)

	if pool.get_active_count() != 3:
		violations.append(
			(
				"max_concurrent: should still have 3 active after exceeding limit, got %d"
				% pool.get_active_count()
			)
		)

	pool.free()
	return violations


## Test that physical, magical, and true damage get different colors.
static func _test_damage_types_are_visually_distinct() -> Array[String]:
	var violations: Array[String] = []

	var pool: MobaFloatingText = FLOATING_TEXT_SCENE.instantiate()
	pool.max_concurrent = 3
	pool._ready()

	# Spawn one of each damage type
	pool.spawn_damage(Vector3(0, 0, 0), 10.0, MobaDamage.DamageType.PHYSICAL, false)
	pool.spawn_damage(Vector3(0, 0, 0), 10.0, MobaDamage.DamageType.MAGICAL, false)
	pool.spawn_damage(Vector3(0, 0, 0), 10.0, MobaDamage.DamageType.TRUE, false)

	# Get the three labels and check their colors
	var labels: Array[Label] = []
	for child in pool.get_children():
		if child is Label and child.visible:
			labels.append(child)

	if labels.size() != 3:
		violations.append("damage_colors: expected 3 visible labels, got %d" % labels.size())
	else:
		var physical_color := labels[0].get_theme_color(&"font_color")
		var magical_color := labels[1].get_theme_color(&"font_color")
		var true_color := labels[2].get_theme_color(&"font_color")

		# Check that colors are different from each other
		if physical_color.is_equal_approx(magical_color):
			violations.append("damage_colors: physical and magical should have different colors")

		if magical_color.is_equal_approx(true_color):
			violations.append("damage_colors: magical and true should have different colors")

		if physical_color.is_equal_approx(true_color):
			violations.append("damage_colors: physical and true should have different colors")

	pool.free()
	return violations


## Test that critical hits get a visually distinct color (red).
static func _test_crit_is_visually_distinct() -> Array[String]:
	var violations: Array[String] = []

	var pool: MobaFloatingText = FLOATING_TEXT_SCENE.instantiate()
	pool.max_concurrent = 2
	pool._ready()

	# Spawn regular and crit damage
	pool.spawn_damage(Vector3(0, 0, 0), 10.0, MobaDamage.DamageType.PHYSICAL, false)
	pool.spawn_damage(Vector3(0, 0, 0), 10.0, MobaDamage.DamageType.PHYSICAL, true)

	# Get the two labels
	var labels: Array[Label] = []
	for child in pool.get_children():
		if child is Label and child.visible:
			labels.append(child)

	if labels.size() != 2:
		violations.append("crit_color: expected 2 visible labels, got %d" % labels.size())
	else:
		var normal_color := labels[0].get_theme_color(&"font_color")
		var crit_color := labels[1].get_theme_color(&"font_color")

		if normal_color.is_equal_approx(crit_color):
			violations.append("crit_color: crit should have a different color than normal damage")

		# Crit should be red-ish (high red component)
		if crit_color.r < 0.8:
			violations.append("crit_color: crit color should be red, got %s" % crit_color)

		# Check that crit text has "!" suffix
		if "!" not in labels[1].text:
			violations.append("crit_color: crit text should include '!' suffix")

	pool.free()
	return violations


## Test that healing gets a visually distinct green color.
static func _test_healing_is_visually_distinct() -> Array[String]:
	var violations: Array[String] = []

	var pool: MobaFloatingText = FLOATING_TEXT_SCENE.instantiate()
	pool.max_concurrent = 2
	pool._ready()

	# Spawn damage and healing
	pool.spawn_damage(Vector3(0, 0, 0), 10.0, MobaDamage.DamageType.PHYSICAL, false)
	pool.spawn_heal(Vector3(0, 0, 0), 10.0)

	# Get the two labels
	var labels: Array[Label] = []
	for child in pool.get_children():
		if child is Label and child.visible:
			labels.append(child)

	if labels.size() != 2:
		violations.append("heal_color: expected 2 visible labels, got %d" % labels.size())
	else:
		var damage_color := labels[0].get_theme_color(&"font_color")
		var heal_color := labels[1].get_theme_color(&"font_color")

		if damage_color.is_equal_approx(heal_color):
			violations.append("heal_color: healing should have a different color than damage")

		# Healing should be green-ish (high green component)
		if heal_color.g < 0.7:
			violations.append("heal_color: heal color should be green, got %s" % heal_color)

		# Healing text should start with "+"
		if not labels[1].text.begins_with("+"):
			violations.append("heal_color: healing text should start with '+'")

	pool.free()
	return violations


## Test that shield absorption is visually distinct (blue).
static func _test_shield_absorption_is_visually_distinct() -> Array[String]:
	var violations: Array[String] = []

	var pool: MobaFloatingText = FLOATING_TEXT_SCENE.instantiate()
	pool.max_concurrent = 2
	pool._ready()

	# Spawn damage and shield
	pool.spawn_damage(Vector3(0, 0, 0), 10.0, MobaDamage.DamageType.PHYSICAL, false)
	pool.spawn_shield_absorbed(Vector3(0, 0, 0), 10.0)

	# Get the two labels
	var labels: Array[Label] = []
	for child in pool.get_children():
		if child is Label and child.visible:
			labels.append(child)

	if labels.size() != 2:
		violations.append("shield_color: expected 2 visible labels, got %d" % labels.size())
	else:
		var damage_color := labels[0].get_theme_color(&"font_color")
		var shield_color := labels[1].get_theme_color(&"font_color")

		if damage_color.is_equal_approx(shield_color):
			violations.append("shield_color: shield should have a different color than damage")

		# Shield should be blue-ish (high blue component)
		if shield_color.b < 0.8:
			violations.append("shield_color: shield color should be blue, got %s" % shield_color)

		# Shield text should start with "S"
		if not labels[1].text.begins_with("S"):
			violations.append("shield_color: shield text should start with 'S'")

	pool.free()
	return violations


## Test that multiple simultaneous spawns produce non-overlapping numbers.
static func _test_multiple_spawns_produce_offset_numbers() -> Array[String]:
	var violations: Array[String] = []

	var pool: MobaFloatingText = FLOATING_TEXT_SCENE.instantiate()
	pool.max_concurrent = 5
	pool._ready()

	# Spawn 5 damage numbers at the exact same location
	# They should be offset to avoid perfect overlap
	for i in range(5):
		pool.spawn_damage(Vector3(0, 0, 0), float(i + 1), MobaDamage.DamageType.PHYSICAL, false)

	# Get the visible labels
	var labels: Array[Label] = []
	for child in pool.get_children():
		if child is Label and child.visible:
			labels.append(child)

	if labels.size() != 5:
		violations.append("offset: expected 5 visible labels, got %d" % labels.size())
		pool.free()
		return violations

	# Check that labels have different positions (offsets)
	var positions: Array[Vector2] = []
	for label in labels:
		positions.append(label.position)

	var has_variation := false
	for i in range(1, positions.size()):
		if not positions[i].is_equal_approx(positions[0]):
			has_variation = true
			break

	if not has_variation:
		violations.append(
			"offset: multiple simultaneous spawns should have different positions to avoid overlap"
		)

	pool.free()
	return violations
