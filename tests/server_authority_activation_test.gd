# Two-peer headless integration test for #320's server-authoritative
# request/resolve routing of ability activation, and for #321's client-side
# prediction and rollback layered on top of it.
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
#     server, damaging the target the server re-resolved from the sent path;
#   - #321: a refused prediction is rolled back by the server's explicit denial
#     RPC, leaving no cooldown and nothing spent; a prediction is visible on the
#     frame the request is sent, before any reply could have arrived; and a
#     confirmed prediction hands over to the server's own value without the
#     cooldown sweep restarting or dipping to zero on any frame in between.
#
# The refusal case is checked FIRST, and deliberately: a prediction system with
# no rollback is not prediction, it is a client that lies. Suppressing the denial
# RPC in Actor._deny_if_predicted() must fail these checks -- if it does not,
# they are passing on replication that would have arrived anyway and are testing
# nothing.
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
	"client observes the server starting the swing it requested",
	"latch holds a forwarded swing the server refused mid-cycle",
	"latch releases once the server confirms the swing started",
	"a refused prediction is rolled back by the server's denial",
	"a refused prediction leaves no cooldown behind",
	"a refused prediction leaves nothing spent",
	"a prediction starts the cooldown sweep before the server replies",
	"a prediction shows the resource spend before the server replies",
	"a confirmed prediction ends on the server's own cooldown",
	"a confirmed prediction never restarts the sweep from full",
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

# Last resource_changed payload seen from the client's combatant.
#
# The HUD's resource bar is driven ONLY by this signal -- moba_combat_hud.gd
# connects it and never polls -- so a check that reads current_resource proves
# the model is right and says nothing about whether the bar ever moved. These
# checks observe what the bar is told.
var _client_resource_emitted := -1.0

# Violation watch: every resource_changed payload must equal what current_resource
# would report at that moment.
#
# That is the exact invariant a prediction needs. An emit site that sends the raw
# _current_resource backing field instead of the prediction-aware getter puts the
# unpredicted number on the bar, and the regen block emits one every frame the
# pool moves -- so the predicted spend is wiped a frame after it appears.
#
# Checked inside the handler rather than by sampling once per frame: the
# replication setter emits the correct value on the same frame the regen block
# emits, and whichever lands second wins the sample, so a wrong emit hides. It is
# still a wrong frame on the bar.
#
# A fixed ceiling would not work here. The prediction is an OFFSET, so the value
# it reports legitimately drifts upward with regeneration while the request is in
# flight; only the gap between payload and getter is invariant.
var _resource_watch_armed := false
var _resource_watch_violation := ""


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	if await _connect_peers():
		await _test_successful_activation()
		await _test_server_side_refusal()
		await _test_basic_attack_request()
		await _test_forwarded_latch_survives_refusal()
		await _test_refused_prediction_rolls_back()
		await _test_prediction_is_immediate()
		await _test_confirmed_prediction_does_not_snap()

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

	var client_combatant := _combatant(_client_actor)
	if client_combatant != null:
		client_combatant.resource_changed.connect(_on_client_resource_changed)

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

	# Re-send exactly as PlayerController3D does on the forwarded path, rather
	# than on a more forgiving loop of its own: the controller holds the pending
	# target while the swing is unconfirmed and stops the moment its replicated
	# MobaStateMachine shows the server started one. Mirroring that policy here
	# is what keeps this check honest about the path that actually ships -- a
	# looser retry would pass even if the shipped latch dropped every order.
	var client_state := _client_actor.get_node("MobaStateMachine") as MobaStateMachine
	var previous_state := -1
	var swing_confirmed := false

	# Evaluate the latch in the SAME order the controller does: request, then
	# read the replicated state immediately, then wait a frame. The ordering is
	# load-bearing. The request has only just been sent when the state is read,
	# so that read still shows the pre-swing state -- which is exactly how the
	# neutral state gets observed before the server's BASIC_ATTACK_WINDUP
	# replicates back a frame or two later. Reading after the await instead
	# would miss the neutral frame entirely and never confirm anything, which is
	# a property of the observation order, not of the code under test.
	for _i in range(120):
		var current_state: int = client_state.current_state
		var swing_started: bool = (
			current_state == MobaState.BASIC_ATTACK_WINDUP
			and previous_state != MobaState.BASIC_ATTACK_WINDUP
		)
		if previous_state != -1 and swing_started:
			# The controller clears its latch here and stops re-requesting.
			swing_confirmed = true
			break
		previous_state = current_state

		_hold_target_in_reach()
		await physics_frame
		_client_actor.try_basic_attack(_enemy)

	if swing_confirmed:
		_pass("client observes the server starting the swing it requested")
	else:
		_fail("client never saw the server start a swing it requested")

	# Let the confirmed swing finish its wind-up and land its damage, without
	# re-requesting -- exactly as the controller behaves once its latch clears.
	for _i in range(60):
		_hold_target_in_reach()
		await physics_frame
		if enemy_combatant.current_health < health_before:
			break

	if enemy_combatant.current_health < health_before:
		_pass("client basic attack request lands on the server")
	else:
		_fail(
			"basic attack never reached the server: target health unchanged at %.1f" % health_before
		)


## The refused-first-request case, checked against the shipped decision itself.
##
## This is the regression the latch exists to prevent and the one the retry loop
## above cannot show: when the server refuses a client's swing because the actor
## is still recovering from the previous one, PlayerController3D must HOLD the
## pending target and re-request, not drop the order. get_attack_target() arms
## the latch exactly once per order -- it cancel_order()s first, so _attack_target
## is already gone and nothing can re-arm it -- so a dropped latch means the
## player's click silently produces no swing at all.
##
## Calls PlayerController3D._hold_forwarded_attack() directly rather than
## re-deriving its policy a third time: a copy of the rule here could stay green
## while the shipped rule regressed, which is the whole failure mode being
## guarded against.
func _test_forwarded_latch_survives_refusal() -> void:
	var controller := _client_actor.get_node_or_null("Controller") as PlayerController3D
	if controller == null:
		_fail("setup: client actor has no PlayerController3D")
		return
	var client_state := _client_actor.get_node("MobaStateMachine") as MobaStateMachine

	# Drive the actor into a basic-attack cycle, then arm a fresh order while it
	# is still mid-swing -- the exact moment the server refuses.
	_hold_target_in_reach()
	_client_actor.try_basic_attack(_enemy)
	var swinging := false
	for _i in range(60):
		_hold_target_in_reach()
		await physics_frame
		if (
			client_state.current_state == MobaState.BASIC_ATTACK_WINDUP
			or client_state.current_state == MobaState.BASIC_ATTACK_RECOVERY
		):
			swinging = true
			break
	if not swinging:
		_fail("setup: could not get the client actor into a basic-attack cycle")
		return

	# Arm as get_attack_target() does for a new order.
	controller._pending_attack_target = _enemy
	controller._basic_attack_pending = true
	controller._last_observed_attack_state = -1

	_hold_target_in_reach()
	if controller._hold_forwarded_attack():
		_pass("latch holds a forwarded swing the server refused mid-cycle")
	else:
		_fail("latch dropped a forwarded swing while the actor was still mid-cycle")
		return

	# Once the cycle ends and the server starts THIS order's swing, the latch
	# must release rather than re-request forever.
	var released := false
	for _i in range(120):
		_hold_target_in_reach()
		await physics_frame
		if not controller._hold_forwarded_attack():
			released = true
			break
		_client_actor.try_basic_attack(_enemy)

	if released:
		_pass("latch releases once the server confirms the swing started")
	else:
		_fail("latch never released: a single order would re-request indefinitely")


## Record what the client's combatant last told its resource_changed listeners,
## and flag any emit that breaks the predicted ceiling while a prediction stands.
func _on_client_resource_changed(current: float, _maximum: float) -> void:
	_client_resource_emitted = current

	if not _resource_watch_armed or _resource_watch_violation != "":
		return
	var client_combatant := _combatant(_client_actor)
	if client_combatant == null:
		return
	var reported: float = client_combatant.current_resource
	if not is_equal_approx(current, reported):
		_resource_watch_violation = (
			"emitted %.2f while current_resource reports %.2f" % [current, reported]
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


## The refusal path, first, because a prediction with no rollback is worse than
## no prediction at all (#321).
##
## Wipes the CLIENT's ledger so its copy believes the ability is ready -- the
## same stale client _test_server_side_refusal() uses -- while the SERVER's
## cooldown is still running. The client therefore predicts, the server refuses,
## and the only thing that can correct the client is the explicit
## Actor.deny_activation() RPC: the combat state replicates on-change, and a
## refusal changes nothing on the server for it to re-send.
##
## The settle window is a fraction of a second, well inside
## MobaPredictionLedger.TIMEOUT_SECONDS, so a pass here is the denial
## arriving and not the backstop expiring.
func _test_refused_prediction_rolls_back() -> void:
	var server_combatant := _combatant(_server_actor)
	var client_combatant := _combatant(_client_actor)
	if server_combatant == null or client_combatant == null:
		return

	# Quiet the forwarded-attack latch the basic-attack checks above left running.
	# While it holds, PlayerController3D re-requests a swing EVERY frame, and each
	# re-request makes a fresh basic-attack prediction whose notification carries
	# the (correct) resource value -- which would mask a rollback that corrected
	# the model and told the HUD nothing. Cleared through the controller's own
	# fields rather than by faking a drop, so the latch is genuinely idle.
	var controller := _client_actor.get_node_or_null("Controller") as PlayerController3D
	if controller != null:
		controller.set("_basic_attack_pending", false)
		controller.set("_pending_attack_target", null)
	client_combatant.get_prediction_ledger().rollback()
	await _settle()

	# Re-arm the server's cooldown so the next request is refused on it.
	var context := MobaCastContext.new(_client_actor, null, Vector3.FORWARD, Vector3.ZERO)
	_client_actor.try_activate_slot(_SLOT, context)
	await _settle()
	if server_combatant.get_cooldown_remaining(_ABILITY) <= 0.0:
		_fail("setup: server cooldown did not arm before the refusal check")
		return

	# Put BOTH peers at full resource before predicting. At maximum the regen
	# block emits nothing, and a replicated value that did not move emits nothing
	# either -- so after the refusal the rollback's own notification is the only
	# thing that can still update the bar. Without this, regen would keep
	# emitting the correct post-rollback number every frame and would mask a
	# rollback that corrected the model silently.
	server_combatant.restore_to_full()
	await _settle()

	# The client's ledger is wiped AFTER that settle, not before: the server's
	# cooldown snapshot replicates during it and would re-arm the ledger, leaving
	# the client correctly believing the ability is on cooldown -- at which point
	# it declines to predict and there is nothing to roll back.
	client_combatant.clear_all_cooldowns()
	client_combatant.restore_to_full()

	# Cleared last, so the assertions below can only pass on an emit the REFUSAL
	# caused -- restore_to_full() above emits one of its own.
	_client_resource_emitted = -1.0

	_client_actor.try_activate_slot(_SLOT, context)

	# Asked per ability rather than "any prediction at all": an unconfirmed swing
	# left over from the basic-attack checks above is a different question, and
	# either could otherwise mask the other.
	if not client_combatant.get_prediction_ledger().has(_ABILITY):
		_fail("client did not predict the activation it was about to be refused")
		return

	await _settle()

	if not client_combatant.get_prediction_ledger().has(_ABILITY):
		_pass("a refused prediction is rolled back by the server's denial")
	else:
		_fail("client still holds a prediction the server refused")

	# What the client shows must be the server's truth, not the guess. The
	# server's own cooldown is still running and replicates, so the client is
	# expected to show THAT -- what must not survive is the predicted sweep the
	# client started from its own wiped ledger.
	var predicted_sweep := MobaAbilityLibrary.get_ability(_ABILITY).cooldown
	var client_cooldown := client_combatant.get_cooldown_remaining(_ABILITY)
	if is_equal_approx(client_cooldown, server_combatant.get_cooldown_remaining(_ABILITY)):
		_pass("a refused prediction leaves no cooldown behind")
	else:
		_fail(
			(
				"client cooldown %.2f is neither the server's %.2f nor rolled back"
				% [client_cooldown, server_combatant.get_cooldown_remaining(_ABILITY)]
			)
		)
	if client_cooldown >= predicted_sweep:
		_fail("the refused prediction's own sweep survived the rollback")

	# Nothing spent: the client is back on the server's own resource exactly,
	# carrying no predicted debit for a cast that never happened.
	#
	# Compared against the SERVER's value, not against what the client showed
	# before the request: restore_to_full() above put a number on the client that
	# was never true, and the server's real value replicating over it is the
	# rollback working, not a spend. The predicted debit is what must be gone,
	# and an exact match is what proves it is.
	#
	# Checked on the emitted payload as well as the getter: the bar has no other
	# input, so a rollback that corrected the model without telling its listeners
	# would leave the wrong number on screen indefinitely.
	var matches_model := is_equal_approx(
		client_combatant.current_resource, server_combatant.current_resource
	)
	var matches_emit := is_equal_approx(_client_resource_emitted, server_combatant.current_resource)
	if _client_resource_emitted < 0.0:
		_fail("the rollback told the HUD nothing, so the predicted spend stays on the bar")
	elif matches_model and matches_emit:
		_pass("a refused prediction leaves nothing spent")
	elif not matches_model:
		_fail(
			(
				"client resource %.1f does not match the server's %.1f after rollback"
				% [client_combatant.current_resource, server_combatant.current_resource]
			)
		)
	else:
		_fail(
			(
				"rollback corrected the model but told the HUD %.1f, not %.1f"
				% [_client_resource_emitted, server_combatant.current_resource]
			)
		)


## The prediction itself: the sweep and the spend must be visible on the frame
## the request goes out, not a round trip later.
##
## Read with no await at all between the request and the assertions -- an await
## would let the server's reply arrive and make a passing check unable to tell
## prediction from replication, which is the whole point of this one.
func _test_prediction_is_immediate() -> void:
	var server_combatant := _combatant(_server_actor)
	var client_combatant := _combatant(_client_actor)
	if server_combatant == null or client_combatant == null:
		return

	# Drop anything the refusal check left outstanding, so this check measures its
	# own prediction rather than inheriting a stale overlay through the accessors.
	client_combatant.get_prediction_ledger().rollback()

	# Both ledgers clear, so the request is one the server will confirm.
	server_combatant.clear_all_cooldowns()
	server_combatant.restore_to_full()
	client_combatant.clear_all_cooldowns()
	client_combatant.restore_to_full()
	await _settle()

	# Drop the SERVER off full so resource regeneration is actually running. At
	# maximum the regen block emits nothing (it only emits when the value moves),
	# which would make the survival check below vacuous -- it would pass whether
	# or not the regen emit carries the predicted value, because it never fires.
	server_combatant.spend_resource(server_combatant.maximum_resource * 0.25)
	await _settle()
	if server_combatant.current_resource >= server_combatant.maximum_resource:
		_fail("setup: server is still at full resource, so regeneration cannot fire")
		return

	var client_resource_before := client_combatant.current_resource
	if client_combatant.get_cooldown_remaining(_ABILITY) > 0.0:
		_fail("setup: client cooldown was not clear before the prediction check")
		return

	# Cleared so the assertion below can only pass on an emit the REQUEST caused,
	# and the watch armed so every later emit is checked against the getter.
	_client_resource_emitted = -1.0
	_resource_watch_violation = ""
	_resource_watch_armed = true

	var context := MobaCastContext.new(_client_actor, null, Vector3.FORWARD, Vector3.ZERO)
	_client_actor.try_activate_slot(_SLOT, context)

	# Same frame. The server has not even received the packet yet.
	if client_combatant.get_cooldown_remaining(_ABILITY) > 0.0:
		_pass("a prediction starts the cooldown sweep before the server replies")
	else:
		_fail("client shows no cooldown on the frame it sent the request")

	# Read from the signal payload, not from current_resource. The bar has no
	# other input, so asserting the getter would pass even if the prediction
	# never reached the HUD at all -- and a later regen emit carrying the raw
	# unpredicted value would silently undo it on the next frame.
	var cost := MobaAbilityLibrary.get_ability(_ABILITY).resource_cost
	if _client_resource_emitted < 0.0:
		_fail("predicting emitted no resource_changed, so the HUD bar never moved")
	elif is_equal_approx(client_resource_before - _client_resource_emitted, cost):
		_pass("a prediction shows the resource spend before the server replies")
	else:
		_fail(
			(
				"resource_changed reported %.1f, not the predicted %.1f"
				% [_client_resource_emitted, client_resource_before - cost]
			)
		)

	# The prediction must SURVIVE the regeneration frames that follow. The regen
	# block emits every frame the pool moves, and emitting the raw backing field
	# there re-asserts the unpredicted value and wipes the predicted spend off
	# the bar within a frame of it appearing.
	for _i in range(_SETTLE_FRAMES):
		await physics_frame
		if not client_combatant.get_prediction_ledger().has(_ABILITY):
			break
	if _resource_watch_violation != "":
		_fail("an emit contradicted the predicted state: %s" % _resource_watch_violation)
	_resource_watch_armed = false


## Confirmation: the server's replicated value takes the prediction's place
## without the sweep visibly restarting.
##
## Samples every frame across the whole window rather than checking the endpoints.
## A snap is by definition something that happens on ONE frame -- endpoints that
## match prove nothing about the frames between them, which is exactly where a
## prediction handed over badly would show.
func _test_confirmed_prediction_does_not_snap() -> void:
	var server_combatant := _combatant(_server_actor)
	var client_combatant := _combatant(_client_actor)
	if server_combatant == null or client_combatant == null:
		return

	server_combatant.clear_all_cooldowns()
	server_combatant.restore_to_full()
	client_combatant.clear_all_cooldowns()
	client_combatant.restore_to_full()
	await _settle()

	var context := MobaCastContext.new(_client_actor, null, Vector3.FORWARD, Vector3.ZERO)
	_client_actor.try_activate_slot(_SLOT, context)

	var previous := client_combatant.get_cooldown_remaining(_ABILITY)
	var snapped_upward := false
	var dropped_to_zero := false
	for _i in range(_SETTLE_FRAMES * 2):
		await physics_frame
		var current := client_combatant.get_cooldown_remaining(_ABILITY)
		# The sweep may only ever run down. Going back UP is the visible restart
		# the criterion forbids; reaching zero mid-flight and climbing again is
		# the same fault seen from the other side.
		if current > previous + 0.001:
			snapped_upward = true
		if current <= 0.0:
			dropped_to_zero = true
		previous = current

	if client_combatant.get_prediction_ledger().has(_ABILITY):
		_fail("the server confirmed the activation but the client kept predicting")
	elif is_equal_approx(
		client_combatant.get_cooldown_remaining(_ABILITY),
		server_combatant.get_cooldown_remaining(_ABILITY)
	):
		_pass("a confirmed prediction ends on the server's own cooldown")
	else:
		_fail(
			(
				"client settled on cooldown %.2f, server holds %.2f"
				% [
					client_combatant.get_cooldown_remaining(_ABILITY),
					server_combatant.get_cooldown_remaining(_ABILITY)
				]
			)
		)

	if not snapped_upward and not dropped_to_zero:
		_pass("a confirmed prediction never restarts the sweep from full")
	elif snapped_upward:
		_fail("the cooldown sweep jumped backwards when the server's value arrived")
	else:
		_fail("the cooldown sweep fell to zero before the server's value arrived")
