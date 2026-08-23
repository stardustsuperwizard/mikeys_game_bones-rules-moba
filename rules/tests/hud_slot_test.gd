## Test suite for the reusable MobaAbilitySlot control.
##
## Covers charge-label visibility for single- vs multi-charge abilities, the
## empty state, that the remaining-seconds readout reaches zero on the same
## tick the ability becomes ready, size stability across states, and that a
## freed combatant renders a neutral state instead of throwing.
class_name HudSlotTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const SLOT_SCENE = preload("res://rules/ui/moba_ability_slot.tscn")


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_charge_label_visibility())
	all_violations.append_array(_test_empty_state())
	all_violations.append_array(_test_cooldown_readout_reaches_zero())
	all_violations.append_array(_test_size_stable_across_states())
	all_violations.append_array(_test_freed_combatant_is_neutral())

	if all_violations.is_empty():
		return true

	printerr("\n=== HUD Slot Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


static func _make_combatant(resource: float = 100.0) -> MobaCombatant:
	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = resource
	return combatant


static func _make_ability(id: String, charges: int, cost: float = 10.0) -> MobaAbility:
	var ability = MobaAbility.new()
	ability.id = id
	ability.name = "Test " + id
	ability.resource_cost = cost
	ability.cooldown = 4.0
	ability.charges = charges
	return ability


static func _test_charge_label_visibility() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	combatant.register_ability(_make_ability("single_charge", 1))
	combatant.register_ability(_make_ability("multi_charge", 3))

	var slot: MobaAbilitySlot = SLOT_SCENE.instantiate()

	slot.set_ability(combatant, &"single_charge")
	if slot.get_node("ChargeLabel").visible:
		violations.append("charge_label: single-charge ability should show no charge count")

	slot.set_ability(combatant, &"multi_charge")
	var charge_label: Label = slot.get_node("ChargeLabel")
	if not charge_label.visible:
		violations.append("charge_label: multi-charge ability should show a charge count")
	if charge_label.text != "3":
		violations.append("charge_label: expected '3', got '%s'" % charge_label.text)

	slot.free()
	combatant.free()
	return violations


static func _test_empty_state() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	combatant.register_ability(_make_ability("empty_case", 1))

	var slot: MobaAbilitySlot = SLOT_SCENE.instantiate()
	slot.set_ability(combatant, &"empty_case")
	slot.clear()

	if not slot.is_empty():
		violations.append("empty_state: slot should report empty after clear()")
	if not slot.visible:
		violations.append("empty_state: an empty slot must stay visible")
	if slot.get_node("NameLabel").text != MobaAbilitySlot.EMPTY_NAME_PLACEHOLDER:
		violations.append("empty_state: empty slot should render the name placeholder")
	if slot.get_node("CooldownSweep").visible:
		violations.append("empty_state: empty slot should show no cooldown sweep")

	slot.free()
	combatant.free()
	return violations


static func _test_cooldown_readout_reaches_zero() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	combatant.register_ability(_make_ability("sweep_case", 1))

	var slot: MobaAbilitySlot = SLOT_SCENE.instantiate()
	slot.set_ability(combatant, &"sweep_case")
	combatant.commit_activate(&"sweep_case")
	slot.refresh()

	var cooldown_label: Label = slot.get_node("CooldownLabel")
	if not slot.get_node("CooldownSweep").visible:
		violations.append("cooldown_readout: a slot on cooldown should show a sweep")
	if cooldown_label.text == "0.0":
		violations.append("cooldown_readout: readout should be non-zero while on cooldown")

	var ticks := 0
	var became_ready := false
	while ticks < 200:
		combatant.tick(0.1)
		slot.refresh()
		ticks += 1
		var blocked: bool = (
			combatant.can_activate(&"sweep_case") == MobaCombatant.ActivationFailure.NO_CHARGES
		)
		if not blocked:
			became_ready = true
			if cooldown_label.text != "0.0":
				violations.append(
					"cooldown_readout: readout '%s' should be zero once ready" % cooldown_label.text
				)
			if slot.get_node("CooldownSweep").visible:
				violations.append("cooldown_readout: sweep should clear once ready")
			break
		# Still blocked: the readout must not have reached zero early.
		if cooldown_label.text == "0.0" and combatant.get_cooldown_remaining(&"sweep_case") >= 0.05:
			violations.append("cooldown_readout: readout reached zero before the ability was ready")
			break

	if not became_ready:
		violations.append("cooldown_readout: ability never became ready")

	slot.free()
	combatant.free()
	return violations


static func _test_size_stable_across_states() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant(0.0)
	combatant.register_ability(_make_ability("size_case", 3))

	var slot: MobaAbilitySlot = SLOT_SCENE.instantiate()
	slot.clear()
	var empty_size := slot.get_combined_minimum_size()

	slot.set_ability(combatant, &"size_case")
	var unaffordable_size := slot.get_combined_minimum_size()

	combatant.restore_resource(100.0)
	slot.refresh()
	var ready_size := slot.get_combined_minimum_size()

	combatant.commit_activate(&"size_case")
	slot.refresh()
	var cooldown_size := slot.get_combined_minimum_size()

	if unaffordable_size != empty_size:
		violations.append(
			"size_stable: unaffordable size %s != empty %s" % [unaffordable_size, empty_size]
		)
	if ready_size != empty_size:
		violations.append("size_stable: ready size %s != empty %s" % [ready_size, empty_size])
	if cooldown_size != empty_size:
		violations.append("size_stable: cooldown size %s != empty %s" % [cooldown_size, empty_size])

	slot.free()
	combatant.free()
	return violations


static func _test_freed_combatant_is_neutral() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	combatant.register_ability(_make_ability("freed_case", 1))

	var slot: MobaAbilitySlot = SLOT_SCENE.instantiate()
	slot.set_ability(combatant, &"freed_case")
	combatant.free()

	slot.refresh()
	if not slot.is_empty():
		violations.append("freed_combatant: slot should report empty once the combatant is gone")
	if slot.get_node("NameLabel").text != MobaAbilitySlot.EMPTY_NAME_PLACEHOLDER:
		violations.append("freed_combatant: slot should render the neutral placeholder")

	slot.free()
	return violations
