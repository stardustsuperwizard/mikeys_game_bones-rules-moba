## Bootstrap autoload for running tests in headless mode.
##
## This autoload runs the extraction contract test during headless validation
## to check that the rules module contains no outward references, and runs the
## ability data validation test to ensure all ability and passive resources
## pass semantic validation.
##
## The test results are printed to stderr. Violations are reported with file paths
## and line numbers for easy debugging.
extends Node

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		# Run the extraction contract test
		var extraction_passed = ExtractionContractTest.run()
		
		if extraction_passed:
			print("\nExtraction Contract Test PASSED")
		
		# Run the ability data validation test
		var ability_data_passed = AbilityDataTest.run()
		
		if ability_data_passed:
			print("\nAbility Data Test PASSED")
		
		# Run the combatant test
		var combatant_passed = CombatantTest.run()
		
		if combatant_passed:
			print("\nCombatant Test PASSED")
		
		# Run the resource test
		var resource_passed = ResourceTest.run()
		
		if resource_passed:
			print("\nResource Test PASSED")
		
		# Run the formulas test
		var formulas_passed = FormulasTest.run()
		
		if formulas_passed:
			print("\nFormulas Test PASSED")
		
		# Run the state machine test
		var state_machine_passed = StateMachineTest.run()
		
		if state_machine_passed:
			print("\nState Machine Test PASSED")
		
		# Exit after the tests complete to avoid loading the main scene
		call_deferred("_quit_engine")

func _quit_engine() -> void:
	get_tree().quit()
