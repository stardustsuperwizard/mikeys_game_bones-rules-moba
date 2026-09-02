## Helper for saving and loading MobaCharacterBuild resources to/from disk.
##
## Provides simple persistence for player-created characters under user://
## directory, allowing save/load/delete operations without direct filesystem
## access in the calling script.
class_name CharacterStorage

## Directory where saved characters are stored.
const SAVE_DIR := "user://characters/"


## Save a character build to disk, creating directory if needed.
##
## Returns true on success, false on failure. Errors are pushed on failure.
## The saved file is a resource, serializable and loadable by Godot.
static func save_character(build: MobaCharacterBuild, file_name: String) -> bool:
	# Ensure the directory exists
	_ensure_save_dir()

	# Validate filename - reject paths with "/" or ".." to prevent directory traversal
	if "/" in file_name or ".." in file_name:
		push_error("Character filename cannot contain path separators: %s" % file_name)
		return false

	var file_path := SAVE_DIR + file_name + ".tres"

	# Godot's ResourceSaver handles the actual write
	var error := ResourceSaver.save(build, file_path)
	if error != OK:
		push_error("Failed to save character to %s (error %d)" % [file_path, error])
		return false

	return true


## Load a character build from disk by filename (without .tres extension).
##
## Returns the loaded build on success, null on failure. Errors are pushed on failure.
static func load_character(file_name: String) -> MobaCharacterBuild:
	# Validate filename - same security check as save
	if "/" in file_name or ".." in file_name:
		push_error("Character filename cannot contain path separators: %s" % file_name)
		return null

	var file_path := SAVE_DIR + file_name + ".tres"

	# Check if file exists
	if not ResourceLoader.exists(file_path):
		push_error("Character file not found: %s" % file_path)
		return null

	# Load the resource
	var resource = ResourceLoader.load(file_path)
	if resource == null:
		push_error("Failed to load character from %s" % file_path)
		return null

	var build := resource as MobaCharacterBuild
	if build == null:
		push_error("Loaded resource is not a MobaCharacterBuild: %s" % file_path)
		return null

	return build


## List all saved character file names (without .tres extension).
##
## Returns an empty array if the directory doesn't exist or is empty.
static func list_characters() -> Array[String]:
	var result: Array[String] = []

	# Early return if directory doesn't exist
	if not DirAccess.dir_exists_absolute(SAVE_DIR.trim_suffix("/")):
		return result

	var dir = DirAccess.open(SAVE_DIR)
	if dir == null:
		push_error("Failed to open save directory: %s" % SAVE_DIR)
		return result

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		# Include only .tres files, skip hidden and non-resource files
		if not file_name.begins_with(".") and file_name.ends_with(".tres"):
			# Remove .tres extension
			var char_name := file_name.trim_suffix(".tres")
			result.append(char_name)

		file_name = dir.get_next()

	return result


## Delete a saved character by filename (without .tres extension).
##
## Returns true on success, false on failure. Errors are pushed on failure.
static func delete_character(file_name: String) -> bool:
	# Validate filename - same security check as save/load
	if "/" in file_name or ".." in file_name:
		push_error("Character filename cannot contain path separators: %s" % file_name)
		return false

	var file_path := SAVE_DIR + file_name + ".tres"

	# Check if file exists
	if not ResourceLoader.exists(file_path):
		push_error("Character file not found: %s" % file_path)
		return false

	var error := DirAccess.remove_absolute(file_path)
	if error != OK:
		push_error("Failed to delete character from %s (error %d)" % [file_path, error])
		return false

	return true


## Ensure the save directory exists, creating it if necessary.
## Errors are pushed on failure.
static func _ensure_save_dir() -> void:
	# Check if directory exists first
	if DirAccess.dir_exists_absolute(SAVE_DIR.trim_suffix("/")):
		return

	# For user:// paths, Godot creates parent directories automatically.
	# We just need to ensure the user:// root exists and can be accessed.
	var dir = DirAccess.open("user://")
	if dir == null:
		push_error("Failed to access user:// directory")
		return

	# Try to create the characters subdirectory
	var error_code := dir.make_dir("characters")
	if error_code != OK and error_code != ERR_ALREADY_EXISTS:
		push_error("Failed to create characters directory (error %d)" % error_code)
