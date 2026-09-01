## Test suite for the settable replication properties added for #313.
##
## A MultiplayerSynchronizer applying a server-authoritative value on a remote
## peer assigns through the ordinary property setter. These checks pin that
## such an assignment drives the same signal a local mutation would have, so
## the HUD binders -- which observe signals, never polled properties -- cannot
## tell a replicated change from a local one.
##
## Signal observation uses a Dictionary rather than a plain local bool because
## GDScript lambdas capture locals by value: `var fired := false` reassigned
## inside a lambda mutates the lambda's own copy and the outer variable stays
## false, which would make every check here pass vacuously. This matches the
## `seen := {...}` convention already used in effect_container_test.gd.
class_name ReplicationPropertiesTest

const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")


## Run the replication properties test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_settable_current_health())
	all_violations.append_array(_test_settable_current_resource())
	all_violations.append_array(_test_settable_shields_snapshot())
	all_violations.append_array(_test_settable_effects_snapshot())
	all_violations.append_array(_test_settable_cooldowns_snapshot())
	all_violations.append_array(_test_settable_state_machine_state())
	all_violations.append_array(_test_state_machine_no_double_emit())
	all_violations.append_array(_test_unchanged_snapshot_is_silent())
	all_violations.append_array(_test_snapshot_reconciles_changes())
	all_violations.append_array(_test_spawn_state_before_ready())

	if all_violations.is_empty():
		return true

	printerr("\n=== Replication Properties Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Build a combatant with the baseline stat block at full health.
static func _make_combatant() -> MobaCombatant:
	var combatant := MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	return combatant


## Assigning current_health emits health_changed with the applied value.
static func _test_settable_current_health() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var seen := {"fired": false, "health": 0.0}
	combatant.health_changed.connect(
		func(current: float, _maximum: float):
			seen["fired"] = true
			seen["health"] = current
	)

	var new_health := 250.0
	combatant.current_health = new_health

	if not seen["fired"]:
		violations.append("settable_current_health: health_changed signal was not emitted")
	elif not is_equal_approx(seen["health"], new_health):
		violations.append(
			(
				"settable_current_health: signal reported health %f, expected %f"
				% [seen["health"], new_health]
			)
		)

	if not is_equal_approx(combatant.current_health, new_health):
		violations.append(
			(
				"settable_current_health: current_health is %f, expected %f"
				% [combatant.current_health, new_health]
			)
		)

	return violations


## Assigning current_resource emits resource_changed with the applied value.
static func _test_settable_current_resource() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	combatant._current_resource = 100.0

	var seen := {"fired": false, "resource": 0.0}
	combatant.resource_changed.connect(
		func(current: float, _maximum: float):
			seen["fired"] = true
			seen["resource"] = current
	)

	var new_resource := 50.0
	combatant.current_resource = new_resource

	if not seen["fired"]:
		violations.append("settable_current_resource: resource_changed signal was not emitted")
	elif not is_equal_approx(seen["resource"], new_resource):
		violations.append(
			(
				"settable_current_resource: signal reported resource %f, expected %f"
				% [seen["resource"], new_resource]
			)
		)

	if not is_equal_approx(combatant.current_resource, new_resource):
		violations.append(
			(
				"settable_current_resource: current_resource is %f, expected %f"
				% [combatant.current_resource, new_resource]
			)
		)

	return violations


## Assigning active_shields_snapshot rebuilds the pool and emits shield_changed
## exactly once, with each shield's mid-life `remaining` preserved.
static func _test_settable_shields_snapshot() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var seen := {"count": 0, "total": 0.0}
	combatant.shield_changed.connect(
		func(total: float):
			seen["count"] += 1
			seen["total"] = total
	)

	combatant.active_shields_snapshot = [
		{"amount": 100.0, "source": &"test_shield", "remaining": 5.0},
		{"amount": 50.0, "source": &"another_shield", "remaining": 3.0},
	]

	if seen["count"] == 0:
		violations.append("settable_shields_snapshot: shield_changed signal was not emitted")
	elif seen["count"] != 1:
		violations.append(
			(
				"settable_shields_snapshot: shield_changed emitted %d times, expected exactly 1"
				% seen["count"]
			)
		)

	if not is_equal_approx(seen["total"], 150.0):
		violations.append(
			"settable_shields_snapshot: signal reported total %f, expected 150.0" % seen["total"]
		)

	var active_shields := combatant.get_active_shields()
	if active_shields.size() != 2:
		violations.append(
			"settable_shields_snapshot: expected 2 shields, got %d" % active_shields.size()
		)
	else:
		# The snapshot carries elapsed time, not the original duration: a
		# restored shield must not silently reset to full duration.
		if not is_equal_approx(active_shields[0].remaining, 5.0):
			violations.append(
				(
					"settable_shields_snapshot: first shield remaining is %f, expected 5.0"
					% active_shields[0].remaining
				)
			)
		if active_shields[0].source != &"test_shield":
			violations.append("settable_shields_snapshot: first shield lost its source")

	if not is_equal_approx(combatant.total_shield(), 150.0):
		violations.append(
			(
				"settable_shields_snapshot: total_shield is %f, expected 150.0"
				% combatant.total_shield()
			)
		)

	# The snapshot is the whole pool, not an addition to it: re-applying an
	# empty snapshot must clear the shields rather than leave them standing.
	combatant.active_shields_snapshot = []
	if not is_equal_approx(combatant.total_shield(), 0.0):
		violations.append(
			(
				"settable_shields_snapshot: empty snapshot left total_shield at %f, expected 0.0"
				% combatant.total_shield()
			)
		)

	return violations


## Assigning active_effects_snapshot applies the effects and emits
## effect_applied, so the status tray updates on a remote peer.
static func _test_settable_effects_snapshot() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var seen := {"applied": 0}
	combatant.get_effect_container().effect_applied.connect(
		func(_source_id: StringName, _stat: StringName): seen["applied"] += 1
	)

	combatant.active_effects_snapshot = [
		{
			"source_ability_id": &"test_ability",
			"stat": MobaStatBlock.ARMOR,
			"magnitude": 10.0,
			"is_percentage": false,
			"remaining": 5.0,
			"stacks": 1,
			"max_stacks": 1,
			"is_debuff": false,
		}
	]

	if seen["applied"] == 0:
		violations.append("settable_effects_snapshot: effect_applied signal was not emitted")

	var container := combatant.get_effect_container()
	if not container.has_modifier(&"test_ability", MobaStatBlock.ARMOR):
		violations.append(
			"settable_effects_snapshot: modifier was not found after setting snapshot"
		)

	var flat_bonus := container.get_flat_bonus(MobaStatBlock.ARMOR)
	if not is_equal_approx(flat_bonus, 10.0):
		violations.append(
			"settable_effects_snapshot: armor bonus is %f, expected 10.0" % flat_bonus
		)

	# A round trip through get_snapshot()/set_snapshot() must be lossless, or
	# replicated effects would drift from the server's every time they resend.
	var round_tripped: Array = container.get_snapshot()
	if round_tripped.size() != 1:
		violations.append(
			(
				"settable_effects_snapshot: get_snapshot returned %d entries, expected 1"
				% round_tripped.size()
			)
		)

	return violations


## Assigning active_cooldowns_snapshot restores remaining time and charges, so
## a client's own ability slots show the server's cooldown state.
static func _test_settable_cooldowns_snapshot() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()

	var ability := MobaAbility.new()
	ability.id = "test_ability"
	ability.cooldown = 5.0
	ability.charges = 1
	combatant.register_ability(ability)

	combatant.active_cooldowns_snapshot = [
		{
			"ability_id": &"test_ability",
			"timer_remaining": 3.5,
			"available_charges": 0,
		}
	]

	var remaining := combatant.get_cooldown_remaining(&"test_ability")
	if not is_equal_approx(remaining, 3.5):
		violations.append("settable_cooldowns_snapshot: remaining is %f, expected 3.5" % remaining)

	var charges := combatant.get_charges(&"test_ability")
	if charges != 0:
		violations.append("settable_cooldowns_snapshot: charges is %d, expected 0" % charges)

	return violations


## Assigning current_state emits state_changed(from, to) exactly as a local
## try_enter() would, and stays silent on a same-state assignment.
static func _test_settable_state_machine_state() -> Array[String]:
	var violations: Array[String] = []

	var state_machine := MobaStateMachine.new()
	state_machine._ready()

	var seen := {"count": 0, "from": -1, "to": -1}
	state_machine.state_changed.connect(
		func(from: int, to: int):
			seen["count"] += 1
			seen["from"] = from
			seen["to"] = to
	)

	state_machine.current_state = MobaState.MOVING

	if seen["count"] == 0:
		violations.append("settable_state_machine_state: state_changed signal was not emitted")
	else:
		if seen["count"] != 1:
			violations.append(
				(
					"settable_state_machine_state: state_changed emitted %d times, expected 1"
					% seen["count"]
				)
			)
		if seen["from"] != MobaState.IDLE:
			violations.append(
				(
					"settable_state_machine_state: signal reported from_state %d, expected %d"
					% [seen["from"], MobaState.IDLE]
				)
			)
		if seen["to"] != MobaState.MOVING:
			violations.append(
				(
					"settable_state_machine_state: signal reported to_state %d, expected %d"
					% [seen["to"], MobaState.MOVING]
				)
			)

	if state_machine.current_state != MobaState.MOVING:
		violations.append(
			(
				"settable_state_machine_state: current_state is %d, expected %d"
				% [state_machine.current_state, MobaState.MOVING]
			)
		)

	# Re-entry is silent on the local path (try_enter returns true without
	# emitting), so a redundant replicated value must be silent too.
	seen["count"] = 0
	state_machine.current_state = MobaState.MOVING
	if seen["count"] != 0:
		violations.append(
			"settable_state_machine_state: state_changed should not emit when setting to same state"
		)

	return violations


## The local transition paths must keep emitting state_changed exactly once.
##
## Regression guard: routing try_enter()/tick()/revive() through the new
## setter instead of the backing field would emit twice per transition and
## would emit before `remaining` was consistent.
static func _test_state_machine_no_double_emit() -> Array[String]:
	var violations: Array[String] = []

	var state_machine := MobaStateMachine.new()
	state_machine._ready()

	var seen := {"count": 0}
	state_machine.state_changed.connect(func(_from: int, _to: int): seen["count"] += 1)

	state_machine.try_enter(MobaState.MOVING)
	if seen["count"] != 1:
		violations.append(
			"state_machine_no_double_emit: try_enter emitted %d times, expected 1" % seen["count"]
		)

	# A duration-bearing entry, then expiry through tick(), is one emit each.
	seen["count"] = 0
	state_machine.try_enter(MobaState.ABILITY_CAST, 1.0)
	if seen["count"] != 1:
		violations.append(
			(
				"state_machine_no_double_emit: try_enter(ABILITY_CAST) emitted %d times, expected 1"
				% seen["count"]
			)
		)
	if not is_equal_approx(state_machine.remaining, 1.0):
		violations.append(
			(
				"state_machine_no_double_emit: remaining is %f after try_enter, expected 1.0"
				% state_machine.remaining
			)
		)

	seen["count"] = 0
	state_machine.tick(1.5)
	if seen["count"] != 1:
		violations.append(
			"state_machine_no_double_emit: tick expiry emitted %d times, expected 1" % seen["count"]
		)
	if state_machine.current_state != MobaState.IDLE:
		violations.append("state_machine_no_double_emit: tick expiry did not return to IDLE")

	return violations


## Re-applying an identical snapshot must emit nothing at all.
##
## Regression guard for the clear-and-rebuild the snapshot setters used to do.
## The snapshots carry `remaining`, which decays every tick on the authority,
## so these properties re-arrive every frame while anything is active. A
## teardown-and-recreate emitted effect_expired + effect_applied per entry per
## frame, which frees and rebuilds every status tray icon ~60x/second, while
## the local path for a steady effect emits nothing.
static func _test_unchanged_snapshot_is_silent() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	var effects_snapshot: Array = [
		{
			"source_ability_id": &"steady_buff",
			"stat": MobaStatBlock.ARMOR,
			"magnitude": 10.0,
			"is_percentage": false,
			"duration": 8.0,
			"remaining": 5.0,
			"stacks": 1,
			"max_stacks": 3,
			"is_debuff": false,
		}
	]
	var shields_snapshot: Array = [
		{"amount": 100.0, "source": &"steady_shield", "remaining": 5.0},
	]

	combatant.active_effects_snapshot = effects_snapshot
	combatant.active_shields_snapshot = shields_snapshot

	# Count only what happens after the initial apply.
	var seen := {"applied": 0, "expired": 0, "refreshed": 0, "stacks": 0, "shield": 0}
	container.effect_applied.connect(
		func(_source: StringName, _stat: StringName): seen["applied"] += 1
	)
	container.effect_expired.connect(
		func(_source: StringName, _stat: StringName): seen["expired"] += 1
	)
	container.effect_refreshed.connect(
		func(_source: StringName, _stat: StringName): seen["refreshed"] += 1
	)
	container.effect_stacks_changed.connect(
		func(_source: StringName, _stat: StringName, _stacks: int): seen["stacks"] += 1
	)
	combatant.shield_changed.connect(func(_total: float): seen["shield"] += 1)

	# Re-send the identical snapshot the way an on-change property would.
	for _i in range(5):
		combatant.active_effects_snapshot = effects_snapshot
		combatant.active_shields_snapshot = shields_snapshot

	for key in ["applied", "expired", "refreshed", "stacks", "shield"]:
		if seen[key] != 0:
			(
				violations
				. append(
					(
						"unchanged_snapshot_is_silent: %s emitted %d times over 5 identical re-applies, expected 0"
						% [key, seen[key]]
					)
				)
			)

	# Silence must not mean "did nothing": the state is still there.
	if not container.has_modifier(&"steady_buff", MobaStatBlock.ARMOR):
		violations.append("unchanged_snapshot_is_silent: the effect was lost")
	if not is_equal_approx(combatant.total_shield(), 100.0):
		violations.append(
			(
				"unchanged_snapshot_is_silent: total_shield is %f, expected 100.0"
				% combatant.total_shield()
			)
		)

	# A decaying `remaining` is the common case and must also stay silent.
	var decayed: Array = [effects_snapshot[0].duplicate()]
	decayed[0]["remaining"] = 4.0
	combatant.active_effects_snapshot = decayed
	if seen["applied"] != 0 or seen["expired"] != 0 or seen["refreshed"] != 0:
		violations.append("unchanged_snapshot_is_silent: a decaying remaining should emit nothing")

	return violations


## A snapshot that genuinely changes must still emit the right signal.
##
## The counterpart to the silence check above: reconciling must not go so far
## that a real change stops reaching the HUD.
static func _test_snapshot_reconciles_changes() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	var base_entry := {
		"source_ability_id": &"buff",
		"stat": MobaStatBlock.ARMOR,
		"magnitude": 10.0,
		"is_percentage": false,
		"duration": 8.0,
		"remaining": 5.0,
		"stacks": 1,
		"max_stacks": 3,
		"is_debuff": false,
	}
	combatant.active_effects_snapshot = [base_entry]

	var seen := {"applied": 0, "expired": 0, "refreshed": 0, "stacks": 0}
	container.effect_applied.connect(
		func(_source: StringName, _stat: StringName): seen["applied"] += 1
	)
	container.effect_expired.connect(
		func(_source: StringName, _stat: StringName): seen["expired"] += 1
	)
	container.effect_refreshed.connect(
		func(_source: StringName, _stat: StringName): seen["refreshed"] += 1
	)
	container.effect_stacks_changed.connect(
		func(_source: StringName, _stat: StringName, _stacks: int): seen["stacks"] += 1
	)

	# A stack gain reports as a stack change, once.
	var stacked := base_entry.duplicate()
	stacked["stacks"] = 2
	combatant.active_effects_snapshot = [stacked]
	if seen["stacks"] != 1:
		violations.append(
			(
				"snapshot_reconciles_changes: stack gain emitted %d stacks_changed, expected 1"
				% seen["stacks"]
			)
		)

	# remaining going back up is a refresh on the authority.
	var refreshed := stacked.duplicate()
	refreshed["remaining"] = 8.0
	combatant.active_effects_snapshot = [refreshed]
	if seen["refreshed"] != 1:
		violations.append(
			(
				"snapshot_reconciles_changes: refresh emitted %d effect_refreshed, expected 1"
				% seen["refreshed"]
			)
		)

	# A new identity is an apply, and the old one going away is an expiry.
	var replacement := base_entry.duplicate()
	replacement["source_ability_id"] = &"other_buff"
	combatant.active_effects_snapshot = [replacement]
	if seen["applied"] != 1:
		violations.append(
			(
				"snapshot_reconciles_changes: new identity emitted %d effect_applied, expected 1"
				% seen["applied"]
			)
		)
	if seen["expired"] != 1:
		(
			violations
			. append(
				(
					"snapshot_reconciles_changes: removed identity emitted %d effect_expired, expected 1"
					% seen["expired"]
				)
			)
		)

	# An empty snapshot clears the container.
	combatant.active_effects_snapshot = []
	if container.has_modifier(&"other_buff", MobaStatBlock.ARMOR):
		violations.append("snapshot_reconciles_changes: empty snapshot left an effect behind")

	# Cooldown snapshots must round-trip the duration, not fabricate it from
	# the remaining time -- an ability slot draws remaining over duration.
	var ability := MobaAbility.new()
	ability.id = "cd_ability"
	ability.cooldown = 10.0
	ability.charges = 1
	combatant.register_ability(ability)
	combatant.active_cooldowns_snapshot = [
		{
			"ability_id": &"cd_ability",
			"timer_remaining": 2.5,
			"timer_duration": 10.0,
			"available_charges": 0,
		}
	]
	var round_tripped: Array = combatant.active_cooldowns_snapshot
	if round_tripped.size() != 1:
		violations.append("snapshot_reconciles_changes: cooldown snapshot did not round-trip")
	elif not is_equal_approx(float(round_tripped[0].get("timer_duration", 0.0)), 10.0):
		violations.append(
			(
				"snapshot_reconciles_changes: cooldown timer_duration is %f, expected 10.0"
				% float(round_tripped[0].get("timer_duration", 0.0))
			)
		)

	return violations


## Replicated spawn state arrives before _ready(); the combatant must cope.
##
## A MultiplayerSynchronizer applies spawn-state properties during add_child(),
## inside ENTER_TREE. Before this was handled, the setters faulted on a null
## _runtime_stat_block and _ready() then overwrote the replicated health with a
## full-health default, so a peer joining mid-fight saw full health.
static func _test_spawn_state_before_ready() -> Array[String]:
	var violations: Array[String] = []

	# Deliberately NOT _make_combatant(): that seeds _runtime_stat_block, which
	# is the very thing absent before _ready() runs.
	var combatant := MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK

	var seen := {"health": 0}
	combatant.health_changed.connect(func(_c: float, _m: float): seen["health"] += 1)

	combatant.current_health = 120.0

	if seen["health"] == 0:
		violations.append(
			"spawn_state_before_ready: health_changed did not fire for a pre-_ready assignment"
		)
	if not is_equal_approx(combatant.current_health, 120.0):
		violations.append(
			(
				"spawn_state_before_ready: current_health is %f, expected 120.0"
				% combatant.current_health
			)
		)
	if combatant.maximum_health <= 0.0:
		violations.append(
			(
				"spawn_state_before_ready: maximum_health unavailable before _ready() (%f)"
				% combatant.maximum_health
			)
		)

	# _ready() must leave a replicated value alone rather than resetting to full.
	combatant._ready()
	if not is_equal_approx(combatant.current_health, 120.0):
		(
			violations
			. append(
				(
					"spawn_state_before_ready: _ready() overwrote replicated health with %f, expected 120.0"
					% combatant.current_health
				)
			)
		)

	# A combatant that was never seeded still defaults to full health.
	var fresh := MobaCombatant.new()
	fresh.stat_block = _BASELINE_STAT_BLOCK
	fresh._ready()
	if not is_equal_approx(fresh.current_health, fresh.maximum_health):
		(
			violations
			. append(
				(
					"spawn_state_before_ready: unseeded combatant should start at full health, got %f of %f"
					% [fresh.current_health, fresh.maximum_health]
				)
			)
		)

	return violations
