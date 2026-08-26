## Combat loadout definition. Holds one weapon and ability slots (4 action + 1 passive).
class_name MobaLoadout
extends Resource

## The weapon equipped in this loadout.
##
## Deliberately shared authored equipment data, not duplicated per combatant. A
## combatant's loadout is a shallow copy of the assigned resource (see
## MobaCombatant.loadout), and authored loadouts reference their weapon as an
## ExtResource, so every combatant assigned the same loadout .tres shares one
## MobaWeapon instance.
##
## That sharing is safe because no production code path mutates a MobaWeapon's
## fields in place: a loadout's weapon is replaced wholesale. Writing to a field
## of a weapon read back off a live combatant would write through to every other
## combatant sharing that file. Some test fixtures do mutate one in place -- see
## rules/tests/loadout_test.gd -- and are harmless only because each fixture call
## builds its own MobaWeapon rather than loading the authored file.
@export var weapon: MobaWeapon

## Four action ability id slots (fixed-size array).
@export var action_slot_1: String = ""
@export var action_slot_2: String = ""
@export var action_slot_3: String = ""
@export var action_slot_4: String = ""

## One passive ability id slot.
@export var passive_slot: String = ""


## Get an action slot value by 1-based index (1..4).
## Returns empty string if index is out of range; errors are pushed instead.
func get_action_slot(index: int) -> String:
	if index < 1 or index > 4:
		push_error("Action slot index out of range [1..4]: %d" % index)
		return ""

	match index:
		1:
			return action_slot_1
		2:
			return action_slot_2
		3:
			return action_slot_3
		4:
			return action_slot_4
	return ""


## Set an action slot value by 1-based index (1..4).
## Rejects out-of-range indices and duplicate ability ids with explicit errors.
func set_action_slot(index: int, ability_id: String) -> void:
	if index < 1 or index > 4:
		push_error("Action slot index out of range [1..4]: %d" % index)
		return

	# Check for duplicate ability ids in other action slots (excluding empty strings)
	if ability_id != "":
		var existing_slots: Array[String] = [
			action_slot_1, action_slot_2, action_slot_3, action_slot_4
		]
		for i in range(existing_slots.size()):
			if i + 1 != index and existing_slots[i] == ability_id:
				push_error(
					(
						"Duplicate ability id '%s' already occupies action slot %d"
						% [ability_id, i + 1]
					)
				)
				return

	match index:
		1:
			action_slot_1 = ability_id
		2:
			action_slot_2 = ability_id
		3:
			action_slot_3 = ability_id
		4:
			action_slot_4 = ability_id


## Get the passive slot value.
func get_passive_slot() -> String:
	return passive_slot


## Get the equipped weapon.
func get_weapon() -> MobaWeapon:
	return weapon


## Set the passive slot value.
func set_passive_slot(ability_id: String) -> void:
	passive_slot = ability_id


## Validate the loadout. Rejects invalid configurations with clear error messages.
## Returns true if valid, false otherwise.
func validate() -> bool:
	var action_slots: Array[String] = [action_slot_1, action_slot_2, action_slot_3, action_slot_4]
	var non_empty_count: int = 0
	var seen_ids: Dictionary = {}

	for i in range(action_slots.size()):
		var slot_value = action_slots[i]
		if slot_value != "":
			non_empty_count += 1
			if slot_value in seen_ids:
				push_error(
					(
						"Duplicate ability id '%s' occupies both action slot %d and action slot %d"
						% [slot_value, seen_ids[slot_value], i + 1]
					)
				)
				return false
			seen_ids[slot_value] = i + 1

	if non_empty_count > 4:
		push_error("Too many action abilities: %d (maximum 4)" % non_empty_count)
		return false

	return true
