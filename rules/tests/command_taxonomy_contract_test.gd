## Contract test for the command taxonomy: a new command is one Action subclass.
##
## Demonstrates the invariant: a new player-originated command is implemented as a new
## Action subclass, with its own FAILURE_* constant block matching MobaAbilityAction's
## convention, and requires no edit to ActionRunner or Authority.
##
## The test constructs a test Actor with a MobaCombatant child and nonzero owner_id,
## defines a throwaway Action subclass, and runs it through ActionRunner twice:
## once with a requester_id matching the actor's owner_id (expect success), and
## once with a mismatched requester_id (expect denial by Authority). Both are verified
## without any change to scripts/action_runner.gd or scripts/authority.gd.
class_name CommandTaxonomyContractTest


## Test-local Action subclass demonstrating the command taxonomy.
## This Action is defined here for this test only and is never exported or reused.
class TestCommandAction:
	extends Action
	## Failure reasons for this test command type, following MobaAbilityAction's convention.
	const FAILURE_UNKNOWN = &"test_command_unknown"
	const FAILURE_NOT_READY = &"test_command_not_ready"

	var _is_ready: bool = true

	func _init(p_actor: Actor) -> void:
		super(p_actor)

	func set_ready(ready: bool) -> void:
		_is_ready = ready

	func execute() -> ActionResult:
		if not _is_ready:
			return ActionResult.new(false, FAILURE_NOT_READY)
		return ActionResult.new(true)


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_matching_requester_succeeds())
	all_violations.append_array(_test_mismatched_requester_denied())

	if all_violations.is_empty():
		return true

	printerr("\n=== Command Taxonomy Contract Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Test case 1: ActionRunner admits a request when requester_id matches actor.owner_id.
## Demonstrates that Authority.can_perform() is satisfied and execute() runs.
static func _test_matching_requester_succeeds() -> Array[String]:
	var violations: Array[String] = []

	var actor := _create_test_actor(1)
	var action := TestCommandAction.new(actor)

	var result := ActionRunner.run(action, 1)  # requester_id matches owner_id

	if not result.success:
		violations.append(
			"matching_requester_succeeds: run(action, 1) should succeed for owner_id 1"
		)

	return violations


## Test case 2: ActionRunner denies a request when requester_id does not match actor.owner_id.
## Demonstrates that Authority.can_perform() blocks access and execute() never runs.
static func _test_mismatched_requester_denied() -> Array[String]:
	var violations: Array[String] = []

	var actor := _create_test_actor(1)
	var action := TestCommandAction.new(actor)

	var result := ActionRunner.run(action, 2)  # requester_id does NOT match owner_id

	if result.success:
		violations.append(
			"mismatched_requester_denied: run(action, 2) should be refused for owner_id 1"
		)

	return violations


## Helper to create a test actor with MobaCombatant child and nonzero owner_id,
## matching the pattern from AuthorityTest.
static func _create_test_actor(owner_id: int) -> Actor:
	var actor := Actor.new()
	actor.owner_id = owner_id

	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	actor.add_child(combatant)

	return actor
