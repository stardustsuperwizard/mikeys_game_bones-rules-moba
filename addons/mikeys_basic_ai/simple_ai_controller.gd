# A reference/default implementation of Bones' Controller contract -- a
# dumb aggro-range-and-chase decision loop, kept only to prove the contract
# works end to end (move/attack/interact via the same Action/Rules/Authority
# pipeline as PlayerController). Treat this exactly like a default network
# transport adapter: swap it for a real AI by writing a new Controller
# subclass (behavior tree, utility AI, GOAP, whatever the game needs) and
# pointing an actor's "Controller" node at that script instead -- nothing
# else in Bones needs to change.
class_name SimpleAIController
extends Controller

const HOME_ARRIVAL_DISTANCE = 0.2

@export var aggro_range := 10.0
@export var attack_range := 2.0

var target: Actor
var home_position: Vector3
var _returning_home := false

func _ready() -> void:
	actor.add_to_group("nonplayers")
	home_position = actor.global_position

func get_move_direction() -> Vector3:
	_update_target()

	if target:
		var distance := actor.global_position.distance_to(target.global_position)
		if distance <= attack_range:
			return Vector3.ZERO
		return actor.global_position.direction_to(target.global_position)

	if _returning_home:
		var home_distance := actor.global_position.distance_to(home_position)
		if home_distance <= HOME_ARRIVAL_DISTANCE:
			_returning_home = false
			return Vector3.ZERO
		return actor.global_position.direction_to(home_position)

	return Vector3.ZERO

func get_attack_target() -> Actor:
	if target == null:
		return null

	if actor.global_position.distance_to(target.global_position) <= attack_range:
		return target

	return null

func _update_target() -> void:
	if target:
		if actor.global_position.distance_to(target.global_position) > aggro_range:
			target = null
			_returning_home = true
		return

	var found := _find_target()
	if found:
		target = found
		_returning_home = false

func _find_target() -> Actor:
	var nearest: Actor = null
	var nearest_dist := aggro_range
	for node in actor.get_tree().get_nodes_in_group("players"):
		var player := node as Actor
		if not player:
			continue
		var dist := actor.global_position.distance_to(player.global_position)
		if dist <= nearest_dist:
			nearest = player
			nearest_dist = dist
	return nearest
