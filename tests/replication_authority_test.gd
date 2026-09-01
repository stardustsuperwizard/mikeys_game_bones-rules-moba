# Headless integration test for the #313 per-subtree multiplayer authority split.
#
# Run with:
#   godot --headless --path . --script tests/replication_authority_test.gd
#
# Covers, in order:
#   - a spawned actor keeps the connecting peer's authority on the Actor, Body,
#     Controller and the input/caster nodes -- today's movement model, unchanged;
#   - MobaCombatant and its sibling MobaStateMachine are re-set to the server
#     (peer 1) regardless of which peer owns the Actor;
#   - the lazily-created MobaEffectContainer inherits peer 1 from MobaCombatant
#     rather than needing its own explicit call;
#   - both MultiplayerSynchronizer nodes land on the right side of that split.
#
# That last check is the one with teeth. CombatStateSynchronizer is a child of
# MobaCombatant precisely so the recursive set_multiplayer_authority(1) on that
# node also claims the synchronizer. Parented to the Actor root instead -- the
# obvious place, and where it does NOT belong -- the earlier recursive
# set_multiplayer_authority(authority_id) would leave it owned by the connecting
# peer, and a client would be able to broadcast its own claimed health to every
# other peer. The scene tree is what enforces that, so a scene edit can silently
# undo it; this test is what catches the undo.
#
# Authority is asserted against a non-1 peer id, so a node that merely defaulted
# to the server is distinguishable from one deliberately set to it.
#
# Spawning goes through WorldManager.spawn(), not a local copy of its authority
# sequence, so deleting the set_multiplayer_authority(1) calls from
# scripts/world_manager.gd fails this test rather than sliding past it.
#
# This test is NOT wired into tests/test_bootstrap.gd: it loads game scenes and
# a WorldManager, matching the precedent set by tests/session_manager_test.gd.
extends SceneTree

const _PLAYER_SPAWN_POINT := preload("res://resources/player_spawn_point.tres")
const _ENEMY_SPAWN_POINT := preload("res://resources/enemy_spawn_point.tres")

# A peer id that is neither the server (1) nor "unowned" (0).
const _OWNING_PEER := 7

# Nodes that must stay owned by whichever peer owns the Actor.
const _PEER_OWNED := ["Body", "Controller", "BodyTransformSynchronizer"]

# Nodes that must always be server-authoritative.
const _SERVER_OWNED := [
	"MobaCombatant",
	"MobaStateMachine",
	"MobaCombatant/CombatStateSynchronizer",
]

const _EXPECTED_CHECKS: Array[String] = [
	"player actor keeps owning peer",
	"player peer-owned subtree keeps owning peer",
	"player combat subtree is server-authoritative",
	"player effect container inherits server authority",
	"enemy combat subtree is server-authoritative",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	_test_player_authority_split()
	_test_enemy_authority_split()

	_finish()


## Spawn through the real WorldManager.
##
## Deliberately calls WorldManager.spawn() rather than re-applying the
## authority sequence here: a copy of that sequence would stay green if
## someone deleted the set_multiplayer_authority(1) calls from
## scripts/world_manager.gd, which is the regression most worth catching.
## A bare WorldManager has no MultiplayerSpawner child, so spawn() falls
## through to _spawn_actor() directly -- the same function the spawner
## calls as its spawn_function in the real scene.
func _spawn(spawn_point: SpawnPoint, authority_id: int) -> Node:
	var world_manager := WorldManager.new()
	root.add_child(world_manager)

	var actor: Node = world_manager.spawn(spawn_point, authority_id)
	if actor == null:
		return null

	# _spawn_actor() returns an unparented actor; the MultiplayerSpawner is
	# what parents it in the real scene. Add it so _ready() runs, matching
	# what a spawned actor actually experiences.
	world_manager.add_child(actor)
	return actor


## The player's movement subtree stays with the connecting peer while its
## combat subtree is the server's.
func _test_player_authority_split() -> void:
	var actor := _spawn(_PLAYER_SPAWN_POINT, _OWNING_PEER)

	if actor.get_multiplayer_authority() != _OWNING_PEER:
		_fail(
			(
				"Actor authority should be %d, got %d"
				% [_OWNING_PEER, actor.get_multiplayer_authority()]
			)
		)
	else:
		_pass("player actor keeps owning peer")

	if _check_authority(actor, _PEER_OWNED, _OWNING_PEER, "player"):
		_pass("player peer-owned subtree keeps owning peer")

	if _check_authority(actor, _SERVER_OWNED, 1, "player"):
		_pass("player combat subtree is server-authoritative")

	# The effect container is added as a runtime child of MobaCombatant on first
	# use, so it takes that node's server authority. It must be a real child:
	# add_child() is refused while MobaCombatant is itself still being set up,
	# which is exactly when replicated spawn state first touches it, and a
	# cached-but-unparented container would be leaked and outside the subtree
	# whose authority it is supposed to carry.
	var combatant := actor.get_node("MobaCombatant")
	var container: Node = combatant.get_effect_container()
	if container == null:
		_fail("setup: player MobaCombatant returned no effect container")
	elif container.get_parent() != combatant:
		_fail("MobaEffectContainer is not parented to MobaCombatant (orphaned)")
	elif container.get_multiplayer_authority() != 1:
		_fail(
			(
				"MobaEffectContainer authority should be 1, got %d"
				% container.get_multiplayer_authority()
			)
		)
	else:
		_pass("player effect container inherits server authority")

	actor.queue_free()


## The same split holds for world/bot content, which spawns with authority 0.
func _test_enemy_authority_split() -> void:
	var actor := _spawn(_ENEMY_SPAWN_POINT, 0)

	if _check_authority(actor, _SERVER_OWNED, 1, "enemy"):
		_pass("enemy combat subtree is server-authoritative")

	actor.queue_free()


## Assert every named node under `actor` holds `expected` authority.
## Returns true when they all do, so the caller records a single check.
func _check_authority(actor: Node, paths: Array, expected: int, label: String) -> bool:
	var ok := true
	for path in paths:
		var node := actor.get_node_or_null(NodePath(path))
		if node == null:
			_fail("setup: %s/%s not found" % [label, path])
			ok = false
			continue
		if node.get_multiplayer_authority() != expected:
			_fail(
				(
					"%s/%s authority should be %d, got %d"
					% [label, path, expected, node.get_multiplayer_authority()]
				)
			)
			ok = false
	return ok


func _pass(check: String) -> void:
	_completed.append(check)
	print("PASS %s" % check)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	for check in _EXPECTED_CHECKS:
		if check not in _completed:
			_failures.append("check never ran: %s" % check)

	if _failures.is_empty():
		print("\nAll %d replication authority checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
