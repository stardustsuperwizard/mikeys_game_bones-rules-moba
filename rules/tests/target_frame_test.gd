## Test suite for the standalone MobaTargetFrame control.
##
## Covers: rebinding without duplicate or stale connections, name resolution
## from the parent Actor, bars seeded at bind and updated from their signals,
## shields rendering as an overlay on the same bar as health, visibility tied to
## whether a target is bound, and the frame dropping a target that dies or is
## freed.
class_name TargetFrameTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaDamage = preload("res://rules/core/moba_damage.gd")
const TARGET_FRAME_SCENE = preload("res://rules/ui/moba_target_frame.tscn")

const HEALTH_BAR_PATH := "VBoxContainer/HealthContainer/HealthBar"
const SHIELD_BAR_PATH := "VBoxContainer/HealthContainer/ShieldBar"
const HEALTH_LABEL_PATH := "VBoxContainer/HealthContainer/HealthLabel"
const NAME_LABEL_PATH := "VBoxContainer/NameLabel"


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_rebind_has_single_connection())
	all_violations.append_array(_test_rebind_leaves_no_stale_data())
	all_violations.append_array(_test_name_from_actor())
	all_violations.append_array(_test_bars_follow_signals())
	all_violations.append_array(_test_frame_visibility())
	all_violations.append_array(_test_shield_overlays_health_bar())
	all_violations.append_array(_test_freed_target_hides_frame())
	all_violations.append_array(_test_dead_target_hides_frame())

	if all_violations.is_empty():
		return true

	printerr("\n=== Target Frame Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


static func _make_combatant() -> MobaCombatant:
	var combatant := MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._runtime_stat_block.crit_chance = 0.0
	return combatant


static func _connection_count(sig: Signal, target: Object) -> int:
	var count := 0
	for connection in sig.get_connections():
		if (connection["callable"] as Callable).get_object() == target:
			count += 1
	return count


static func _test_rebind_has_single_connection() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()

	frame.bind_target(combatant)
	frame.bind_target(combatant)

	var health_connections := _connection_count(combatant.health_changed, frame)
	var shield_connections := _connection_count(combatant.shield_changed, frame)
	if health_connections != 1:
		violations.append(
			"rebind: expected 1 health_changed connection, got %d" % health_connections
		)
	if shield_connections != 1:
		violations.append(
			"rebind: expected 1 shield_changed connection, got %d" % shield_connections
		)

	frame.unbind_target()
	if _connection_count(combatant.health_changed, frame) != 0:
		violations.append("rebind: unbind_target() left a health_changed connection behind")
	if _connection_count(combatant.shield_changed, frame) != 0:
		violations.append("rebind: unbind_target() left a shield_changed connection behind")

	frame.free()
	combatant.free()
	return violations


## Rebinding to a different target must leave no connection to the old one and
## no trace of its values on screen.
static func _test_rebind_leaves_no_stale_data() -> Array[String]:
	var violations: Array[String] = []

	var first := _make_combatant()
	var second := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()

	frame.bind_target(first)
	first.apply_shield(40.0, &"first_source", 5.0)
	frame.bind_target(second)

	if _connection_count(first.health_changed, frame) != 0:
		violations.append("stale: rebinding left a health_changed connection on the old target")
	if _connection_count(first.shield_changed, frame) != 0:
		violations.append("stale: rebinding left a shield_changed connection on the old target")
	if _connection_count(second.health_changed, frame) != 1:
		violations.append("stale: rebinding did not connect health_changed on the new target")

	var health_bar: TextureProgressBar = frame.get_node_or_null(HEALTH_BAR_PATH)
	var shield_bar: TextureProgressBar = frame.get_node_or_null(SHIELD_BAR_PATH)
	if not is_equal_approx(shield_bar.value, health_bar.value):
		violations.append("stale: the new unshielded target still shows the old target's shield")

	# A signal from the old target must no longer move the frame.
	var value_before: float = health_bar.value
	first.apply_damage(MobaDamage.new(10.0, MobaDamage.DamageType.PHYSICAL, null, false))
	if not is_equal_approx(health_bar.value, value_before):
		violations.append("stale: the old target still drives the frame after rebinding")

	frame.free()
	first.free()
	second.free()
	return violations


## The name falls back to the parent Actor's node name, and is cleared on
## unbind. The character-sheet branch above it is deliberately not exercised
## here: Actor.character_sheet is statically typed to the game-side
## CharacterSheet, so the only value this suite could attach is a CharacterSheet
## -- naming which from rules/ is exactly the outward dependency the extraction
## contract exists to prevent. A duck-typed stand-in is not an option: the
## assignment is a parse error, and Object.set() refuses it silently. So the
## branch is covered by the widget's own guards and by the editor check in the
## pull request instead of by a reference this module must not carry.
static func _test_name_from_actor() -> Array[String]:
	var violations: Array[String] = []

	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()
	var name_label: Label = frame.get_node_or_null(NAME_LABEL_PATH)

	var actor := Actor.new()
	actor.name = "SandRaider"
	var combatant := _make_combatant()
	combatant.name = "MobaCombatant"
	actor.add_child(combatant)

	frame.bind_target(combatant)
	if name_label.text != "SandRaider":
		violations.append(
			"name: expected the actor node name with no sheet, got '%s'" % name_label.text
		)

	frame.unbind_target()
	if name_label.text != "":
		violations.append("name: unbind_target() left the previous target's name on screen")

	# A combatant with no Actor parent must render blank rather than error.
	var orphan := _make_combatant()
	frame.bind_target(orphan)
	if name_label.text != "":
		violations.append(
			(
				"name: a target with no Actor parent should render a blank name, got '%s'"
				% name_label.text
			)
		)

	frame.unbind_target()
	frame.free()
	actor.free()
	orphan.free()
	return violations


static func _test_bars_follow_signals() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()
	frame.bind_target(combatant)

	var maximum_health: float = combatant.maximum_health
	var health_bar: TextureProgressBar = frame.get_node_or_null(HEALTH_BAR_PATH)
	var health_label: Label = frame.get_node_or_null(HEALTH_LABEL_PATH)

	# Seeded by bind_target(), without waiting for a signal.
	if not is_equal_approx(health_bar.value, maximum_health):
		violations.append(
			"bars: bind_target() should seed health %f, got %f" % [maximum_health, health_bar.value]
		)
	if not is_equal_approx(health_bar.max_value, maximum_health):
		violations.append("bars: health bar maximum should be %f" % maximum_health)
	if health_label.text != "%d / %d" % [roundi(maximum_health), roundi(maximum_health)]:
		violations.append("bars: health label should read current / maximum")

	combatant.apply_damage(MobaDamage.new(10.0, MobaDamage.DamageType.PHYSICAL, null, false))
	if health_bar.value >= maximum_health:
		violations.append("bars: health bar did not follow health_changed")
	if not is_equal_approx(health_bar.value, combatant.current_health):
		violations.append("bars: health bar value diverged from the combatant's health")

	frame.free()
	combatant.free()
	return violations


static func _test_frame_visibility() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()

	# Hidden straight out of the scene, before _ready() has had a chance to run.
	if frame.visible:
		violations.append("visibility: frame should be hidden initially")

	frame.bind_target(combatant)
	if not frame.visible:
		violations.append("visibility: frame should be visible after bind_target(combatant)")

	frame.unbind_target()
	if frame.visible:
		violations.append("visibility: frame should be hidden after unbind_target()")

	frame.bind_target(combatant)
	frame.bind_target(null)
	if frame.visible:
		violations.append("visibility: frame should be hidden when bound to null")

	frame.free()
	combatant.free()
	return violations


## Shields are an overlay on the health bar, not a separate number: both bars
## share one scale, and the shield bar's fill runs past the health fill's end by
## exactly the shield amount.
static func _test_shield_overlays_health_bar() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()
	frame.bind_target(combatant)

	var health_bar: TextureProgressBar = frame.get_node_or_null(HEALTH_BAR_PATH)
	var shield_bar: TextureProgressBar = frame.get_node_or_null(SHIELD_BAR_PATH)

	# With no shield the two fills coincide, so no shield segment shows.
	if not is_equal_approx(shield_bar.value, health_bar.value):
		violations.append("shield: an unshielded target should show no shield segment")

	combatant.apply_damage(MobaDamage.new(20.0, MobaDamage.DamageType.TRUE, null, false))
	combatant.apply_shield(50.0, &"test_source", 5.0)

	if not is_equal_approx(shield_bar.max_value, health_bar.max_value):
		violations.append("shield: shield and health bars must share one scale")
	if not is_equal_approx(shield_bar.value - health_bar.value, 50.0):
		violations.append(
			(
				"shield: shield segment should be 50.0 wide, got %f"
				% (shield_bar.value - health_bar.value)
			)
		)
	if not is_equal_approx(health_bar.value, combatant.current_health):
		violations.append("shield: the shield must not eat into the health fill")

	# A shield taking the target past maximum health must not be truncated.
	combatant.apply_shield(500.0, &"big_source", 5.0)
	if not is_equal_approx(shield_bar.value, combatant.current_health + combatant.total_shield()):
		violations.append("shield: an overshield should extend the scale rather than clip")

	frame.free()
	combatant.free()
	return violations


static func _test_freed_target_hides_frame() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()

	frame.bind_target(combatant)
	if not frame.visible:
		violations.append("freed_target: frame should be visible after bind_target()")

	combatant.free()
	frame._process(0.0)

	if frame.visible:
		violations.append("freed_target: frame should hide when target is freed")
	if frame.get_combatant() != null:
		violations.append("freed_target: frame should drop its reference to a freed target")

	frame.free()
	return violations


static func _test_dead_target_hides_frame() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var frame: MobaTargetFrame = TARGET_FRAME_SCENE.instantiate()

	frame.bind_target(combatant)
	if not frame.visible:
		violations.append("dead_target: frame should be visible after bind_target()")

	combatant.apply_damage(MobaDamage.new(9999.0, MobaDamage.DamageType.TRUE, null, false))
	frame._process(0.0)

	if frame.visible:
		violations.append("dead_target: frame should hide when target dies")
	if _connection_count(combatant.health_changed, frame) != 0:
		violations.append("dead_target: dropping a dead target should drop its connections")

	frame.free()
	combatant.free()
	return violations
