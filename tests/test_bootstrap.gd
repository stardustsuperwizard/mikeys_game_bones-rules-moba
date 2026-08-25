## Bootstrap autoload for running tests in headless mode.
##
## Runs every rules/ test suite during headless validation and makes the result
## the process exit code: 0 when every suite passes, 1 when any suite fails.
##
## That exit code is the whole point of this file. `validate-godot.sh` runs
## `godot --headless --quit` and treats a non-zero exit as a failed build, so a
## suite that returns false must exit non-zero or the failure is invisible to
## CI -- a green check would mean only "the project imports and boots", not
## "the tests pass".
##
## Individual suites print their own violation detail to stderr; this file adds
## the per-suite pass/fail line and the closing summary.
extends Node

## Suite names that returned false this run.
var _failures: Array[String] = []

## Suite names that returned true this run.
var _passes: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		return

	var tree_script: Script = get_tree().get_script()
	if tree_script != null:
		return

	_check("Extraction Contract Test", ExtractionContractTest.run())
	_check("Ability Data Test", AbilityDataTest.run())
	_check("Combatant Test", CombatantTest.run())
	_check("Effect Container Test", EffectContainerTest.run())
	_check("Resource Test", ResourceTest.run())
	_check("Formulas Test", FormulasTest.run())
	_check("State Machine Test", StateMachineTest.run())
	_check("Cooldown Test", CooldownTest.run())
	_check("Ability Library Test", AbilityLibraryTest.run())
	_check("Ability Activation Test", AbilityActivationTest.run())
	_check("Loadout Test", LoadoutTest.run())
	_check("HUD Slot Test", HudSlotTest.run())
	_check("HUD Test", HudTest.run())

	_report()

	# Exit after the tests complete to avoid loading the main scene.
	call_deferred("_quit_engine")


## Record and announce one suite's result.
func _check(suite_name: String, passed: bool) -> void:
	if passed:
		_passes.append(suite_name)
		print("PASS %s" % suite_name)
	else:
		_failures.append(suite_name)
		printerr("FAIL %s" % suite_name)


func _report() -> void:
	var total := _passes.size() + _failures.size()
	if _failures.is_empty():
		print("\nAll %d test suites passed." % total)
		return

	printerr("\n%d of %d test suites FAILED: %s" % [_failures.size(), total, ", ".join(_failures)])


func _quit_engine() -> void:
	get_tree().quit(1 if not _failures.is_empty() else 0)
