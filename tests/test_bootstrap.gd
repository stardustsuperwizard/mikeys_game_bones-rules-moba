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

## Expected suite names in execution order. Used to detect truncated runs.
var _expected_suites: Array[String] = [
	"Extraction Contract Test",
	"Ability Data Test",
	"Combatant Test",
	"Effect Container Test",
	"Resource Test",
	"Formulas Test",
	"Crowd Control Data Test",
	"State Machine Test",
	"Cooldown Test",
	"Ability Library Test",
	"Ability Activation Test",
	"Targeting Test",
	"Cast Cancel Test",
	"Channel Test",
	"Brace Ability Test",
	"Crowd Control Test",
	"Crowd Control Displacement Test",
	"Shield Bash Ability Test",
	"Shield Test",
	"Sustain Test",
	"Loadout Test",
	"HUD Slot Test",
	"HUD Test",
	"Cast Bar Test",
	"Status Tray Test",
	"Floating Text Test",
	"Death Test",
	"Target Frame Test",
	"Input Intent Test",
]


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		return

	var tree_script: Script = get_tree().get_script()
	if tree_script != null:
		return

	# The targeting suite is the one suite that awaits physics frames: a body
	# only registers with the physics space once a frame has been processed.
	# It has to finish BEFORE _finalize is queued -- call_deferred fires at the
	# end of the current frame, so a suite that suspends after that point would
	# have the summary printed out from under it, reporting every later suite
	# as never run. Resolving it here keeps its _check() in _expected_suites
	# order below while confining the awaits to a point where nothing is queued.
	var targeting_passed: bool = await TargetingTest.run()

	# Queue completion logic BEFORE any suites run, so it executes even if
	# a suite aborts due to compilation error or runtime error.
	call_deferred("_finalize")

	_check("Extraction Contract Test", ExtractionContractTest.run())
	_check("Ability Data Test", AbilityDataTest.run())
	_check("Combatant Test", CombatantTest.run())
	_check("Effect Container Test", EffectContainerTest.run())
	_check("Resource Test", ResourceTest.run())
	_check("Formulas Test", FormulasTest.run())
	_check("Crowd Control Data Test", CrowdControlDataTest.run())
	_check("State Machine Test", StateMachineTest.run())
	_check("Cooldown Test", CooldownTest.run())
	_check("Ability Library Test", AbilityLibraryTest.run())
	_check("Ability Activation Test", AbilityActivationTest.run())
	_check("Targeting Test", targeting_passed)
	_check("Cast Cancel Test", CastCancelTest.run())
	_check("Channel Test", ChannelTest.run())
	_check("Brace Ability Test", BraceAbilityTest.run())
	_check("Crowd Control Test", CrowdControlTest.run())
	_check("Crowd Control Displacement Test", CrowdControlDisplacementTest.run())
	_check("Shield Bash Ability Test", ShieldBashAbilityTest.run())
	_check("Shield Test", ShieldTest.run())
	_check("Sustain Test", SustainTest.run())
	_check("Loadout Test", LoadoutTest.run())
	_check("HUD Slot Test", HudSlotTest.run())
	_check("HUD Test", HudTest.run())
	_check("Cast Bar Test", CastBarTest.run())
	_check("Status Tray Test", StatusTrayTest.run())
	_check("Floating Text Test", FloatingTextTest.run())
	_check("Death Test", DeathTest.run())
	_check("Target Frame Test", TargetFrameTest.run())
	_check("Input Intent Test", InputIntentTest.run())


## Record and announce one suite's result.
func _check(suite_name: String, passed: bool) -> void:
	# _expected_suites and the _check() calls in _ready() are both maintained by
	# hand, and the truncation math above is only meaningful while they agree. A
	# suite that runs without being listed would push the actual count past the
	# expected one and silently switch truncation detection off, so treat the
	# drift itself as a failure rather than letting it hide the next abort.
	if suite_name not in _expected_suites:
		_failures.append(suite_name)
		printerr("FAIL %s" % suite_name)
		printerr("  %s ran but is not in _expected_suites; add it there." % suite_name)
		return

	if passed:
		_passes.append(suite_name)
		print("PASS %s" % suite_name)
	else:
		_failures.append(suite_name)
		printerr("FAIL %s" % suite_name)


## Finalize the test run: report results and exit. Called via call_deferred
## to guarantee it runs even if a suite aborts due to compilation error or
## runtime error.
func _finalize() -> void:
	_report()
	_quit_engine()


func _report() -> void:
	var actual_count := _passes.size() + _failures.size()
	var expected_count := _expected_suites.size()

	# Check if fewer suites ran than expected (indicates a truncated run).
	if actual_count < expected_count:
		var missing_suites: Array[String] = []
		for suite_name in _expected_suites:
			if suite_name not in _passes and suite_name not in _failures:
				missing_suites.append(suite_name)

		printerr(
			(
				"\n%d of %d test suites never ran: %s"
				% [missing_suites.size(), expected_count, ", ".join(missing_suites)]
			)
		)
		return

	# Report normal pass/fail outcomes.
	if _failures.is_empty():
		print("\nAll %d test suites passed." % actual_count)
		return

	printerr(
		"\n%d of %d test suites FAILED: %s" % [_failures.size(), actual_count, ", ".join(_failures)]
	)


func _quit_engine() -> void:
	var actual_count := _passes.size() + _failures.size()
	var expected_count := _expected_suites.size()
	var should_fail := not _failures.is_empty() or actual_count < expected_count
	get_tree().quit(1 if should_fail else 0)
