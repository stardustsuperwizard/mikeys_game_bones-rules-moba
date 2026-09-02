## Contract test ensuring every player-originated command is gated.
##
## Verifies that direct calls to MobaCombatant mutator methods only appear in
## proper contexts: inside rules/tests/ (unit tests exercising internals),
## resolution code within rules/ (e.g. rules/abilities/ or rules/core/),
## or engine-driven cleanup (MobaDeathHandler).
##
## A direct call in scripts/ or rules/input/ (the game-side input pathway)
## violates the command-gate invariant: every player-originated command must
## pass through Action → ActionRunner → Authority.
class_name CommandMutatorContractTest

## Paths to scan for violations.
const SCAN_PATHS := ["res://scripts/", "res://rules/input/"]

## MobaCombatant public methods that mutate combat state.
## Must be maintained whenever a new mutator is added to MobaCombatant.
const MUTATOR_METHODS := [
	"basic_attack",
	"break_channel",
	"cancel_cast",
	"apply_damage",
	"apply_healing",
	"apply_shield",
	"apply_crowd_control",
	"apply_stat_modifier",
	# Collaborator seams (#325). These exist for MobaDamageResolver and
	# MobaActivationGate to call, and are the most dangerous methods on the
	# class -- write_health() in particular bypasses the current_health setter's
	# _ensure_runtime_stat_block() and externally-seeded bookkeeping. Being
	# internal-by-intention is exactly why they belong here: nothing but this
	# list stops game-side code picking them up as a shortcut past the gate.
	"write_health",
	"consume_shields",
	"start_cooldown",
	"spend_resource",
	"restore_resource",
	"commit_activate",
	"start_cast",
	"start_channel",
	"start_toggle",
	"deactivate_toggle",
	"cancel_cooldown",
	"respawn",
	# The composed round-boundary reset (#340). Listed for the same reason the
	# five primitives it is built from are: game-side code that called it
	# directly would get all of their effects at once, past the gate.
	"reset_for_round",
	"revive_state",
	"restore_to_full",
	"clear_all_cooldowns",
	"clear_all_active_effects",
	"register_ability",
	"interrupt_for_hard_crowd_control",
	"queue_follow_up_effect_for_displacement",
]


## Run the command mutator contract test.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var violations: Array[String] = []

	for scan_path in SCAN_PATHS:
		var files = _get_files_recursive(scan_path)

		# A scan root that cannot be opened yields an empty file list, and an
		# empty file list yields no violations -- so a moved or renamed root
		# would turn this suite into a vacuous pass while still reporting PASS.
		# That is the exact failure mode the suite exists to prevent, so treat
		# a root with no GDScript in it as a violation rather than as silence.
		var scanned := 0

		for file_path in files:
			if not file_path.ends_with(".gd"):
				continue

			scanned += 1

			var content = _read_file(file_path)
			if content.is_empty():
				continue

			# Check for direct mutator method calls
			var lines = content.split("\n")
			for line_num in range(lines.size()):
				var line = lines[line_num]

				# Skip comment-only lines (same pattern as extraction_contract_test.gd)
				var stripped = line.strip_edges()
				if stripped.begins_with("#"):
					continue

				# Extract code part before any inline comment
				var code_part = line
				if "#" in line:
					code_part = line.split("#")[0]

				# Check for each mutator method call pattern
				for mutator in MUTATOR_METHODS:
					# Look for patterns like .mutator_name( to catch actual calls
					var pattern = "." + mutator + "("
					if pattern in code_part:
						var detail := (
							"%s:%d: direct call to MobaCombatant.%s() violates command gate"
							% [file_path, line_num + 1, mutator]
						)
						violations.append(detail)

		if scanned == 0:
			var empty_root := (
				"%s: scan root has no .gd files; it was moved, renamed, or is unreadable"
				% scan_path
			)
			violations.append(empty_root)

	if violations.is_empty():
		return true

	# Print violations
	printerr("\n=== Command Mutator Contract Violations ===")
	printerr("Direct calls to MobaCombatant mutators must not appear in scripts/ or rules/input/.")
	printerr("Every player-originated command must gate through Action → ActionRunner → Authority.")
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
