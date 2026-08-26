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
const FIXTURES_ABILITIES_DIR := "res://rules/tests/fixtures/abilities/"


## Run the ability data validation test.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []
	var test_results: Array[bool] = []

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

	# Test fixture with bad stat modifier
	test_results.append(_test_bad_stat_modifier())

	# Test that sample_complete has no stat-name violations
	test_results.append(_test_sample_complete_no_violations())

	if all_violations.is_empty() and test_results.all(func(x): return x):
		return true

	# Print violations
	printerr("\n=== Ability Data Validation Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Test that bad_stat_modifier.tres produces the expected violation.
static func _test_bad_stat_modifier() -> bool:
	var fixture_path = FIXTURES_ABILITIES_DIR.path_join("bad_stat_modifier.tres")
	var ability = ResourceLoader.load(fixture_path) as MobaAbility

	if ability == null:
		printerr("ERROR: Failed to load fixture %s" % [fixture_path])
		return false

	var violations = ValidateAbilityData.validate_ability(fixture_path, ability)

	# Should have exactly one violation about the unknown stat "attak_damage"
	var expected_violation_found = false
	for violation in violations:
		if violation.contains("attak_damage") and violation.contains("buff"):
			expected_violation_found = true
			break

	if not expected_violation_found:
		printerr(
			(
				(
					"ERROR: bad_stat_modifier.tres produced no violation naming stat"
					+ " 'attak_damage'. Got: %s"
				)
				% [violations]
			)
		)
		return false

	return true


## Test that sample_complete.tres produces no stat-name violations.
static func _test_sample_complete_no_violations() -> bool:
	var fixture_path = FIXTURES_ABILITIES_DIR.path_join("sample_complete.tres")
	var ability = ResourceLoader.load(fixture_path) as MobaAbility

	if ability == null:
		printerr("ERROR: Failed to load fixture %s" % [fixture_path])
		return false

	var violations = ValidateAbilityData.validate_ability(fixture_path, ability)

	# Check that there are no stat-name violations (lines containing "stat is")
	for violation in violations:
		if violation.contains("stat is"):
			printerr(
				(
					"ERROR: sample_complete.tres should not have stat-name violations. Got: %s"
					% [violation]
				)
			)
			return false

	return true


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
					var actual_type = (
						script.get_global_name() if script != null else resource.get_class()
					)
					printerr(
						(
							"ERROR: %s is not a %s resource (got %s)"
							% [full_path, resource_type_name, actual_type]
						)
					)
			else:
				printerr("ERROR: Failed to load resource from %s" % [full_path])

		file_name = dir.get_next()

	return resources
