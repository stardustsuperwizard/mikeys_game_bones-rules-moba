## Bootstrap autoload for running tests in headless mode.
##
## This autoload runs the extraction contract test during headless validation
## to check that the rules module contains no outward references.
##
## The test result is printed to stderr. Violations are reported with file paths
## and line numbers for easy debugging.
extends Node

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		# Run the extraction contract test
		var test_passed = ExtractionContractTest.run()
		
		if test_passed:
			print("\nExtraction Contract Test PASSED")
		
		# Exit after the test completes to avoid loading the main scene
		call_deferred("_quit_engine")

func _quit_engine() -> void:
	get_tree().quit()
