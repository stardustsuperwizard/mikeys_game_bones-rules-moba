## Test suite for the round and match lifecycle (#340).
##
## Covers: the full round-boundary reset of dead and living combatants, the
## elimination rule that ends a round, the simultaneous-wipe draw, the
## authored best_of threshold that ends a match, and the on-change contract of
## MobaMatchState's settable properties.
class_name RoundLifecycleTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaDamage = preload("res://rules/core/moba_damage.gd")
const MobaState = preload("res://rules/state/moba_state.gd")
const MobaCrowdControlSpec = preload("res://rules/effects/moba_crowd_control_spec.gd")
const MobaStatModifier = preload("res://rules/effects/moba_stat_modifier.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## The authored series length. Loaded, never written in GDScript: how many
## round wins end a match is data, and these checks read it from the .tres the
## game ships rather than restating the number here.
const _ARENA_RULES = preload("res://rules/data/match/arena_best_of_three.tres")

const _CAST_ABILITY = preload("res://rules/tests/fixtures/abilities/cast_time_ability.tres")
const _TOGGLE_ABILITY = preload("res://rules/tests/fixtures/abilities/toggle_ability.tres")


## Run the round lifecycle test suite.
## Returns true if all checks pass, false if any violations found.
static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_dead_combatant_reset_next_round())
	all_violations.append_array(_test_living_combatant_reset_next_round())
	all_violations.append_array(_test_round_continues_while_both_teams_live())
	all_violations.append_array(_test_round_ends_on_single_team_wipe())
	all_violations.append_array(_test_simultaneous_wipe_is_a_draw())
	all_violations.append_array(_test_match_ends_at_authored_threshold())
	all_violations.append_array(_test_authored_best_of_five_needs_three_wins())
	all_violations.append_array(_test_properties_emit_on_change_only())

	if all_violations.is_empty():
		return true

	printerr("\n=== Round Lifecycle Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


# --- Acceptance: a combatant killed mid-round is fully alive next round ---


## Test: a combatant killed mid-round and never respawned is whole again at
## the start of the next round, and can act immediately.
static func _test_dead_combatant_reset_next_round() -> Array[String]:
	var violations: Array[String] = []

	var fixture := _make_combatant()
	var combatant: MobaCombatant = fixture["combatant"]
	var state_machine: MobaStateMachine = fixture["state_machine"]
	var max_health := combatant.maximum_health
	var max_resource := combatant.maximum_resource

	# Spend some resource and start a cooldown, then die without respawning.
	combatant.spend_resource(50.0)
	combatant.start_cooldown(&"test_ability", 20.0, 0.0, 1)
	_kill(combatant)

	if not combatant.is_dead():
		violations.append("dead_reset: combatant is not DEAD before the round boundary")

	var opponent := _make_combatant()
	var team_a: Array[MobaCombatant] = [combatant]
	var team_b: Array[MobaCombatant] = [opponent["combatant"]]
	var match_state := _make_match_state(_ARENA_RULES, team_a, team_b)
	match_state.start_round()

	if state_machine.current_state != MobaState.IDLE:
		violations.append(
			(
				"dead_reset: state is %d after start_round(), expected IDLE"
				% state_machine.current_state
			)
		)

	if combatant.is_dead():
		violations.append("dead_reset: combatant still reports is_dead() after start_round()")

	if combatant.current_health != max_health:
		violations.append(
			(
				"dead_reset: health %f after start_round(), expected %f"
				% [combatant.current_health, max_health]
			)
		)

	if combatant.current_resource != max_resource:
		violations.append(
			(
				"dead_reset: resource %f after start_round(), expected %f"
				% [combatant.current_resource, max_resource]
			)
		)

	if combatant.get_cooldown_remaining(&"test_ability") != 0.0:
		violations.append("dead_reset: cooldown survived the round boundary")

	if combatant.has_died():
		violations.append("dead_reset: has_died() still true, death cannot fire again")

	for action: StringName in [&"move", &"basic_attack", &"ability"]:
		if not combatant.can_perform_action(action):
			violations.append("dead_reset: cannot perform %s after start_round()" % action)

	_free(fixture)
	_free(opponent)
	match_state.free()
	return violations


# --- Acceptance: a survivor's carried state is cleared too ---


## Test: a combatant alive at round end -- mid-cast, toggled on, on cooldown,
## buffed, debuffed, shielded, stunned, and in a non-IDLE state -- has all of
## it cleared and is IDLE at the start of the next round.
static func _test_living_combatant_reset_next_round() -> Array[String]:
	var violations: Array[String] = []

	var fixture := _make_combatant()
	var combatant: MobaCombatant = fixture["combatant"]
	var state_machine: MobaStateMachine = fixture["state_machine"]

	var no_targets: Array[Node] = []
	combatant.start_cast(&"cast_time_ability", _CAST_ABILITY, no_targets, 5.0)
	combatant.start_toggle(&"toggle_ability", _TOGGLE_ABILITY, no_targets)
	combatant.start_cooldown(&"test_ability", 20.0, 0.0, 1)
	combatant.apply_shield(100.0, &"test", 30.0)

	var modifier := MobaStatModifier.new()
	modifier.stat = MobaStatBlock.ATTACK_DAMAGE
	modifier.amount = 10.0
	modifier.is_percentage = false
	modifier.duration = 30.0
	modifier.stacking = MobaStatModifier.Stacking.REFRESH
	combatant.get_effect_container().apply_modifier(modifier, &"test_ability")

	var stun := MobaCrowdControlSpec.new()
	stun.type = MobaCrowdControlSpec.CCType.STUN
	stun.duration = 10.0
	stun.affected_by_tenacity = false
	combatant.apply_crowd_control(stun, combatant)

	state_machine.try_enter(MobaState.ABILITY_CAST, 5.0)
	combatant.write_health(1.0)

	var opponent := _make_combatant()
	var team_a: Array[MobaCombatant] = [combatant]
	var team_b: Array[MobaCombatant] = [opponent["combatant"]]
	var match_state := _make_match_state(_ARENA_RULES, team_a, team_b)
	match_state.start_round()

	if combatant.is_casting():
		violations.append("living_reset: cast survived the round boundary")

	if combatant.is_toggled_on(&"toggle_ability"):
		violations.append("living_reset: toggle survived the round boundary")

	if combatant.get_cooldown_remaining(&"test_ability") != 0.0:
		violations.append("living_reset: cooldown survived the round boundary")

	if combatant.total_shield() != 0.0:
		violations.append("living_reset: shield survived the round boundary")

	if combatant.get_effect_container().has_modifier(&"test_ability", MobaStatBlock.ATTACK_DAMAGE):
		violations.append("living_reset: stat modifier survived the round boundary")

	if combatant.has_any_crowd_control():
		violations.append("living_reset: crowd control survived the round boundary")

	if state_machine.current_state != MobaState.IDLE:
		violations.append(
			(
				"living_reset: state is %d after start_round(), expected IDLE"
				% state_machine.current_state
			)
		)

	if combatant.current_health != combatant.maximum_health:
		violations.append(
			(
				"living_reset: health %f after start_round(), expected %f"
				% [combatant.current_health, combatant.maximum_health]
			)
		)

	for action: StringName in [&"move", &"basic_attack", &"ability"]:
		if not combatant.can_perform_action(action):
			violations.append("living_reset: cannot perform %s after start_round()" % action)

	_free(fixture)
	_free(opponent)
	match_state.free()
	return violations


# --- Acceptance: a round does not end while both teams have a survivor ---


## Test: with one dead and one living combatant on each team, ticking does not
## end the round or move either score.
static func _test_round_continues_while_both_teams_live() -> Array[String]:
	var violations: Array[String] = []

	var fixtures: Array[Dictionary] = []
	for i in range(4):
		fixtures.append(_make_combatant())

	var team_a: Array[MobaCombatant] = [fixtures[0]["combatant"], fixtures[1]["combatant"]]
	var team_b: Array[MobaCombatant] = [fixtures[2]["combatant"], fixtures[3]["combatant"]]
	var match_state := _make_match_state(_ARENA_RULES, team_a, team_b)

	var rounds_seen := {"count": 0}
	match_state.round_ended.connect(func(_winner: int): rounds_seen["count"] += 1)

	match_state.start_round()
	_kill(team_a[1])
	_kill(team_b[1])

	for i in range(5):
		match_state.tick(0.1)

	if rounds_seen["count"] != 0:
		violations.append(
			(
				"round_continues: round_ended fired %d times with survivors on both teams"
				% rounds_seen["count"]
			)
		)

	if match_state.team_a_score != 0 or match_state.team_b_score != 0:
		violations.append(
			(
				"round_continues: scores moved to %d-%d with survivors on both teams"
				% [match_state.team_a_score, match_state.team_b_score]
			)
		)

	if not match_state.round_in_progress:
		violations.append(
			"round_continues: round_in_progress went false with survivors on both teams"
		)

	for fixture in fixtures:
		_free(fixture)
	match_state.free()
	return violations


# --- Acceptance: a single-team wipe ends the round, once ---


## Test: on the tick where Team B's living count reaches zero, Team A's score
## increments by exactly one, Team B's does not move, and round_ended reports
## Team A.
static func _test_round_ends_on_single_team_wipe() -> Array[String]:
	var violations: Array[String] = []

	var fixtures: Array[Dictionary] = []
	for i in range(2):
		fixtures.append(_make_combatant())

	var team_a: Array[MobaCombatant] = [fixtures[0]["combatant"]]
	var team_b: Array[MobaCombatant] = [fixtures[1]["combatant"]]
	var match_state := _make_match_state(_ARENA_RULES, team_a, team_b)

	var seen := {"winners": []}
	match_state.round_ended.connect(func(winner: int): seen["winners"].append(winner))

	match_state.start_round()
	_kill(team_b[0])
	match_state.tick(0.1)

	if seen["winners"] != [MobaMatchState.TEAM_A]:
		violations.append(
			"wipe_ends_round: round_ended winners were %s, expected [0]" % [seen["winners"]]
		)

	if match_state.team_a_score != 1:
		violations.append(
			"wipe_ends_round: team_a_score is %d, expected 1" % match_state.team_a_score
		)

	if match_state.team_b_score != 0:
		violations.append(
			"wipe_ends_round: team_b_score is %d, expected 0" % match_state.team_b_score
		)

	# The next round has already started, so Team B is alive again and further
	# ticks must not re-score the round that just ended.
	match_state.tick(0.1)

	if match_state.team_a_score != 1:
		violations.append(
			(
				"wipe_ends_round: team_a_score is %d after a further tick, expected 1"
				% match_state.team_a_score
			)
		)

	for fixture in fixtures:
		_free(fixture)
	match_state.free()
	return violations


# --- Acceptance: a simultaneous wipe is a draw ---


## Test: a tick where both teams reach zero living combatants changes neither
## score, emits no round_ended, and starts a new round (both teams alive).
static func _test_simultaneous_wipe_is_a_draw() -> Array[String]:
	var violations: Array[String] = []

	var fixtures: Array[Dictionary] = []
	for i in range(2):
		fixtures.append(_make_combatant())

	var team_a: Array[MobaCombatant] = [fixtures[0]["combatant"]]
	var team_b: Array[MobaCombatant] = [fixtures[1]["combatant"]]
	var match_state := _make_match_state(_ARENA_RULES, team_a, team_b)

	var rounds_seen := {"count": 0}
	match_state.round_ended.connect(func(_winner: int): rounds_seen["count"] += 1)

	match_state.start_round()
	_kill(team_a[0])
	_kill(team_b[0])
	match_state.tick(0.1)

	if rounds_seen["count"] != 0:
		violations.append(
			"draw: round_ended fired %d times on a simultaneous wipe" % rounds_seen["count"]
		)

	if match_state.team_a_score != 0 or match_state.team_b_score != 0:
		violations.append(
			(
				"draw: scores moved to %d-%d on a simultaneous wipe"
				% [match_state.team_a_score, match_state.team_b_score]
			)
		)

	if not match_state.round_in_progress:
		violations.append("draw: round_in_progress went false on a simultaneous wipe")

	if team_a[0].is_dead() or team_b[0].is_dead():
		violations.append("draw: combatants were not reset for the replayed round")

	for fixture in fixtures:
		_free(fixture)
	match_state.free()
	return violations


# --- Acceptance: the match ends the moment the authored threshold is reached ---


## Test: with the authored best_of = 3 (rounds_to_win() == 2), the match ends
## on Team B's second round win -- not on its first, and without a third round.
static func _test_match_ends_at_authored_threshold() -> Array[String]:
	var violations: Array[String] = []

	if _ARENA_RULES.rounds_to_win() != 2:
		(
			violations
			. append(
				(
					"match_ends: authored arena_best_of_three.tres reports rounds_to_win() == %d, expected 2"
					% _ARENA_RULES.rounds_to_win()
				)
			)
		)

	var fixtures: Array[Dictionary] = []
	for i in range(2):
		fixtures.append(_make_combatant())

	var team_a: Array[MobaCombatant] = [fixtures[0]["combatant"]]
	var team_b: Array[MobaCombatant] = [fixtures[1]["combatant"]]
	var match_state := _make_match_state(_ARENA_RULES, team_a, team_b)

	var seen := {"ended": []}
	match_state.match_ended.connect(func(winner: int): seen["ended"].append(winner))

	match_state.start_round()

	# Round 1 to Team B.
	_kill(team_a[0])
	match_state.tick(0.1)

	if not seen["ended"].is_empty():
		violations.append("match_ends: match_ended fired after one round win")

	if match_state.winning_team != MobaMatchState.NO_WINNER:
		violations.append(
			(
				"match_ends: winning_team is %d after one round win, expected -1"
				% match_state.winning_team
			)
		)

	# Round 2 to Team B: the authored threshold.
	_kill(team_a[0])
	match_state.tick(0.1)

	if seen["ended"] != [MobaMatchState.TEAM_B]:
		violations.append("match_ends: match_ended reported %s, expected [1]" % [seen["ended"]])

	if match_state.winning_team != MobaMatchState.TEAM_B:
		violations.append("match_ends: winning_team is %d, expected 1" % match_state.winning_team)

	if match_state.round_in_progress:
		violations.append("match_ends: round_in_progress still true after the match ended")

	if match_state.team_b_score != 2:
		violations.append("match_ends: team_b_score is %d, expected 2" % match_state.team_b_score)

	for fixture in fixtures:
		_free(fixture)
	match_state.free()
	return violations


# --- Acceptance: the threshold comes from the resource, not from GDScript ---


## Test: authoring best_of = 5 on the same resource type raises the threshold
## to 3 round wins -- two wins no longer end the match. Uses a duplicate of the
## shipped .tres, so the only thing that changed is the authored value.
static func _test_authored_best_of_five_needs_three_wins() -> Array[String]:
	var violations: Array[String] = []

	var best_of_five := _ARENA_RULES.duplicate() as MobaMatchRules
	best_of_five.best_of = 5

	if best_of_five.rounds_to_win() != 3:
		violations.append(
			"best_of_five: rounds_to_win() is %d, expected 3" % best_of_five.rounds_to_win()
		)

	var fixtures: Array[Dictionary] = []
	for i in range(2):
		fixtures.append(_make_combatant())

	var team_a: Array[MobaCombatant] = [fixtures[0]["combatant"]]
	var team_b: Array[MobaCombatant] = [fixtures[1]["combatant"]]
	var match_state := _make_match_state(best_of_five, team_a, team_b)

	var seen := {"ended": []}
	match_state.match_ended.connect(func(winner: int): seen["ended"].append(winner))

	match_state.start_round()

	for round_index in range(2):
		_kill(team_b[0])
		match_state.tick(0.1)

	if not seen["ended"].is_empty():
		violations.append("best_of_five: match ended after two round wins, expected three")

	if match_state.winning_team != MobaMatchState.NO_WINNER:
		violations.append(
			(
				"best_of_five: winning_team is %d after two round wins, expected -1"
				% match_state.winning_team
			)
		)

	_kill(team_b[0])
	match_state.tick(0.1)

	if seen["ended"] != [MobaMatchState.TEAM_A]:
		violations.append(
			(
				"best_of_five: match_ended reported %s after three round wins, expected [0]"
				% [seen["ended"]]
			)
		)

	for fixture in fixtures:
		_free(fixture)
	match_state.free()
	return violations


# --- Acceptance: the settable properties emit only on change ---


## Test: each settable property emits its change signal when assigned a
## different value and stays silent when assigned its current value -- the
## on-change contract a MultiplayerSynchronizer needs.
static func _test_properties_emit_on_change_only() -> Array[String]:
	var violations: Array[String] = []

	var match_state := MobaMatchState.new()
	var seen := {"a": 0, "b": 0, "winner": 0, "in_progress": 0}

	match_state.team_a_score_changed.connect(func(_value: int): seen["a"] += 1)
	match_state.team_b_score_changed.connect(func(_value: int): seen["b"] += 1)
	match_state.winning_team_changed.connect(func(_value: int): seen["winner"] += 1)
	match_state.round_in_progress_changed.connect(func(_value: bool): seen["in_progress"] += 1)

	match_state.team_a_score = 1
	match_state.team_b_score = 2
	match_state.winning_team = MobaMatchState.TEAM_B
	match_state.round_in_progress = true

	if seen != {"a": 1, "b": 1, "winner": 1, "in_progress": 1}:
		violations.append("on_change: changed assignments emitted %s, expected one each" % [seen])

	if match_state.team_a_score != 1 or match_state.team_b_score != 2:
		violations.append(
			(
				"on_change: scores read back as %d-%d, expected 1-2"
				% [match_state.team_a_score, match_state.team_b_score]
			)
		)

	if match_state.winning_team != MobaMatchState.TEAM_B or not match_state.round_in_progress:
		violations.append("on_change: winning_team/round_in_progress did not read back as assigned")

	# Re-assigning the current value must be a silent no-op.
	match_state.team_a_score = 1
	match_state.team_b_score = 2
	match_state.winning_team = MobaMatchState.TEAM_B
	match_state.round_in_progress = true

	if seen != {"a": 1, "b": 1, "winner": 1, "in_progress": 1}:
		violations.append("on_change: unchanged assignments emitted again (%s)" % [seen])

	match_state.free()
	return violations


# --- Fixtures ---


## Build a headless combatant: an Actor with a MobaCombatant, a loaded
## MobaStateMachine, and a Body, matching the fixture pattern death_test.gd
## and toggle_test.gd already use. The Actor is never added to a scene tree,
## so _ready() does not run and the runtime stat block is seeded here.
static func _make_combatant() -> Dictionary:
	var actor := Actor.new()
	actor.owner_id = 1

	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = _BASELINE_STAT_BLOCK.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = _BASELINE_STAT_BLOCK.get_stat_value(MobaStatBlock.RESOURCE)
	actor.add_child(combatant)

	var state_machine := MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	var body := Node3D.new()
	body.name = "Body"
	actor.add_child(body)

	return {"actor": actor, "combatant": combatant, "state_machine": state_machine}


## Build a MobaMatchState with both rosters registered. Never added to a scene
## tree: nothing here depends on _ready(), and tick() is caller-driven.
static func _make_match_state(
	match_rules: MobaMatchRules, team_a: Array[MobaCombatant], team_b: Array[MobaCombatant]
) -> MobaMatchState:
	var match_state := MobaMatchState.new()
	match_state.rules = match_rules
	match_state.register_team(MobaMatchState.TEAM_A, team_a)
	match_state.register_team(MobaMatchState.TEAM_B, team_b)
	return match_state


## Kill a combatant outright with unmitigable damage.
static func _kill(combatant: MobaCombatant) -> void:
	var lethal := MobaDamage.new(
		100000.0, MobaDamage.DamageType.TRUE, combatant, false, 0.0, 0.0, false
	)
	combatant.apply_damage(lethal)


## Free a fixture built by _make_combatant().
static func _free(fixture: Dictionary) -> void:
	var actor: Actor = fixture["actor"]
	actor.free()
