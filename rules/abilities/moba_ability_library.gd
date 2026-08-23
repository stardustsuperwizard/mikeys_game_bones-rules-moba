## MobaAbilityLibrary loads and indexes all MobaAbility .tres files from a target directory.
##
## Provides safe-by-construction loading: a bad file is reported by path and excluded,
## never crashes startup, and never prevents valid abilities from loading. An empty id, or
## an id that duplicates one already indexed, is treated the same as a load error: reported
## by path and excluded, keeping whichever resource for that id was scanned first.
##
## Follows the MobaRules pattern of static methods and static cache state.
class_name MobaAbilityLibrary

## Static cache: ability_id -> MobaAbility resource
static var _cache: Dictionary = {}

## Whether the cache has been populated
static var _loaded: bool = false


## Get an ability by id. Returns null if not found.
static func get_ability(id: StringName) -> MobaAbility:
	_ensure_loaded()
	return _cache.get(id, null)


## Lazily load and index all abilities from the target directory.
## Loads from the provided directory (or the default data root if not provided).
static func _ensure_loaded(directory: String = "") -> void:
	if _loaded:
		return

	if directory == "":
		directory = MobaRules.DATA_ROOT + "abilities/"

	_load_and_index(directory)
	_loaded = true


## Load all .tres files from the target directory and index them by id.
## Files that fail to load or are not MobaAbility instances are reported and skipped.
static func _load_and_index(directory: String) -> void:
	var dir = DirAccess.open(directory)

	if dir == null:
		push_error("MobaAbilityLibrary: Failed to open directory: %s" % directory)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		# Only process .tres files, skip hidden files
		if not file_name.begins_with(".") and file_name.ends_with(".tres"):
			var full_path = directory.path_join(file_name)
			_load_single_ability(full_path)

		file_name = dir.get_next()


## Load a single ability file and add it to the cache if valid.
## Reports errors for invalid files but does not crash.
static func _load_single_ability(file_path: String) -> void:
	var resource = ResourceLoader.load(file_path)

	if resource == null:
		printerr("MobaAbilityLibrary: Failed to load resource from %s" % file_path)
		return

	# Check if the resource is actually a MobaAbility by script class name
	var script = resource.get_script()
	if script == null or script.get_global_name() != "MobaAbility":
		var actual_type = script.get_global_name() if script != null else resource.get_class()
		printerr(
			(
				"MobaAbilityLibrary: %s is not a MobaAbility resource (got %s)"
				% [file_path, actual_type]
			)
		)
		return

	var ability := resource as MobaAbility

	if ability.id == "":
		printerr("MobaAbilityLibrary: %s has an empty id and was excluded" % file_path)
		return

	var id := StringName(ability.id)

	if _cache.has(id):
		printerr(
			(
				"MobaAbilityLibrary: %s has duplicate id '%s'; keeping the first-loaded resource"
				% [file_path, ability.id]
			)
		)
		return

	_cache[id] = ability


## Reset the cache (primarily for testing).
static func _reset() -> void:
	_cache.clear()
	_loaded = false
