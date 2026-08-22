## Extraction contract test for the rules module.
##
## Verifies that no files under rules/ contain outward references to
## res://scripts/, res://scenes/, or res://resources/.
##
## The rules module is designed to be extracted wholesale into
## addons/mikeys_game_rules_moba without editing a single file.
## This test enforces the architectural constraint that allows that extraction.
class_name ExtractionContractTest

const RULES_DIR := "res://rules/"
const FORBIDDEN_PREFIXES := ["res://scripts/", "res://scenes/", "res://resources/"]


## Run the extraction contract test.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var violations: Array[String] = []
	var files = _get_files_recursive(RULES_DIR)

	for file_path in files:
		# Skip the test file itself and UID files
		if file_path.ends_with("extraction_contract_test.gd") or file_path.ends_with(".uid"):
			continue

		# Only check GDScript files and data files
		if not (
			file_path.ends_with(".gd")
			or file_path.ends_with(".json")
			or file_path.ends_with(".tres")
		):
			continue

		var content = _read_file(file_path)
		if content.is_empty():
			continue

		# Check for forbidden references
		for forbidden in FORBIDDEN_PREFIXES:
			var lines = content.split("\n")
			for line_num in range(lines.size()):
				var line = lines[line_num]

				# Skip comments: lines starting with # or ## in GDScript
				if file_path.ends_with(".gd"):
					# Remove comments for checking
					var code_part = line
					if "#" in line:
						# Be careful: # in strings should not strip
						# Simple approach: check if this is a pure comment line
						var stripped = line.strip_edges()
						if stripped.begins_with("#"):
							continue  # Skip comment-only lines
						# For inline comments, extract the part before #
						# This is a simplification; a full solution would parse strings
						code_part = line.split("#")[0]

					if forbidden in code_part:
						violations.append("%s:%d: %s" % [file_path, line_num + 1, forbidden])
				else:
					# For JSON and .tres files, check the entire line
					if forbidden in line:
						violations.append("%s:%d: %s" % [file_path, line_num + 1, forbidden])

	if violations.is_empty():
		return true

	# Print violations
	printerr("\n=== Extraction Contract Violations ===")
	printerr(
		"Files in rules/ must not reference res://scripts/, res://scenes/, or res://resources/"
	)
	printerr("")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


## Get all files under a directory recursively.
static func _get_files_recursive(dir_path: String) -> Array:
	var files: Array = []
	var dir = DirAccess.open(dir_path)

	if dir == null:
		return files

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not file_name.begins_with("."):
			var full_path = dir_path.path_join(file_name)

			if dir.current_is_dir():
				files.append_array(_get_files_recursive(full_path))
			else:
				files.append(full_path)

		file_name = dir.get_next()

	return files


## Read file content safely.
static func _read_file(file_path: String) -> String:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
