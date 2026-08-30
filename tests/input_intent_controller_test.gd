# Headless integration test for PlayerController3D's consumption of input intents.
#
# Run with:
#   godot --headless --path . --script tests/input_intent_controller_test.gd
#
# Loads the real main scene and drives the real MobaInputRouter on the player,
# testing that ability and jump activation arrive as intents rather than as
# direct Input action reads. Exits non-zero on the first failed expectation.
#
# Covers, in order:
#   - the router and scheme nodes exist on the player and the controller is
#     connected to the router's intent_emitted signal;
#   - MobaInputScheme's scheme_changed is reachable through the controller;
#   - AbilityIntent phases other than PRESS activate nothing;
#   - an ability_1 press driven through the router activates slot 1;
#   - a jump press driven through the router raises exactly one jump request,
#     and holding jump does not raise a second.
#
# The router is driven through its action_strength_source injection point rather
# than through Input, which is what lets a headless run with no device attached
# step a press and a hold deterministically.
#
# This test is NOT wired into tests/test_bootstrap.gd; it is a manual integration
# check matching tests/mouse_action_test.gd's own precedent.
extends SceneTree

## Slot 1 of the player's melee_bruiser loadout. Registered on activation, so a
## non-zero cooldown on it is the observable that slot 1 actually fired.
const _SLOT_1_ABILITY: StringName = &"power_strike"

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame

	var player := scene.get_node_or_null("WorldManager/Player") as Actor
	if player == null:
		_fail("setup: player not found")
		return _finish()

	var controller := player.controller as PlayerController3D
	var router := player.get_node_or_null("MobaInputRouter") as MobaInputRouter
	var scheme := player.get_node_or_null("MobaInputScheme") as MobaInputScheme
	var combatant := player.get_node_or_null("MobaCombatant") as MobaCombatant
	var state_machine := player.get_node_or_null("MobaStateMachine") as MobaStateMachine
	if state_machine == null:
		_fail("setup: state machine not found")
		return _finish()
	if controller == null or router == null or scheme == null or combatant == null:
		_fail(
			(
				"setup: controller=%s router=%s scheme=%s combatant=%s"
				% [controller, router, scheme, combatant]
			)
		)
		return _finish()
	print("PASS player carries a MobaInputRouter and a MobaInputScheme")

	# --- the controller listens to the router ---------------------------
	if not router.intent_emitted.is_connected(controller._on_intent_emitted):
		_fail("wiring: controller is not connected to the router's intent_emitted signal")
	else:
		print("PASS controller is connected to intent_emitted")

	# --- the scheme is reachable for future prompt work -----------------
	if controller.get_input_scheme() != scheme:
		_fail(
			(
				"scheme: get_input_scheme() returned %s, expected the scene's MobaInputScheme"
				% controller.get_input_scheme()
			)
		)
	elif not controller.get_input_scheme().has_signal("scheme_changed"):
		_fail("scheme: scheme_changed is not reachable through get_input_scheme()")
	else:
		print("PASS scheme_changed is reachable through get_input_scheme()")

	# --- let the player land --------------------------------------------
	# The player spawns above the ground and falls. Casting before it lands fails
	# illegal_state, which would look like a wiring failure and is not one, so
	# wait for the landing rather than for a fixed number of frames. The state
	# machine reads IDLE while the fall is still in progress, so the floor
	# contact is what is waited on here, not the state alone.
	var body := player.get_node("Body") as CharacterBody3D
	var landed := false
	for _frame in 240:
		await physics_frame
		if body.is_on_floor() and state_machine.current_state == MobaState.IDLE:
			landed = true
			break
	if not landed:
		_fail(
			(
				"setup: player never settled (on_floor=%s state=%s), so slot 1 cannot be judged"
				% [body.is_on_floor(), MobaState.state_to_string(state_machine.current_state)]
			)
		)
		return _finish()

	# --- a target, so slot 1 is judged on range rather than invalid_target
	# power_strike is TARGETED with range 2.0. _ability_target() resolves it from
	# the click-order system's attack target, which is set directly here: this
	# test is about where ability input arrives from, not about click orders,
	# which tests/mouse_action_test.gd already covers.
	var dummy := _make_dummy(scene, body.global_position + Vector3(0, 0, 1.0))
	await physics_frame

	# Everything from here to the slot-1 assertion runs inside one frame, with no
	# await between. A target this close is inside basic-attack range, so letting
	# a physics frame run would fire the proximity auto-attack and leave the
	# player in BASIC_ATTACK_WINDUP, where an ability is illegal -- a real rule,
	# but not the one under test.
	controller._attack_target = dummy
	if state_machine.current_state != MobaState.IDLE:
		_fail(
			(
				"ability: player left IDLE (state %s) before the press, so slot 1 cannot be judged"
				% MobaState.state_to_string(state_machine.current_state)
			)
		)
		return _finish()

	# --- phases other than PRESS activate nothing -----------------------
	# The task deliberately handles PRESS only: no ability in the current loadout
	# data resolves on release, so every other phase must be inert.
	for phase in [
		MobaIntent.AbilityIntent.Phase.AIM,
		MobaIntent.AbilityIntent.Phase.RELEASE,
		MobaIntent.AbilityIntent.Phase.CANCEL,
	]:
		var ignored := MobaIntent.AbilityIntent.new()
		ignored.slot = 1
		ignored.phase = phase
		router.intent_emitted.emit(ignored)

	if combatant.get_cooldown_remaining(_SLOT_1_ABILITY) > 0.0:
		_fail("phases: an AbilityIntent phase other than PRESS activated slot 1")
	else:
		print("PASS AbilityIntent AIM, RELEASE and CANCEL activate nothing")

	# --- an ability_1 press through the router fires slot 1 -------------
	router.action_strength_source = func(action: StringName) -> float:
		return 1.0 if action == &"ability_1" else 0.0
	router.poll()

	var slot_1_cooldown := combatant.get_cooldown_remaining(_SLOT_1_ABILITY)
	if slot_1_cooldown <= 0.0:
		_fail("ability: an ability_1 press through the router did not activate slot 1")
	else:
		print(
			"PASS ability_1 press through the router activated slot 1 (cd %.1fs)" % slot_1_cooldown
		)

	# --- a jump press through the router raises one request -------------
	# Read the request in the same frame the press is polled in. ActorBody3D
	# calls consume_jump() every physics frame, so awaiting one here would drain
	# the request before the assertion and report a working wiring as broken.
	controller.consume_jump()  # drain anything the frames above buffered

	router.action_strength_source = func(action: StringName) -> float:
		return 1.0 if action == &"jump" else 0.0
	router.poll()

	if not controller.consume_jump():
		_fail("jump: a jump press through the router raised no jump request")
	elif controller.consume_jump():
		_fail("jump: the jump request was not consumed by the first read")
	else:
		print("PASS jump press through the router raised exactly one jump request")

	# Holding jump is Edge.HELD, which emits no further JumpIntent -- a held key
	# must not machine-gun the jump request.
	router.poll()
	if controller.consume_jump():
		_fail("jump: holding jump raised a second jump request")
	else:
		print("PASS holding jump raises no further jump request")

	dummy.queue_free()
	_finish()


func _make_dummy(parent: Node, position: Vector3) -> Actor:
	var dummy := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Actor
	dummy.name = "AbilityDummy"
	dummy.hostile = true
	dummy.get_node("Controller").free()  # inert target: no controller, no decisions
	(dummy.get_node("Body") as Node3D).position = position
	parent.add_child(dummy)
	return dummy


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nALL INPUT INTENT CONTROLLER CHECKS PASSED")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL " + f)
		quit(1)
