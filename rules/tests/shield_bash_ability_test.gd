## Test suite for the Shield Bash ability's damage and crowd control delivery through the ability pipeline.
##
## Covers rules/data/abilities/shield_bash.tres and MobaAbilityAction's damage and
## effects seams: activating Shield Bash must apply ~40 physical damage (mitigated
## per the target's armor) and put the target into CROWD_CONTROLLED with a 1-second stun.
##
## Lives in its own file to provide end-to-end testing through the real MobaAbilityAction
## pipeline, not direct apply_crowd_control() calls.
class_name ShieldBashAbilityTest

const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaAbilityAction = preload("res://rules/abilities/moba_ability_action.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## Base defensive values this suite pins on the target before activation.
const BASE_ARMOR := 30.0
const BASE_MAGIC_RESISTANCE := 0.0

## Shield Bash's authored base_damage is 40.0
const SHIELD_BASH_BASE_DAMAGE := 40.0

## §8 mitigation: multiplier = 100 / (100 + Defense)
## Unbuffed: 100 / (100 + 30) = 100/130 = ~76.9
const EXPECTED_DAMAGE_AT_BASE_ARMOR := 76.9

## Slack for damage figures
const DAMAGE_TOLERANCE := 0.05

## Stun duration is 1.0 second
const STUN_DURATION := 1.0

## Tick slightly past expiry
const TICK_PAST_EXPIRY := 1.1


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_shield_bash_damage_and_stun())
	all_violations.append_array(_test_shield_bash_stun_expiry())

	if all_violations.is_empty():
		return true

	printerr("\n=== Shield Bash Ability Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Build a caster and target with real MobaCombatant and MobaStateMachine as child nodes.
static func _create_caster_and_target() -> Dictionary:
	var shield_bash_ability = MobaAbilityLibrary.get_ability(&"shield_bash")
	if shield_bash_ability == null:
		return {}

	var caster_actor = Actor.new()
	caster_actor.owner_id = 1

	var caster_combatant = MobaCombatant.new()
	caster_combatant.name = "MobaCombatant"
	caster_combatant.stat_block = _BASELINE_STAT_BLOCK
	caster_combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	caster_combatant._current_health = caster_combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.HEALTH
	)
	caster_combatant._current_resource = caster_combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)
	caster_combatant.register_ability(shield_bash_ability)
	caster_actor.add_child(caster_combatant)

	var caster_state_machine = MobaStateMachine.new()
	caster_state_machine.name = "MobaStateMachine"
	caster_state_machine._load_state_table()
	caster_actor.add_child(caster_state_machine)

	var target_actor = Actor.new()
	target_actor.owner_id = 2

	var target_combatant = MobaCombatant.new()
	target_combatant.name = "MobaCombatant"
	target_combatant.stat_block = _BASELINE_STAT_BLOCK
	target_combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	target_combatant._current_health = target_combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.HEALTH
	)
	target_combatant._current_resource = target_combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)
	target_combatant._runtime_stat_block.armor = BASE_ARMOR
	target_combatant._runtime_stat_block.magic_resistance = BASE_MAGIC_RESISTANCE
	target_actor.add_child(target_combatant)

	var target_state_machine = MobaStateMachine.new()
	target_state_machine.name = "MobaStateMachine"
	target_state_machine._load_state_table()
	target_actor.add_child(target_state_machine)

	return {
		"caster_actor": caster_actor,
		"caster_combatant": caster_combatant,
		"caster_state_machine": caster_state_machine,
		"target_actor": target_actor,
		"target_combatant": target_combatant,
		"target_state_machine": target_state_machine
	}


## Activate Shield Bash on the target through the real ability pipeline.
static func _activate_shield_bash(caster: Node, target: Node):
	var context = MobaCastContext.new(caster, target)
	var action = MobaAbilityAction.new(caster, &"shield_bash", context)
	return action.execute()


## Test 1: Shield Bash applies damage and stuns the target.
static func _test_shield_bash_damage_and_stun() -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()

	var data = _create_caster_and_target()
	if data.is_empty():
		MobaAbilityLibrary._reset()
		violations.append(
			"shield_bash_damage_and_stun: shield_bash.tres did not load as a MobaAbility with id 'shield_bash'"
		)
		return violations

	var caster = data["caster_actor"]
	var target = data["target_actor"]
	var target_combatant = data["target_combatant"]
	var target_state_machine = data["target_state_machine"]

	# Capture pre-activation health
	var target_health_before = target_combatant.current_health

	# Activate Shield Bash
	var result = _activate_shield_bash(caster, target)
	if not result.success:
		violations.append(
			"shield_bash_damage_and_stun: activation should succeed, got: %s" % result.reason
		)

	# Verify damage was applied
	var target_health_after = target_combatant.current_health
	if target_health_after >= target_health_before:
		violations.append(
			"shield_bash_damage_and_stun: target should take damage (before %f, after %f)"
			% [target_health_before, target_health_after]
		)

	# Verify damage is approximately correct (40 base with 30 armor mitigation)
	var damage_taken = target_health_before - target_health_after
	if absf(damage_taken - EXPECTED_DAMAGE_AT_BASE_ARMOR) > DAMAGE_TOLERANCE:
		violations.append(
			(
				"shield_bash_damage_and_stun: damage should be about %f per §8, got %f"
				% [EXPECTED_DAMAGE_AT_BASE_ARMOR, damage_taken]
			)
		)

	# Verify target entered CROWD_CONTROLLED
	if target_state_machine.current_state != MobaState.CROWD_CONTROLLED:
		violations.append(
			"shield_bash_damage_and_stun: target should be CROWD_CONTROLLED, got state %d"
			% target_state_machine.current_state
		)

	# Verify STUN entry is active
	if not target_combatant.has_crowd_control(MobaCrowdControlSpec.CCType.STUN):
		violations.append("shield_bash_damage_and_stun: target should have active STUN")

	# Verify target cannot move while stunned
	if target_combatant.can_perform_action(&"move"):
		violations.append("shield_bash_damage_and_stun: stunned target should not be able to move")

	# Verify target cannot basic_attack while stunned
	if target_combatant.can_perform_action(&"basic_attack"):
		violations.append("shield_bash_damage_and_stun: stunned target should not be able to basic_attack")

	# Verify target cannot use ability while stunned
	if target_combatant.can_perform_action(&"ability"):
		violations.append("shield_bash_damage_and_stun: stunned target should not be able to use ability")

	MobaAbilityLibrary._reset()

	return violations


## Test 2: Shield Bash's stun expires after 1 second, returning to IDLE.
static func _test_shield_bash_stun_expiry() -> Array[String]:
	var violations: Array[String] = []

	MobaAbilityLibrary._reset()

	var data = _create_caster_and_target()
	if data.is_empty():
		MobaAbilityLibrary._reset()
		violations.append(
			"shield_bash_stun_expiry: shield_bash.tres did not load as a MobaAbility with id 'shield_bash'"
		)
		return violations

	var caster = data["caster_actor"]
	var target = data["target_actor"]
	var target_combatant = data["target_combatant"]
	var target_state_machine = data["target_state_machine"]

	# Activate Shield Bash
	var result = _activate_shield_bash(caster, target)
	if not result.success:
		violations.append("shield_bash_stun_expiry: activation should succeed, got: %s" % result.reason)

	# Verify target is stunned
	if target_state_machine.current_state != MobaState.CROWD_CONTROLLED:
		violations.append("shield_bash_stun_expiry: target should be CROWD_CONTROLLED after activation")

	# Advance past stun duration
	target_combatant.tick(TICK_PAST_EXPIRY)

	# Verify target is back to IDLE
	if target_state_machine.current_state != MobaState.IDLE:
		violations.append(
			"shield_bash_stun_expiry: target should be IDLE after stun expires, got state %d"
			% target_state_machine.current_state
		)

	# Verify STUN entry is no longer active
	if target_combatant.has_crowd_control(MobaCrowdControlSpec.CCType.STUN):
		violations.append("shield_bash_stun_expiry: target should not have STUN after expiry")

	# Verify target can act again
	if not target_combatant.can_perform_action(&"move"):
		violations.append("shield_bash_stun_expiry: target should be able to move after stun expires")

	if not target_combatant.can_perform_action(&"basic_attack"):
		violations.append("shield_bash_stun_expiry: target should be able to basic_attack after stun expires")

	if not target_combatant.can_perform_action(&"ability"):
		violations.append("shield_bash_stun_expiry: target should be able to use ability after stun expires")

	MobaAbilityLibrary._reset()

	return violations
