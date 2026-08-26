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
		violations.append("silenced_blocks_ability: silenced target should not be able to use ability")

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
		violations.append("disarmed_blocks_basic_attack: disarmed target should not be able to basic_attack")

	# Verify target can move
	if not target.can_perform_action(&"move"):
		violations.append("disarmed_blocks_basic_attack: disarmed target should be able to move")

	# Verify target can use ability
	if not target.can_perform_action(&"ability"):
		violations.append("disarmed_blocks_basic_attack: disarmed target should be able to use ability")

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
		violations.append("refused_while_dashing: target should not enter CROWD_CONTROLLED while DASHING")

	# Verify the CC entry was not tracked
	if target.has_crowd_control(MobaCrowdControlSpec.CCType.STUN):
		violations.append("refused_while_dashing: STUN should not be tracked while DASHING")

	return violations
