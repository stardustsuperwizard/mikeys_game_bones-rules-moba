## Test suite for MobaBasicAttackAction.
##
## Covers: a basic attack routed through ActionRunner, which is what #304
## changed -- PlayerController3D and EnemyAIController3D used to call
## MobaCombatant.basic_attack() directly, bypassing Authority entirely.
##
## Two properties matter and are asserted here:
##
## 1. The gate is live. An attack requested for an actor the requester does
##    not own is refused by Authority.can_perform() before execute() runs, so
##    the swing never starts and the target takes no damage. A regression that
##    routes basic attack around ActionRunner again fails this case.
## 2. The swing is unchanged. Routing through ActionRunner must not alter
##    combat outcomes, so the parity case runs the same scenario twice -- once
##    through the old direct basic_attack() call, once through ActionRunner --
##    and requires the damage dealt to be identical.
##
## Fixtures are built standalone and never enter the SceneTree, matching
## AuthorityTest and LoadoutTest. Actor.global_position is a computed getter
## that reads a "Body" child and falls back to Vector3.ZERO, so an Actor built
## without one sits at the origin; attacker and target are therefore always
## within the fixture weapon's attack_range and range never confounds a case.
class_name BasicAttackActionTest

const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## Long enough that the origin-to-origin fixture distance is always inside it.
const _WEAPON_RANGE := 10.0
const _WEAPON_DAMAGE := 50.0
const _WEAPON_WIND_UP := 0.1


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_authority_denies_unowned_actor())
	all_violations.append_array(_test_owning_peer_deals_same_damage_as_direct_call())
	all_violations.append_array(_test_target_without_combatant_reports_its_own_reason())

	if all_violations.is_empty():
		return true

	printerr("\n=== Basic Attack Action Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Build a MobaCombatant with health, resource, and crit forced off so damage
## is deterministic. Private-field setup matches LoadoutTest's fixtures.
static func _make_combatant() -> MobaCombatant:
	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = 500.0
	combatant._current_resource = 250.0
	# Crit would make the parity comparison below depend on RNG draw order
	# rather than on the routing change under test.
	combatant._runtime_stat_block.crit_chance = 0.0
	return combatant


## Attach the MobaCombatant/MobaStateMachine children MobaBasicAttackAction and
## MobaBasicAttackCycle look up by name in production.
static func _make_actor(owner_id: int) -> Actor:
	var actor := Actor.new()
	actor.owner_id = owner_id
	actor.add_child(_make_combatant())

	var state_machine := MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	return actor


## An attacker whose combatant carries a weapon, so basic_attack() has
## something to swing and can actually succeed.
static func _make_attacker(owner_id: int) -> Actor:
	var actor := _make_actor(owner_id)

	var weapon := MobaWeapon.new()
	weapon.damage = _WEAPON_DAMAGE
	weapon.attack_speed = 1.0
	weapon.wind_up = _WEAPON_WIND_UP
	weapon.recovery = 0.2
	weapon.attack_range = _WEAPON_RANGE

	var loadout := MobaLoadout.new()
	loadout.weapon = weapon
	_combatant_of(actor).loadout = loadout

	return actor


static func _combatant_of(actor: Actor) -> MobaCombatant:
	return actor.get_node("MobaCombatant") as MobaCombatant


static func _state_machine_of(actor: Actor) -> MobaStateMachine:
	return actor.get_node("MobaStateMachine") as MobaStateMachine


## Carry a started swing through wind-up so its damage lands, then report how
## much health the target lost.
static func _damage_dealt_after_wind_up(attacker: Actor, target: Actor) -> float:
	var target_combatant := _combatant_of(target)
	var before := target_combatant._current_health
	_combatant_of(attacker).tick(_WEAPON_WIND_UP + 0.01)
	return before - target_combatant._current_health


## Test 1: Authority refuses a basic attack for an actor the requester does not
## own. The refusal must happen before the swing starts -- an attack that was
## denied but still wound up or still dealt damage would defeat the gate.
static func _test_authority_denies_unowned_actor() -> Array[String]:
	var violations: Array[String] = []

	var attacker := _make_attacker(1)
	var target := _make_actor(0)
	var target_combatant := _combatant_of(target)
	var health_before := target_combatant._current_health

	var action := MobaBasicAttackAction.new(attacker, target)
	var result := ActionRunner.run(action, 2)

	if result.success:
		violations.append(
			"authority_denies_unowned_actor: requester_id 2 should be refused for owner_id 1"
		)

	# ActionRunner returns a bare failure on a denial; the FAILURE_* reasons
	# belong to execute(), which must not have run at all here.
	if result.reason != &"":
		violations.append(
			(
				"authority_denies_unowned_actor: denial should carry no reason, got '%s'"
				% result.reason
			)
		)

	if _state_machine_of(attacker).current_state == MobaState.BASIC_ATTACK_WINDUP:
		violations.append(
			"authority_denies_unowned_actor: denied attack should not have entered wind-up"
		)

	if _damage_dealt_after_wind_up(attacker, target) != 0.0:
		violations.append("authority_denies_unowned_actor: denied attack should deal no damage")

	if target_combatant._current_health != health_before:
		violations.append("authority_denies_unowned_actor: target health should be untouched")

	# Freeing the Actor frees the combatant/state-machine children with it.
	# These fixtures never enter the SceneTree, so nothing else will.
	attacker.free()
	target.free()

	return violations


## Test 2: routing through ActionRunner does not change the swing. The same
## scenario is run twice -- once through the direct MobaCombatant.basic_attack()
## call the controllers used before #304, once through ActionRunner -- and the
## damage dealt must be identical and non-zero.
static func _test_owning_peer_deals_same_damage_as_direct_call() -> Array[String]:
	var violations: Array[String] = []

	# Baseline: the pre-#304 path, calling the combatant directly.
	var direct_attacker := _make_attacker(1)
	var direct_target := _make_actor(0)
	if not _combatant_of(direct_attacker).basic_attack(_combatant_of(direct_target)):
		violations.append("same_damage_as_direct_call: direct basic_attack() should succeed")
	var direct_damage := _damage_dealt_after_wind_up(direct_attacker, direct_target)

	# The #304 path: same fixture, issued through ActionRunner by the owning peer.
	var routed_attacker := _make_attacker(1)
	var routed_target := _make_actor(0)
	var action := MobaBasicAttackAction.new(routed_attacker, routed_target)
	var result := ActionRunner.run(action, 1)

	if not result.success:
		violations.append(
			(
				"same_damage_as_direct_call: owning peer should be admitted, got reason '%s'"
				% result.reason
			)
		)

	if _state_machine_of(routed_attacker).current_state != MobaState.BASIC_ATTACK_WINDUP:
		violations.append("same_damage_as_direct_call: accepted attack should enter wind-up")

	var routed_damage := _damage_dealt_after_wind_up(routed_attacker, routed_target)

	if direct_damage <= 0.0:
		violations.append(
			(
				"same_damage_as_direct_call: baseline direct call should deal damage, got %f"
				% direct_damage
			)
		)

	if routed_damage != direct_damage:
		violations.append(
			(
				"same_damage_as_direct_call: routed damage %f should equal direct damage %f"
				% [routed_damage, direct_damage]
			)
		)

	direct_attacker.free()
	direct_target.free()
	routed_attacker.free()
	routed_target.free()

	return violations


## Test 3: a target carrying no MobaCombatant is reported as its own failure
## reason rather than as a generic declined swing. Both controllers branch on
## this constant to drop a pending attack that can never resolve, so collapsing
## it into FAILURE_ATTACK_NOT_STARTED would latch that attack forever.
static func _test_target_without_combatant_reports_its_own_reason() -> Array[String]:
	var violations: Array[String] = []

	var attacker := _make_attacker(1)
	var target := Actor.new()

	var action := MobaBasicAttackAction.new(attacker, target)
	var result := ActionRunner.run(action, 1)

	if result.success:
		violations.append("target_without_combatant: attack on a combatant-less target should fail")

	if result.reason != MobaBasicAttackAction.FAILURE_NO_TARGET_COMBATANT:
		violations.append(
			(
				"target_without_combatant: expected '%s', got '%s'"
				% [MobaBasicAttackAction.FAILURE_NO_TARGET_COMBATANT, result.reason]
			)
		)

	attacker.free()
	target.free()

	return violations
