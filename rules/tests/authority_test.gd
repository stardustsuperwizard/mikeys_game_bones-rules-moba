## Test suite for the Authority ownership gate.
##
## Covers: Authority.can_perform() across both of its branches -- an owned
## actor (nonzero owner_id) admitting only its own peer, and the unowned/AI
## actor (owner_id == 0) admitting any requester.
##
## The gate was vacuously true before #303: every Actor spawned with
## owner_id == 0, so the first branch was unreachable and can_perform()
## always returned true. These cases exist to keep it live -- a regression
## that reverts owner_id to a constant 0 fails the mismatch case below.
class_name AuthorityTest


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_owned_actor_rejects_other_peer())
	all_violations.append_array(_test_owned_actor_accepts_owning_peer())
	all_violations.append_array(_test_unowned_actor_accepts_any_peer())

	if all_violations.is_empty():
		return true

	printerr("\n=== Authority Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Helper to create a test actor with a real MobaCombatant child node, matching
## how a spawned actor is shaped in production, and with owner_id set to the
## value WorldManager._spawn_actor() would have written from the spawn point's
## authority_id.
##
## Constructed standalone (never added to a SceneTree) like every other suite
## here; MobaCombatant's stat_block has a default preload, so it needs no
## further setup for an ownership check.
static func _create_test_actor(owner_id: int) -> Actor:
	var actor := Actor.new()
	actor.owner_id = owner_id

	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	actor.add_child(combatant)

	return actor


## Test 1: an owned actor refuses a requester that is not its owning peer.
## This is the case the gate existed for and never reached before #303.
static func _test_owned_actor_rejects_other_peer() -> Array[String]:
	var violations: Array[String] = []

	var actor := _create_test_actor(1)
	var action := Action.new(actor)

	if Authority.can_perform(action, 2):
		violations.append(
			"owned_actor_rejects_other_peer: requester_id 2 should be refused for owner_id 1"
		)

	return violations


## Test 2: an owned actor admits its own peer.
static func _test_owned_actor_accepts_owning_peer() -> Array[String]:
	var violations: Array[String] = []

	var actor := _create_test_actor(1)
	var action := Action.new(actor)

	if not Authority.can_perform(action, 1):
		violations.append(
			"owned_actor_accepts_owning_peer: requester_id 1 should be admitted for owner_id 1"
		)

	return violations


## Test 3: an unowned (AI) actor still admits any requester, so the coverage
## above does not silently narrow the owner_id == 0 branch.
static func _test_unowned_actor_accepts_any_peer() -> Array[String]:
	var violations: Array[String] = []

	var actor := _create_test_actor(0)
	var action := Action.new(actor)

	for requester_id in [0, 1, 2]:
		if not Authority.can_perform(action, requester_id):
			violations.append(
				"unowned_actor_accepts_any_peer: requester_id %d should be admitted" % requester_id
			)

	return violations
