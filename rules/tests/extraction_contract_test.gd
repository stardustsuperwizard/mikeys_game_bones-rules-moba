## Extraction contract test for the rules/ module.
##
## Walks every .gd file under rules/ and asserts that none of them reference
## the game-layer paths that are forbidden by the extraction contract:
##   res://scripts/    res://scenes/    res://resources/
##
## Forbidden strings are assembled at runtime from parts so that this source
## file does not itself contain the literal forbidden strings and therefore
## cannot falsely trigger its own check.
##
## Run headless:
##   godot --headless --script rules/tests/extraction_contract_test.gd

extends SceneTree

func _init() -> void:
	_run_contract_check()
	quit()


func _run_contract_check() -> void:
	# Assemble forbidden patterns at runtime to avoid literal matches in this file.
	var forbidden: Array[String] = [
		"res://" + "scripts/",
		"res://" + "scenes/",
		"res://" + "resources/",
	]

	var self_path: String = get_script().resource_path

	var violations: int = 0
	var files: Array[String] = _collect_gd_files("res://rules")

	for file_path in files:
		# Skip this test file itself.
		if file_path == self_path:
			continue

		var text: String = FileAccess.get_file_as_string(file_path)
		if text.is_empty() and FileAccess.get_open_error() != OK:
			push_error("ExtractionContractTest: could not read " + file_path)
			violations += 1
			continue

		var lines: PackedStringArray = text.split("\n")
		for line_index in range(lines.size()):
			var line: String = lines[line_index]
			for pattern in forbidden:
				if line.contains(pattern):
					var msg: String = (
						"FAIL  extraction contract violated\n"
						+ "      file:    " + file_path + "\n"
						+ "      line:    " + str(line_index + 1) + "\n"
						+ "      pattern: " + pattern + "\n"
						+ "      content: " + line.strip_edges()
					)
					print(msg)
					push_error(msg)
					violations += 1

	if violations == 0:
		print("PASS  extraction contract — no forbidden references found in rules/")
	else:
		assert(false, "ExtractionContractTest: " + str(violations) + " violation(s) found — see output above.")


## Recursively collects all .gd file paths under `root_path`.
func _collect_gd_files(root_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir: DirAccess = DirAccess.open(root_path)
	if dir == null:
		push_error("ExtractionContractTest: cannot open directory " + root_path)
		return result

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path: String = root_path + "/" + entry
		if dir.current_is_dir():
			result.append_array(_collect_gd_files(full_path))
		elif entry.ends_with(".gd"):
			result.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return result
