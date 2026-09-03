## Drives the round/match lifecycle for the arena scene.
##
## MobaMatchState holds the lifecycle and deliberately never reads
## `multiplayer` or decides whether it should be running. This controller is
## the one place that decides: it registers the team rosters, starts the first
## round, and ticks the state -- but only on the process that owns the match,
## which is the offline process acting as its own server, or the server itself.
## A pure client never ticks its own copy; it observes the four replicated
## properties and follows the server into the lobby when the match is decided.
class_name MatchController
extends Node

## Where a decided match returns to. The same scene scripts/main_menu.gd
## leaves in the other direction.
const LOBBY_SCENE_PATH := "res://scenes/lobby/lobby.tscn"

## The lifecycle state, authored as a child in scenes/main.tscn so its four
## replicated properties exist under a stable node path before
## MatchStateSynchronizer resolves its replication config. Creating it from
## code here would leave that config pointing at a node that does not exist
## yet: a MultiplayerSynchronizer child readies before its parent does.
@onready var match_state: MobaMatchState = $MobaMatchState


func _ready() -> void:
	if _is_authoritative():
		match_state.match_ended.connect(_on_match_ended)
		_register_teams()
		match_state.start_round()
		return

	# A pure client. winning_team arrives on-change through
	# MatchStateSynchronizer, and assigning it drives winning_team_changed
	# here exactly as a local decision would have on the server.
	match_state.winning_team_changed.connect(_on_winning_team_replicated)


func _physics_process(delta: float) -> void:
	if not _is_authoritative():
		return
	match_state.tick(delta)


## True when this process decides the match: offline, or the server.
##
## Mirrors WorldManager._is_dedicated_server() -- the autoload is reached by
## node path rather than by its global name, because a test running under
## `--script` compiles this file without the autoload registered and a bare
## `SessionManager` reference would fail to compile there.
func _is_authoritative() -> bool:
	var session := get_node_or_null(^"/root/SessionManager")
	if session != null and session.mode == session.Mode.OFFLINE:
		return true
	return multiplayer.is_server()


## Register both rosters from the arena's actors.
##
## The union of the "players" and "nonplayers" groups is every actor carrying a
## Controller. Side is read off actor.team, never off which group the actor
## landed in: a bot authored with team 0 belongs to Team A despite being
## AI-controlled.
func _register_teams() -> void:
	var team_a: Array[MobaCombatant] = []
	var team_b: Array[MobaCombatant] = []

	for group in [&"players", &"nonplayers"]:
		for node in get_tree().get_nodes_in_group(group):
			var actor := node as Actor
			if actor == null:
				continue

			var combatant := actor.get_node_or_null(^"MobaCombatant") as MobaCombatant
			if combatant == null:
				continue

			if actor.team == MobaMatchState.TEAM_A:
				if not team_a.has(combatant):
					team_a.append(combatant)
			elif actor.team == MobaMatchState.TEAM_B:
				if not team_b.has(combatant):
					team_b.append(combatant)
			else:
				push_error("MatchController: %s has unknown team %d." % [actor.name, actor.team])

	match_state.register_team(MobaMatchState.TEAM_A, team_a)
	match_state.register_team(MobaMatchState.TEAM_B, team_b)


## The server decided the match. Yield one processed frame first so the final
## team_a_score/team_b_score/winning_team values leave through
## MatchStateSynchronizer before the scene under it is torn down.
func _on_match_ended(_winning_team: int) -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)


## A client saw the replicated result. Follow the server back to the lobby.
func _on_winning_team_replicated(value: int) -> void:
	if value == MobaMatchState.NO_WINNER:
		return
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)
