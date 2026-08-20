# Extraction contract test for the rules/ module.
#
# Verifies that no file under rules/ references res://scripts/, res://scenes/,
# or res://resources/. This enforces the one-way dependency rule: the game
# depends on rules/, never the reverse.
#
# Run with:
#   godot --headless --path . --script rules/tests/extraction_contract_test.gd
#
# The forbidden strings are assembled at runtime so this file cannot
# trigger its own violation check. The test also skips itself by name.
extends SceneTree

const _RULES_ROOT := "res://rules"
const _SELF_PATH := "res://rules/tests/extraction_contract_test.gd"

var _failures: Array[String] = []

func _initialize() -> void:
	_run()

func _run() -> void:
	# Assemble forbidden prefixes at runtime to avoid matching them literally
	# in this source file.
	var forbidden: Array[String] = []
	forbidden.append("res://" + "scripts/")
	forbidden.append("res://" + "scenes/")
	forbidden.append("res://" + "resources/")

	_scan_dir(_RULES_ROOT, forbidden)

	if _failures.is_empty():
		print("PASS extraction contract: no forbidden references found under rules/")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL " + f)
		quit(1)

func _scan_dir(path: String, forbidden: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path := path + "/" + entry
		if dir.current_is_dir():
			_scan_dir(full_path, forbidden)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn") or entry.ends_with(".tres"):
			_check_file(full_path, forbidden)
		entry = dir.get_next()
	dir.list_dir_end()

func _check_file(path: String, forbidden: Array[String]) -> void:
	if path == _SELF_PATH:
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var lines := text.split("\n")
	for i in lines.size():
		for prefix in forbidden:
			if prefix in lines[i]:
				_failures.append("%s:%d contains forbidden reference '%s'" % [path, i + 1, prefix])
