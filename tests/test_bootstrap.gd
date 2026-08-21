## Bootstrap autoload for running tests in headless mode.
##
## This autoload runs the extraction contract test during headless validation.
## It runs before the main scene fully initializes, allowing the test to complete
## and report results.
extends Node

func _ready() -> void:
	# Run the extraction contract test only in headless mode
	# (i.e., during .github/scripts/validate-godot.sh)
	if DisplayServer.get_name() == "headless":
		var test_passed = ExtractionContractTest.run()
		
		if not test_passed:
			# Test failed - exit with error code
			get_tree().quit(1)
		else:
			print("\nExtraction Contract Test PASSED")
			# Test passed - exit cleanly
			get_tree().quit(0)






