## Test suite for crowd control effect application and the anti-perma-stun rule.
##
## Tests that hard crowd control (STUN, ROOT, SILENCE, DISARM, FEAR, TAUNT, BLIND)
## enters and maintains the CROWD_CONTROLLED state, that multiple entries of
## different types coexist independently, that the same CCType uses max(remaining, new_duration)
## rule (never a sum), and that DEAD combatants refuse crowd control outright.
##
## §60 regression test: apply a 1.0 second stun, advance 0.3 seconds, apply another
## 1.0 second stun, assert remaining is 1.0 and not 1.7.
class_name CrowdControlTest

const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")


## Minimal Node exposing a settable global_position, matching
## LoadoutTest._TestPositionedNode -- MobaCombatant._is_in_range() duck-types
## on the parent's global_position and a plain Actor (extends Node) has none.
class _TestPositionedNode:
	extends Node
	var global_position: Vector3 = Vector3.ZERO


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_anti_perma_stun_rule())
	all_violations.append_array(_test_rooted_blocks_move())
	all_violations.append_array(_test_silenced_blocks_ability())
	all_violations.append_array(_test_disarmed_blocks_basic_attack())
	all_violations.append_array(_test_stunned_blocks_all())
	all_violations.append_array(_test_different_cc_types_coexist())
	all_violations.append_array(_test_crowd_control_refused_on_dead())
	all_violations.append_array(_test_crowd_control_refused_while_dashing())
	all_violations.append_array(_test_blind_causes_attacker_miss())
	all_violations.append_array(_test_blind_zero_magnitude_never_misses())
	all_violations.append_array(_test_cc_intersects_with_state_outside_crowd_controlled())
	all_violations.append_array(_test_crowd_control_remaining_duration())

	if all_violations.is_empty():
		return true

	printerr("\n=== Crowd Control Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Build a combatant with a real MobaCombatant and MobaStateMachine as child nodes.
static func _create_combatant() -> Dictionary:
	var actor = Actor.new()
	actor.owner_id = 1

	var combatant = MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)
	actor.add_child(combatant)

	var state_machine = MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	return {"actor": actor, "combatant": combatant, "state_machine": state_machine}


## Test §60: anti-perma-stun rule - apply 1.0s stun, advance 0.3s, apply 1.0s stun,
## assert remaining is 1.0 (not 1.7, not 2.0).
static func _test_anti_perma_stun_rule() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_combatant()
	var target = data["combatant"]
	var source = MobaCombatant.new()
	source.name = "Source"
	source.stat_block = _BASELINE_STAT_BLOCK
	source._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	source._current_health = source._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	source._current_resource = source._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)

	# First stun: 1.0 second
	var spec1 = MobaCrowdControlSpec.new()
	spec1.type = MobaCrowdControlSpec.CCType.STUN
	spec1.duration = 1.0
	spec1.affected_by_tenacity = false

	target.apply_crowd_control(spec1, source)

	# Verify target is in CROWD_CONTROLLED
	if data["state_machine"].current_state != MobaState.CROWD_CONTROLLED:
		violations.append("anti_perma_stun: target should be CROWD_CONTROLLED after first stun")

	# Advance 0.3 seconds
	target.tick(0.3)

	# Check remaining (should be ~0.7)
	var remaining_after_tick = target.get_crowd_control_spec(MobaCrowdControlSpec.CCType.STUN)
	if remaining_after_tick == null:
		violations.append("anti_perma_stun: STUN entry should exist after 0.3s tick")
		return violations

	# Second stun: 1.0 second (should set remaining to max(0.7, 1.0) = 1.0)
	var spec2 = MobaCrowdControlSpec.new()
	spec2.type = MobaCrowdControlSpec.CCType.STUN
	spec2.duration = 1.0
	spec2.affected_by_tenacity = false

	target.apply_crowd_control(spec2, source)

	# Verify the remaining duration is 1.0, not 1.7 or 2.0
	# We need to check the internal state; the spec is just returned from the accessor
	# Since we can't directly access the remaining field without a new method,
	# we'll tick and verify expiry behavior
	target.tick(0.99)

	# Should still be CROWD_CONTROLLED
	if data["state_machine"].current_state != MobaState.CROWD_CONTROLLED:
		violations.append("anti_perma_stun: target should still be CROWD_CONTROLLED at 0.99s")

	# Tick 0.02 more (total 1.01)
	target.tick(0.02)

	# Should now be IDLE (stun expired)
	if data["state_machine"].current_state != MobaState.IDLE:
		violations.append("anti_perma_stun: target should be IDLE after 1.01s total")

	return violations


## Test ROOT: blocks move but allows basic_attack and ability
static func _test_rooted_blocks_move() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_combatant()
	var target = data["combatant"]
	var source = MobaCombatant.new()
	source.name = "Source"
	source.stat_block = _BASELINE_STAT_BLOCK
	source._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	source._current_health = source._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Apply ROOT
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.ROOT
	spec.duration = 1.0
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Verify target cannot move
	if target.can_perform_action(&"move"):
		violations.append("rooted_blocks_move: rooted target should not be able to move")

	# Verify target can basic_attack
	if not target.can_perform_action(&"basic_attack"):
		violations.append("rooted_blocks_move: rooted target should be able to basic_attack")

	# Verify target can use ability
	if not target.can_perform_action(&"ability"):
		violations.append("rooted_blocks_move: rooted target should be able to use ability")

	return violations


## Test SILENCE: blocks ability but allows move and basic_attack
static func _test_silenced_blocks_ability() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_combatant()
	var target = data["combatant"]
	var source = MobaCombatant.new()
	source.name = "Source"
	source.stat_block = _BASELINE_STAT_BLOCK
	source._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	source._current_health = source._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Apply SILENCE
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.SILENCE
	spec.duration = 1.0
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Verify target cannot use ability
	if target.can_perform_action(&"ability"):
		violations.append(
			"silenced_blocks_ability: silenced target should not be able to use ability"
		)

	# Verify target can move
	if not target.can_perform_action(&"move"):
		violations.append("silenced_blocks_ability: silenced target should be able to move")

	# Verify target can basic_attack
	if not target.can_perform_action(&"basic_attack"):
		violations.append("silenced_blocks_ability: silenced target should be able to basic_attack")

	return violations


## Test DISARM: blocks basic_attack but allows move and ability
static func _test_disarmed_blocks_basic_attack() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_combatant()
	var target = data["combatant"]
	var source = MobaCombatant.new()
	source.name = "Source"
	source.stat_block = _BASELINE_STAT_BLOCK
	source._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	source._current_health = source._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Apply DISARM
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.DISARM
	spec.duration = 1.0
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Verify target cannot basic_attack
	if target.can_perform_action(&"basic_attack"):
		violations.append(
			"disarmed_blocks_basic_attack: disarmed target should not be able to basic_attack"
		)

	# Verify target can move
	if not target.can_perform_action(&"move"):
		violations.append("disarmed_blocks_basic_attack: disarmed target should be able to move")

	# Verify target can use ability
	if not target.can_perform_action(&"ability"):
		violations.append(
			"disarmed_blocks_basic_attack: disarmed target should be able to use ability"
		)

	return violations


## Test STUN: blocks move, basic_attack, and ability
static func _test_stunned_blocks_all() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_combatant()
	var target = data["combatant"]
	var source = MobaCombatant.new()
	source.name = "Source"
	source.stat_block = _BASELINE_STAT_BLOCK
	source._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	source._current_health = source._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Apply STUN
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.STUN
	spec.duration = 1.0
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Verify target cannot move
	if target.can_perform_action(&"move"):
		violations.append("stunned_blocks_all: stunned target should not be able to move")

	# Verify target cannot basic_attack
	if target.can_perform_action(&"basic_attack"):
		violations.append("stunned_blocks_all: stunned target should not be able to basic_attack")

	# Verify target cannot use ability
	if target.can_perform_action(&"ability"):
		violations.append("stunned_blocks_all: stunned target should not be able to use ability")

	return violations


## Test different CC types coexist: Root + Silence from different sources
static func _test_different_cc_types_coexist() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_combatant()
	var target = data["combatant"]
	var source1 = MobaCombatant.new()
	source1.name = "Source1"
	source1.stat_block = _BASELINE_STAT_BLOCK
	source1._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	source1._current_health = source1._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	var source2 = MobaCombatant.new()
	source2.name = "Source2"
	source2.stat_block = _BASELINE_STAT_BLOCK
	source2._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	source2._current_health = source2._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Apply ROOT from source1
	var spec1 = MobaCrowdControlSpec.new()
	spec1.type = MobaCrowdControlSpec.CCType.ROOT
	spec1.duration = 1.0
	spec1.affected_by_tenacity = false

	target.apply_crowd_control(spec1, source1)

	# Apply SILENCE from source2
	var spec2 = MobaCrowdControlSpec.new()
	spec2.type = MobaCrowdControlSpec.CCType.SILENCE
	spec2.duration = 1.0
	spec2.affected_by_tenacity = false

	target.apply_crowd_control(spec2, source2)

	# Verify both are active
	if not target.has_crowd_control(MobaCrowdControlSpec.CCType.ROOT):
		violations.append("different_cc_types_coexist: ROOT should be active")

	if not target.has_crowd_control(MobaCrowdControlSpec.CCType.SILENCE):
		violations.append("different_cc_types_coexist: SILENCE should be active")

	# Verify restrictions from both apply
	# Should not be able to move (ROOT blocks)
	if target.can_perform_action(&"move"):
		violations.append("different_cc_types_coexist: should not be able to move (ROOT)")

	# Should not be able to use ability (SILENCE blocks)
	if target.can_perform_action(&"ability"):
		violations.append("different_cc_types_coexist: should not be able to use ability (SILENCE)")

	# Should be able to basic_attack (neither blocks it)
	if not target.can_perform_action(&"basic_attack"):
		violations.append("different_cc_types_coexist: should be able to basic_attack")

	return violations


## Test crowd control is refused on DEAD combatants
static func _test_crowd_control_refused_on_dead() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_combatant()
	var target = data["combatant"]
	var source = MobaCombatant.new()
	source.name = "Source"
	source.stat_block = _BASELINE_STAT_BLOCK
	source._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	source._current_health = source._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Kill the target
	target._current_health = 0.0

	# Apply STUN
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.STUN
	spec.duration = 1.0
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Verify target is not in CROWD_CONTROLLED
	if data["state_machine"].current_state == MobaState.CROWD_CONTROLLED:
		violations.append("refused_on_dead: dead target should not enter CROWD_CONTROLLED")

	# Verify the CC entry was not tracked
	if target.has_crowd_control(MobaCrowdControlSpec.CCType.STUN):
		violations.append("refused_on_dead: dead target should not have STUN entry")

	return violations


## Test crowd control is refused while DASHING (displacement_only policy)
static func _test_crowd_control_refused_while_dashing() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_combatant()
	var target = data["combatant"]
	var state_machine = data["state_machine"]
	var source = MobaCombatant.new()
	source.name = "Source"
	source.stat_block = _BASELINE_STAT_BLOCK
	source._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	source._current_health = source._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Enter DASHING state (which has displacement_only policy for hard_cc)
	state_machine.try_enter(MobaState.DASHING, 1.0)

	# Apply STUN (non-displacement hard-CC)
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.STUN
	spec.duration = 1.0
	spec.affected_by_tenacity = false

	target.apply_crowd_control(spec, source)

	# Verify target is not in CROWD_CONTROLLED
	if state_machine.current_state == MobaState.CROWD_CONTROLLED:
		violations.append(
			"refused_while_dashing: target should not enter CROWD_CONTROLLED while DASHING"
		)

	# Verify the CC entry was not tracked
	if target.has_crowd_control(MobaCrowdControlSpec.CCType.STUN):
		violations.append("refused_while_dashing: STUN should not be tracked while DASHING")

	return violations


## Build an attacker (with a loadout+weapon) and a target, both positioned at
## the origin so range is never the limiting factor, mirroring
## LoadoutTest._create_test_actor_with_loadout_and_weapon().
static func _create_attacker_and_target() -> Dictionary:
	var attacker := _TestPositionedNode.new()
	attacker.global_position = Vector3.ZERO

	var attacker_combatant := MobaCombatant.new()
	attacker_combatant.name = "MobaCombatant"
	attacker_combatant.stat_block = _BASELINE_STAT_BLOCK
	attacker_combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	attacker_combatant._current_health = attacker_combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.HEALTH
	)
	attacker_combatant._current_resource = attacker_combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)

	var loadout := MobaLoadout.new()
	var weapon := MobaWeapon.new()
	weapon.damage = 50.0
	weapon.attack_speed = 1.0
	weapon.wind_up = 0.1
	weapon.recovery = 0.2
	weapon.attack_range = 10.0
	weapon.damage_type = MobaDamage.DamageType.PHYSICAL
	loadout.weapon = weapon
	attacker_combatant.loadout = loadout
	attacker.add_child(attacker_combatant)

	var attacker_state_machine := MobaStateMachine.new()
	attacker_state_machine.name = "MobaStateMachine"
	attacker_state_machine._load_state_table()
	attacker.add_child(attacker_state_machine)

	var target := _TestPositionedNode.new()
	target.global_position = Vector3.ZERO

	var target_combatant := MobaCombatant.new()
	target_combatant.name = "MobaCombatant"
	target_combatant.stat_block = _BASELINE_STAT_BLOCK
	target_combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	target_combatant._current_health = target_combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.HEALTH
	)
	target.add_child(target_combatant)

	return {
		"attacker": attacker,
		"attacker_combatant": attacker_combatant,
		"attacker_state_machine": attacker_state_machine,
		"target": target,
		"target_combatant": target_combatant,
	}


## Run one full basic-attack cycle (windup then recovery) from attacker to target.
static func _run_basic_attack_cycle(data: Dictionary) -> void:
	var attacker_combatant: MobaCombatant = data["attacker_combatant"]
	var target_combatant: MobaCombatant = data["target_combatant"]
	var weapon = attacker_combatant.loadout.get_weapon()

	attacker_combatant.basic_attack(target_combatant)
	attacker_combatant.tick(weapon.wind_up + 0.01)
	attacker_combatant.tick(weapon.recovery + 0.01)


## Test that an active BLIND entry on the attacker rolls a miss chance at
## basic-attack resolution: magnitude=1.0 forces the roll (always < 1.0,
## since MobaRules.roll_blind() draws from [0.0, 1.0)) to register as a miss,
## skipping apply_damage() entirely while the attack cycle still completes.
static func _test_blind_causes_attacker_miss() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_attacker_and_target()
	var attacker_combatant: MobaCombatant = data["attacker_combatant"]
	var target_combatant: MobaCombatant = data["target_combatant"]
	var attacker_state_machine: MobaStateMachine = data["attacker_state_machine"]

	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.BLIND
	spec.duration = 5.0
	spec.magnitude = 1.0
	spec.affected_by_tenacity = false
	attacker_combatant.apply_crowd_control(spec, attacker_combatant)

	var target_health_before = target_combatant.current_health
	_run_basic_attack_cycle(data)

	if target_combatant.current_health != target_health_before:
		violations.append(
			(
				"blind_causes_attacker_miss: fully-blinded attacker's hit should have missed,"
				+ " target took damage"
			)
		)

	if attacker_state_machine.current_state != MobaState.IDLE:
		(
			violations
			. append(
				(
					"blind_causes_attacker_miss: attack cycle should still complete (windup/recovery/cooldown)"
					+ " and return attacker to IDLE even on a miss"
				)
			)
		)

	return violations


## Test that a BLIND entry with magnitude=0.0 never causes a miss (the roll,
## drawn from [0.0, 1.0), is never < 0.0), proving the miss-chance branch is
## a magnitude-gated roll and not an unconditional skip.
static func _test_blind_zero_magnitude_never_misses() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_attacker_and_target()
	var attacker_combatant: MobaCombatant = data["attacker_combatant"]
	var target_combatant: MobaCombatant = data["target_combatant"]

	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.BLIND
	spec.duration = 5.0
	spec.magnitude = 0.0
	spec.affected_by_tenacity = false
	attacker_combatant.apply_crowd_control(spec, attacker_combatant)

	var target_health_before = target_combatant.current_health
	_run_basic_attack_cycle(data)

	if target_combatant.current_health >= target_health_before:
		violations.append(
			"blind_zero_magnitude_never_misses: a 0.0-magnitude BLIND should never cause a miss"
		)

	return violations


## Regression test: can_perform_action() must INTERSECT the current real state's
## legality with active CC restrictions once current_state has drifted away from
## CROWD_CONTROLLED, not substitute the CC union for it. BLIND doesn't block
## basic_attack, so applying it and starting an attack succeeds and enters
## BASIC_ATTACK_WINDUP; but mid-windup, the state table alone already forbids a
## NEW attack (BASIC_ATTACK_WINDUP's basic_attack policy is "no"). If
## can_perform_action() ever substituted the CC union for the real state's
## answer instead of intersecting with it, this would wrongly report true.
static func _test_cc_intersects_with_state_outside_crowd_controlled() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_attacker_and_target()
	var attacker_combatant: MobaCombatant = data["attacker_combatant"]
	var target_combatant: MobaCombatant = data["target_combatant"]
	var attacker_state_machine: MobaStateMachine = data["attacker_state_machine"]

	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.BLIND
	spec.duration = 5.0
	spec.magnitude = 1.0
	spec.affected_by_tenacity = false
	attacker_combatant.apply_crowd_control(spec, attacker_combatant)

	if not attacker_combatant.basic_attack(target_combatant):
		violations.append(
			"cc_intersects_with_state: basic_attack should succeed while only BLIND is active"
		)
		return violations

	if attacker_state_machine.current_state != MobaState.BASIC_ATTACK_WINDUP:
		violations.append(
			(
				"cc_intersects_with_state: attacker should be in BASIC_ATTACK_WINDUP"
				+ " after basic_attack()"
			)
		)
		return violations

	if attacker_combatant.can_perform_action(&"basic_attack"):
		violations.append(
			(
				"cc_intersects_with_state: mid-windup should still forbid a new attack even"
				+ " though the only active CC entry (BLIND) doesn't block basic_attack"
			)
		)

	return violations


## Test: get_crowd_control_remaining() returns correct duration for active CC.
static func _test_crowd_control_remaining_duration() -> Array[String]:
	var violations: Array[String] = []

	var data = _create_combatant()
	var target = data["combatant"]
	var source = MobaCombatant.new()
	source.name = "Source"
	source.stat_block = _BASELINE_STAT_BLOCK
	source._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	source._current_health = source._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	source._current_resource = source._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)

	# Before any CC, remaining should be 0.0 for all types
	if not is_equal_approx(target.get_crowd_control_remaining(MobaCrowdControlSpec.CCType.STUN), 0.0):
		violations.append("cc_remaining: should be 0.0 when no STUN active")

	# Apply a 2.0 second stun
	var spec = MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.STUN
	spec.duration = 2.0
	spec.affected_by_tenacity = false
	target.apply_crowd_control(spec, source)

	# Immediately after application, should be close to 2.0
	var remaining_at_start = target.get_crowd_control_remaining(MobaCrowdControlSpec.CCType.STUN)
	if not is_equal_approx(remaining_at_start, 2.0):
		violations.append(
			(
				"cc_remaining: STUN remaining should be ~2.0 at start, got %f"
				% remaining_at_start
			)
		)

	# Advance 0.5 seconds
	target.tick(0.5)

	# Remaining should now be ~1.5
	var remaining_after_half_second = target.get_crowd_control_remaining(MobaCrowdControlSpec.CCType.STUN)
	if not is_equal_approx(remaining_after_half_second, 1.5):
		violations.append(
			(
				"cc_remaining: after 0.5s tick, STUN remaining should be ~1.5, got %f"
				% remaining_after_half_second
			)
		)

	# Advance another 2.0 seconds to expire the CC
	target.tick(2.0)

	# After expiry, should be 0.0
	var remaining_after_expiry = target.get_crowd_control_remaining(MobaCrowdControlSpec.CCType.STUN)
	if not is_equal_approx(remaining_after_expiry, 0.0):
		violations.append(
			(
				"cc_remaining: after expiry, STUN remaining should be 0.0, got %f"
				% remaining_after_expiry
			)
		)

	# Test with multiple CC types coexisting
	var root_spec = MobaCrowdControlSpec.new()
	root_spec.type = MobaCrowdControlSpec.CCType.ROOT
	root_spec.duration = 3.0
	root_spec.affected_by_tenacity = false
	target.apply_crowd_control(root_spec, source)

	# Both should be active with their own durations
	var stun_remaining = target.get_crowd_control_remaining(MobaCrowdControlSpec.CCType.STUN)
	var root_remaining = target.get_crowd_control_remaining(MobaCrowdControlSpec.CCType.ROOT)

	# ROOT should be ~3.0, STUN should be 0.0 (expired)
	if not is_equal_approx(root_remaining, 3.0):
		violations.append(
			(
				"cc_remaining: newly applied ROOT should be ~3.0, got %f"
				% root_remaining
			)
		)

	if not is_equal_approx(stun_remaining, 0.0):
		violations.append(
			(
				"cc_remaining: expired STUN should be 0.0, got %f"
				% stun_remaining
			)
		)

	return violations
