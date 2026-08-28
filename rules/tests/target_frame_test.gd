## Test suite for MobaTargetFrame.
##
## Covers: rebinding without duplicate connections, bars seeded and updated from
## their signals, frame visibility tied to target binding, frame self-hiding when
## target dies or is freed, and shield rendering as an overlay.
class_name TargetFrameTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaLoadout = preload("res://rules/abilities/moba_loadout.gd")
const MobaDamage = preload("res://rules/core/moba_damage.gd")
const TARGET_FRAME_SCENE = preload("res://rules/ui/moba_target_frame.tscn")


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_rebind_has_single_connection())
	all_violations.append_array(_test_bars_follow_signals())
	all_violations.append_array(_test_frame_visibility())
	all_violations.append_array(_test_shield_overlay())
	all_violations.append_array(_test_freed_target_hides_frame())
	all_violations.append_array(_test_dead_target_hides_frame())

	if all_violations.is_empty():
		return true

	printerr("\n=== Target Frame Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


static func _make_combatant() -> MobaCombatant:
	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)
	combatant._runtime_stat_block.crit_chance = 0.0  # Disable crit for predictable tests
	return combatant


static func _test_rebind_has_single_connection() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()

	frame.bind(combatant)
	frame.bind(combatant)

	var health_connections: int = 0
	for connection in combatant.health_changed.get_connections():
		if (connection["callable"] as Callable).get_object() == frame:
			health_connections += 1

	var shield_connections: int = 0
	for connection in combatant.shield_changed.get_connections():
		if (connection["callable"] as Callable).get_object() == frame:
			shield_connections += 1

	if health_connections != 1:
		violations.append("rebind: expected 1 health_changed connection, got %d" % health_connections)
	if shield_connections != 1:
		violations.append("rebind: expected 1 shield_changed connection, got %d" % shield_connections)

	frame.unbind()
	for connection in combatant.health_changed.get_connections():
		if (connection["callable"] as Callable).get_object() == frame:
			violations.append("rebind: unbind() left a health_changed connection behind")
	for connection in combatant.shield_changed.get_connections():
		if (connection["callable"] as Callable).get_object() == frame:
			violations.append("rebind: unbind() left a shield_changed connection behind")

	frame.free()
	combatant.free()
	return violations


static func _test_bars_follow_signals() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()
	frame.bind(combatant)

	var maximum_health: float = combatant.get_stat(MobaStatBlock.HEALTH)
	var health_bar: TextureProgressBar = frame.get_node_or_null("VBoxContainer/HealthContainer/HealthBar")
	var health_label: Label = frame.get_node_or_null("VBoxContainer/HealthContainer/HealthLabel")

	# Seeded by bind(), without waiting for a signal.
	if not is_equal_approx(health_bar.value, maximum_health):
		violations.append(
			"bars: bind() should seed health %f, got %f" % [maximum_health, health_bar.value]
		)
	if not is_equal_approx(health_bar.max_value, maximum_health):
		violations.append("bars: health bar maximum should be %f" % maximum_health)
	if health_label.text != "%d / %d" % [roundi(maximum_health), roundi(maximum_health)]:
		violations.append("bars: health label should read current / maximum")

	var damage := MobaDamage.new(10.0, MobaDamage.DamageType.PHYSICAL, null, false)
	combatant.apply_damage(damage)
	if health_bar.value >= maximum_health:
		violations.append("bars: health bar did not follow health_changed")

	frame.free()
	combatant.free()
	return violations


static func _test_frame_visibility() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()

	# Frame starts hidden
	if frame.visible:
		violations.append("visibility: frame should be hidden initially")

	# Frame becomes visible when bound
	frame.bind(combatant)
	if not frame.visible:
		violations.append("visibility: frame should be visible after bind(combatant)")

	# Frame hides when unbound
	frame.unbind()
	if frame.visible:
		violations.append("visibility: frame should be hidden after unbind()")

	# Frame hides when bound to null
	frame.bind(combatant)
	frame.bind(null)
	if frame.visible:
		violations.append("visibility: frame should be hidden when bound to null")

	frame.free()
	combatant.free()
	return violations


static func _test_shield_overlay() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()
	frame.bind(combatant)

	var shield_bar: ProgressBar = frame.get_node_or_null("VBoxContainer/HealthContainer/ShieldBar")

	# Shield bar starts hidden (no shields)
	if shield_bar.visible:
		violations.append("shield: shield bar should be hidden with 0 shields")

	# Apply shield
	combatant.apply_shield(50.0, &"test_source", 5.0)
	if not shield_bar.visible:
		violations.append("shield: shield bar should be visible with shields")
	if not is_equal_approx(shield_bar.value, 50.0):
		violations.append(
			"shield: shield bar value should be 50.0, got %f" % shield_bar.value
		)

	frame.free()
	combatant.free()
	return violations


static func _test_freed_target_hides_frame() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()

	frame.bind(combatant)
	if not frame.visible:
		violations.append("freed_target: frame should be visible after bind()")

	# Free the combatant
	combatant.free()
	# Trigger the _process check
	frame._process(0.0)

	if frame.visible:
		violations.append("freed_target: frame should hide when target is freed")

	frame.free()
	return violations


static func _test_dead_target_hides_frame() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()

	frame.bind(combatant)
	if not frame.visible:
		violations.append("dead_target: frame should be visible after bind()")

	# Kill the combatant
	var lethal_damage := MobaDamage.new(9999.0, MobaDamage.DamageType.TRUE, null, false)
	combatant.apply_damage(lethal_damage)

	# Trigger the _process check
	frame._process(0.0)

	if frame.visible:
		violations.append("dead_target: frame should hide when target dies")

	frame.free()
	combatant.free()
	return violations
