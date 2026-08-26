## Data model for crowd control legality per effect type.
##
## Loads effect legality data from crowd_control_effects.json and exposes
## static query methods to determine which actions are blocked by each crowd
## control type. This is pure data and query logic; it does not apply crowd
## control to a combatant or change any state.
##
## All eleven MobaCrowdControlSpec.CCType effects are represented in the table,
## even though some have all-false columns (SLOW, KNOCKBACK, PULL, KNOCK_UP,
## FEAR, TAUNT, BLIND) because they achieve their effects through other
## mechanisms: SLOW via stat modifier, displacement via velocity, FEAR/TAUNT
## via intent override, and BLIND via miss chance at resolution.
class_name MobaCrowdControl

## Recognized column names and their expected boolean type, used to validate
## the data table at load time.
const _REQUIRED_COLUMNS = ["blocks_move", "blocks_basic_attack", "blocks_ability"]

## Set when the data table failed to load or validate. Detectable by callers
## and tests rather than only observable through push_error side effects.
static var load_failed: bool = false

## The problem that caused the most recent load failure, or "" when the table
## loaded cleanly. Lets a caller or test assert *why* a table was rejected,
## not merely that it was -- a table refused by the wrong check still sets
## load_failed, and without this the mistake is invisible.
static var load_error: String = ""

static var _cc_table: Dictionary = {}
static var _table_loaded: bool = false


## Ensure the CC table is loaded before use. Called lazily before each query.
static func _ensure_loaded() -> void:
	if _table_loaded:
		return

	_load_cc_table()
	_table_loaded = true


static func _load_cc_table() -> void:
	var json_path = "res://rules/data/crowd_control_effects.json"
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		_fail("Failed to load crowd_control_effects.json at %s" % json_path)
		return

	var content = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		_fail("Failed to parse crowd_control_effects.json: %s" % json.get_error_message())
		return

	_parse_cc_table(json.data)


## Validate and load the crowd control table from parsed data.
## Returns true on success, false (with load_failed set and push_error called)
## on any validation failure.
static func _parse_cc_table(data: Variant) -> bool:
	_cc_table = {}
	load_failed = false
	load_error = ""

	var error_message := _first_cc_table_error(data)

	if error_message == "":
		return true

	_fail(error_message)
	return false


## Record a load failure: report it loudly and leave it detectable.
static func _fail(message: String) -> void:
	push_error(message)
	load_failed = true
	load_error = message


## Returns the first validation problem found in `data`, or "" if the whole
## table is valid. Stops at the first problem, so the reported error is always
## the earliest one.
static func _first_cc_table_error(data: Variant) -> String:
	if data is not Dictionary:
		return "crowd_control_effects.json root must be a dictionary"

	# Collect all CC type names from the enum
	var expected_cc_types: Array[String] = []
	for cc_type_name in MobaCrowdControlSpec.CCType.keys():
		expected_cc_types.append(cc_type_name)

	# Check that we have exactly the right CC types
	if data.keys().size() != expected_cc_types.size():
		return (
			"crowd_control_effects.json: expected %d CC types, found %d"
			% [
				expected_cc_types.size(),
				data.keys().size(),
			]
		)

	# Validate and process each CC type
	for cc_type_name_str: String in data.keys():
		# Verify the CC type name exists in the enum
		if cc_type_name_str not in expected_cc_types:
			return "Unknown CC type in crowd_control_effects.json: %s" % cc_type_name_str

		var cc_data = data[cc_type_name_str]
		if cc_data is not Dictionary:
			return "CC entry for %s must be a dictionary" % cc_type_name_str

		var entry_error = _first_cc_entry_error(cc_type_name_str, cc_data)
		if entry_error != "":
			return entry_error

		# Key by enum index, not by name, mirroring MobaStateMachine's
		# `_state_table[state_idx]`. The queries take an int, so keying by int
		# is what lets their `not in _cc_table` guard actually reject an
		# out-of-range value instead of indexing CCType.keys() blind.
		_cc_table[MobaCrowdControlSpec.CCType[cc_type_name_str]] = cc_data

	return ""


## Returns the first validation problem found in one CC type's column values,
## or "" if the entry is valid.
static func _first_cc_entry_error(cc_type_name_str: String, cc_data: Dictionary) -> String:
	# Validate all required columns exist
	for column_name in _REQUIRED_COLUMNS:
		if column_name not in cc_data:
			return "CC type %s missing column '%s'" % [cc_type_name_str, column_name]

		var value = cc_data[column_name]
		if value is not bool:
			return (
				"CC type %s column %s value must be bool, got %s"
				% [cc_type_name_str, column_name, typeof(value)]
			)

	return ""


## Check if a crowd control type blocks movement.
## Returns false if the table failed to load, or if the type is invalid.
static func blocks_move(type: int) -> bool:
	_ensure_loaded()

	if load_failed:
		push_error("Cannot answer blocks_move(%d): CC table failed to load" % type)
		return false

	if type not in _cc_table:
		push_error("Unknown CC type: %d" % type)
		return false

	return _cc_table[type].get("blocks_move", false)


## Check if a crowd control type blocks basic attacks.
## Returns false if the table failed to load, or if the type is invalid.
static func blocks_basic_attack(type: int) -> bool:
	_ensure_loaded()

	if load_failed:
		push_error("Cannot answer blocks_basic_attack(%d): CC table failed to load" % type)
		return false

	if type not in _cc_table:
		push_error("Unknown CC type: %d" % type)
		return false

	return _cc_table[type].get("blocks_basic_attack", false)


## Check if a crowd control type blocks abilities.
## Returns false if the table failed to load, or if the type is invalid.
static func blocks_ability(type: int) -> bool:
	_ensure_loaded()

	if load_failed:
		push_error("Cannot answer blocks_ability(%d): CC table failed to load" % type)
		return false

	if type not in _cc_table:
		push_error("Unknown CC type: %d" % type)
		return false

	return _cc_table[type].get("blocks_ability", false)


## For testing only: feed a hand-built table through the same validation path
## used by _load_cc_table(), so malformed-table handling can be exercised
## without touching the JSON resource on disk.
static func load_cc_table_for_testing(data: Variant) -> bool:
	return _parse_cc_table(data)


## For testing only: reset the table state to allow re-testing load failures.
##
## Call this after a test that leaves a malformed table behind: the next
## _ensure_loaded() reloads from disk, so a consumer reading `load_failed`
## without first issuing a query does not see a stale failure.
static func reset_for_testing() -> void:
	_cc_table = {}
	_table_loaded = false
	load_failed = false
	load_error = ""
