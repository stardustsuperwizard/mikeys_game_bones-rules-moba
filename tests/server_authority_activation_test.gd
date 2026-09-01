# Two-peer headless integration test for #320's server-authoritative
# request/resolve routing of ability activation.
#
# Run with:
#   godot --headless --path . --script tests/server_authority_activation_test.gd
#
# Covers, in order:
#   - a client's activation request crosses a real ENet connection, is resolved
#     by the server, and commits the server's own cooldown and resource ledger;
#   - the resulting state replicates back to the requesting client through the
#     CombatStateSynchronizer already configured in scenes/player/player.tscn --
#     observed here, never rebuilt;
#   - a second request the SERVER's ledger says is on cooldown is refused and
#     never executes, even though the client's local ledger has been wiped clean
#     first so that its own copy believes the ability is ready;
#   - the client's own copy of the actor never resolves anything locally: only
#     the server's ActionRunner.run() ever runs;
#   - a client's BASIC ATTACK request takes the same route and lands on the
#     server, damaging the target the server re-resolved from the sent path.
#
# Both peers live in one headless process, as two MultiplayerAPI contexts bound
# to two subtrees via SceneTree.set_multiplayer(), talking over loopback ENet.
# The subtrees are deliberately shaped identically ("Arena/Player" under each
# multiplayer root) because Godot addresses an RPC by the receiver's path
# relative to its MultiplayerAPI root_path -- mismatched shapes mean the RPC
# arrives nowhere and the test would pass by never testing anything.
#
# Spawning goes through the real WorldManager.spawn(), not a local copy of its
# authority sequence, for the reason tests/replication_authority_test.gd gives:
# a copy would stay green if someone deleted the authority calls from
# scripts/world_manager.gd.
#
# This test is NOT wired into tests/test_bootstrap.gd; it loads game scenes and
# opens a socket, matching the precedent set by tests/session_manager_test.gd
# and tests/replication_authority_test.gd.
extends SceneTree

const _PLAYER_SPAWN_POINT := preload("res://resources/player_spawn_point.tres")
const _ENEMY_SPAWN_POINT := preload("res://resources/enemy_spawn_point.tres")

# Loopback port for the two peers. Fixed rather than random so a failure is
# reproducible; high enough to stay clear of anything privileged.
const _PORT := 27320

# The slot the test casts from. The authored melee_bruiser loadout puts
# power_strike (TARGETED, range 2.0) in slot 1; this test rebinds slot 1 to
# aimed_shot instead, which is a SKILLSHOT and therefore needs no explicit
# target node -- only the aim_direction the request already carries. That keeps
# the test on the acceptance criterion that matters (a client-computed aim
# direction reaching the server, which then resolves the skillshot itself) and
# off an artifact of running two "peers" inside one process: Actor.get_path()
# is absolute, so a target path minted under /root/ClientPeer would not resolve
# under /root/ServerPeer. Two real peers have identical absolute trees and do
# not have that problem.
const _SLOT := 1
const _ABILITY := &"aimed_shot"

# Frames to wait for an RPC and the replication that follows it. Generous: this
# is a loopback socket, and over-waiting only costs a few milliseconds while
# under-waiting produces a flaky pass.
const _SETTLE_FRAMES := 20

const _EXPECTED_CHECKS: Array[String] = [
	"client and server complete an ENet handshake",
	"client activation request resolves on the server",
	"server commits cooldown and resource for the request",
	"client never resolves the activation locally",
	"server state replicates back to the requesting client",
	"server refuses a request its own ledger has on cooldown",
	"refused request leaves server resource unspent",
	"client basic attack request is forwarded, not resolved locally",
	"client basic attack request lands on the server",
]

var _failures: Array[String] = []
var _completed: Array[String] = []

var _server_api: MultiplayerAPI
var _client_api: MultiplayerAPI
var _server_actor: Actor
var _client_actor: Actor

# The basic-attack target. Deliberately ONE node rather than a copy per branch:
# it stands in for the copy each peer would hold at the same absolute path in a
# real two-process session. Actor.get_path() is absolute, and the two "peers"
# here are two subtrees of one process, so a target minted under /root/ClientPeer
# could never be re-resolved under /root/ServerPeer. Sharing the node restores
# the property that actually matters -- the server re-resolves the path it was
# sent, against its own tree, and damages what it found there -- without the
# production code bending to accommodate the harness.
var _enemy: Actor

var _client_id := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	if await _connect_peers():
		await _test_successful_activation()
		await _test_server_side_refusal()
		await _test_basic_attack_request()

	_finish()


## Bring up a server and a client MultiplayerAPI over loopback ENet, each bound
## to its own subtree, and spawn one player actor into each with the authority
## split WorldManager applies in the real game.
func _connect_peers() -> bool:
	var server_branch := Node3D.new()
	server_branch.name = "ServerPeer"
	root.add_child(server_branch)

	var client_branch := Node3D.new()
	client_branch.name = "ClientPeer"
	root.add_child(client_branch)

	_server_api = MultiplayerAPI.create_default_interface()
	_client_api = MultiplayerAPI.create_default_interface()
	set_multiplayer(_server_api, ^"/root/ServerPeer")
	set_multiplayer(_client_api, ^"/root/ClientPeer")

	var server_peer := ENetMultiplayerPeer.new()
	if server_peer.create_server(_PORT, 4) != OK:
		_fail("setup: could not open an ENet server on port %d" % _PORT)
		return false
	_server_api.multiplayer_peer = server_peer

	var client_peer := ENetMultiplayerPeer.new()
	if client_peer.create_client("127.0.0.1", _PORT) != OK:
		_fail("setup: could not open an ENet client to port %d" % _PORT)
		return false
	_client_api.multiplayer_peer = client_peer

	# Wait for the handshake. Both APIs are polled by the SceneTree because
	# set_multiplayer() registered them; the loop only has to give that time.
	var connected := false
	for _i in range(240):
		await process_frame
		if _client_api.get_unique_id() > 1 and _server_api.get_peers().size() > 0:
			connected = true
			break

	if not connected:
		_fail("setup: client and server never completed an ENet handshake")
		return false

	_client_id = _client_api.get_unique_id()
	_pass("client and server complete an ENet handshake")

	# One actor per peer, at the same relative path under each multiplayer root,
	# both owned by the client -- the server's copy of a connected client's
	# player, and that client's own copy of it.
	_server_actor = _spawn_into(server_branch)
	_client_actor = _spawn_into(client_branch)
	if _server_actor == null or _client_actor == null:
		_fail("setup: player actor did not spawn on both peers")
		return false

	_rebind_slot(_server_actor)
	_rebind_slot(_client_actor)

	_enemy = _spawn_enemy_into(server_branch.get_node("Arena"))
	if _enemy == null:
		_fail("setup: basic-attack target did not spawn")
		return false

	# Let both actors finish _ready() and their first physics frame.
	await physics_frame
	await physics_frame
	return true


## Spawn one player actor under `branch` through the real WorldManager, owned by
## the connected client's peer id.
func _spawn_into(branch: Node) -> Actor:
	var world_manager := WorldManager.new()
	world_manager.name = "Arena"
	branch.add_child(world_manager)

	var actor := world_manager.spawn(_PLAYER_SPAWN_POINT, _client_id)
	if actor == null:
		return null

	# spawn() returns an unparented actor; MultiplayerSpawner is what parents it
	# in the real scene. The name is pinned so both peers agree on the path the
	# RPC and the synchronizer are addressed by.
	actor.name = "Player"
	world_manager.add_child(actor)
	return actor


## Spawn the shared basic-attack target under the server's arena.
func _spawn_enemy_into(arena: Node) -> Actor:
	var world_manager := arena as WorldManager
	var enemy := world_manager.spawn(_ENEMY_SPAWN_POINT, 0)
	if enemy == null:
		return null
	enemy.name = "Enemy"
	world_manager.add_child(enemy)
	return enemy


## Stand the target inside the server player's melee reach (the longsword's
## attack_range is 2.0).
##
## Re-applied every frame of the swing rather than placed once: this scene has
## no floor, so both CharacterBody3Ds free-fall, and the AI controller steers
## the enemy besides. Left alone they drift tens of units apart within a second
## and the swing starts failing on distance -- an artifact of a bare test tree,
## not anything about request routing. Pinning the range keeps the check on what
## it is meant to measure.
func _hold_target_in_reach() -> void:
	var player_body := _server_actor.get_node_or_null("Body") as Node3D
	var enemy_body := _enemy.get_node_or_null("Body") as Node3D
	if player_body != null and enemy_body != null:
		enemy_body.global_position = player_body.global_position + Vector3(1.0, 0.0, 0.0)


## Rebind action slot 1 to the skillshot this test casts. The combatant holds a
## shallow copy of the authored loadout, so this is duplicated before writing to
## avoid mutating rules/data/loadouts/melee_bruiser.tres for every other actor.
func _rebind_slot(actor: Actor) -> void:
	var combatant := actor.get_node_or_null("MobaCombatant") as MobaCombatant
	if combatant == null:
		return
	var loadout := (combatant.loadout as MobaLoadout).duplicate() as MobaLoadout
	loadout.set_action_slot(_SLOT, String(_ABILITY))
	combatant.loadout = loadout


## A client's activation request reaches the server, resolves there, and comes
## back only as replicated state.
func _test_successful_activation() -> void:
	var server_combatant := _combatant(_server_actor)
	var client_combatant := _combatant(_client_actor)
	if server_combatant == null or client_combatant == null:
		_fail("setup: an actor is missing its MobaCombatant")
		return

	var server_resource_before := server_combatant.current_resource

	# The client asks. try_activate_slot() must take its RPC branch here: this
	# actor's `multiplayer` is the client API, which has a peer and is not the
	# server. A null return is that branch reporting it forwarded the ask.
	var context := MobaCastContext.new(_client_actor, null, Vector3.FORWARD, Vector3.ZERO)
	var client_result := _client_actor.try_activate_slot(_SLOT, context)
	if client_result != null:
		_fail("client resolved the activation locally instead of forwarding it")
	else:
		_pass("client never resolves the activation locally")

	await _settle()

	if server_combatant.get_cooldown_remaining(_ABILITY) > 0.0:
		_pass("client activation request resolves on the server")
	else:
		_fail("server never resolved the client's request: %s is not on cooldown" % _ABILITY)
		return

	if server_combatant.current_resource < server_resource_before:
		_pass("server commits cooldown and resource for the request")
	else:
		_fail(
			(
				"server did not spend resource: %.1f before, %.1f after"
				% [server_resource_before, server_combatant.current_resource]
			)
		)

	# The client learns the outcome only through CombatStateSynchronizer.
	if client_combatant.current_resource == server_combatant.current_resource:
		_pass("server state replicates back to the requesting client")
	else:
		_fail(
			(
				"server resource %.1f did not replicate to the client, which sees %.1f"
				% [server_combatant.current_resource, client_combatant.current_resource]
			)
		)


## A request the server's own ledger has on cooldown is refused, no matter what
## the client's copy believes.
func _test_server_side_refusal() -> void:
	var server_combatant := _combatant(_server_actor)
	var client_combatant := _combatant(_client_actor)
	if server_combatant == null or client_combatant == null:
		return

	# Wipe the CLIENT's ledger so its local copy believes the ability is ready
	# and off cooldown -- the stale-or-tampered client the criterion describes.
	# The server's ledger is untouched and still holds the cooldown.
	client_combatant.clear_all_cooldowns()
	client_combatant.restore_to_full()

	if server_combatant.get_cooldown_remaining(_ABILITY) <= 0.0:
		_fail("setup: server cooldown expired before the refusal could be tested")
		return

	var server_resource_before := server_combatant.current_resource
	var server_cooldown_before := server_combatant.get_cooldown_remaining(_ABILITY)

	var context := MobaCastContext.new(_client_actor, null, Vector3.FORWARD, Vector3.ZERO)
	_client_actor.try_activate_slot(_SLOT, context)

	await _settle()

	# A refused activation must not re-arm the cooldown. Elapsed time may have
	# decayed it a little -- the server ticks its copy of a client-owned actor
	# on purpose -- so the check is that it did not go UP, not that it is equal.
	var server_cooldown_after := server_combatant.get_cooldown_remaining(_ABILITY)
	if server_cooldown_after <= server_cooldown_before:
		_pass("server refuses a request its own ledger has on cooldown")
	else:
		_fail(
			(
				"refused request re-armed the server cooldown: %.2f -> %.2f"
				% [server_cooldown_before, server_cooldown_after]
			)
		)

	# Resource regenerates on the server's copy across the settle window, so the
	# refusal shows up as "never went DOWN" rather than "did not change": a cast
	# that had executed would have spent the ability's cost out of it, which no
	# amount of regeneration inside a handful of frames could mask.
	if server_combatant.current_resource >= server_resource_before:
		_pass("refused request leaves server resource unspent")
	else:
		_fail(
			(
				"refused request spent server resource: %.1f -> %.1f"
				% [server_resource_before, server_combatant.current_resource]
			)
		)


## A client's basic attack takes the same route: forwarded over RPC, resolved
## only by the server, and landing on the target the server re-resolved itself.
func _test_basic_attack_request() -> void:
	var enemy_combatant := _combatant(_enemy)
	if enemy_combatant == null:
		_fail("setup: basic-attack target has no MobaCombatant")
		return

	_hold_target_in_reach()
	await physics_frame

	var health_before := enemy_combatant.current_health

	# try_basic_attack() must forward rather than resolve: same null contract as
	# the activation path.
	var client_result := _client_actor.try_basic_attack(_enemy)
	if client_result == null:
		_pass("client basic attack request is forwarded, not resolved locally")
	else:
		_fail("client resolved the basic attack locally instead of forwarding it")

	# The swing has a wind-up: MobaBasicAttackAction returns attack_not_started
	# while the cycle is still recovering, so the request is re-sent across a
	# few frames the way a controller holding a pending target would.
	for _i in range(90):
		_hold_target_in_reach()
		await physics_frame
		if enemy_combatant.current_health < health_before:
			break
		_client_actor.try_basic_attack(_enemy)

	if enemy_combatant.current_health < health_before:
		_pass("client basic attack request lands on the server")
	else:
		_fail(
			"basic attack never reached the server: target health unchanged at %.1f" % health_before
		)


func _combatant(actor: Actor) -> MobaCombatant:
	if actor == null:
		return null
	return actor.get_node_or_null("MobaCombatant") as MobaCombatant


## Give the RPC and the replication that follows it time to land.
func _settle() -> void:
	for _i in range(_SETTLE_FRAMES):
		await physics_frame


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
		print("\nAll %d server authority checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
