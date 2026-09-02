## Character creation screen: build, name, save, and load a character.
##
## A game-flow UI where a player picks primary and secondary Discipline, allocates
## stats, picks a weapon, selects four action abilities and one passive, names the
## result, saves it, and can reload and edit previously saved characters.
##
## All controls are operable via gamepad (using ui_accept/ui_cancel and focus
## navigation) and touch (with appropriately sized tap targets). No affordance
## depends on a hover state (§53).
##
## Every legality decision goes through MobaBuildValidator.validate(); no
## Discipline/stat-pool checks are re-implemented here. The UI's own
## "don't overspend the pool" affordance is a UX nicety on top of that
## single source of truth.
extends Control

## Stat allocation policy file to load. Authored as .tres, loaded once in _ready().
const STAT_ALLOCATION_POLICY_PATH := "res://rules/data/stat_blocks/stat_allocation_policy.tres"

## Template builds directory for "load template" feature.
const TEMPLATES_DIR := "res://rules/data/builds/"

## Minimum touch-target size to ensure gamepad and touch afford same sized buttons.
const TOUCH_TARGET_SIZE := Vector2(60, 60)

## Discipline enum constant strings for display (indexed by enum value).
const DISCIPLINE_NAMES := ["Warrior", "Guardian", "Slayer", "Marksman", "Mystic", "Adventurer"]

# Loaded stat allocation policy (Authoritative source for pool size and per-stat cap)
var _allocation_policy: MobaStatAllocationPolicy

# Currently edited build (the form's working copy)
var _current_build: MobaCharacterBuild

# Resolved control node references
var _primary_discipline_option: OptionButton
var _secondary_discipline_option: OptionButton
var _stat_points_label: Label
var _stat_controls: Dictionary  # StringName -> the row Control holding that stat's Spinbox
var _stat_controls_container: VBoxContainer

# Guards _update_stat_display() against re-entering itself when writing a
# spinbox's max_value clamps its value and emits value_changed.
var _refreshing_stats: bool = false
var _weapon_option: OptionButton
var _action_ability_options: Array[OptionButton]  # action_slot_options[0..3]
var _passive_ability_option: OptionButton
var _character_name_input: LineEdit
var _save_button: Button
var _cancel_button: Button
var _load_template_button: Button
var _template_option: OptionButton
var _load_character_button: Button
var _saved_character_option: OptionButton
var _error_label: Label

# Weapon list cache (file_name -> MobaWeapon resource)
var _weapon_cache: Dictionary = {}

# Available templates cache (file_name -> display_name)
var _templates_cache: Dictionary = {}

# Ability library cache (discipline -> [ability_ids])
var _abilities_by_discipline: Dictionary = {}


## Build validator failure constants mapped to human-readable messages.
## Keyed on MobaBuildValidator constants (not raw StringName literals) to prevent
## silent drift if the validator's constants ever change.
func _get_failure_messages() -> Dictionary:
	return {
		MobaBuildValidator.FAILURE_DISCIPLINES_NOT_DISTINCT:
		"Primary and secondary Disciplines must be different.",
		MobaBuildValidator.FAILURE_LOADOUT_INVALID: "Loadout configuration is invalid.",
		MobaBuildValidator.FAILURE_UNKNOWN_ABILITY: "One of the selected abilities does not exist.",
		MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES:
		"All abilities must belong to the primary or secondary Discipline.",
		MobaBuildValidator.FAILURE_STAT_ALLOCATION_NEGATIVE: "Stat allocations cannot be negative.",
		MobaBuildValidator.FAILURE_STAT_ALLOCATION_UNKNOWN_STAT:
		"One or more allocated stats are invalid.",
		MobaBuildValidator.FAILURE_STAT_ALLOCATION_EXCEEDS_PER_STAT_MAX:
		"One or more stats exceeds the per-stat maximum.",
		MobaBuildValidator.FAILURE_STAT_POOL_OVERSPENT: "Total stat points exceed the pool.",
	}


func _ready() -> void:
	# Load the authoritative stat allocation policy from .tres
	_allocation_policy = ResourceLoader.load(STAT_ALLOCATION_POLICY_PATH)
	if _allocation_policy == null:
		push_error("Failed to load stat allocation policy from %s" % STAT_ALLOCATION_POLICY_PATH)
		return

	# Resolve all UI node references (matching main_menu.gd's pattern)
	_resolve_controls()

	# Validate that all expected controls were resolved
	if _primary_discipline_option == null or _secondary_discipline_option == null:
		push_error("Failed to resolve discipline option buttons")
		return
	if _weapon_option == null:
		push_error("Failed to resolve weapon option button")
		return
	if _action_ability_options.any(func(opt): return opt == null):
		push_error("Failed to resolve one or more action ability option buttons")
		return
	if _passive_ability_option == null:
		push_error("Failed to resolve passive ability option button")
		return
	if _character_name_input == null or _save_button == null or _cancel_button == null:
		push_error("Failed to resolve name input or save/cancel buttons")
		return

	# Initialize the working build
	_current_build = MobaCharacterBuild.new()
	_current_build.loadout = MobaLoadout.new()

	# Populate option buttons and caches
	_build_stat_rows()
	_populate_discipline_options()
	_populate_weapon_options()
	_populate_template_options()
	_populate_template_option_button()
	_populate_saved_characters_option()
	_populate_ability_cache()

	# Connect all signal handlers
	_connect_signals()

	# Set focus to the primary discipline picker for gamepad/keyboard navigation
	if _primary_discipline_option.focus_mode != Control.FOCUS_NONE:
		_primary_discipline_option.grab_focus()

	# Initialize display
	_update_stat_display()
	_update_ability_options()


## Resolve all control node references from the scene.
## Matches the pattern used in main_menu.gd: resolve from one container
## to avoid long node paths.
func _resolve_controls() -> void:
	var main_container := $MarginContainer/VBoxContainer

	# Main controls - note: these use get_node_or_null to avoid errors if paths don't match
	_primary_discipline_option = (
		main_container.get_node_or_null(
			^"DisciplineSection/PrimaryDisciplineContainer/PrimaryDisciplineOption"
		)
		as OptionButton
	)
	_secondary_discipline_option = (
		main_container.get_node_or_null(
			^"DisciplineSection/SecondaryDisciplineContainer/SecondaryDisciplineOption"
		)
		as OptionButton
	)

	_stat_points_label = main_container.get_node_or_null(^"StatSection/StatsLabel") as Label
	_weapon_option = (
		main_container.get_node_or_null(^"LoadoutSection/WeaponContainer/WeaponOption")
		as OptionButton
	)

	_action_ability_options = [
		(
			main_container.get_node_or_null(
				^"LoadoutSection/ActionAbilitiesContainer/Action1Container/Action1Option"
			)
			as OptionButton
		),
		(
			main_container.get_node_or_null(
				^"LoadoutSection/ActionAbilitiesContainer/Action2Container/Action2Option"
			)
			as OptionButton
		),
		(
			main_container.get_node_or_null(
				^"LoadoutSection/ActionAbilitiesContainer/Action3Container/Action3Option"
			)
			as OptionButton
		),
		(
			main_container.get_node_or_null(
				^"LoadoutSection/ActionAbilitiesContainer/Action4Container/Action4Option"
			)
			as OptionButton
		),
	]
	_passive_ability_option = (
		main_container.get_node_or_null(^"LoadoutSection/PassiveContainer/PassiveAbilityOption")
		as OptionButton
	)

	_character_name_input = main_container.get_node_or_null(^"CharacterNameInput") as LineEdit

	_save_button = main_container.get_node_or_null(^"ButtonContainer/SaveButton") as Button
	_cancel_button = main_container.get_node_or_null(^"ButtonContainer/CancelButton") as Button
	_template_option = (
		main_container.get_node_or_null(^"LoadTemplateSection/TemplateOption") as OptionButton
	)
	_load_template_button = (
		main_container.get_node_or_null(^"LoadTemplateSection/TemplateLoadButton") as Button
	)
	_saved_character_option = (
		main_container.get_node_or_null(^"LoadSavedSection/SavedCharacterOption") as OptionButton
	)
	_load_character_button = (
		main_container.get_node_or_null(^"LoadSavedSection/LoadCharacterButton") as Button
	)

	_error_label = main_container.get_node_or_null(^"ErrorLabel") as Label

	_stat_controls_container = (
		main_container.get_node_or_null(^"StatSection/StatScroll/StatControls") as VBoxContainer
	)


## Build one row per allocatable stat, from the policy rather than from the scene.
##
## The scene ships StatControls empty on purpose. It previously carried three
## authored rows -- health, attack_damage, armor -- while the shipped policy
## leaves allocatable_stats empty, which get_allocatable_stats() expands to
## every stat MobaStatBlock defines. _resolve_controls() then dropped the
## seventeen with no matching node behind an `if node != null`, so the policy
## governed the pool and the per-stat cap but not which stats a player could
## actually spend on, and a policy naming a stat the scene had no row for would
## have vanished without a word.
func _build_stat_rows() -> void:
	if _stat_controls_container == null or _allocation_policy == null:
		return

	for child in _stat_controls_container.get_children():
		child.queue_free()
		_stat_controls_container.remove_child(child)

	_stat_controls = {}

	for stat_name in _allocation_policy.get_allocatable_stats():
		var row := HBoxContainer.new()
		row.name = String(stat_name)

		var label := Label.new()
		label.text = _stat_display_name(stat_name)
		label.custom_minimum_size = Vector2(180, 0)
		row.add_child(label)

		var spinbox := SpinBox.new()
		spinbox.name = "Spinbox"
		spinbox.min_value = 0
		spinbox.step = 1
		spinbox.rounded = true
		spinbox.value = 0
		# The cap is set here and refreshed on every _update_stat_display(),
		# which also clamps it against what is left in the pool.
		spinbox.max_value = _allocation_policy.per_stat_cap
		spinbox.custom_minimum_size = TOUCH_TARGET_SIZE
		spinbox.focus_mode = Control.FOCUS_ALL
		row.add_child(spinbox)

		_stat_controls_container.add_child(row)
		_stat_controls[stat_name] = row


## Turn a stat's StringName into something a player can read:
## &"attack_damage" -> "Attack Damage".
func _stat_display_name(stat_name: StringName) -> String:
	var words := String(stat_name).split("_", false)
	var parts: Array[String] = []
	for word in words:
		parts.append(word.capitalize())
	return " ".join(parts)


## Populate the discipline option buttons with the six discipline choices.
## Sets all Disciplines available initially; re-filtering happens when
## the other discipline changes.
func _populate_discipline_options() -> void:
	if _primary_discipline_option == null or _secondary_discipline_option == null:
		return

	# Clear any existing items
	_primary_discipline_option.clear()
	_secondary_discipline_option.clear()

	# Add all six discipline options to both pickers
	# Note: OptionButton.add_item() takes a variant as metadata, but we pass
	# ints (discipline enum values) which OptionButton will use internally.
	for i in range(MobaAbility.Discipline.values().size()):
		var discipline_name = DISCIPLINE_NAMES[i] if i < DISCIPLINE_NAMES.size() else str(i)
		_primary_discipline_option.add_item(discipline_name)
		_primary_discipline_option.set_item_metadata(_primary_discipline_option.item_count - 1, i)
		_secondary_discipline_option.add_item(discipline_name)
		_secondary_discipline_option.set_item_metadata(
			_secondary_discipline_option.item_count - 1, i
		)

	# Set initial selections (Warrior primary, Guardian secondary - matching melee_bruiser_build.tres)
	_primary_discipline_option.select(0)
	_secondary_discipline_option.select(1)

	# Ensure touch-sized tap targets
	_primary_discipline_option.custom_minimum_size = TOUCH_TARGET_SIZE
	_secondary_discipline_option.custom_minimum_size = TOUCH_TARGET_SIZE

	# Enable focus navigation (needed for gamepad support)
	_primary_discipline_option.focus_mode = Control.FOCUS_ALL
	_secondary_discipline_option.focus_mode = Control.FOCUS_ALL


## Populate weapon option button by scanning rules/data/weapons/ for all .tres files.
## Weapons are not filtered by Discipline (per the Scope).
func _populate_weapon_options() -> void:
	if _weapon_option == null:
		return

	_weapon_option.clear()
	_weapon_cache.clear()

	var dir = DirAccess.open(MobaRules.DATA_ROOT + "weapons/")
	if dir == null:
		push_error("Failed to open weapons directory: %s" % (MobaRules.DATA_ROOT + "weapons/"))
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	var index := 0

	while file_name != "":
		# Process .tres files only
		if not file_name.begins_with(".") and file_name.ends_with(".tres"):
			var file_path = (MobaRules.DATA_ROOT + "weapons/").path_join(file_name)
			var weapon = ResourceLoader.load(file_path) as MobaWeapon

			if weapon != null:
				# Use the file name (without extension) as the display name
				var display_name := file_name.trim_suffix(".tres")
				_weapon_option.add_item(display_name, index)
				_weapon_cache[index] = weapon
				index += 1

		file_name = dir.get_next()

	if index == 0:
		_weapon_option.add_item("(No weapons available)", -1)

	_weapon_option.select(0)
	_weapon_option.custom_minimum_size = TOUCH_TARGET_SIZE
	_weapon_option.focus_mode = Control.FOCUS_ALL

	# select() does not emit item_selected, so nothing here would reach
	# _on_weapon_changed and the build would keep a null weapon while the picker
	# read "longsword". With one weapon shipped there is no second entry to
	# select, so the signal could never fire and every hand-built character
	# saved weaponless -- MobaBuildValidator has no opinion on a null weapon
	# (D3), so nothing downstream caught it either.
	_apply_selected_weapon()


## Populate template load button's options (not a full menu, just a button
## that triggers a template picker). Called to cache templates for later.
func _populate_template_options() -> void:
	_templates_cache.clear()

	var dir = DirAccess.open(TEMPLATES_DIR)
	if dir == null:
		# Templates directory not found is not an error; just means no templates
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		# Process .tres files only
		if not file_name.begins_with(".") and file_name.ends_with(".tres"):
			var file_path = TEMPLATES_DIR.path_join(file_name)
			var template = ResourceLoader.load(file_path) as MobaCharacterBuild

			if template != null:
				var display_name := file_name.trim_suffix(".tres")
				_templates_cache[display_name] = template

		file_name = dir.get_next()

	# If no templates found, disable the load template button
	if _templates_cache.is_empty():
		_load_template_button.disabled = true


## Populate the template OptionButton with all available templates from cache.
func _populate_template_option_button() -> void:
	if _template_option == null:
		return

	_template_option.custom_minimum_size = TOUCH_TARGET_SIZE
	_template_option.focus_mode = Control.FOCUS_ALL

	_template_option.clear()

	# Item 0 is always a placeholder, and real templates start at 1, because
	# _on_load_template() treats index 0 as "nothing chosen yet". Filling from
	# index 0 instead put the first template in the slot the handler refuses --
	# with a single shipped template that is every template, so the Load button
	# answered "Please select a template" no matter what the player did.
	_template_option.add_item("(Select a template)")

	_template_option.disabled = _templates_cache.is_empty()
	if _templates_cache.is_empty():
		_template_option.select(0)
		return

	var index := 1
	for template_name in _templates_cache:
		_template_option.add_item(template_name)
		_template_option.set_item_metadata(index, template_name)
		index += 1

	_template_option.select(0)


## Populate the saved characters OptionButton with all saved characters.
func _populate_saved_characters_option() -> void:
	if _saved_character_option == null:
		return

	# Presentation setup happens before the empty-list branch below. Leaving it
	# after an early return meant a fresh install -- the one case where there
	# are no saved characters yet -- got a picker with no touch-sized tap
	# target, which is exactly the "operable by touch" bar this screen has to
	# clear.
	_saved_character_option.custom_minimum_size = TOUCH_TARGET_SIZE
	_saved_character_option.focus_mode = Control.FOCUS_ALL

	_saved_character_option.clear()
	_saved_character_option.add_item("(No saved characters)")

	var saved_chars = CharacterStorage.list_characters()

	# Assigned on both branches, never only on one: this runs again after every
	# successful save, so a picker disabled while the directory was empty has
	# to re-enable itself once the first character lands in it.
	_saved_character_option.disabled = saved_chars.is_empty()
	if saved_chars.is_empty():
		_saved_character_option.select(0)
		return

	var index := 1
	for char_name in saved_chars:
		_saved_character_option.add_item(char_name)
		_saved_character_option.set_item_metadata(index, char_name)
		index += 1

	_saved_character_option.select(0)


## Populate the ability cache by scanning rules/data/abilities/ and indexing
## by discipline. This allows quick O(1) lookup when filtering abilities for
## discipline changes.
func _populate_ability_cache() -> void:
	_abilities_by_discipline.clear()

	# Initialize arrays for each discipline
	for d in range(MobaAbility.Discipline.values().size()):
		_abilities_by_discipline[d] = []

	# Scan the abilities directory and load each resource
	var dir = DirAccess.open(MobaRules.DATA_ROOT + "abilities/")
	if dir == null:
		push_error("Failed to open abilities directory: %s" % (MobaRules.DATA_ROOT + "abilities/"))
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		# Process .tres files only
		if not file_name.begins_with(".") and file_name.ends_with(".tres"):
			var ability_path = (MobaRules.DATA_ROOT + "abilities/").path_join(file_name)
			var ability = ResourceLoader.load(ability_path) as MobaAbility

			if ability != null:
				var discipline = ability.discipline
				# Index by the ability's authoritative id field, not the filename
				_abilities_by_discipline[discipline].append(ability.id)

		file_name = dir.get_next()


## Connect all signal handlers for interactive controls.
func _connect_signals() -> void:
	if _primary_discipline_option == null or _secondary_discipline_option == null:
		return

	# Discipline changes trigger ability re-filtering
	_primary_discipline_option.item_selected.connect(_on_primary_discipline_changed)
	_secondary_discipline_option.item_selected.connect(_on_secondary_discipline_changed)

	# Stat controls emit signals when values change
	for stat_name in _stat_controls:
		var row = _stat_controls[stat_name] as Control
		var spinbox = row.get_node(^"Spinbox") as SpinBox
		if spinbox != null:
			spinbox.value_changed.connect(_on_stat_value_changed.bindv([stat_name]))

	# Action abilities can be changed
	for i in range(_action_ability_options.size()):
		if _action_ability_options[i] != null:
			_action_ability_options[i].item_selected.connect(
				_on_action_ability_changed.bindv([i + 1])
			)

	# Passive ability can be changed
	if _passive_ability_option != null:
		_passive_ability_option.item_selected.connect(_on_passive_ability_changed)

	# Weapon selection
	if _weapon_option != null:
		_weapon_option.item_selected.connect(_on_weapon_changed)

	# Save and load buttons
	if _save_button != null:
		_save_button.pressed.connect(_on_save)
	if _cancel_button != null:
		_cancel_button.pressed.connect(_on_cancel)
	if _load_template_button != null:
		_load_template_button.pressed.connect(_on_load_template)
	if _load_character_button != null:
		_load_character_button.pressed.connect(_on_load_character)


## Update the stat display: show total points spent vs. available pool,
## and constrain each stat spinbox's max value to prevent overspend.
## This is a UX affordance: MobaBuildValidator.validate() is the sole legality authority.
func _update_stat_display() -> void:
	if _stat_controls.is_empty() or _stat_points_label == null:
		return

	# Writing spinbox.max_value below can clamp that spinbox's value, which
	# emits value_changed, which re-enters here through
	# _on_stat_value_changed(). It converges today because every pass writes
	# the spinboxes straight from _current_build rather than from what it
	# reads back off them -- but that is a property of the current handler,
	# not of the design, and the guard costs one bool.
	if _refreshing_stats:
		return
	_refreshing_stats = true

	# Calculate total spent
	var total_spent := 0
	for stat_name in _current_build.stat_allocation:
		var points: int = _current_build.stat_allocation[stat_name]
		if points > 0:
			total_spent += points

	# Calculate remaining points
	var points_remaining = _allocation_policy.total_points - total_spent

	# Update each spinbox's range and current value
	for stat_name in _stat_controls:
		var row = _stat_controls[stat_name] as Control
		var spinbox = row.get_node(^"Spinbox") as SpinBox

		# Ensure spinbox has focus mode set
		spinbox.focus_mode = Control.FOCUS_ALL

		# Get current value before changing max (to avoid jumping)
		var current_value: int = _current_build.stat_allocation.get(stat_name, 0)

		# Clamp the max to prevent exceeding pool:
		# max = min(per_stat_cap, current_value + points_remaining)
		# This allows incrementing within remaining pool while respecting the cap
		var max_for_this_stat = mini(
			_allocation_policy.per_stat_cap, current_value + points_remaining
		)
		spinbox.max_value = max_for_this_stat

		# Set the current value (or 0 if not allocated)
		spinbox.value = current_value

	# Label written from the allocation as it stands AFTER the loop, not the
	# total read before it. A clamp inside the loop reaches _current_build
	# through _on_stat_value_changed() while the guard above suppresses the
	# nested refresh, so a label written up front could describe an allocation
	# that no longer exists by the time the loop ends.
	var spent_after := 0
	for stat_name in _current_build.stat_allocation:
		var points: int = _current_build.stat_allocation[stat_name]
		if points > 0:
			spent_after += points

	_stat_points_label.text = (
		"Stat Points: %d / %d (remaining: %d)"
		% [
			spent_after,
			_allocation_policy.total_points,
			_allocation_policy.total_points - spent_after
		]
	)

	_refreshing_stats = false


## Rebuild the ability options for both action and passive slots.
## Called when disciplines change to filter abilities by discipline membership.
func _update_ability_options() -> void:
	if _primary_discipline_option == null or _secondary_discipline_option == null:
		return

	var primary_disc = _primary_discipline_option.get_selected_id()
	var secondary_disc = _secondary_discipline_option.get_selected_id()

	# Collect all valid ability ids for these two disciplines
	var valid_abilities: Array[String] = []
	valid_abilities.append_array(_abilities_by_discipline.get(primary_disc, []))
	valid_abilities.append_array(_abilities_by_discipline.get(secondary_disc, []))

	# Remove duplicates (in case same ability somehow belongs to both)
	valid_abilities = _unique_array(valid_abilities)

	# Update action ability options
	for i in range(_action_ability_options.size()):
		var option = _action_ability_options[i]
		option.clear()
		option.add_item("(None)")
		option.set_item_metadata(0, "")

		var idx := 1
		for ability_id in valid_abilities:
			var ability = MobaAbilityLibrary.get_ability(StringName(ability_id))
			if ability != null:
				option.add_item(ability.name)
				option.set_item_metadata(idx, ability_id)
				idx += 1

		# Set to current value if it's still valid, else clear BOTH the picker
		# and the slot behind it. Resetting only the picker left the build
		# holding an ability from the Discipline the player just navigated away
		# from: Save then refused with "All abilities must belong to the primary
		# or secondary Discipline" against a form showing no such ability, which
		# is an error with nothing the player can act on.
		var current_ability_id = _current_build.loadout.get_action_slot(i + 1)
		if not _select_option_by_data(option, current_ability_id):
			_current_build.loadout.set_action_slot(i + 1, "")

		option.custom_minimum_size = TOUCH_TARGET_SIZE
		option.focus_mode = Control.FOCUS_ALL

	# Update passive ability option
	_passive_ability_option.clear()
	_passive_ability_option.add_item("(None)")
	_passive_ability_option.set_item_metadata(0, "")

	var idx := 1
	for ability_id in valid_abilities:
		var ability = MobaAbilityLibrary.get_ability(StringName(ability_id))
		if ability != null:
			_passive_ability_option.add_item(ability.name)
			_passive_ability_option.set_item_metadata(idx, ability_id)
			idx += 1

	# Same for the passive slot, and for the same reason.
	var current_passive_id = _current_build.loadout.get_passive_slot()
	if not _select_option_by_data(_passive_ability_option, current_passive_id):
		_current_build.loadout.set_passive_slot("")

	_passive_ability_option.custom_minimum_size = TOUCH_TARGET_SIZE
	_passive_ability_option.focus_mode = Control.FOCUS_ALL


## Helper: Select an option by data value, returning true if found, false otherwise.
func _select_option_by_data(option: OptionButton, data_value: String) -> bool:
	for i in range(option.item_count):
		if option.get_item_metadata(i) == data_value:
			option.select(i)
			return true

	# Not found, select the first (None) option
	option.select(0)
	return false


## Helper: Return a duplicate array with duplicates removed (order may not be preserved).
func _unique_array(arr: Array[String]) -> Array[String]:
	var seen := {}
	var result: Array[String] = []
	for item in arr:
		if item not in seen:
			seen[item] = true
			result.append(item)
	return result


## Signal handler: Primary discipline changed.
func _on_primary_discipline_changed(_index: int) -> void:
	_current_build.primary_discipline = MobaAbility.Discipline.values()[
		_primary_discipline_option.get_selected_id()
	]
	_error_label.text = ""
	_update_ability_options()


## Signal handler: Secondary discipline changed.
func _on_secondary_discipline_changed(_index: int) -> void:
	_current_build.secondary_discipline = MobaAbility.Discipline.values()[
		_secondary_discipline_option.get_selected_id()
	]
	_error_label.text = ""
	_update_ability_options()


## Signal handler: Stat allocation spinbox changed.
func _on_stat_value_changed(value: float, stat_name: StringName) -> void:
	var int_value = int(value)

	# Store in the build
	if int_value > 0:
		_current_build.stat_allocation[stat_name] = int_value
	else:
		_current_build.stat_allocation.erase(stat_name)

	# Update display to show new total
	_update_stat_display()
	_error_label.text = ""


## Signal handler: Action ability option changed.
## Handles duplicate ability rejection by reverting selection if set_action_slot fails.
func _on_action_ability_changed(_index: int, slot: int) -> void:
	var option = _action_ability_options[slot - 1]
	var ability_id = option.get_selected_metadata()
	var old_ability_id = _current_build.loadout.get_action_slot(slot)

	# Try to set the ability. If it's a duplicate, loadout will reject it with push_error.
	_current_build.loadout.set_action_slot(slot, ability_id)

	# Check if the assignment actually took (it won't if it was a duplicate)
	if _current_build.loadout.get_action_slot(slot) != ability_id:
		# Revert the UI selection to what was actually set
		_select_option_by_data(option, old_ability_id)
		_error_label.text = "That ability is already selected in another slot."
		return

	_error_label.text = ""


## Signal handler: Passive ability option changed.
func _on_passive_ability_changed(_index: int) -> void:
	var ability_id = _passive_ability_option.get_selected_metadata()
	_current_build.loadout.set_passive_slot(ability_id)
	_error_label.text = ""


## Signal handler: Weapon option changed.
func _on_weapon_changed(_index: int) -> void:
	_apply_selected_weapon()
	_error_label.text = ""


## Copy whatever the weapon picker currently shows into the working build.
## The single place the picker's selection becomes build state, so the
## populate path and the player's own selection cannot disagree.
func _apply_selected_weapon() -> void:
	if _weapon_option == null or _current_build == null:
		return

	var weapon = _weapon_cache.get(_weapon_option.get_selected_id(), null) as MobaWeapon
	if weapon != null:
		_current_build.loadout.weapon = weapon


## Signal handler: Load template button pressed.
## Loads the selected template from the OptionButton into the form.
func _on_load_template() -> void:
	# get_selected()/get_selected_metadata(), not the id-keyed pair: metadata is
	# indexed by position. The two coincide only because every item here is
	# added without an explicit id. Item 0 is the "(Select a template)"
	# placeholder and carries no metadata.
	if _template_option == null or _template_option.get_selected() < 1:
		_error_label.text = "Please select a template."
		return

	var template_name = _template_option.get_selected_metadata()
	var template = _templates_cache.get(template_name, null)
	if template == null:
		_error_label.text = "Template not found."
		return

	_load_template(template)


## Signal handler: Load character button pressed.
## Loads the selected saved character from the OptionButton into the form.
func _on_load_character() -> void:
	# Index, not id. add_item() without an explicit id makes the two equal here,
	# so reading metadata by id happens to work today -- but get_item_metadata()
	# is indexed by position, and the two diverge the moment any item is added
	# with an id of its own. Item 0 is the "(No saved characters)" placeholder
	# and carries no metadata.
	if _saved_character_option == null or _saved_character_option.get_selected() < 1:
		_error_label.text = "Please select a saved character."
		return

	var char_name = _saved_character_option.get_selected_metadata()
	var build = CharacterStorage.load_character(char_name)
	if build == null:
		_error_label.text = "Failed to load character."
		return

	# Re-saving updates this same character because _on_save() derives the
	# filename from character_name, which _load_template() has just restored.
	# There is deliberately no separate "file being edited" handle: a second
	# identity for the same character is how a rename silently forks one saved
	# character into two.
	_load_template(build)


## Load a template build into the form, pre-filling all fields.
## The player can then save unmodified or edit further.
func _load_template(template: MobaCharacterBuild) -> void:
	if template == null:
		_error_label.text = "Failed to load template."
		return

	# Copy all fields from template to current build
	_current_build.character_name = template.character_name
	_current_build.primary_discipline = template.primary_discipline
	_current_build.secondary_discipline = template.secondary_discipline
	_current_build.stat_allocation = template.stat_allocation.duplicate()
	_current_build.loadout = (
		template.loadout.duplicate() if template.loadout != null else MobaLoadout.new()
	)

	# Update all UI elements to reflect the template
	_character_name_input.text = _current_build.character_name

	# Update disciplines
	for i in range(MobaAbility.Discipline.values().size()):
		if MobaAbility.Discipline.values()[i] == _current_build.primary_discipline:
			_primary_discipline_option.select(i)
			break

	for i in range(MobaAbility.Discipline.values().size()):
		if MobaAbility.Discipline.values()[i] == _current_build.secondary_discipline:
			_secondary_discipline_option.select(i)
			break

	# Update stats
	_update_stat_display()

	# Update weapon. Matched on resource_path rather than by comparing Resource
	# instances: a build loaded from user:// resolves its weapon through
	# ResourceLoader, which usually hands back the very object already in
	# _weapon_cache but is not contractually required to. On a cache miss an
	# identity test finds nothing, leaves the picker showing item 0, and puts
	# the screen back in the displayed-vs-saved split that the select()/
	# item_selected fix removed.
	var equipped_weapon: MobaWeapon = _current_build.loadout.weapon
	if equipped_weapon != null:
		var matched := false
		for cached_id in _weapon_cache:
			var cached: MobaWeapon = _weapon_cache[cached_id]
			if cached != null and cached.resource_path == equipped_weapon.resource_path:
				_weapon_option.select(_weapon_option.get_item_index(cached_id))
				matched = true
				break

		if not matched:
			# The build carries a weapon this screen cannot offer. Keep the
			# build's weapon -- it is the saved truth -- and say so rather than
			# letting the picker imply a weapon that is not equipped.
			_error_label.text = (
				"This character's weapon is not in %sweapons/ and cannot be shown."
				% MobaRules.DATA_ROOT
			)

	# Update abilities
	_update_ability_options()

	_error_label.text = ""


## Signal handler: Save button pressed.
## Validates the build, surfaces any errors as readable text, and persists
## to disk if valid.
func _on_save() -> void:
	# Read character name from input
	_current_build.character_name = _character_name_input.text.strip_edges()

	if _current_build.character_name.is_empty():
		_error_label.text = "Character name is required."
		return

	# Validate the build using the authoritative validator
	var failure_reason := MobaBuildValidator.validate(_current_build, _allocation_policy)

	if failure_reason != &"":
		# Map the failure constant to human-readable text
		var failure_messages = _get_failure_messages()
		var message = failure_messages.get(
			failure_reason, "Unknown validation error: %s" % failure_reason
		)
		_error_label.text = message
		return

	# Sanitize the filename: remove invalid characters and path separators
	var file_name = _sanitize_filename(_current_build.character_name)
	if file_name.is_empty():
		_error_label.text = (
			"Character name contains invalid characters. "
			+ "Use only letters, numbers, and spaces."
		)
		return

	if CharacterStorage.save_character(_current_build, file_name):
		# Refresh the picker so the character just saved is immediately
		# loadable. Without this the list only ever reflects what was on disk
		# when the screen opened, and a player who saves and then tries to
		# reload their character is told there are none.
		_populate_saved_characters_option()
		_error_label.text = "Saved successfully."
	else:
		_error_label.text = "Failed to save character."


## Signal handler: Cancel button pressed.
## Return to the main menu.
func _on_cancel() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


## Helper: Sanitize a filename by removing invalid characters.
## Returns empty string if the name contains no valid characters.
func _sanitize_filename(name: String) -> String:
	# Allow only alphanumeric, spaces, and underscores
	var sanitized := ""
	for char in name:
		if (
			(char >= "a" and char <= "z")
			or (char >= "A" and char <= "Z")
			or (char >= "0" and char <= "9")
			or char == " "
			or char == "_"
		):
			sanitized += char

	return sanitized.strip_edges()


## Helper: Accept the ui_cancel action to close this screen.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
