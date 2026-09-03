## Appearance catalog: loads and validates appearance ids from the catalog data.
##
## Provides safe-by-construction loading: a bad file is reported and excluded,
## never crashes startup. Exposes static query methods to check whether an
## appearance id is legal in each category (helms, chests, color_schemes).
##
## All methods are static, take plain values, and touch no node and no scene tree.
class_name MobaAppearanceCatalog

## The catalog data: {"helms": [...], "chests": [...], "color_schemes": [...]}
static var _catalog: Dictionary = {}

## Whether the catalog has been loaded
static var _loaded: bool = false

## Set when the catalog failed to load
static var load_failed: bool = false

## The problem that caused the most recent load failure, or "" when the catalog
## loaded cleanly.
static var load_error: String = ""


## Ensure the catalog is loaded before use.
static func _ensure_loaded() -> void:
	if _loaded:
		return

	_load_catalog()
	_loaded = true


## Load the appearance catalog from the JSON file.
static func _load_catalog() -> void:
	var json_path = MobaRules.DATA_ROOT + "appearance/catalog.json"
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		_fail("Failed to load appearance catalog at %s" % json_path)
		return

	var content = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		_fail("Failed to parse appearance catalog: %s" % json.get_error_message())
		return

	_parse_catalog(json.data)


## Validate and load the appearance catalog from parsed data.
static func _parse_catalog(data: Variant) -> bool:
	_catalog = {}
	load_failed = false
	load_error = ""

	if data is not Dictionary:
		_fail("Appearance catalog root must be a dictionary")
		return false

	# Validate required keys
	if "helms" not in data or "chests" not in data or "color_schemes" not in data:
		_fail("Appearance catalog must have 'helms', 'chests', and 'color_schemes' keys")
		return false

	# Validate helms
	if data["helms"] is not Array:
		_fail("Appearance catalog 'helms' must be an array")
		return false
	for helm_id in data["helms"]:
		if helm_id is not String:
			_fail("Each helm id must be a string")
			return false

	# Validate chests
	if data["chests"] is not Array:
		_fail("Appearance catalog 'chests' must be an array")
		return false
	for chest_id in data["chests"]:
		if chest_id is not String:
			_fail("Each chest id must be a string")
			return false

	# Validate color_schemes
	if data["color_schemes"] is not Array:
		_fail("Appearance catalog 'color_schemes' must be an array")
		return false
	for scheme_id in data["color_schemes"]:
		if scheme_id is not String:
			_fail("Each color scheme id must be a string")
			return false

	# Store the catalog
	_catalog = {
		"helms": data["helms"], "chests": data["chests"], "color_schemes": data["color_schemes"]
	}

	return true


## Record a load failure: report it loudly and leave it detectable.
static func _fail(message: String) -> void:
	push_error(message)
	load_failed = true
	load_error = message


## Check whether a helm id is legal (empty or in the catalog).
## Returns true if the id is empty or present in the catalog.
static func is_helm_legal(helm_id: StringName) -> bool:
	_ensure_loaded()

	if load_failed:
		push_error("Cannot check helm legality: catalog failed to load")
		return false

	if helm_id == "":
		return true

	return helm_id in _catalog.get("helms", [])


## Check whether a chest id is legal (empty or in the catalog).
## Returns true if the id is empty or present in the catalog.
static func is_chest_legal(chest_id: StringName) -> bool:
	_ensure_loaded()

	if load_failed:
		push_error("Cannot check chest legality: catalog failed to load")
		return false

	if chest_id == "":
		return true

	return chest_id in _catalog.get("chests", [])


## Check whether a color scheme id is legal (empty or in the catalog).
## Returns true if the id is empty or present in the catalog.
static func is_color_scheme_legal(color_scheme_id: StringName) -> bool:
	_ensure_loaded()

	if load_failed:
		push_error("Cannot check color scheme legality: catalog failed to load")
		return false

	if color_scheme_id == "":
		return true

	return color_scheme_id in _catalog.get("color_schemes", [])


## Get all valid helm ids (not including empty).
static func get_helm_ids() -> Array:
	_ensure_loaded()
	if load_failed:
		return []
	return _catalog.get("helms", [])


## Get all valid chest ids (not including empty).
static func get_chest_ids() -> Array:
	_ensure_loaded()
	if load_failed:
		return []
	return _catalog.get("chests", [])


## Get all valid color scheme ids (not including empty).
static func get_color_scheme_ids() -> Array:
	_ensure_loaded()
	if load_failed:
		return []
	return _catalog.get("color_schemes", [])


## For testing only: reset the catalog state to allow re-testing load failures.
static func reset_for_testing() -> void:
	_catalog = {}
	_loaded = false
	load_failed = false
	load_error = ""
