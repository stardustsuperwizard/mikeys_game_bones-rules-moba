## Test suite for the reusable MobaCombatHUD.
##
## Covers rebinding without duplicate connections, bars seeded and updated from
## their signals, the four action slots holding fixed positional order, the
## passive grouping's empty state, and the focused-slot tooltip seam.
class_name HudTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaLoadout = preload("res://rules/abilities/moba_loadout.gd")
const HUD_SCENE = preload("res://rules/ui/moba_combat_hud.tscn")


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_rebind_has_single_connection())
	all_violations.append_array(_test_bars_follow_signals())
	all_violations.append_array(_test_slot_order_is_fixed())
	all_violations.append_array(_test_passive_empty_state())
	all_violations.append_array(_test_tooltip_follows_focus())
	all_violations.append_array(_test_freed_combatant_clears_binding())

	if all_violations.is_empty():
		return true

	printerr("\n=== HUD Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


static func _make_ability(id: String) -> MobaAbility:
	var ability = MobaAbility.new()
	ability.id = id
	ability.name = "Test " + id
	ability.resource_cost = 10.0
	ability.cooldown = 4.0
	ability.charges = 1
	return ability


static func _make_combatant(passive_id: String = "") -> MobaCombatant:
	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)

	var loadout = MobaLoadout.new()
	for index in range(1, 5):
		loadout.set_action_slot(index, "slot_%d" % index)
	loadout.set_passive_slot(passive_id)
	combatant.loadout = loadout

	for index in range(1, 5):
		combatant.register_ability(_make_ability("slot_%d" % index))
	if passive_id != "":
		combatant.register_ability(_make_ability(passive_id))

	return combatant


static func _test_rebind_has_single_connection() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var hud: MobaCombatHUD = HUD_SCENE.instantiate()

	hud.bind(combatant)
	hud.bind(combatant)

	var health_connections: int = combatant.health_changed.get_connections().size()
	var resource_connections: int = combatant.resource_changed.get_connections().size()
	var hud_health: int = 0
	for connection in combatant.health_changed.get_connections():
		if (connection["callable"] as Callable).get_object() == hud:
			hud_health += 1
	var hud_resource: int = 0
	for connection in combatant.resource_changed.get_connections():
		if (connection["callable"] as Callable).get_object() == hud:
			hud_resource += 1

	if hud_health != 1:
		violations.append("rebind: expected 1 health_changed connection, got %d" % hud_health)
	if hud_resource != 1:
		violations.append("rebind: expected 1 resource_changed connection, got %d" % hud_resource)
	if health_connections < 1 or resource_connections < 1:
		violations.append("rebind: HUD did not connect the combatant signals at all")

	hud.unbind()
	for connection in combatant.health_changed.get_connections():
		if (connection["callable"] as Callable).get_object() == hud:
			violations.append("rebind: unbind() left a health_changed connection behind")

	hud.free()
	combatant.free()
	return violations


static func _test_bars_follow_signals() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var hud: MobaCombatHUD = HUD_SCENE.instantiate()
	hud.bind(combatant)

	var maximum_health: float = combatant.get_stat(MobaStatBlock.HEALTH)
	var health_bar: TextureProgressBar = hud.get_node(
		"Layout/BottomBar/Bars/HealthRow/HealthBar"
	)
	var resource_bar: TextureProgressBar = hud.get_node(
		"Layout/BottomBar/Bars/ResourceRow/ResourceBar"
	)
	var health_label: Label = hud.get_node("Layout/BottomBar/Bars/HealthRow/HealthLabel")

	# Seeded by bind(), without waiting for a signal.
	if not is_equal_approx(health_bar.value, maximum_health):
		violations.append(
			"bars: bind() should seed health %f, got %f" % [maximum_health, health_bar.value]
		)
	if not is_equal_approx(health_bar.max_value, maximum_health):
		violations.append("bars: health bar maximum should be %f" % maximum_health)
	if health_label.text != "%d / %d" % [roundi(maximum_health), roundi(maximum_health)]:
		violations.append("bars: health label should read current / maximum")

	combatant.apply_damage(10.0, MobaAbility.DamageType.PHYSICAL, null)
	if health_bar.value >= maximum_health:
		violations.append("bars: health bar did not follow health_changed")

	var resource_before: float = resource_bar.value
	combatant.spend_resource(5.0)
	if not is_equal_approx(resource_bar.value, resource_before - 5.0):
		violations.append(
			"bars: resource bar did not follow resource_changed (%f)" % resource_bar.value
		)

	hud.free()
	combatant.free()
	return violations


static func _test_slot_order_is_fixed() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var hud: MobaCombatHUD = HUD_SCENE.instantiate()
	hud.bind(combatant)

	var row: HBoxContainer = hud.get_node("Layout/BottomBar/SlotRow/ActionSlots")
	if row.get_child_count() != MobaCombatHUD.ACTION_SLOT_COUNT:
		violations.append("slot_order: expected 4 action slots, got %d" % row.get_child_count())

	for index in range(MobaCombatHUD.ACTION_SLOT_COUNT):
		var slot: MobaAbilitySlot = row.get_child(index)
		var expected := StringName("slot_%d" % (index + 1))
		if slot.get_ability_id() != expected:
			violations.append(
				"slot_order: position %d holds '%s', expected '%s'"
				% [index, slot.get_ability_id(), expected]
			)
		if not slot.visible:
			violations.append("slot_order: slot %d must stay visible" % (index + 1))

	# Slot 1 stays leftmost when slot 2 goes on cooldown.
	combatant.commit_activate(&"slot_2")
	for slot in hud.get_action_slots():
		slot.refresh()
	if (row.get_child(0) as MobaAbilitySlot).get_ability_id() != &"slot_1":
		violations.append("slot_order: slot 1 stopped being leftmost after slot 2 went on cooldown")
	if row.get_child_count() != MobaCombatHUD.ACTION_SLOT_COUNT:
		violations.append("slot_order: slot count changed while slot 2 was on cooldown")

	hud.free()
	combatant.free()
	return violations


static func _test_passive_empty_state() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var hud: MobaCombatHUD = HUD_SCENE.instantiate()
	hud.bind(combatant)

	var passive: MobaAbilitySlot = hud.get_passive_slot()
	if passive == null:
		hud.free()
		combatant.free()
		return ["passive: the HUD has no passive grouping slot"]
	if not passive.is_empty():
		violations.append("passive: no passive selected should render the empty state")
	if not passive.visible:
		violations.append("passive: the passive grouping must stay visible when empty")
	if passive.get_node("NameLabel").text != MobaAbilitySlot.EMPTY_NAME_PLACEHOLDER:
		violations.append("passive: empty passive grouping should render the name placeholder")

	var row: HBoxContainer = hud.get_node("Layout/BottomBar/SlotRow/ActionSlots")
	if row.get_child_count() != MobaCombatHUD.ACTION_SLOT_COUNT:
		violations.append("passive: action slots collapsed while the passive grouping was empty")

	hud.free()
	combatant.free()

	var with_passive := _make_combatant("aegis")
	var hud_with_passive: MobaCombatHUD = HUD_SCENE.instantiate()
	hud_with_passive.bind(with_passive)
	if hud_with_passive.get_passive_slot().get_ability_id() != &"aegis":
		violations.append("passive: configured passive id should reach the passive grouping")
	hud_with_passive.free()
	with_passive.free()

	return violations


static func _test_tooltip_follows_focus() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var hud: MobaCombatHUD = HUD_SCENE.instantiate()
	hud.bind(combatant)

	if hud.is_tooltip_visible():
		violations.append("tooltip: should stay closed while nothing holds focus")

	var slot: MobaAbilitySlot = hud.get_action_slots()[1]
	slot.set_focused(true)

	if hud.get_focused_slot() != slot:
		violations.append("tooltip: the HUD did not track the focused slot")
	if not hud.is_tooltip_visible():
		violations.append("tooltip: focusing a slot should open the tooltip")

	var name_label: Label = hud.get_node("Layout/BottomBar/Tooltip/TooltipText/TooltipName")
	var status_label: Label = hud.get_node("Layout/BottomBar/Tooltip/TooltipText/TooltipStatus")
	if name_label.text != "Test slot_2":
		violations.append("tooltip: expected the ability name, got '%s'" % name_label.text)
	if status_label.text == "":
		violations.append("tooltip: expected a status describing what the ability is doing")

	combatant.commit_activate(&"slot_2")
	slot.set_focused(false)
	slot.set_focused(true)
	if not status_label.text.begins_with("Recharging"):
		violations.append(
			"tooltip: an ability on cooldown should report recharging, got '%s'" % status_label.text
		)

	slot.set_focused(false)
	if hud.get_focused_slot() != null:
		violations.append("tooltip: losing focus should clear the focused slot")
	if hud.is_tooltip_visible():
		violations.append("tooltip: losing focus should close the tooltip")

	hud.free()
	combatant.free()
	return violations


static func _test_freed_combatant_clears_binding() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var hud: MobaCombatHUD = HUD_SCENE.instantiate()
	hud.bind(combatant)
	combatant.free()

	hud._process(0.016)
	if hud.get_combatant() != null:
		violations.append("freed_combatant: the HUD should clear its binding")
	for slot in hud.get_action_slots():
		if not slot.is_empty():
			violations.append("freed_combatant: slots should render the empty state")
			break

	hud._process(0.016)

	hud.free()
	return violations
