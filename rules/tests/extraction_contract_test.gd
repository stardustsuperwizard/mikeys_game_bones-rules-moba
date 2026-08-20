# Extraction contract test for rules/
#
# Walks every .gd and .tscn file under rules/ and asserts that none of them
# reference res://scripts/, res://scenes/, or res://resources/.
#
# Run with:
#   godot --headless --path . --script rules/tests/extraction_contract_test.gd
#
# The test skips its own source file so that the forbidden prefix strings
# stored in the constant below do not trigger a false positive.
extends SceneTree

const _SELF_PATH := "res://rules/tests/extraction_contract_test.gd"

# Assembled at runtime so this file itself does not contain the literal
# forbidden strings and self-match on its own content.
var _forbidden: Array[String] = []

var _failures: Array[String] = []

func _initialize() -> void:
	_forbidden = [
		"res://" + "scripts/",
		"res://" + "scenes/",
		"res://" + "resources/",
	]
	_scan_dir("res://rules")
	_finish()


func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		_fail("Could not open directory: %s" % path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := path + "/" + entry
			if dir.current_is_dir():
				_scan_dir(full)
			else:
				_check_file(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _check_file(path: String) -> void:
	var ext := path.get_extension()
	if ext not in ["gd", "tscn", "tres"]:
		return
	if path == _SELF_PATH:
		return
	var text := FileAccess.get_file_as_string(path)
	for forbidden in _forbidden:
		if forbidden in text:
			_find_violations(path, text, forbidden)


func _find_violations(path: String, text: String, forbidden: String) -> void:
	var lines := text.split("\n")
	for i in lines.size():
		if forbidden in lines[i]:
			_fail("%s:%d  references %s" % [path, i + 1, forbidden])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS extraction contract: no outward references found")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL " + f)
		quit(1)
