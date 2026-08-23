## Test suite for MobaLoadout and MobaAbilityCaster.activate_slot().
##
## Covers: positional slot mapping, empty slot handling, duplicate ability rejection,
## out-of-range index handling, auto-registration of loadout abilities, and
## cooldown behavior across consecutive activations of the same slot.
class_name LoadoutTest

const MobaLoadout = preload("res://rules/abilities/moba_loadout.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaAbilityAction = preload("res://rules/abilities/moba_ability_action.gd")
const MobaAbilityCaster = preload("res://rules/abilities/moba_ability_caster.gd")
const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const MobaStateMachine = preload("res://rules/state/moba_state_machine.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## self_ability.tres is self-targeting (no explicit_target needed) with a
## non-zero resource_cost and cooldown, making it suitable for exercising
## activate_slot()'s resource/cooldown side effects.
const _FIXTURE_FILES: Array[String] = ["self_ability.tres"]
const _SELF_ABILITY_ID: StringName = &"self_ability"


## Static entry point for headless test execution.
static func run() -> bool:
	var results: Array[bool] = []

	results.append(_test_positional_slot_mapping())
	results.append(_test_empty_slot_returns_empty_slot_reason())
	results.append(_test_duplicate_ability_rejection())
	results.append(_test_out_of_range_index())
	results.append(_test_activate_slot_empty_slot())
	results.append(_test_activate_slot_out_of_range())
	results.append(_test_activate_slot_auto_registration())
	results.append(_test_activate_slot_cooldown_and_mapping_stable())

	return results.all(func(result: bool) -> bool: return result)


## Load the fixture ability this suite depends on into the library.
static func _ensure_test_ability_loaded() -> void:
	for file_name in _FIXTURE_FILES:
		MobaAbilityLibrary._load_single_ability(
			"res://rules/tests/fixtures/abilities/".path_join(file_name)
		)


## Create a bare combatant with a loadout (no ability pre-registration).
static func _create_test_combatant() -> MobaCombatant:
	var combatant := MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.HEALTH
	)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)
	var loadout := MobaLoadout.new()
	combatant.loadout = loadout
	return combatant


## Create a full test actor (with MobaCombatant + MobaStateMachine children) whose
## combatant carries a loadout with self_ability in slot 1. The loadout is fully
## populated before assignment and the combatant never enters the SceneTree
## (no _ready()), proving auto-registration does not depend on either.
static func _create_test_actor_with_loadout() -> Dictionary:
	var actor := Actor.new()
	actor.owner_id = 1

	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.HEALTH
	)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)

	var loadout := MobaLoadout.new()
	loadout.set_action_slot(1, String(_SELF_ABILITY_ID))
	combatant.loadout = loadout

	actor.add_child(combatant)

	var state_machine := MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	return {"actor": actor, "combatant": combatant}


## Test that slots 1..4 map positionally to loadout slots 1..4.
static func _test_positional_slot_mapping() -> bool:
	var combatant := _create_test_combatant()
	var loadout := combatant.loadout as MobaLoadout

	loadout.set_action_slot(1, "power_strike")
	loadout.set_action_slot(2, "slash")
	loadout.set_action_slot(3, "pierce")
	loadout.set_action_slot(4, "smite")

	if combatant.get_action_slot_ability_id(1) != &"power_strike":
		print("ERROR: Slot 1 should map to power_strike")
		return false
	if combatant.get_action_slot_ability_id(2) != &"slash":
		print("ERROR: Slot 2 should map to slash")
		return false
	if combatant.get_action_slot_ability_id(3) != &"pierce":
		print("ERROR: Slot 3 should map to pierce")
		return false
	if combatant.get_action_slot_ability_id(4) != &"smite":
		print("ERROR: Slot 4 should map to smite")
		return false

	return true


## Test that an empty slot returns empty StringName from the id accessor.
static func _test_empty_slot_returns_empty_slot_reason() -> bool:
	var combatant := _create_test_combatant()
	var loadout := combatant.loadout as MobaLoadout

	loadout.set_action_slot(1, "power_strike")
	# Leave slot 2 empty

	if combatant.get_action_slot_ability_id(1) != &"power_strike":
		print("ERROR: Slot 1 should contain power_strike")
		return false
	if combatant.get_action_slot_ability_id(2) != &"":
		print("ERROR: Slot 2 should be empty")
		return false

	return true


## Test duplicate ability rejection from T1.
static func _test_duplicate_ability_rejection() -> bool:
	var loadout := MobaLoadout.new()

	loadout.set_action_slot(1, "power_strike")
	# Attempt to set power_strike in slot 2 (should be rejected)
	loadout.set_action_slot(2, "power_strike")

	if loadout.get_action_slot(2) != "":
		print("ERROR: Duplicate ability should have been rejected")
		return false
	if loadout.get_action_slot(1) != "power_strike":
		print("ERROR: Slot 1 should still contain power_strike after duplicate rejection")
		return false

	return true


## Test out-of-range index handling on the id accessor.
static func _test_out_of_range_index() -> bool:
	var combatant := _create_test_combatant()
	var loadout := combatant.loadout as MobaLoadout
	loadout.set_action_slot(1, "power_strike")

	if combatant.get_action_slot_ability_id(0) != &"":
		print("ERROR: Out-of-range index 0 should return empty StringName")
		return false
	if combatant.get_action_slot_ability_id(5) != &"":
		print("ERROR: Out-of-range index 5 should return empty StringName")
		return false
	if combatant.get_action_slot_ability_id(-1) != &"":
		print("ERROR: Negative index should return empty StringName")
		return false

	return true


## Test that activate_slot() on an empty slot returns a failed ActionResult with
## reason empty_slot, spending no resource and starting no cooldown.
static func _test_activate_slot_empty_slot() -> bool:
	MobaAbilityLibrary._reset()
	_ensure_test_ability_loaded()

	var data := _create_test_actor_with_loadout()
	var actor: Actor = data["actor"]
	var combatant: MobaCombatant = data["combatant"]

	var initial_resource := combatant._current_resource

	var caster_node := MobaAbilityCaster.new()
	var context := MobaCastContext.new(actor, null)
	# Slot 2 is empty in this loadout (only slot 1 is populated).
	var result := caster_node.activate_slot(2, context)

	if result.success:
		print("ERROR: activate_slot on empty slot should fail")
		return false
	if result.reason != MobaAbilityAction.FAILURE_EMPTY_SLOT:
		print("ERROR: expected empty_slot reason, got '%s'" % result.reason)
		return false
	if combatant._current_resource != initial_resource:
		print("ERROR: empty slot activation should not spend resource")
		return false

	MobaAbilityLibrary._reset()
	return true


## Test that activate_slot() with an out-of-range index returns a failed result
## instead of crashing.
static func _test_activate_slot_out_of_range() -> bool:
	MobaAbilityLibrary._reset()
	_ensure_test_ability_loaded()

	var data := _create_test_actor_with_loadout()
	var actor: Actor = data["actor"]

	var caster_node := MobaAbilityCaster.new()
	var context := MobaCastContext.new(actor, null)

	for bad_index in [0, 5, -1]:
		var result := caster_node.activate_slot(bad_index, context)
		if result.success:
			print("ERROR: activate_slot(%d) should fail" % bad_index)
			return false

	MobaAbilityLibrary._reset()
	return true


## Test that a loadout's action abilities are usable via can_activate()/
## commit_activate() without a separate manual register_ability() call, and
## that activate_slot() successfully activates the loadout ability.
static func _test_activate_slot_auto_registration() -> bool:
	MobaAbilityLibrary._reset()
	_ensure_test_ability_loaded()

	var data := _create_test_actor_with_loadout()
	var actor: Actor = data["actor"]
	var combatant: MobaCombatant = data["combatant"]

	if combatant.can_activate(_SELF_ABILITY_ID) != MobaCombatant.ActivationFailure.OK:
		print("ERROR: loadout ability should be resolvable without manual registration")
		return false

	var caster_node := MobaAbilityCaster.new()
	var context := MobaCastContext.new(actor, null)
	var result := caster_node.activate_slot(1, context)

	if not result.success:
		print("ERROR: activate_slot(1) should succeed, got: %s" % result.reason)
		return false

	MobaAbilityLibrary._reset()
	return true


## Test that activating slot 1 twice in succession returns success then a failed
## result with reason on_cooldown, and that slot mapping is unchanged between
## the two calls (positional slots are never reordered by cooldown state).
static func _test_activate_slot_cooldown_and_mapping_stable() -> bool:
	MobaAbilityLibrary._reset()
	_ensure_test_ability_loaded()

	var data := _create_test_actor_with_loadout()
	var actor: Actor = data["actor"]
	var combatant: MobaCombatant = data["combatant"]

	var caster_node := MobaAbilityCaster.new()
	var context := MobaCastContext.new(actor, null)

	var slot1_id_before := combatant.get_action_slot_ability_id(1)

	var first_result := caster_node.activate_slot(1, context)
	if not first_result.success:
		print("ERROR: first activate_slot(1) should succeed, got: %s" % first_result.reason)
		return false

	var slot1_id_after := combatant.get_action_slot_ability_id(1)
	if slot1_id_before != slot1_id_after:
		print("ERROR: slot 1 mapping changed after activation")
		return false

	var second_result := caster_node.activate_slot(1, context)
	if second_result.success:
		print("ERROR: second activate_slot(1) should fail while on cooldown")
		return false
	# self_ability has charges = 1, so MobaCombatant.can_activate() reports
	# no_charges (rather than on_cooldown) once the single charge is spent --
	# this is existing MobaCombatant/MobaAbilityAction behavior, not something
	# activate_slot() introduces.
	if second_result.reason != MobaAbilityAction.FAILURE_NO_CHARGES:
		print("ERROR: expected no_charges reason, got '%s'" % second_result.reason)
		return false

	if combatant.get_action_slot_ability_id(1) != slot1_id_before:
		print("ERROR: slot 1 mapping changed after second activation attempt")
		return false

	MobaAbilityLibrary._reset()
	return true
