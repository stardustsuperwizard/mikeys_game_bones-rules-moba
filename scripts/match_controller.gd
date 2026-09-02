## Match lifecycle controller for a two-team MOBA match.
##
## Owns a MobaMatchState and drives it according to the session mode:
## - On the server or in offline mode, registers team rosters and calls tick()
##   each frame to advance the round and match state.
## - On a pure client, replicates match state through a MultiplayerSynchronizer
##   and returns to the main menu when the match ends.
##
## When the match ends, returns to res://scenes/ui/main_menu.tscn via
## get_tree().change_scene_to_file(). Gives clients a chance to observe the
## final replicated score before the scene changes.
class_name MatchController
extends Node

## Authored series length. Assigned a .tres from rules/data/match/ so no round
## count or win threshold is written in GDScript.
@export var rules: MobaMatchRules = preload("res://rules/data/match/arena_best_of_three.tres")

## The match state. Owned by this controller.
var match_state: MobaMatchState


func _ready() -> void:
	# Create and configure the match state
	match_state = MobaMatchState.new()
	match_state.rules = rules
	add_child(match_state)

	# Only the server or offline process starts the match
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		_register_teams()
		_start_match()


func _physics_process(delta: float) -> void:
	# Only tick on the server or in offline mode
	if multiplayer.is_server() or (multiplayer.has_multiplayer_peer() == false):
		if match_state != null:
			match_state.tick(delta)


func _register_teams() -> void:
	## Enumerate all arena actors and register them by team.
	var all_players := get_tree().get_nodes_in_group("players")
	var all_nonplayers := get_tree().get_nodes_in_group("nonplayers")

	# Combine both groups to get all actors
	var all_actors: Array[Node] = []
	all_actors.append_array(all_players)
	all_actors.append_array(all_nonplayers)

	# Build rosters by team
	var team_a_combatants: Array[MobaCombatant] = []
	var team_b_combatants: Array[MobaCombatant] = []

	for node in all_actors:
		var actor := node as Actor
		if actor == null:
			continue

		var combatant := actor.get_node_or_null("MobaCombatant") as MobaCombatant
		if combatant == null:
			continue

		if actor.team == 0:
			team_a_combatants.append(combatant)
		elif actor.team == 1:
			team_b_combatants.append(combatant)

	# Register the rosters
	match_state.register_team(MobaMatchState.TEAM_A, team_a_combatants)
	match_state.register_team(MobaMatchState.TEAM_B, team_b_combatants)


func _start_match() -> void:
	## Start the first round and listen for match end.
	match_state.start_round()
	match_state.match_ended.connect(_on_match_ended)

	# On clients, listen for winning_team changes to know when match ends
	if not (multiplayer.is_server() or not multiplayer.has_multiplayer_peer()):
		match_state.winning_team_changed.connect(_on_client_match_ended)


func _on_match_ended(winning_team: int) -> void:
	## Called when the match ends on the server. Wait one frame to let clients
	## observe the final score, then return to the main menu.
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_client_match_ended(winning_team: int) -> void:
	## Called when the client observes the match end through replication.
	## Return to the main menu.
	if winning_team != MobaMatchState.NO_WINNER:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
