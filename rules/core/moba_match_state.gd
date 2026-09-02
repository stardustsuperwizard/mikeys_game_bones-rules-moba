## Round and match lifecycle for a two-team match.
##
## Owns the elimination-driven state machine above combat: a round ends when
## exactly one team is fully eliminated, every registered combatant is fully
## reset between rounds, and the match ends when a team reaches the authored
## win threshold in MobaMatchRules.
##
## Team index 0 is Team A and team index 1 is Team B, here and everywhere else
## that touches team membership.
##
## Time advances only through tick(delta), called by whatever owns this node;
## there is no _process or _physics_process here, the same rule every other
## rules/ system follows. This class also never reads `multiplayer` and never
## decides whether it should be running -- the caller decides that, the way
## it already decides whether to tick combatants.
class_name MobaMatchState
extends Node

## Emitted when team_a_score is assigned a value different from its current one.
signal team_a_score_changed(value: int)
## Emitted when team_b_score is assigned a value different from its current one.
signal team_b_score_changed(value: int)
## Emitted when winning_team is assigned a value different from its current one.
signal winning_team_changed(value: int)
## Emitted when round_in_progress is assigned a value different from its current one.
signal round_in_progress_changed(value: bool)
## Emitted once per decided round, with the team that won it. Not emitted for
## a draw (a simultaneous wipe), which decides nothing.
signal round_ended(winning_team: int)
## Emitted once, when a team's round wins reach rules.rounds_to_win().
signal match_ended(winning_team: int)

## Team index of Team A.
const TEAM_A := 0
## Team index of Team B.
const TEAM_B := 1

## No team has won yet. The value winning_team holds while the match runs.
const NO_WINNER := -1

## Authored series length. Assigned a .tres from rules/data/match/ so no round
## count or win threshold is written in GDScript.
@export var rules: MobaMatchRules = null

# The four settable, on-change properties below follow the pattern
# rules/tests/replication_properties_test.gd pins for MobaCombatant's
# current_health and MobaStateMachine's current_state: assignment of an
# unchanged value is a silent no-op, and any other assignment emits. That is
# what lets a MultiplayerSynchronizer later replicate them the same on-change
# way CombatStateSynchronizer already replicates combat state -- a remote peer
# applying a server value drives the same signal a local decision would have.
#
# Wiring that synchronizer is not this class's job, and neither is deciding
# whether it is the server: this class only makes the properties settable in
# the shape a synchronizer needs.

## Rounds Team A has won.
var team_a_score: int:
	get:
		return _team_a_score
	set(value):
		if value == _team_a_score:
			return
		_team_a_score = value
		team_a_score_changed.emit(value)

## Rounds Team B has won.
var team_b_score: int:
	get:
		return _team_b_score
	set(value):
		if value == _team_b_score:
			return
		_team_b_score = value
		team_b_score_changed.emit(value)

## The team that won the match, or NO_WINNER while it is still in progress.
var winning_team: int:
	get:
		return _winning_team
	set(value):
		if value == _winning_team:
			return
		_winning_team = value
		winning_team_changed.emit(value)

## True between start_round() and the end of a decided round.
var round_in_progress: bool:
	get:
		return _round_in_progress
	set(value):
		if value == _round_in_progress:
			return
		_round_in_progress = value
		round_in_progress_changed.emit(value)

## Backing fields for the properties above. The properties are the only seam
## that writes them, so every change goes through the on-change guard.
var _team_a_score: int = 0
var _team_b_score: int = 0
var _winning_team: int = NO_WINNER
var _round_in_progress: bool = false

## Registered combatants per team, indexed by team id: index 0 is Team A,
## index 1 is Team B. Populated by register_team(); populating that call from
## real spawn data belongs to whatever owns this node.
var _rosters: Array[Array] = [[], []]


## Register a team's combatants, replacing any previously registered roster
## for that team. team_id must be TEAM_A (0) or TEAM_B (1).
func register_team(team_id: int, combatants: Array[MobaCombatant]) -> void:
	if team_id != TEAM_A and team_id != TEAM_B:
		push_error("MobaMatchState.register_team: unknown team id %d" % team_id)
		return

	_rosters[team_id] = combatants.duplicate()


## Begin a round: fully reset every registered combatant on both teams, then
## mark the round in progress. Called for the first round by the owner, and
## for every later round by tick() itself.
func start_round() -> void:
	for roster: Array in _rosters:
		for combatant: MobaCombatant in roster:
			if combatant != null:
				combatant.reset_for_round()

	round_in_progress = true


## Advance the round/match state one step. Counts living combatants per team
## and ends the round when exactly one team is wiped.
##
## `delta` is unused: nothing here is duration-based, elimination is. It is
## still taken so this matches every other tick(delta) in rules/ and so a
## caller drives match state from the same loop it drives combat from.
func tick(_delta: float) -> void:
	if not round_in_progress:
		return

	var team_a_living := _living_count(TEAM_A)
	var team_b_living := _living_count(TEAM_B)

	# Both teams still standing: the round continues.
	if team_a_living > 0 and team_b_living > 0:
		return

	# Simultaneous wipe: a draw. Neither score changes and a new round starts.
	# Planner-selected default of the two options #281 names; see the plan
	# comment on that Issue. Flag rather than re-decide it.
	if team_a_living == 0 and team_b_living == 0:
		start_round()
		return

	_end_round(TEAM_A if team_b_living == 0 else TEAM_B)


## Living combatants on one team. A null entry counts as nobody.
func _living_count(team_id: int) -> int:
	var living := 0
	for combatant: MobaCombatant in _rosters[team_id]:
		if combatant != null and not combatant.is_dead():
			living += 1
	return living


## Score a decided round for `round_winner`, then either end the match or
## start the next round.
func _end_round(round_winner: int) -> void:
	var score := 0
	if round_winner == TEAM_A:
		team_a_score += 1
		score = team_a_score
	else:
		team_b_score += 1
		score = team_b_score

	round_ended.emit(round_winner)

	if rules == null:
		# With no authored rules there is no win threshold to reach, and
		# inventing one here would be exactly the GDScript-side round count
		# the data rule forbids. Play on, and say why.
		push_error("MobaMatchState.rules is unassigned; the match cannot end.")
		start_round()
		return

	if score < rules.rounds_to_win():
		start_round()
		return

	winning_team = round_winner
	round_in_progress = false
	match_ended.emit(round_winner)
