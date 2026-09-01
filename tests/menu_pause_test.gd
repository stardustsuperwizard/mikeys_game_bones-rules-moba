# Headless integration test for the main menu and pause overlay (Issue #314).
#
# Run with:
#   godot --headless --path . --script tests/menu_pause_test.gd
#
# Covers, in order:
#   - the main menu scene loads and its three entry points are wired;
#   - the menu stretches to the viewport instead of collapsing to zero size;
#   - Play Offline leaves SessionManager OFFLINE with no ENet peer;
#   - scenes/main.tscn carries the pause overlay, so the world scene run
#     directly from the editor still has one;
#   - the overlay draws above the combat HUD's CanvasLayer and still processes
#     while the tree is paused;
#   - the `pause` action opens the overlay and pauses the tree;
#   - Resume unpauses and hides it again.
#
# host()/join() are not exercised: both bind a real ENet socket and join() needs
# a second Godot instance, which a single headless process cannot provide. Those
# are the Issue's human-validation criteria, matching the same carve-out in
# tests/session_manager_test.gd.
#
# SessionManager is reached through /root/SessionManager, not its global
# identifier: autoload identifiers are not registered under --script, so the
# bare name is a compile error here. scripts/main_menu.gd and
# scripts/pause_menu.gd resolve it the same way for the same reason.
#
# Every check appends its name to _completed and the run is only green when all
# of _EXPECTED_CHECKS are present. A GDScript runtime error aborts the enclosing
# function silently and returns null, which a plain "no failures recorded" exit
# would report as success -- the same trap tests/test_bootstrap.gd guards with
# its _expected_suites count.
#
# This test is NOT wired into tests/test_bootstrap.gd; it is a manual
# integration check matching tests/session_manager_test.gd's own precedent.
extends SceneTree

const _MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const _MAIN_SCENE := preload("res://scenes/main.tscn")

## Layer the combat HUD occupies. rules/ui/moba_combat_hud.tscn is a CanvasLayer
## and leaves `layer` at its default, so the pause overlay must exceed this to
## cover it.
const _HUD_LAYER: int = 1

const _EXPECTED_CHECKS: Array[String] = [
	"main menu scene loads",
	"main menu fills the viewport",
	"main menu offers offline, host and join",
	"play offline leaves no network peer",
	"main scene carries the pause overlay",
	"pause overlay draws above the combat HUD",
	"pause overlay processes while paused",
	"pause action opens the overlay",
	"resume unpauses and hides the overlay",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# The tree is not live yet inside _initialize(); Node.multiplayer is still
	# null until it has processed a frame, and go_offline() writes through it.
	await process_frame

	await _test_main_menu()
	_test_offline_flow()
	await _test_pause_menu()

	_finish()


## The main menu instantiates, lays out, and exposes all three entry points.
func _test_main_menu() -> void:
	var menu := _MAIN_MENU_SCENE.instantiate() as Control
	if menu == null:
		_fail("main menu scene did not instantiate as a Control")
		return

	root.add_child(menu)
	await process_frame

	_pass("main menu scene loads")

	# Guards a real regression class: writing `anchors_left` (not a property --
	# the real ones are `anchor_left`/`anchor_right`/...) loads without error and
	# silently leaves the menu at zero size, so every button is unclickable while
	# the scene still "loads fine".
	if menu.anchor_right != 1.0 or menu.anchor_bottom != 1.0:
		_fail(
			(
				"main menu root should stretch to the viewport, got anchors %f,%f"
				% [menu.anchor_right, menu.anchor_bottom]
			)
		)
	elif menu.size.x <= 0.0 or menu.size.y <= 0.0:
		_fail("main menu root collapsed to zero size: %s" % str(menu.size))
	else:
		_pass("main menu fills the viewport")

	var buttons := {
		"OfflineButton": "CenterContainer/VBoxContainer/OfflineButton",
		"HostButton": "CenterContainer/VBoxContainer/HostContainer/HostButton",
		"JoinButton": "CenterContainer/VBoxContainer/JoinContainer/JoinButton",
	}
	var fields := {
		"host port": "CenterContainer/VBoxContainer/HostContainer/HBoxContainer/PortInput",
		"join address": "CenterContainer/VBoxContainer/JoinContainer/HBoxContainer/AddressInput",
		"join port": "CenterContainer/VBoxContainer/JoinContainer/HBoxContainer2/JoinPortInput",
	}

	var missing: Array[String] = []
	for label in buttons:
		var button := menu.get_node_or_null(NodePath(buttons[label])) as Button
		if button == null:
			missing.append(label)
		elif not button.pressed.get_connections().size() > 0:
			missing.append("%s (not connected)" % label)
	for label in fields:
		if menu.get_node_or_null(NodePath(fields[label])) as LineEdit == null:
			missing.append("%s field" % label)

	if not missing.is_empty():
		_fail("main menu missing entry points: %s" % ", ".join(missing))
	else:
		_pass("main menu offers offline, host and join")

	menu.queue_free()


## The Play Offline path leaves the session offline with no network peer.
func _test_offline_flow() -> void:
	var session := _session()
	if session == null:
		_fail("setup: SessionManager autoload not found at /root/SessionManager")
		return

	# The same call the Play Offline button makes. The button itself cannot be
	# pressed here: it changes scene, which would tear down this test's tree.
	session.go_offline()

	if session.mode != session.Mode.OFFLINE:
		_fail("Play Offline should leave mode OFFLINE, got %d" % session.mode)
	elif session.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_fail("Play Offline should leave no ENet peer")
	elif session.multiplayer.get_unique_id() != 1:
		_fail("offline unique id should be 1, got %d" % session.multiplayer.get_unique_id())
	else:
		_pass("play offline leaves no network peer")


## The world scene carries a working pause overlay.
func _test_pause_menu() -> void:
	var scene := _MAIN_SCENE.instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	var pause_menu := _pause_overlay_of(scene)
	if pause_menu == null:
		return

	await _test_pause_opens(pause_menu)


## Find the overlay in the world scene and check how it is configured.
## Returns null (having recorded the failure) when it is unusable.
func _pause_overlay_of(scene: Node) -> CanvasLayer:
	var pause_menu := scene.get_node_or_null("PauseMenu") as CanvasLayer
	if pause_menu == null:
		_fail("PauseMenu not found in scenes/main.tscn (or is not a CanvasLayer)")
		return null

	# A script that failed to compile is silently dropped from its node, leaving
	# a bare CanvasLayer that loads cleanly and does nothing.
	if pause_menu.get_script() == null:
		_fail("PauseMenu has no script attached; scripts/pause_menu.gd failed to compile")
		return null

	_pass("main scene carries the pause overlay")

	if pause_menu.layer <= _HUD_LAYER:
		_fail(
			(
				"pause overlay layer %d must exceed the combat HUD's %d to cover it"
				% [pause_menu.layer, _HUD_LAYER]
			)
		)
	else:
		_pass("pause overlay draws above the combat HUD")

	# Without PROCESS_MODE_ALWAYS the overlay stops receiving _input() the moment
	# it pauses the tree: Escape would open it and never close it again.
	if pause_menu.process_mode != Node.PROCESS_MODE_ALWAYS:
		_fail(
			(
				"pause overlay process_mode should be PROCESS_MODE_ALWAYS (%d), got %d"
				% [Node.PROCESS_MODE_ALWAYS, pause_menu.process_mode]
			)
		)
		return null

	_pass("pause overlay processes while paused")
	return pause_menu


## The pause action pauses the tree and shows the overlay.
func _test_pause_opens(pause_menu: CanvasLayer) -> void:
	if paused:
		_fail("tree should not start paused")
		return
	if pause_menu.visible:
		_fail("pause overlay should start hidden")
		return

	# parse_input_event() only queues the event; Godot accumulates input and
	# delivers it on its own schedule, so without the explicit flush the
	# awaited frame can come and go before _input() ever sees it.
	var pause_event := InputEventAction.new()
	pause_event.action = "pause"
	pause_event.pressed = true
	Input.parse_input_event(pause_event)
	Input.flush_buffered_events()
	await process_frame

	if not paused:
		_fail("the pause action should pause the tree")
		return
	if not pause_menu.visible:
		_fail("the pause action should show the overlay")
		return

	_pass("pause action opens the overlay")
	await _test_resume(pause_menu)


## Resume unpauses the tree and hides the overlay again.
func _test_resume(pause_menu: CanvasLayer) -> void:
	var resume_button := (
		pause_menu.get_node_or_null(^"Overlay/Center/Panel/Margin/Buttons/ResumeButton") as Button
	)
	if resume_button == null:
		_fail("Resume button not found in the pause overlay")
		return

	resume_button.pressed.emit()
	await process_frame

	if paused:
		_fail("Resume should unpause the tree")
		return
	if pause_menu.visible:
		_fail("Resume should hide the overlay")
		return

	_pass("resume unpauses and hides the overlay")


## The SessionManager autoload. Autoloads are instantiated under --script too,
## and it is this node -- not a locally constructed one -- that the menus and
## WorldManager read, so a second instance would be renamed and ignored.
func _session() -> Node:
	return root.get_node_or_null(^"/root/SessionManager")


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
		print("\nAll %d menu and pause checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
