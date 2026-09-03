# Headless integration test for PeerIdentityRegistry: the session-scoped identity
# store for accepted peer builds that survives WorldManager resets.
#
# Run with:
#   godot --headless --path . --script tests/peer_identity_registry_test.gd
#
# Covers, in order:
#   - a peer's accepted build is retrievable after the WorldManager that received
#     the submission is freed and a new one constructed;
#   - WorldManager.submit_build() and WorldManager.get_peer_build() remain unchanged
#     in signature and behavior;
#   - an accepted build is a snapshot: editing the caller's build after submission
#     does not change what the registry returns;
#   - PeerIdentityRegistry.get_peer_build(peer_id) for a peer with no accepted build
#     returns the shipped fallback, not null and not an empty build;
#   - a peer's registry entry is cleared when that peer disconnects via the code path
#     WorldManager._on_peer_disconnected() now delegates through.
#
# This test is NOT wired into tests/test_bootstrap.gd: it loads game scenes and
# a WorldManager, matching the precedent set by tests/session_manager_test.gd.
extends SceneTree

const _PLAYER_SPAWN_POINT := preload("res://resources/player_spawn_point.tres")

# The shipped fallback, both as the source of a legal weapon for the builds
# below and as what an unsubmitted peer is asserted to get back.
const _FALLBACK_BUILD := preload("res://rules/data/builds/melee_bruiser_build.tres")

# One peer id per check. The registry is process-global and outlives every
# WorldManager built here, so a shared id would let one check pass on state a
# previous check left behind -- an ordering dependency that only surfaces when
# a check is reordered or removed.
const _PEER_RESET := 11
const _PEER_SUBMIT_SIGNATURE := 12
const _PEER_GET_SIGNATURE := 13
const _PEER_LEGAL := 14
const _PEER_ILLEGAL := 15
const _PEER_REFUSAL := 16
const _PEER_OWNERSHIP := 17
const _PEER_SNAPSHOT := 18
const _PEER_NEVER_SUBMITTED := 19
const _PEER_DISCONNECT := 20

# A second peer, used as the requester that does not own the actor.
const _OTHER_PEER := 9

const _EXPECTED_CHECKS: Array[String] = [
	"accepted build survives worldmanager reset",
	"worldmanager.submit_build signature unchanged",
	"worldmanager.get_peer_build signature unchanged",
	"legal submission succeeds",
	"illegal submission refused",
	"refusal preserves accepted build",
	"cannot submit for another peer",
	"accepted build is snapshot",
	"unsubmitted peer returns fallback",
	"peer disconnect clears entry",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	await _test_build_survives_worldmanager_reset()
	_test_worldmanager_submit_signature()
	_test_worldmanager_get_signature()
	_test_legal_submission()
	_test_illegal_submission_refused()
	_test_refusal_preserves_build()
	_test_cannot_submit_for_another()
	_test_accepted_build_is_snapshot()
	_test_unsubmitted_peer_returns_fallback()
	_test_peer_disconnect_clears_entry()

	_finish()


## Create a WorldManager without a MultiplayerSpawner
func _make_world_manager() -> WorldManager:
	var world_manager := WorldManager.new()
	world_manager.player_spawn_point = _PLAYER_SPAWN_POINT
	root.add_child(world_manager)
	return world_manager


## Spawn a player actor for a peer and return it
func _spawn_player(world_manager: WorldManager, peer_id: int) -> Actor:
	world_manager.spawn_player_for_peer(peer_id)
	var actor: Actor = world_manager._peer_actors.get(peer_id)
	if actor != null and actor.get_parent() == null:
		world_manager.add_child(actor)
	return actor


## A legal WARRIOR/GUARDIAN build
func _make_legal_build(name: String, allocation: Dictionary) -> MobaCharacterBuild:
	var loadout := MobaLoadout.new()
	loadout.set_action_slot(1, "whirlwind")
	loadout.set_action_slot(2, "shield_bash")
	loadout.weapon = _FALLBACK_BUILD.loadout.weapon

	var typed_allocation: Dictionary[StringName, int] = {}
	typed_allocation.assign(allocation)

	var build := MobaCharacterBuild.new()
	build.character_name = name
	build.primary_discipline = MobaAbility.Discipline.WARRIOR
	build.secondary_discipline = MobaAbility.Discipline.GUARDIAN
	build.stat_allocation = typed_allocation
	build.loadout = loadout

	return build


## An accepted build persists after the WorldManager is freed and recreated.
func _test_build_survives_worldmanager_reset() -> void:
	var registry := _get_registry()
	if registry == null:
		_fail("setup: PeerIdentityRegistry autoload not found")
		return

	var wm1 := _make_world_manager()
	var actor := _spawn_player(wm1, _PEER_RESET)
	if actor == null:
		_fail("setup: player actor did not spawn")
		wm1.queue_free()
		return

	var build := _make_legal_build("Persistent", {})
	if not wm1.submit_build(_PEER_RESET, build).success:
		_fail("setup: legal build was refused")
		wm1.queue_free()
		return

	# Verify the registry has it
	if registry.get_peer_build(_PEER_RESET).character_name != "Persistent":
		_fail("registry did not store the build")
		wm1.queue_free()
		return

	# Free the first WorldManager
	wm1.queue_free()
	await process_frame

	# Create a new WorldManager
	var wm2 := _make_world_manager()

	# The registry still has it even though wm1 is gone ...
	if registry.get_peer_build(_PEER_RESET).character_name != "Persistent":
		_fail("build was lost when WorldManager was freed")
		wm2.queue_free()
		return

	# ... and the replacement WorldManager reaches that same surviving storage,
	# which is the half that would regress if the delegation were dropped.
	if wm2.get_peer_build(_PEER_RESET).character_name != "Persistent":
		_fail("the replacement WorldManager did not see the surviving build")
		wm2.queue_free()
		return

	_pass("accepted build survives worldmanager reset")
	wm2.queue_free()


## WorldManager.submit_build() has not changed signature
func _test_worldmanager_submit_signature() -> void:
	var wm := _make_world_manager()
	var actor := _spawn_player(wm, _PEER_SUBMIT_SIGNATURE)
	if actor == null:
		_fail("setup: player actor did not spawn")
		wm.queue_free()
		return

	var build := _make_legal_build("Test", {})

	# Original signature: submit_build(peer_id: int, build: MobaCharacterBuild, requester_id: int = -1)
	# This should work exactly as before
	var result := wm.submit_build(_PEER_SUBMIT_SIGNATURE, build)
	if not result.success:
		_fail("submit_build call failed")
		wm.queue_free()
		return

	_pass("worldmanager.submit_build signature unchanged")
	wm.queue_free()


## WorldManager.get_peer_build() has not changed signature
func _test_worldmanager_get_signature() -> void:
	var wm := _make_world_manager()
	var actor := _spawn_player(wm, _PEER_GET_SIGNATURE)
	if actor == null:
		_fail("setup: player actor did not spawn")
		wm.queue_free()
		return

	var build := _make_legal_build("Test", {})
	wm.submit_build(_PEER_GET_SIGNATURE, build)

	# Original signature: get_peer_build(peer_id: int) -> MobaCharacterBuild
	# This should work exactly as before
	var retrieved: MobaCharacterBuild = wm.get_peer_build(_PEER_GET_SIGNATURE)
	if retrieved == null:
		_fail("get_peer_build returned null")
		wm.queue_free()
		return

	_pass("worldmanager.get_peer_build signature unchanged")
	wm.queue_free()


## A legal submission through WorldManager is accepted
func _test_legal_submission() -> void:
	var wm := _make_world_manager()
	var actor := _spawn_player(wm, _PEER_LEGAL)
	if actor == null:
		_fail("setup: player actor did not spawn")
		wm.queue_free()
		return

	var build := _make_legal_build("Legal", {})
	var result := wm.submit_build(_PEER_LEGAL, build)
	if not result.success:
		_fail("legal build was refused: %s" % String(result.reason))
		wm.queue_free()
		return

	_pass("legal submission succeeds")
	wm.queue_free()


## An illegal submission is refused
func _test_illegal_submission_refused() -> void:
	var wm := _make_world_manager()
	var actor := _spawn_player(wm, _PEER_ILLEGAL)
	if actor == null:
		_fail("setup: player actor did not spawn")
		wm.queue_free()
		return

	var illegal := _make_legal_build("Illegal", {})
	# Add an ability outside the WARRIOR/GUARDIAN pair
	illegal.loadout.set_action_slot(3, "aimed_shot")

	var result := wm.submit_build(_PEER_ILLEGAL, illegal)
	if result.success:
		_fail("illegal build was accepted")
		wm.queue_free()
		return
	if result.reason != MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES:
		_fail(
			(
				"illegal build refused with '%s', expected '%s'"
				% [
					String(result.reason),
					String(MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES),
				]
			)
		)
		wm.queue_free()
		return

	_pass("illegal submission refused")
	wm.queue_free()


## A refused submission does not overwrite the previously accepted build
func _test_refusal_preserves_build() -> void:
	var wm := _make_world_manager()
	var actor := _spawn_player(wm, _PEER_REFUSAL)
	if actor == null:
		_fail("setup: player actor did not spawn")
		wm.queue_free()
		return

	var accepted := _make_legal_build("Keeper", {})
	if not wm.submit_build(_PEER_REFUSAL, accepted).success:
		_fail("setup: legal build was refused")
		wm.queue_free()
		return

	var illegal := _make_legal_build("Illegal", {})
	illegal.loadout.set_action_slot(3, "aimed_shot")
	wm.submit_build(_PEER_REFUSAL, illegal)

	var stored := wm.get_peer_build(_PEER_REFUSAL)
	if stored.character_name != "Keeper":
		_fail("refusal overwrote the accepted build")
		wm.queue_free()
		return

	_pass("refusal preserves accepted build")
	wm.queue_free()


## A peer cannot submit a build for another peer's actor
func _test_cannot_submit_for_another() -> void:
	var wm := _make_world_manager()
	var actor := _spawn_player(wm, _PEER_OWNERSHIP)
	if actor == null:
		_fail("setup: player actor did not spawn")
		wm.queue_free()
		return

	var build := _make_legal_build("Hijack", {})
	var result := wm.submit_build(_PEER_OWNERSHIP, build, _OTHER_PEER)

	if result.success:
		_fail("a peer submitted a build for another peer's actor")
		wm.queue_free()
		return

	_pass("cannot submit for another peer")
	wm.queue_free()


## An accepted build is a snapshot; editing the original does not affect the stored copy
func _test_accepted_build_is_snapshot() -> void:
	var wm := _make_world_manager()
	var actor := _spawn_player(wm, _PEER_SNAPSHOT)
	if actor == null:
		_fail("setup: player actor did not spawn")
		wm.queue_free()
		return

	var submitted := _make_legal_build("Snapshot", {MobaStatBlock.ARMOR: 2})
	if not wm.submit_build(_PEER_SNAPSHOT, submitted).success:
		_fail("setup: legal build was refused")
		wm.queue_free()
		return

	# Edit every mutable part of the caller's build after acceptance: the name,
	# the stat allocation Dictionary, and the loadout sub-Resource. Each is a
	# separate way a shallow copy would leak the caller's later edits into
	# authoritative state.
	submitted.character_name = "Tampered"
	submitted.stat_allocation[MobaStatBlock.ARMOR] = 999
	submitted.loadout.set_action_slot(1, "aimed_shot")

	var stored := wm.get_peer_build(_PEER_SNAPSHOT)
	if stored.character_name != "Snapshot":
		_fail("stored build's name was affected by post-submission edit")
		wm.queue_free()
		return

	if stored.stat_allocation.get(MobaStatBlock.ARMOR, 0) != 2:
		_fail("stored build's stat allocation was affected by post-submission edit")
		wm.queue_free()
		return

	if stored.loadout.get_action_slot(1) != "whirlwind":
		_fail(
			(
				"stored build's loadout slot changed after acceptance: got '%s', expected 'whirlwind'"
				% stored.loadout.get_action_slot(1)
			)
		)
		wm.queue_free()
		return

	_pass("accepted build is snapshot")
	wm.queue_free()


## A peer with no accepted build returns the fallback
func _test_unsubmitted_peer_returns_fallback() -> void:
	var wm := _make_world_manager()

	var fallback := wm.get_peer_build(_PEER_NEVER_SUBMITTED)
	if fallback == null:
		_fail("unsubmitted peer returned null instead of fallback")
		wm.queue_free()
		return

	if fallback.character_name != _FALLBACK_BUILD.character_name:
		_fail(
			(
				"unsubmitted peer returned '%s', expected the shipped fallback '%s'"
				% [fallback.character_name, _FALLBACK_BUILD.character_name]
			)
		)
		wm.queue_free()
		return

	if fallback.loadout == null:
		_fail("unsubmitted peer returned a build with no loadout")
		wm.queue_free()
		return

	_pass("unsubmitted peer returns fallback")
	wm.queue_free()


## Disconnecting a peer clears its registry entry
func _test_peer_disconnect_clears_entry() -> void:
	var registry := _get_registry()
	if registry == null:
		_fail("setup: PeerIdentityRegistry autoload not found")
		return

	var wm := _make_world_manager()
	var actor := _spawn_player(wm, _PEER_DISCONNECT)
	if actor == null:
		_fail("setup: player actor did not spawn")
		wm.queue_free()
		return

	var build := _make_legal_build("Disconnecting", {})
	if not wm.submit_build(_PEER_DISCONNECT, build).success:
		_fail("setup: legal build was refused")
		wm.queue_free()
		return

	# Verify the build is stored
	if registry.get_peer_build(_PEER_DISCONNECT).character_name != "Disconnecting":
		_fail("setup: build was not stored")
		wm.queue_free()
		return

	# Simulate disconnect
	wm._on_peer_disconnected(_PEER_DISCONNECT)

	# After disconnect, get_peer_build should return fallback for that peer
	var after_disconnect: MobaCharacterBuild = registry.get_peer_build(_PEER_DISCONNECT)
	if after_disconnect.character_name != _FALLBACK_BUILD.character_name:
		_fail(
			(
				"disconnect left '%s' for the peer, expected the shipped fallback '%s'"
				% [after_disconnect.character_name, _FALLBACK_BUILD.character_name]
			)
		)
		wm.queue_free()
		return

	if after_disconnect.loadout == null:
		_fail("after disconnect, peer returned a build with no loadout")
		wm.queue_free()
		return

	_pass("peer disconnect clears entry")
	wm.queue_free()


## Get the PeerIdentityRegistry autoload
func _get_registry() -> Node:
	return root.get_node_or_null(^"/root/PeerIdentityRegistry")


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
		print("\nAll %d peer identity registry checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
