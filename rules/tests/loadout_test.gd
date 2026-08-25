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
	results.append(_test_basic_attack_cycle())
	results.append(_test_attack_cadence_one_per_second())
	results.append(_test_attack_cadence_one_point_five_per_second())
	results.append(_test_attack_cycle_limiter())
	results.append(_test_attack_idle_time_when_interval_longer())
	results.append(_test_basic_attack_state_legality())
	results.append(_test_basic_attack_refuses_out_of_range())
	results.append(_test_basic_attack_refuses_dead_target())
	results.append(_test_basic_attack_refuses_when_state_forbids())
	results.append(_test_basic_attack_damage_amount())
	results.append(_test_basic_attack_no_weapon_fails_cleanly())

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
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
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
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
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
	# on_cooldown (the correct failure reason for single-charge abilities).
	if second_result.reason != MobaAbilityAction.FAILURE_ON_COOLDOWN:
		print("ERROR: expected on_cooldown reason, got '%s'" % second_result.reason)
		return false

	if combatant.get_action_slot_ability_id(1) != slot1_id_before:
		print("ERROR: slot 1 mapping changed after second activation attempt")
		return false

	MobaAbilityLibrary._reset()
	return true


static func _test_basic_attack_cycle() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]
	var state_machine: MobaStateMachine = data["state_machine"]

	var initial_health = target._current_health

	if not combatant.basic_attack(target):
		print("ERROR: basic_attack should succeed")
		return false

	if state_machine.current_state != MobaState.BASIC_ATTACK_WINDUP:
		print("ERROR: Should be in BASIC_ATTACK_WINDUP")
		return false

	var wind_up = combatant.loadout.get_weapon().wind_up
	combatant.tick(wind_up + 0.01)

	if state_machine.current_state != MobaState.BASIC_ATTACK_RECOVERY:
		print("ERROR: Should have transitioned to BASIC_ATTACK_RECOVERY after wind-up")
		return false

	if target._current_health >= initial_health:
		print("ERROR: Target should have taken damage")
		return false

	var recovery = combatant.loadout.get_weapon().recovery
	combatant.tick(recovery + 0.01)

	if state_machine.current_state != MobaState.IDLE:
		print("ERROR: Should return to IDLE after recovery")
		return false

	return true


## Simulates repeat-attacking for `seconds` of gameplay by ticking in small
## steps and calling basic_attack() whenever is_basic_attack_ready() allows
## it - the same loop the game side would run - and returns how many
## attacks resolved (via basic_attack_resolved).
static func _simulate_attacks_for(
	combatant: MobaCombatant, target: MobaCombatant, seconds: float
) -> int:
	# GDScript lambdas capture local variables by value, so an int counter
	# mutated inside the lambda would not be visible outside it. A one-element
	# Array is a reference type, so mutating its contents from the lambda is
	# visible to this function after the signal fires.
	var resolved_count = [0]
	var handler = func(_t, _d): resolved_count[0] += 1
	combatant.basic_attack_resolved.connect(handler)

	var step = 0.01
	var elapsed = 0.0
	while elapsed < seconds:
		if combatant.is_basic_attack_ready():
			combatant.basic_attack(target)
		combatant.tick(step)
		elapsed += step

	combatant.basic_attack_resolved.disconnect(handler)
	return resolved_count[0]


static func _test_attack_cadence_one_per_second() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]

	combatant._runtime_stat_block.attack_speed = 1.0

	var resolved = _simulate_attacks_for(combatant, target, 1.0)
	if resolved != 1:
		print("ERROR: Expected exactly 1 attack at 1.0 attack speed, got %d" % resolved)
		return false

	return true


static func _test_attack_cadence_one_point_five_per_second() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]

	combatant._runtime_stat_block.attack_speed = 1.5

	var resolved = _simulate_attacks_for(combatant, target, 2.0)
	if resolved != 3:
		print("ERROR: Expected exactly 3 attacks over 2s at 1.5 attack speed, got %d" % resolved)
		return false

	return true


static func _test_attack_cycle_limiter() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]

	combatant._runtime_stat_block.attack_speed = 1.0
	var weapon = combatant.loadout.get_weapon()
	weapon.wind_up = 0.6
	weapon.recovery = 0.5

	if not combatant.basic_attack(target):
		print("ERROR: First attack should succeed")
		return false

	# At t=1.0 the attack-speed interval has already elapsed, but the cycle
	# (0.6 wind-up + 0.5 recovery = 1.1s) has not finished (still 0.1s of
	# recovery left), so the cycle -- not the interval -- must be the
	# reason the next attack is refused.
	combatant.tick(1.0)

	if combatant.basic_attack(target):
		print("ERROR: Second attack should not be ready when cycle exceeds interval")
		return false

	combatant.tick(0.15)
	if not combatant.basic_attack(target):
		print("ERROR: Second attack should be ready after cycle completes")
		return false

	return true


static func _test_attack_idle_time_when_interval_longer() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]

	var weapon = combatant.loadout.get_weapon()
	weapon.wind_up = 0.2
	weapon.recovery = 0.2

	combatant._runtime_stat_block.attack_speed = 1.0

	if not combatant.basic_attack(target):
		print("ERROR: First attack should succeed")
		return false

	combatant.tick(0.4)

	if combatant.basic_attack(target):
		print("ERROR: Second attack should not be ready before interval")
		return false

	combatant.tick(0.6)
	if not combatant.basic_attack(target):
		print("ERROR: Second attack should be ready after interval")
		return false

	return true


static func _test_basic_attack_state_legality() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]
	var state_machine: MobaStateMachine = data["state_machine"]

	if not combatant.basic_attack(target):
		print("ERROR: basic_attack should succeed")
		return false

	if state_machine.current_state != MobaState.BASIC_ATTACK_WINDUP:
		print("ERROR: Should be in BASIC_ATTACK_WINDUP")
		return false
	if state_machine.can(&"ability"):
		print("ERROR: can(ability) should be false during wind-up")
		return false

	var weapon = combatant.loadout.get_weapon()
	combatant.tick(weapon.wind_up + 0.01)

	if state_machine.current_state != MobaState.BASIC_ATTACK_RECOVERY:
		print("ERROR: Should be in BASIC_ATTACK_RECOVERY")
		return false
	if not state_machine.can(&"ability"):
		print("ERROR: can(ability) should be true during recovery")
		return false
	if state_machine.can(&"basic_attack"):
		print("ERROR: can(basic_attack) should be false during recovery")
		return false

	return true


static func _test_basic_attack_refuses_out_of_range() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]
	var target_actor: Node = data["target_actor"]
	var state_machine: MobaStateMachine = data["state_machine"]

	target_actor.global_position = Vector3(100.0, 0.0, 0.0)
	var initial_health = target._current_health

	if combatant.basic_attack(target):
		print("ERROR: basic_attack should refuse an out-of-range target")
		return false
	if state_machine.current_state != MobaState.IDLE:
		print("ERROR: Should not have entered the cycle")
		return false
	if target._current_health != initial_health:
		print("ERROR: Out-of-range target should not take damage")
		return false

	return true


static func _test_basic_attack_refuses_dead_target() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]
	var state_machine: MobaStateMachine = data["state_machine"]

	target._current_health = 0.0

	if combatant.basic_attack(target):
		print("ERROR: basic_attack should refuse a dead target")
		return false
	if state_machine.current_state != MobaState.IDLE:
		print("ERROR: Should not have entered the cycle")
		return false

	return true


static func _test_basic_attack_refuses_when_state_forbids() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]
	var state_machine: MobaStateMachine = data["state_machine"]

	if not combatant.basic_attack(target):
		print("ERROR: First attack should succeed")
		return false

	var initial_health = target._current_health
	if combatant.basic_attack(target):
		print("ERROR: basic_attack should refuse while already in the cycle")
		return false
	if target._current_health != initial_health:
		print("ERROR: Refused attack should not apply damage")
		return false
	if state_machine.current_state != MobaState.BASIC_ATTACK_WINDUP:
		print("ERROR: Cycle should be unaffected by the refused call")
		return false

	return true


static func _test_basic_attack_damage_amount() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]

	var weapon = combatant.loadout.get_weapon()
	var attack_damage = combatant.get_stat(MobaStatBlock.ATTACK_DAMAGE)
	var expected_amount = MobaFormulas.basic_attack_damage(weapon.damage, attack_damage)

	# One-element Arrays are reference types, so mutating their contents from
	# inside a lambda is visible here after the signal fires; a plain float
	# local would only be mutated inside the lambda's own captured-by-value copy.
	var observed_amount = [-1.0]
	var handler = func(t, d):
		if t == target:
			observed_amount[0] = d
	combatant.basic_attack_resolved.connect(handler)

	var observed_raw = [-1.0]
	var damage_handler = func(raw, _final, _damage_type, _was_crit, _source): observed_raw[0] = raw
	target.damage_resolved.connect(damage_handler)

	if not combatant.basic_attack(target):
		combatant.basic_attack_resolved.disconnect(handler)
		target.damage_resolved.disconnect(damage_handler)
		print("ERROR: basic_attack should succeed")
		return false

	combatant.tick(weapon.wind_up + 0.01)
	combatant.basic_attack_resolved.disconnect(handler)
	target.damage_resolved.disconnect(damage_handler)

	if not is_equal_approx(observed_amount[0], expected_amount):
		print("ERROR: Expected damage %f, got %f" % [expected_amount, observed_amount[0]])
		return false
	if not is_equal_approx(observed_raw[0], expected_amount):
		print("ERROR: Expected damage_resolved raw %f, got %f" % [expected_amount, observed_raw[0]])
		return false

	return true


static func _test_basic_attack_no_weapon_fails_cleanly() -> bool:
	var data := _create_test_actor_with_loadout_and_weapon()
	var combatant: MobaCombatant = data["combatant"]
	var target: MobaCombatant = data["target"]
	var state_machine: MobaStateMachine = data["state_machine"]

	combatant.loadout.weapon = null

	if combatant.basic_attack(target):
		print("ERROR: basic_attack should fail cleanly with no weapon equipped")
		return false
	if state_machine.current_state != MobaState.IDLE:
		print("ERROR: Should not have entered the cycle without a weapon")
		return false

	return true


## A lightweight stand-in for a positioned parent node in tests. A plain Node
## with a real (settable, non-computed) global_position field -- not Node3D,
## whose global_position getter/setter requires the node to be inside a live
## SceneTree -- matching ability_activation_test.gd's _TestTarget pattern.
class _TestPositionedNode:
	extends Node
	var global_position: Vector3 = Vector3.ZERO


static func _create_test_actor_with_loadout_and_weapon() -> Dictionary:
	var attacker := _TestPositionedNode.new()
	attacker.global_position = Vector3.ZERO

	var attacker_combatant := MobaCombatant.new()
	attacker_combatant.name = "MobaCombatant"
	attacker_combatant.stat_block = _BASELINE_STAT_BLOCK
	attacker_combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	attacker_combatant._current_health = 500.0
	attacker_combatant._current_resource = 250.0

	var loadout := MobaLoadout.new()
	var weapon := MobaWeapon.new()
	weapon.damage = 50.0
	weapon.attack_speed = 1.0
	weapon.wind_up = 0.1
	weapon.recovery = 0.2
	weapon.attack_range = 10.0
	loadout.weapon = weapon

	attacker_combatant.loadout = loadout
	attacker.add_child(attacker_combatant)

	var state_machine := MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	attacker.add_child(state_machine)

	var target_actor := _TestPositionedNode.new()
	target_actor.global_position = Vector3(5.0, 0.0, 0.0)

	var target_combatant := MobaCombatant.new()
	target_combatant.name = "MobaCombatant"
	target_combatant.stat_block = _BASELINE_STAT_BLOCK
	target_combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	target_combatant._current_health = 500.0
	target_combatant._current_resource = 250.0

	target_actor.add_child(target_combatant)

	var target_state_machine := MobaStateMachine.new()
	target_state_machine.name = "MobaStateMachine"
	target_state_machine._load_state_table()
	target_actor.add_child(target_state_machine)

	return {
		"actor": attacker,
		"combatant": attacker_combatant,
		"state_machine": state_machine,
		"target": target_combatant,
		"target_actor": target_actor
	}
