# Headless integration test for lobby build inspection: a present peer pulling a
# read-only summary of another present peer's accepted build.
#
# Run with:
#   godot --headless --path . --script tests/lobby_build_inspector_test.gd
#
# Covers, in order:
#   - a submitted build round-trips through _resolve_inspect_build() with every
#     display field intact: character name, both Disciplines, weapon, all four
#     action slots, the passive slot, and the full stat allocation;
#   - the reply is addressed to the requesting peer with rpc_id and is never
#     broadcast, verified structurally against the source;
#   - a peer with no spawned lobby avatar resolves to an explicit empty result
#     rather than an error or a dropped request;
#   - the panel's interactive controls are focusable and touch-sized, and no
#     affordance depends on a hover state;
#   - inspecting twice returns identical data and leaves the stored build
#     untouched, including when the caller edits the payload it got back;
#   - the panel offers a focusable entry point per present peer.
#
# This test is NOT wired into tests/test_bootstrap.gd: it loads game scenes and a
# LobbyManager, matching the precedent set by tests/lobby_manager_test.gd and
# tests/session_manager_test.gd.
extends SceneTree

const _LOBBY_SPAWN_POINT := preload("res://resources/lobby_player_spawn_point.tres")
const _PANEL_SCENE := preload("res://scenes/lobby/build_inspector_panel.tscn")
const _MANAGER_SOURCE_PATH := "res://scripts/lobby_manager.gd"

# One peer id per check, so no check inherits another's state.
const _PEER_ROUND_TRIP := 31
const _PEER_ABSENT := 32
const _PEER_IDEMPOTENT := 33
const _PEER_LIST_A := 34
const _PEER_LIST_B := 35

const _EXPECTED_CHECKS: Array[String] = [
	"submitted build round-trips with every display field",
	"reply is addressed to the requester, never broadcast",
	"absent peer resolves to an explicit empty result",
	"panel controls are focusable and touch-sized",
	"inspection is idempotent and does not mutate stored state",
	"panel offers a focusable entry point per present peer",
	"selection is reachable before any inspection",
	"peer list follows presence changes after ready",
	"a zero-valued stat is rendered, not dropped",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	_test_submitted_build_round_trips()
	_test_reply_targets_requester_only()
	_test_absent_peer_resolves_empty()
	await _test_panel_controls_are_accessible()
	_test_inspection_is_idempotent()
	await _test_panel_lists_present_peers()
	await _test_selection_is_reachable_before_any_inspection()
	await _test_peer_list_follows_presence()
	await _test_zero_stat_is_rendered()

	_finish()


## A LobbyManager with no MultiplayerSpawner, matching lobby_manager_test.gd.
func _make_lobby_manager() -> LobbyManager:
	var lobby_manager := LobbyManager.new()
	lobby_manager.avatar_spawn_point = _LOBBY_SPAWN_POINT
	root.add_child(lobby_manager)
	return lobby_manager


## Spawn an avatar and parent it, so it is present in the tree the way a
## spawner-driven avatar would be.
func _spawn_avatar(lobby_manager: LobbyManager, peer_id: int) -> Actor:
	lobby_manager.spawn_avatar_for_peer(peer_id)
	var actor: Actor = lobby_manager._peer_avatars.get(peer_id)
	if actor != null and actor.get_parent() == null:
		lobby_manager.add_child(actor)
	return actor


## A legal WARRIOR/GUARDIAN build, shaped like peer_identity_registry_test.gd's.
func _make_legal_build(character_name: String) -> MobaCharacterBuild:
	var fallback: MobaCharacterBuild = load("res://rules/data/builds/melee_bruiser_build.tres")

	var loadout := MobaLoadout.new()
	loadout.set_action_slot(1, "whirlwind")
	loadout.set_action_slot(2, "shield_bash")
	loadout.weapon = fallback.loadout.weapon

	var allocation: Dictionary[StringName, int] = {}
	allocation.assign({&"health": 2, &"armor": 1})

	var build := MobaCharacterBuild.new()
	build.character_name = character_name
	build.primary_discipline = MobaAbility.Discipline.WARRIOR
	build.secondary_discipline = MobaAbility.Discipline.GUARDIAN
	build.stat_allocation = allocation
	build.loadout = loadout

	return build


func _registry() -> Node:
	return root.get_node_or_null(^"/root/PeerIdentityRegistry")


## Every display field the Issue names comes back matching what was submitted.
func _test_submitted_build_round_trips() -> void:
	var registry := _registry()
	if registry == null:
		_fail("setup: PeerIdentityRegistry autoload not found")
		return

	var manager := _make_lobby_manager()
	var build := _make_legal_build("Roundtrip Rowan")
	var problem := _submit_and_encode(manager, registry, _PEER_ROUND_TRIP, build)
	if problem != "":
		_fail_cleanup(problem, [manager])
		return

	var encoded := manager._resolve_inspect_build(_PEER_ROUND_TRIP)
	var allocation: Dictionary = encoded.get("stat_allocation", {})
	var slots: PackedStringArray = encoded.get("action_slots", PackedStringArray())

	# Every display field the Scope names, checked as one table so a mismatch
	# reports the field rather than the first early return that noticed.
	var expected := {
		"character_name": "Roundtrip Rowan",
		"primary_discipline": int(MobaAbility.Discipline.WARRIOR),
		"secondary_discipline": int(MobaAbility.Discipline.GUARDIAN),
		"weapon_path": build.loadout.weapon.resource_path,
		"passive_slot": build.loadout.passive_slot,
	}

	var mismatches: Array[String] = []
	for field: String in expected:
		if encoded.get(field) != expected[field]:
			mismatches.append("%s was %s" % [field, encoded.get(field)])

	if slots.size() != 4:
		mismatches.append("expected 4 action slots, got %d" % slots.size())
	else:
		var expected_slots := ["whirlwind", "shield_bash", "", ""]
		for i in range(4):
			if slots[i] != expected_slots[i]:
				mismatches.append("action slot %d was %s" % [i + 1, slots[i]])

	if allocation.get(&"health") != 2 or allocation.get(&"armor") != 1:
		mismatches.append("stat_allocation was %s" % allocation)

	if not mismatches.is_empty():
		_fail_cleanup("; ".join(mismatches), [manager])
		return

	_pass("submitted build round-trips with every display field")
	manager.queue_free()


## Spawn the peer's avatar and get its build accepted. Returns "" on success, or
## the reason the setup could not be established.
func _submit_and_encode(
	manager: LobbyManager, registry: Node, peer_id: int, build: MobaCharacterBuild
) -> String:
	var avatar := _spawn_avatar(manager, peer_id)
	if avatar == null:
		return "setup: avatar did not spawn"

	var submission: ActionResult = registry.submit_build(peer_id, avatar, build, peer_id)
	if not submission.success:
		return "setup: legal build was refused (%s)" % submission.reason

	if manager._resolve_inspect_build(peer_id).is_empty():
		return "present peer resolved to an empty result"

	return ""


## The reply goes to the one requester, structurally: the source sends it with
## rpc_id and never with a broadcast rpc().
func _test_reply_targets_requester_only() -> void:
	var manager := _make_lobby_manager()

	if not manager.has_method("_reply_inspect_build"):
		_fail_cleanup("LobbyManager has no _reply_inspect_build inbox", [manager])
		return

	var source := FileAccess.get_file_as_string(_MANAGER_SOURCE_PATH)
	if source == "":
		_fail_cleanup("could not read %s" % _MANAGER_SOURCE_PATH, [manager])
		return

	if not source.contains("_reply_inspect_build.rpc_id(requester_id,"):
		_fail_cleanup("the reply is not addressed with rpc_id(requester_id, ...)", [manager])
		return

	# A broadcast would put another peer's build on every present peer's wire,
	# which is exactly the push this feature is specified not to be.
	if source.contains("_reply_inspect_build.rpc("):
		_fail_cleanup("the reply is broadcast with rpc() somewhere", [manager])
		return

	_pass("reply is addressed to the requester, never broadcast")
	manager.queue_free()


## A peer with no spawned avatar gets an explicit empty answer, not an error.
func _test_absent_peer_resolves_empty() -> void:
	var manager := _make_lobby_manager()

	var never_connected := manager._resolve_inspect_build(_PEER_ABSENT)
	if not never_connected.is_empty():
		_fail_cleanup("a never-connected peer resolved to %s" % never_connected, [manager])
		return

	# And the same for one that was present and then left.
	var avatar := _spawn_avatar(manager, _PEER_ABSENT)
	if avatar == null:
		_fail_cleanup("setup: avatar did not spawn", [manager])
		return

	manager._on_peer_disconnected(_PEER_ABSENT)

	var after_disconnect := manager._resolve_inspect_build(_PEER_ABSENT)
	if not after_disconnect.is_empty():
		_fail_cleanup("a disconnected peer resolved to %s" % after_disconnect, [manager])
		return

	_pass("absent peer resolves to an explicit empty result")
	manager.queue_free()


## Every interactive control is focus-navigable and touch-sized, and nothing
## depends on a hover.
func _test_panel_controls_are_accessible() -> void:
	var panel := _PANEL_SCENE.instantiate()
	root.add_child(panel)
	await process_frame

	var buttons := _find_buttons(panel)
	if buttons.is_empty():
		_fail_cleanup("panel has no interactive controls at all", [panel])
		return

	for button in buttons:
		if button.focus_mode != Control.FOCUS_ALL:
			_fail_cleanup("%s is not focus-navigable" % button.name, [panel])
			return

		if (
			button.custom_minimum_size.x < LobbyBuildInspector.TOUCH_TARGET_SIZE.x
			or button.custom_minimum_size.y < LobbyBuildInspector.TOUCH_TARGET_SIZE.y
		):
			_fail_cleanup("%s is smaller than a touch target" % button.name, [panel])
			return

		# A hover-gated affordance is unreachable by gamepad and by touch alike.
		if button.mouse_entered.get_connections().size() > 0:
			_fail_cleanup("%s has a hover-dependent affordance" % button.name, [panel])
			return

	_pass("panel controls are focusable and touch-sized")
	panel.queue_free()


## Inspecting is a read: twice in a row is identical, and editing the reply
## cannot reach what the registry stores.
func _test_inspection_is_idempotent() -> void:
	var registry := _registry()
	if registry == null:
		_fail("setup: PeerIdentityRegistry autoload not found")
		return

	var manager := _make_lobby_manager()
	var problem := _submit_and_encode(
		manager, registry, _PEER_IDEMPOTENT, _make_legal_build("Steady Sam")
	)
	if problem != "":
		_fail_cleanup(problem, [manager])
		return

	var first := manager._resolve_inspect_build(_PEER_IDEMPOTENT)
	var second := manager._resolve_inspect_build(_PEER_IDEMPOTENT)

	if var_to_str(first) != var_to_str(second):
		_fail_cleanup("two identical requests returned different data", [manager])
		return

	# Editing the payload must not reach the registry's own stored allocation.
	var allocation: Dictionary = first.get("stat_allocation", {})
	allocation[&"health"] = 9999

	var third := manager._resolve_inspect_build(_PEER_IDEMPOTENT)
	if third.get("stat_allocation", {}).get(&"health") != 2:
		_fail_cleanup("editing a reply mutated the stored build", [manager])
		return

	if registry.get_peer_build(_PEER_IDEMPOTENT).character_name != "Steady Sam":
		_fail_cleanup("inspecting changed the stored build", [manager])
		return

	_pass("inspection is idempotent and does not mutate stored state")
	manager.queue_free()


## The panel gives every present peer a focusable way to be selected, which is
## how a request is ever made in the first place.
func _test_panel_lists_present_peers() -> void:
	var manager := _make_lobby_manager()
	_spawn_avatar(manager, _PEER_LIST_A)
	_spawn_avatar(manager, _PEER_LIST_B)

	var panel := _PANEL_SCENE.instantiate() as LobbyBuildInspector
	manager.add_child(panel)
	await process_frame

	# The panel resolves its lobby by path; in the real scene it hangs off a
	# CanvasLayer beside LobbyManager, so point it at this one directly.
	panel.bind_lobby(manager)

	var buttons := _find_buttons(panel)
	var peer_buttons: Array[Button] = []
	for button in buttons:
		if button.text.begins_with("Inspect peer"):
			peer_buttons.append(button)

	if peer_buttons.size() != 2:
		_fail_cleanup("expected 2 peer buttons, got %d" % peer_buttons.size(), [manager])
		return

	for button in peer_buttons:
		if button.focus_mode != Control.FOCUS_ALL:
			_fail_cleanup("peer button %s is not focus-navigable" % button.text, [manager])
			return

	_pass("panel offers a focusable entry point per present peer")
	manager.queue_free()


## The selection affordance is on screen from the start.
##
## Regression guard: the peer buttons once lived inside a panel hidden in
## _ready(), and the only code that revealed it ran on an inspection reply --
## which needed one of those hidden buttons pressed first. Every criterion held
## in the harness while no player could reach the feature at all.
func _test_selection_is_reachable_before_any_inspection() -> void:
	var manager := _make_lobby_manager()
	_spawn_avatar(manager, _PEER_LIST_A)

	var panel := _PANEL_SCENE.instantiate() as LobbyBuildInspector
	manager.add_child(panel)
	await process_frame

	panel.bind_lobby(manager)
	await process_frame

	var reachable: Array[Button] = []
	for button in _find_buttons(panel):
		if button.text.begins_with("Inspect peer") and button.is_visible_in_tree():
			reachable.append(button)

	if reachable.is_empty():
		_fail_cleanup("no peer button is visible without a prior inspection", [manager])
		return

	_pass("selection is reachable before any inspection")
	manager.queue_free()


## A peer arriving after the panel is ready appears in the list, and one leaving
## drops out of it -- without anyone calling refresh_peer_list() by hand.
func _test_peer_list_follows_presence() -> void:
	var manager := _make_lobby_manager()

	var panel := _PANEL_SCENE.instantiate() as LobbyBuildInspector
	manager.add_child(panel)
	await process_frame

	panel.bind_lobby(manager)

	if _count_peer_buttons(panel) != 0:
		_fail_cleanup("expected an empty list before anyone is present", [manager])
		return

	_spawn_avatar(manager, _PEER_LIST_A)
	_spawn_avatar(manager, _PEER_LIST_B)
	await process_frame
	await process_frame

	if _count_peer_buttons(panel) != 2:
		_fail_cleanup(
			"list did not follow two arrivals (got %d)" % _count_peer_buttons(panel), [manager]
		)
		return

	manager._on_peer_disconnected(_PEER_LIST_B)
	await process_frame
	await process_frame

	if _count_peer_buttons(panel) != 1:
		_fail_cleanup(
			"list did not follow a departure (got %d)" % _count_peer_buttons(panel), [manager]
		)
		return

	_pass("peer list follows presence changes after ready")
	manager.queue_free()


## An explicitly submitted 0 is part of "the full stat allocation" and is shown.
func _test_zero_stat_is_rendered() -> void:
	var panel := _PANEL_SCENE.instantiate() as LobbyBuildInspector
	root.add_child(panel)
	await process_frame

	panel._display_stat_allocation({&"health": 0, &"armor": 3})

	var rendered: Array[String] = []
	if panel._stats_container != null:
		for child in panel._stats_container.get_children():
			var label := child as Label
			if label != null and label.name != "StatsLabel":
				rendered.append(label.text)

	var joined := ", ".join(rendered)
	if not joined.contains("Health"):
		_fail_cleanup("a zero-valued stat was dropped (rendered: %s)" % joined, [panel])
		return

	if not joined.contains("+3"):
		_fail_cleanup("a positive stat lost its sign (rendered: %s)" % joined, [panel])
		return

	_pass("a zero-valued stat is rendered, not dropped")
	panel.queue_free()


## Visible peer buttons currently offered by the panel.
func _count_peer_buttons(panel: LobbyBuildInspector) -> int:
	var count := 0
	for button in _find_buttons(panel):
		if button.text.begins_with("Inspect peer"):
			count += 1
	return count


## Every Button in a subtree, so a check covers controls added at runtime too.
func _find_buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	var button := node as Button
	if button != null:
		found.append(button)

	for child in node.get_children():
		found.append_array(_find_buttons(child))

	return found


func _fail_cleanup(message: String, resources: Array) -> void:
	_fail(message)
	for resource in resources:
		if resource is Node:
			(resource as Node).queue_free()


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
		print("\nAll %d build inspection checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
