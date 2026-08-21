## Semantic ability/passive data validator test.
##
## Loads every .tres in rules/data/abilities/ and rules/data/passives/,
## runs the semantic validator over them, and asserts zero problems.

class_name AbilityDataTest

const ValidateAbilityData = preload("res://rules/tools/validate_ability_data.gd")
const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaPassive = preload("res://rules/abilities/moba_passive.gd")

const ABILITIES_DIR := "res://rules/data/abilities/"
const PASSIVES_DIR := "res://rules/data/passives/"

## Run the ability data validation test.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []
	
	# Validate abilities
	var abilities = _load_resources(ABILITIES_DIR, "MobaAbility")
	for ability in abilities:
		var resource_path = ABILITIES_DIR.path_join(ability.resource_path.get_file())
		var violations = ValidateAbilityData.validate_ability(resource_path, ability)
		all_violations.append_array(violations)
	
	# Validate passives
	var passives = _load_resources(PASSIVES_DIR, "MobaPassive")
	for passive in passives:
		var resource_path = PASSIVES_DIR.path_join(passive.resource_path.get_file())
		var violations = ValidateAbilityData.validate_passive(resource_path, passive)
		all_violations.append_array(violations)
	
	if all_violations.is_empty():
		return true
	
	# Print violations
	printerr("\n=== Ability Data Validation Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)
	
	return false

## Load all .tres resources of a specific type from a directory.
static func _load_resources(dir_path: String, resource_type_name: String) -> Array:
	var resources: Array = []
	var dir = DirAccess.open(dir_path)
	
	if dir == null:
		# Directory doesn't exist, return empty array
		return resources
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not file_name.begins_with(".") and file_name.ends_with(".tres"):
			var full_path = dir_path.path_join(file_name)
			var resource = ResourceLoader.load(full_path)
			if resource != null:
				# Check if the resource is of the correct type by checking the script's class name
				var script = resource.get_script()
				if script != null and script.get_global_name() == resource_type_name:
					resources.append(resource)
				elif resource.get_class() == resource_type_name:
					# Fallback for resources without a script
					resources.append(resource)
				else:
					var actual_type = script.get_global_name() if script != null else resource.get_class()
					printerr("ERROR: %s is not a %s resource (got %s)" % [full_path, resource_type_name, actual_type])
			else:
				printerr("ERROR: Failed to load resource from %s" % [full_path])
		
		file_name = dir.get_next()
	
	return resources
