## Headless export tool for MobaAbility and MobaPassive resources to canonical JSON.
##
## Usage:
##   godot --headless --path . -s rules/tools/export_ability_data.gd
##
## Outputs:
##   - rules/data/generated/abilities.json
##   - rules/data/generated/passives.json
##
## Exits with non-zero status on any error.

extends SceneTree

# Preload the resource classes so they're available for loading .tres files
const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaPassive = preload("res://rules/abilities/moba_passive.gd")
const MobaStatModifier = preload("res://rules/effects/moba_stat_modifier.gd")
const MobaCrowdControlSpec = preload("res://rules/effects/moba_crowd_control_spec.gd")

const ABILITIES_DIR := "res://rules/data/abilities/"
const PASSIVES_DIR := "res://rules/data/passives/"
const GENERATED_DIR := "res://rules/data/generated/"
const ABILITIES_OUT := "res://rules/data/generated/abilities.json"
const PASSIVES_OUT := "res://rules/data/generated/passives.json"

var exit_code := 0
var has_run := false


func _process(_delta: float) -> bool:
	if not has_run:
		has_run = true
		_run_export()
	return false


func _run_export() -> void:
	if not DisplayServer.get_name() == "headless":
		printerr("ERROR: This tool must be run in headless mode")
		exit_code = 1
		_quit()
		return

	# Ensure output directory exists
	var abs_generated_dir = ProjectSettings.globalize_path(GENERATED_DIR)
	if not DirAccess.dir_exists_absolute(abs_generated_dir):
		var err = DirAccess.make_dir_recursive_absolute(abs_generated_dir)
		if err != OK:
			printerr("ERROR: Failed to create %s: %s" % [GENERATED_DIR, error_string(err)])
			exit_code = 1
			_quit()
			return

	# Export abilities
	var abilities = _load_resources(ABILITIES_DIR, "MobaAbility")
	var ability_data: Array = []
	for ability in abilities:
		ability_data.append(_serialize_ability(ability))

	if exit_code != 0:
		_quit()
		return

	# Export passives
	var passives = _load_resources(PASSIVES_DIR, "MobaPassive")
	var passive_data: Array = []
	for passive in passives:
		passive_data.append(_serialize_passive(passive))

	if exit_code != 0:
		_quit()
		return

	# Sort by id for deterministic output
	ability_data.sort_custom(func(a: Variant, b: Variant) -> bool: return a["id"] < b["id"])
	passive_data.sort_custom(func(a: Variant, b: Variant) -> bool: return a["id"] < b["id"])

	# Write abilities JSON
	var ability_json = JSON.stringify(ability_data)
	if not _write_canonical_json(ABILITIES_OUT, ability_data):
		exit_code = 1
		_quit()
		return

	# Write passives JSON
	if not _write_canonical_json(PASSIVES_OUT, passive_data):
		exit_code = 1
		_quit()
		return

	print(
		(
			"Successfully exported %d abilities and %d passives"
			% [ability_data.size(), passive_data.size()]
		)
	)
	_quit()


func _load_resources(dir_path: String, resource_type_name: String) -> Array:
	var resources: Array = []
	var dir = DirAccess.open(dir_path)

	if dir == null:
		# Directory doesn't exist yet, return empty array
		return resources

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not file_name.begins_with(".") and file_name.ends_with(".tres"):
			var full_path = dir_path.path_join(file_name)
			var resource = ResourceLoader.load(full_path)
			if resource != null and resource.get_class() == resource_type_name:
				resources.append(resource)
			elif resource == null:
				printerr("ERROR: Failed to load resource from %s" % [full_path])
				exit_code = 1
			elif resource.get_class() != resource_type_name:
				printerr(
					(
						"ERROR: %s is not a %s resource (got %s)"
						% [full_path, resource_type_name, resource.get_class()]
					)
				)
				exit_code = 1

		file_name = dir.get_next()

	return resources


func _serialize_ability(ability: MobaAbility) -> Dictionary:
	var data := {
		"id": ability.id,
		"name": ability.name,
		"discipline": _enum_to_string(MobaAbility.Discipline.keys(), ability.discipline),
		"targeting_type": _enum_to_string(MobaAbility.TargetingType.keys(), ability.targeting_type),
		"aim_assist": _enum_to_string(MobaAbility.AimAssist.keys(), ability.aim_assist),
		"aim_cone_degrees": ability.aim_cone_degrees,
		"magnetism": ability.magnetism,
		"acquisition_range": ability.acquisition_range,
		"damage_type": _enum_to_string(MobaAbility.DamageType.keys(), ability.damage_type),
		"base_damage": ability.base_damage,
		"scaling": ability.scaling,
		"resource_cost": ability.resource_cost,
		"cooldown": ability.cooldown,
		"cast_time": ability.cast_time,
		"channel_duration": ability.channel_duration,
		"channel_tick_interval": ability.channel_tick_interval,
		"range": ability.range,
		"projectile_speed": ability.projectile_speed,
		"area_radius": ability.area_radius,
		"duration": ability.duration,
		"charges": ability.charges,
		"usable_in_air": ability.usable_in_air,
		"touch_viable": ability.touch_viable,
		"crowd_control":
		null if ability.crowd_control == null else _serialize_crowd_control(ability.crowd_control),
		"buffs": [],
		"debuffs": [],
		"max_stacks": ability.max_stacks,
		"cancellable_by_movement": ability.cancellable_by_movement,
		"cancellable_by_hard_cc": ability.cancellable_by_hard_cc,
		"refund_resource_on_cancel": ability.refund_resource_on_cancel,
		"on_cancel": _enum_to_string(MobaAbility.OnCancel.keys(), ability.on_cancel),
		"on_channel_break":
		_enum_to_string(MobaAbility.OnChannelBreak.keys(), ability.on_channel_break),
		"heal_amount": ability.heal_amount,
		"shield_amount": ability.shield_amount,
		"affects_caster": ability.affects_caster,
		"target_allegiance":
		_enum_to_string(MobaAbility.TargetAllegiance.keys(), ability.target_allegiance),
	}

	# Serialize buffs
	for buff in ability.buffs:
		data["buffs"].append(_serialize_stat_modifier(buff))

	# Serialize debuffs
	for debuff in ability.debuffs:
		data["debuffs"].append(_serialize_stat_modifier(debuff))

	return data


func _serialize_passive(passive: MobaPassive) -> Dictionary:
	var data := {
		"id": passive.id,
		"name": passive.name,
		"discipline": _enum_to_string(MobaPassive.Discipline.keys(), passive.discipline),
		"trigger": passive.trigger,
		"effect": null if passive.effect == null else _serialize_stat_modifier(passive.effect),
	}

	return data


func _serialize_stat_modifier(modifier: MobaStatModifier) -> Dictionary:
	var data := {
		"stat": modifier.stat,
		"amount": modifier.amount,
		"is_percentage": modifier.is_percentage,
		"duration": modifier.duration,
		"stacking": _enum_to_string(MobaStatModifier.Stacking.keys(), modifier.stacking),
		"max_stacks": modifier.max_stacks,
	}

	return data


func _serialize_crowd_control(cc: MobaCrowdControlSpec) -> Dictionary:
	var data := {
		"type": _enum_to_string(MobaCrowdControlSpec.CCType.keys(), cc.type),
		"magnitude": cc.magnitude,
		"duration": cc.duration,
		"affected_by_tenacity": cc.affected_by_tenacity,
	}

	return data


func _enum_to_string(enum_keys: PackedStringArray, enum_value: int) -> String:
	if enum_value < 0 or enum_value >= enum_keys.size():
		printerr("ERROR: Enum value %d out of range for keys: %s" % [enum_value, enum_keys])
		exit_code = 1
		return ""

	return enum_keys[enum_value].to_lower()


func _write_canonical_json(file_path: String, data: Variant) -> bool:
	# Create a canonical JSON representation with sorted keys
	var json_str = _to_canonical_json(data)

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		printerr(
			(
				"ERROR: Failed to open %s for writing: %s"
				% [file_path, error_string(FileAccess.get_open_error())]
			)
		)
		return false

	file.store_string(json_str)
	return true


func _to_canonical_json(data: Variant, indent_level: int = 0) -> String:
	var result: String

	match typeof(data):
		TYPE_NIL:
			result = "null"
		TYPE_BOOL:
			result = "true" if data else "false"
		TYPE_INT:
			result = str(data)
		TYPE_FLOAT:
			# Format floats consistently: avoid scientific notation for small numbers
			# Round to reasonable precision to avoid floating point artifacts
			result = "%.17g" % data
		TYPE_STRING:
			result = JSON.stringify(data)
		TYPE_ARRAY:
			result = _array_to_canonical_json(data, indent_level)
		TYPE_DICTIONARY:
			result = _dict_to_canonical_json(data, indent_level)
		_:
			# Fallback to JSON.stringify for unknown types
			result = JSON.stringify(data)

	return result


func _array_to_canonical_json(data: Array, indent_level: int) -> String:
	if data.is_empty():
		return "[]"

	var indent = "\t".repeat(indent_level)
	var next_indent = "\t".repeat(indent_level + 1)
	var items: Array[String] = []

	for item in data:
		items.append(next_indent + _to_canonical_json(item, indent_level + 1))

	return "[\n" + "\n,".join(items) + "\n" + indent + "]"


func _dict_to_canonical_json(data: Dictionary, indent_level: int) -> String:
	if data.is_empty():
		return "{}"

	var indent = "\t".repeat(indent_level)
	var next_indent = "\t".repeat(indent_level + 1)
	# Sort keys for deterministic output
	var keys = data.keys()
	keys.sort()
	var items: Array[String] = []

	for key in keys:
		var value = data[key]
		var value_json = _to_canonical_json(value, indent_level + 1)
		items.append(next_indent + JSON.stringify(key) + ": " + value_json)

	return "{\n" + ",\n".join(items) + "\n" + indent + "}"


func _quit() -> void:
	quit(exit_code)
