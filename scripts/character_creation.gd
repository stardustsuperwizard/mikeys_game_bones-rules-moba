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

## Build validator failure constants mapped to human-readable messages.
## These match the StringName constants from MobaBuildValidator exactly.
const FAILURE_MESSAGES := {
	&"disciplines_not_distinct": "Primary and secondary Disciplines must be different.",
	&"loadout_invalid": "Loadout configuration is invalid.",
	&"unknown_ability": "One of the selected abilities does not exist.",
	&"ability_outside_disciplines":
	"All abilities must belong to the primary or secondary Discipline.",
	&"stat_allocation_negative": "Stat allocations cannot be negative.",
	&"stat_allocation_unknown_stat": "One or more allocated stats are invalid.",
	&"stat_allocation_exceeds_per_stat_max": "One or more stats exceeds the per-stat maximum.",
	&"stat_pool_overspent": "Total stat points exceed the pool.",
}

# Loaded stat allocation policy (Authoritative source for pool size and per-stat cap)
var _allocation_policy: MobaStatAllocationPolicy

# Currently edited build (the form's working copy)
var _current_build: MobaCharacterBuild

# Name of the file being edited (if loaded from saved character, for re-save)
var _edit_file_name: String = ""

# Resolved control node references
var _primary_discipline_option: OptionButton
var _secondary_discipline_option: OptionButton
var _stat_points_label: Label
var _stat_controls: Dictionary  # StringName -> VBoxContainer with label and spinbox
var _weapon_option: OptionButton
var _action_ability_options: Array[OptionButton]  # action_slot_options[0..3]
var _passive_ability_option: OptionButton
var _character_name_input: LineEdit
var _save_button: Button
var _cancel_button: Button
var _load_template_button: Button
var _error_label: Label

# Weapon list cache (file_name -> MobaWeapon resource)
var _weapon_cache: Dictionary = {}

# Available templates cache (file_name -> display_name)
var _templates_cache: Dictionary = {}

# Ability library cache (discipline -> [ability_ids])
var _abilities_by_discipline: Dictionary = {}


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
	_populate_discipline_options()
	_populate_weapon_options()
	_populate_template_options()
	_populate_ability_cache()

	# Connect all signal handlers
	_connect_signals()

	# Set focus to the primary discipline picker for gamepad/keyboard navigation
	if _primary_discipline_option.focus_mode != Control.FOCUS_NONE:
		_primary_discipline_option.grab_focus()

	# Initialize display
	_update_stat_display()
	_update_ability_options()

	# Go back to main menu on cancel
	_cancel_button.pressed.connect(_on_cancel)


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
	_load_template_button = main_container.get_node_or_null(^"TemplateLoadButton") as Button

	_error_label = main_container.get_node_or_null(^"ErrorLabel") as Label

	# Build stat control dictionary. Resolve from a StatControls container
	# that holds one VBox per stat.
	var stat_controls_container = (
		main_container.get_node_or_null(^"StatSection/StatControls") as VBoxContainer
	)
	if stat_controls_container != null and _allocation_policy != null:
		_stat_controls = {}

		for allocatable_stat in _allocation_policy.get_allocatable_stats():
			var stat_vbox = stat_controls_container.get_node_or_null(
				NodePath(str(allocatable_stat))
			)
			if stat_vbox != null:
				_stat_controls[allocatable_stat] = stat_vbox


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


## Populate the ability cache by scanning rules/data/abilities/ and indexing
## by discipline. This allows quick O(1) lookup when filtering abilities for
## discipline changes.
func _populate_ability_cache() -> void:
	_abilities_by_discipline.clear()

	# Initialize arrays for each discipline
	for d in range(MobaAbility.Discipline.values().size()):
		_abilities_by_discipline[d] = []

	# Load all abilities via the library
	MobaAbilityLibrary._ensure_loaded()

	# Iterate through all abilities in the cache and index by discipline
	# Note: MobaAbilityLibrary's cache is static and private, so we need to
	# scan the directory directly like we do for weapons
	var dir = DirAccess.open(MobaRules.DATA_ROOT + "abilities/")
	if dir == null:
		push_error("Failed to open abilities directory: %s" % (MobaRules.DATA_ROOT + "abilities/"))
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		# Process .tres files only
		if not file_name.begins_with(".") and file_name.ends_with(".tres"):
			var file_path = (MobaRules.DATA_ROOT + "abilities/").path_join(file_name)
			var ability = MobaAbilityLibrary.get_ability(StringName(file_name.trim_suffix(".tres")))

			if ability != null:
				var discipline = ability.discipline
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
		var vbox = _stat_controls[stat_name] as VBoxContainer
		var spinbox = vbox.get_node(^"Spinbox") as SpinBox
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

	# Save and load template
	if _save_button != null:
		_save_button.pressed.connect(_on_save)
	if _load_template_button != null:
		_load_template_button.pressed.connect(_on_load_template)


## Update the stat display: show total points spent vs. available pool,
## and constrain each stat spinbox's max value to the per-stat cap.
## Does NOT apply the UI's overspend check to refuse save; that goes
## through MobaBuildValidator.validate() only.
func _update_stat_display() -> void:
	if _stat_controls.is_empty() or _stat_points_label == null:
		return

	# Calculate total spent
	var total_spent := 0
	for stat_name in _current_build.stat_allocation:
		var points: int = _current_build.stat_allocation[stat_name]
		if points > 0:
			total_spent += points

	# Update display label
	_stat_points_label.text = (
		"Stat Points: %d / %d" % [total_spent, _allocation_policy.total_points]
	)

	# Update each spinbox's range and current value
	for stat_name in _stat_controls:
		var vbox = _stat_controls[stat_name] as VBoxContainer
		var spinbox = vbox.get_node(^"Spinbox") as SpinBox

		# Ensure spinbox has focus mode set
		spinbox.focus_mode = Control.FOCUS_ALL

		# Set the max to the per-stat cap
		spinbox.max_value = _allocation_policy.per_stat_cap

		# Set the current value (or 0 if not allocated)
		var current_value: int = _current_build.stat_allocation.get(stat_name, 0)
		spinbox.value = current_value


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

		# Set to current value if it's still valid, else clear
		var current_ability_id = _current_build.loadout.get_action_slot(i + 1)
		_select_option_by_data(option, current_ability_id)

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

	# Set to current value if it's still valid, else clear
	var current_passive_id = _current_build.loadout.get_passive_slot()
	_select_option_by_data(_passive_ability_option, current_passive_id)

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
func _on_action_ability_changed(_index: int, slot: int) -> void:
	var ability_id = _action_ability_options[slot - 1].get_selected_metadata()
	_current_build.loadout.set_action_slot(slot, ability_id)
	_error_label.text = ""


## Signal handler: Passive ability option changed.
func _on_passive_ability_changed(_index: int) -> void:
	var ability_id = _passive_ability_option.get_selected_metadata()
	_current_build.loadout.set_passive_slot(ability_id)
	_error_label.text = ""


## Signal handler: Weapon option changed.
func _on_weapon_changed(index: int) -> void:
	var weapon = _weapon_cache.get(index, null) as MobaWeapon
	if weapon != null:
		_current_build.loadout.weapon = weapon
	_error_label.text = ""


## Signal handler: Load template button pressed.
## Opens a picker to select a template, then pre-fills the form.
func _on_load_template() -> void:
	if _templates_cache.is_empty():
		_error_label.text = "No templates available."
		return

	# For now, simple picker: just load the first template (melee_bruiser_build)
	# In a full implementation, this would be a modal dialog listing all templates
	for template_name in _templates_cache:
		var template = _templates_cache[template_name]
		_load_template(template)
		break  # Load first available template


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

	# Clear edit file name since this is a new character (not loaded from saved)
	_edit_file_name = ""

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

	# Update weapon
	if _current_build.loadout.weapon != null:
		for cached_idx in _weapon_cache:
			if _weapon_cache[cached_idx] == _current_build.loadout.weapon:
				_weapon_option.select(_weapon_option.get_item_index(cached_idx))
				break

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
		var message = FAILURE_MESSAGES.get(
			failure_reason, "Unknown validation error: %s" % failure_reason
		)
		_error_label.text = message
		return

	# Build is valid; persist to disk
	var file_name = _current_build.character_name
	if CharacterStorage.save_character(_current_build, file_name):
		_edit_file_name = file_name
		_error_label.text = "Saved successfully."
	else:
		_error_label.text = "Failed to save character."


## Signal handler: Cancel button pressed.
## Return to the main menu.
func _on_cancel() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


## Helper: Accept the ui_cancel action to close this screen.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_tree().root.set_input_as_handled()
