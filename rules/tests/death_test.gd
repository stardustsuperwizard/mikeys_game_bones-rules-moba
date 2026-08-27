## Test suite for death/respawn feature.
##
## Covers: death transitions to DEAD state exactly once, dead combatants refuse
## damage/healing/actions, effects/shields/CC clear on death, respawn() restores
## state and returns to IDLE, effects/shields/CC do not survive respawn.
class_name DeathTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaDamage = preload("res://rules/core/moba_damage.gd")
const MobaState = preload("res://rules/state/moba_state.gd")
const MobaCrowdControlSpec = preload("res://rules/effects/moba_crowd_control_spec.gd")
const MobaStatModifier = preload("res://rules/effects/moba_stat_modifier.gd")
const MobaRespawnPolicy = preload("res://rules/core/moba_respawn_policy.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")


## Build a respawn policy for tests without referencing production scene/resource
## data (rules/ files may not reference res://resources/ or res://scenes/ --
## see extraction_contract_test.gd). A bare SpawnPoint with only a transform
## is all respawn() reads.
static func _make_test_respawn_policy() -> MobaRespawnPolicy:
	var spawn_point = SpawnPoint.new()
	spawn_point.transform = Transform3D.IDENTITY
	var policy = MobaRespawnPolicy.new()
	policy.respawns = true
	policy.respawn_delay = 3.0
	policy.spawn_point = spawn_point
	return policy


## Run the death/respawn test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []

	# Test 1: Death transitions to DEAD state exactly once
	var death_once_violations = _test_death_fires_once()
	all_violations.append_array(death_once_violations)

	# Test 2: Dead combatant refuses apply_damage
	var dead_refuses_damage_violations = _test_dead_refuses_damage()
	all_violations.append_array(dead_refuses_damage_violations)

	# Test 3: Dead combatant refuses apply_healing
	var dead_refuses_healing_violations = _test_dead_refuses_healing()
	all_violations.append_array(dead_refuses_healing_violations)

	# Test 4: Dead combatant refuses can_perform_action
	var dead_refuses_actions_violations = _test_dead_refuses_actions()
	all_violations.append_array(dead_refuses_actions_violations)

	# Test 5: Effects/shields/CC clear on death
	var clear_on_death_violations = _test_clear_on_death()
	all_violations.append_array(clear_on_death_violations)

	# Test 6: respawn() restores health/resource and returns IDLE
	var respawn_restores_violations = _test_respawn_restores_state()
	all_violations.append_array(respawn_restores_violations)

	# Test 7: respawn() clears cooldowns
	var respawn_clears_cooldowns_violations = _test_respawn_clears_cooldowns()
	all_violations.append_array(respawn_clears_cooldowns_violations)

	# Test 8: Effects/shields/CC do not survive respawn
	var effects_cleared_on_respawn_violations = _test_effects_cleared_on_respawn()
	all_violations.append_array(effects_cleared_on_respawn_violations)

	# Test 9: respawn() on living combatant is refused
	var respawn_on_living_violations = _test_respawn_on_living_refused()
	all_violations.append_array(respawn_on_living_violations)

	# Test 10: Applying CC/shield to an already-dead combatant is refused
	var dead_refuses_cc_and_shield_violations = _test_dead_refuses_cc_and_shield()
	all_violations.append_array(dead_refuses_cc_and_shield_violations)

	if all_violations.is_empty():
		return true

	# Print violations
	printerr("\n=== Death Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Test: Death transitions to DEAD state exactly once
static func _test_death_fires_once() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Add a mock state machine
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"
	parent.add_child(combatant)
	combatant.add_to_group("test")

	# Apply lethal damage
	var damage = MobaDamage.new(
		1000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(damage)

	if state_machine.current_state != MobaState.DEAD:
		violations.append(
			"death_fires_once: expected state DEAD, got %d" % state_machine.current_state
		)

	# Apply lethal damage again - should be refused
	var damage2 = MobaDamage.new(
		1000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	var health_before = combatant.current_health
	combatant.apply_damage(damage2)
	var health_after = combatant.current_health

	if health_before != health_after:
		(
			violations
			. append(
				(
					"death_fires_once: second lethal damage should not change health (before=%f, after=%f)"
					% [health_before, health_after]
				)
			)
		)

	parent.queue_free()
	return violations


## Test: Dead combatant refuses apply_damage
static func _test_dead_refuses_damage() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Add a mock state machine and parent
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"
	parent.add_child(combatant)

	# Kill the combatant
	var lethal_damage = MobaDamage.new(
		1000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(lethal_damage)

	# Try to apply damage to dead combatant
	var health_when_dead = combatant.current_health
	var damage = MobaDamage.new(
		10.0, MobaDamage.DamageType.PHYSICAL, combatant, false, 0.0, 0.0, false
	)

	# damage_resolved should NOT be emitted
	var damage_resolved_emitted = false
	combatant.damage_resolved.connect(
		func(_raw, _final, _type, _crit, _source): damage_resolved_emitted = true
	)

	combatant.apply_damage(damage)

	if combatant.current_health != health_when_dead:
		violations.append(
			"dead_refuses_damage: health changed when applying damage to dead combatant"
		)

	if damage_resolved_emitted:
		violations.append("dead_refuses_damage: damage_resolved was emitted for a dead combatant")

	parent.queue_free()
	return violations


## Test: Dead combatant refuses apply_healing
static func _test_dead_refuses_healing() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Add a mock state machine and parent
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"
	parent.add_child(combatant)

	# Kill the combatant
	var lethal_damage = MobaDamage.new(
		1000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(lethal_damage)

	# Try to heal dead combatant
	var heal_amount = combatant.apply_healing(100.0)

	if heal_amount != 0.0:
		violations.append(
			"dead_refuses_healing: apply_healing returned %f, expected 0.0" % heal_amount
		)

	if combatant.current_health > 0.0:
		violations.append("dead_refuses_healing: health increased on dead combatant")

	parent.queue_free()
	return violations


## Test: Dead combatant refuses actions
static func _test_dead_refuses_actions() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Add a mock state machine and parent
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"
	parent.add_child(combatant)

	# Kill the combatant
	var lethal_damage = MobaDamage.new(
		1000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(lethal_damage)

	# Test move, basic_attack, ability all return false
	if combatant.can_perform_action(&"move"):
		violations.append("dead_refuses_actions: move allowed while DEAD")

	if combatant.can_perform_action(&"basic_attack"):
		violations.append("dead_refuses_actions: basic_attack allowed while DEAD")

	if combatant.can_perform_action(&"ability"):
		violations.append("dead_refuses_actions: ability allowed while DEAD")

	parent.queue_free()
	return violations


## Test: Effects/shields/CC clear on death
static func _test_clear_on_death() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Add a mock state machine and parent
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"
	parent.add_child(combatant)

	# Add some effects, shields, and CC
	var effect_container = combatant.get_effect_container()
	var modifier = MobaStatModifier.new()
	modifier.stat = MobaStatBlock.ATTACK_DAMAGE
	modifier.amount = 10.0
	modifier.is_percentage = false
	modifier.duration = 10.0
	modifier.stacking = MobaStatModifier.Stacking.REFRESH
	effect_container.apply_modifier(modifier, &"test_ability")

	combatant.apply_shield(100.0, &"test", 10.0)

	var cc_spec = MobaCrowdControlSpec.new()
	cc_spec.type = MobaCrowdControlSpec.CCType.STUN
	cc_spec.duration = 5.0
	cc_spec.affected_by_tenacity = false
	combatant.apply_crowd_control(cc_spec, combatant)

	# Kill the combatant
	var lethal_damage = MobaDamage.new(
		1000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(lethal_damage)

	# Check that modifiers are cleared
	if effect_container.has_modifier(&"test_ability", MobaStatBlock.ATTACK_DAMAGE):
		violations.append("clear_on_death: modifiers not cleared on death")

	# Check that shields are cleared
	if combatant.total_shield() > 0.0:
		violations.append(
			"clear_on_death: shields not cleared on death (remaining=%f)" % combatant.total_shield()
		)

	# Check that CC is cleared
	if not combatant._active_cc_entries.is_empty():
		violations.append("clear_on_death: CC entries not cleared on death")

	parent.queue_free()
	return violations


## Test: respawn() restores health/resource and returns IDLE
static func _test_respawn_restores_state() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant.respawn_policy = _make_test_respawn_policy()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)

	var max_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	var max_resource = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.RESOURCE)

	# Add a mock state machine and parent
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"

	# Add a Body node (required for respawn to work)
	var body = Node3D.new()
	body.name = "Body"
	parent.add_child(body)

	parent.add_child(combatant)

	# Kill the combatant
	var lethal_damage = MobaDamage.new(
		1000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(lethal_damage)

	if state_machine.current_state != MobaState.DEAD:
		violations.append("respawn_restores_state: combatant not in DEAD state before respawn")

	# Call respawn
	var respawn_result = combatant.respawn()

	if not respawn_result:
		violations.append("respawn_restores_state: respawn() returned false")

	if combatant.current_health != max_health:
		violations.append(
			(
				"respawn_restores_state: health not restored to maximum (expected=%f, actual=%f)"
				% [max_health, combatant.current_health]
			)
		)

	if combatant.current_resource != max_resource:
		violations.append(
			(
				"respawn_restores_state: resource not restored to maximum (expected=%f, actual=%f)"
				% [max_resource, combatant.current_resource]
			)
		)

	if state_machine.current_state != MobaState.IDLE:
		violations.append(
			(
				"respawn_restores_state: state is not IDLE after respawn (state=%d)"
				% state_machine.current_state
			)
		)

	parent.queue_free()
	return violations


## Test: respawn() clears cooldowns
static func _test_respawn_clears_cooldowns() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant.respawn_policy = _make_test_respawn_policy()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Add a mock state machine and parent
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"

	var body = Node3D.new()
	body.name = "Body"
	parent.add_child(body)

	parent.add_child(combatant)

	# Start a cooldown
	combatant._cooldowns.start(&"test_ability", 5.0, 0.0, 1)

	# Kill and respawn
	var lethal_damage = MobaDamage.new(
		1000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(lethal_damage)
	combatant.respawn()

	# Check that cooldown is cleared
	var remaining = combatant.get_cooldown_remaining(&"test_ability")
	if remaining > 0.0:
		violations.append(
			(
				"respawn_clears_cooldowns: cooldown not cleared after respawn (remaining=%f)"
				% remaining
			)
		)

	parent.queue_free()
	return violations


## Test: Effects/shields/CC do not survive respawn
static func _test_effects_cleared_on_respawn() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant.respawn_policy = _make_test_respawn_policy()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Add a mock state machine and parent
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"

	var body = Node3D.new()
	body.name = "Body"
	parent.add_child(body)

	parent.add_child(combatant)

	# Add effects, shields, and CC
	var effect_container = combatant.get_effect_container()
	var modifier = MobaStatModifier.new()
	modifier.stat = MobaStatBlock.ATTACK_DAMAGE
	modifier.amount = 10.0
	modifier.is_percentage = false
	modifier.duration = 10.0
	modifier.stacking = MobaStatModifier.Stacking.REFRESH
	effect_container.apply_modifier(modifier, &"test_ability")

	combatant.apply_shield(100.0, &"test", 10.0)

	var cc_spec = MobaCrowdControlSpec.new()
	cc_spec.type = MobaCrowdControlSpec.CCType.STUN
	cc_spec.duration = 5.0
	cc_spec.affected_by_tenacity = false
	combatant.apply_crowd_control(cc_spec, combatant)

	# Kill and respawn
	var lethal_damage = MobaDamage.new(
		1000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(lethal_damage)
	combatant.respawn()

	# Check that everything is cleared
	if effect_container.has_modifier(&"test_ability", MobaStatBlock.ATTACK_DAMAGE):
		violations.append("effects_cleared_on_respawn: modifiers not cleared on respawn")

	if combatant.total_shield() > 0.0:
		violations.append(
			(
				"effects_cleared_on_respawn: shields not cleared on respawn (remaining=%f)"
				% combatant.total_shield()
			)
		)

	if not combatant._active_cc_entries.is_empty():
		violations.append("effects_cleared_on_respawn: CC entries not cleared on respawn")

	parent.queue_free()
	return violations


## Test: respawn() on living combatant is refused
static func _test_respawn_on_living_refused() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant.respawn_policy = _make_test_respawn_policy()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Add a mock state machine and parent
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"

	var body = Node3D.new()
	body.name = "Body"
	parent.add_child(body)

	parent.add_child(combatant)

	# Call respawn on living combatant
	var respawn_result = combatant.respawn()

	if respawn_result:
		violations.append("respawn_on_living_refused: respawn() returned true for living combatant")

	if state_machine.current_state != MobaState.IDLE:
		(
			violations
			. append(
				(
					"respawn_on_living_refused: state changed when calling respawn on living combatant (state=%d)"
					% state_machine.current_state
				)
			)
		)

	parent.queue_free()
	return violations


## Test: Applying crowd control or a shield to an already-dead combatant is
## refused -- distinct from _test_clear_on_death(), which only checks that
## pre-existing CC/shields/effects are cleared *at the moment* death fires,
## not that further attempts to apply them while DEAD are rejected.
static func _test_dead_refuses_cc_and_shield() -> Array[String]:
	var violations: Array[String] = []

	var combatant = MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)

	# Add a mock state machine and parent
	var state_machine = MobaStateMachine.new()
	state_machine._ready()
	var parent = Node.new()
	parent.add_child(state_machine)
	state_machine.name = "MobaStateMachine"
	parent.add_child(combatant)

	# Kill the combatant
	var lethal_damage = MobaDamage.new(
		1000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(lethal_damage)

	# Attempt to apply CC to the now-dead combatant
	var cc_spec = MobaCrowdControlSpec.new()
	cc_spec.type = MobaCrowdControlSpec.CCType.STUN
	cc_spec.duration = 5.0
	cc_spec.affected_by_tenacity = false
	combatant.apply_crowd_control(cc_spec, combatant)

	if not combatant._active_cc_entries.is_empty():
		violations.append("dead_refuses_cc_and_shield: CC applied to a dead combatant")

	# Attempt to apply a shield to the now-dead combatant
	combatant.apply_shield(100.0, &"test", 10.0)

	if combatant.total_shield() > 0.0:
		violations.append(
			(
				"dead_refuses_cc_and_shield: shield applied to a dead combatant (total=%f)"
				% combatant.total_shield()
			)
		)

	parent.queue_free()
	return violations
