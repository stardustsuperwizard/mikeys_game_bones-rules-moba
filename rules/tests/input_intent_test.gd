## Test suite for the device-agnostic input intent layer (ruleset §5.4).
##
## Covers the intent vocabulary, the router's action-to-intent translation, the
## ability gesture lifecycle, scheme hot-swap and its hysteresis, and the
## isolation rule that keeps device reads confined to two files.
##
## Runs headless with no device attached. The router reads through an injectable
## strength source and the scheme tracker accepts events directly, so this file
## drives both with synthetic values -- which it must, because the same
## isolation rule it enforces below forbids this file from reading the device
## singleton itself.
class_name InputIntentTest

const MobaLoadout = preload("res://rules/abilities/moba_loadout.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaAbilityCaster = preload("res://rules/abilities/moba_ability_caster.gd")
const MobaCastContext = preload("res://rules/abilities/moba_cast_context.gd")
const MobaAbilityLibrary = preload("res://rules/abilities/moba_ability_library.gd")
const MobaStateMachine = preload("res://rules/state/moba_state_machine.gd")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

## self_ability.tres is self-targeting, so activate_slot() can succeed without
## an explicit target -- the same fixture loadout_test.gd uses for this.
const _SELF_ABILITY_FILE: String = "self_ability.tres"
const _SELF_ABILITY_ID: StringName = &"self_ability"

## The two files permitted to read the device singletons.
const _DEVICE_READERS: Array[String] = [
	"res://rules/input/moba_input_router.gd",
	"res://rules/input/moba_input_scheme.gd",
]


static func run() -> bool:
	var results: Array[bool] = []

	results.append(_test_intents_are_refcounted_not_resource())
	results.append(_test_intent_fields_and_phases())
	results.append(_test_router_translates_movement())
	results.append(_test_move_intent_invariant_holds())
	results.append(_test_router_translates_digital_actions())
	results.append(_test_router_ignores_non_combat_actions())
	results.append(_test_ability_gesture_sequences_press_aim_release())
	results.append(_test_scheme_hot_swaps_exactly_once())
	results.append(_test_scheme_does_not_storm_on_alternating_input())
	results.append(_test_scheme_threshold_exceeds_movement_deadzone())
	results.append(_test_synthetic_ability_intent_drives_caster())
	results.append(_test_device_reads_confined_to_two_files())

	return results.all(func(result: bool) -> bool: return result)


## Build a router whose input comes from a dictionary instead of a device.
static func _router_reading(strengths: Dictionary) -> MobaInputRouter:
	var router := MobaInputRouter.new()
	router.action_strength_source = func(action: StringName) -> float:
		return float(strengths.get(action, 0.0))
	return router


## Poll the router once and return everything it emitted.
static func _poll(router: MobaInputRouter) -> Array:
	var captured: Array = []
	var sink := func(intent: RefCounted) -> void: captured.append(intent)
	router.intent_emitted.connect(sink)
	router.poll()
	router.intent_emitted.disconnect(sink)
	return captured


## Intents are transient and per-frame, so they must never be Resource.
static func _test_intents_are_refcounted_not_resource() -> bool:
	var samples := {
		"MoveIntent": MobaIntent.MoveIntent.new(),
		"AimIntent": MobaIntent.AimIntent.new(),
		"JumpIntent": MobaIntent.JumpIntent.new(),
		"BasicAttackIntent": MobaIntent.BasicAttackIntent.new(),
		"AbilityIntent": MobaIntent.AbilityIntent.new(),
		"LockOnIntent": MobaIntent.LockOnIntent.new(),
		"UtilityIntent": MobaIntent.UtilityIntent.new(),
	}

	for type_name in samples:
		var intent = samples[type_name]
		if not (intent is RefCounted):
			print("ERROR: %s is not RefCounted" % type_name)
			return false
		if intent is Resource:
			print("ERROR: %s extends Resource; intents must be RefCounted" % type_name)
			return false

	return true


## Every intent carries the fields and phase values §5.4 specifies.
static func _test_intent_fields_and_phases() -> bool:
	var aim := MobaIntent.AimIntent.new()
	aim.direction = Vector3(0.0, 0.0, -1.0)
	aim.point = Vector3(4.0, 0.0, 2.0)
	aim.mode = MobaIntent.AimIntent.Mode.POINT
	if aim.mode != MobaIntent.AimIntent.Mode.POINT:
		print("ERROR: AimIntent.mode did not retain POINT")
		return false
	if not aim.point.is_equal_approx(Vector3(4.0, 0.0, 2.0)):
		print("ERROR: AimIntent.point did not retain its value")
		return false

	var attack := MobaIntent.BasicAttackIntent.new()
	attack.held = true
	if not attack.held:
		print("ERROR: BasicAttackIntent.held did not retain true")
		return false

	var utility := MobaIntent.UtilityIntent.new()
	utility.id = &"defend"
	if utility.id != &"defend":
		print("ERROR: UtilityIntent.id did not retain defend")
		return false

	# All four ability phases must exist and be distinct.
	var ability_phases := [
		MobaIntent.AbilityIntent.Phase.PRESS,
		MobaIntent.AbilityIntent.Phase.AIM,
		MobaIntent.AbilityIntent.Phase.RELEASE,
		MobaIntent.AbilityIntent.Phase.CANCEL,
	]
	if ability_phases.size() != _distinct_count(ability_phases):
		print("ERROR: AbilityIntent.Phase values are not distinct")
		return false

	# All three lock-on phases must exist and be distinct, CYCLE included even
	# though nothing produces it yet.
	var lock_phases := [
		MobaIntent.LockOnIntent.Phase.PRESS,
		MobaIntent.LockOnIntent.Phase.RELEASE,
		MobaIntent.LockOnIntent.Phase.CYCLE,
	]
	if lock_phases.size() != _distinct_count(lock_phases):
		print("ERROR: LockOnIntent.Phase values are not distinct")
		return false

	return true


static func _distinct_count(values: Array) -> int:
	var seen := {}
	for value in values:
		seen[value] = true
	return seen.size()


## Each movement row of the §5.4 mapping table produces a MoveIntent whose
## fields match the action driving it.
static func _test_router_translates_movement() -> bool:
	var cases := [
		{"action": &"move_forward", "direction": Vector3(0.0, 0.0, -1.0), "turn": 0.0},
		{"action": &"move_back", "direction": Vector3(0.0, 0.0, 1.0), "turn": 0.0},
		{"action": &"strafe_left", "direction": Vector3(-1.0, 0.0, 0.0), "turn": 0.0},
		{"action": &"strafe_right", "direction": Vector3(1.0, 0.0, 0.0), "turn": 0.0},
		{"action": &"turn_left", "direction": Vector3.ZERO, "turn": -1.0},
		{"action": &"turn_right", "direction": Vector3.ZERO, "turn": 1.0},
	]

	for expected in cases:
		var router := _router_reading({expected["action"]: 1.0})
		var passed := _check_movement_case(router, expected)
		router.free()
		if not passed:
			return false

	return true


static func _check_movement_case(router: MobaInputRouter, expected: Dictionary) -> bool:
	var action = expected["action"]
	var emitted := _poll(router)

	if emitted.size() != 1:
		print("ERROR: %s produced %d intents, expected 1" % [action, emitted.size()])
		return false
	if not (emitted[0] is MobaIntent.MoveIntent):
		print("ERROR: %s did not produce a MoveIntent" % action)
		return false
	if not emitted[0].direction.is_equal_approx(expected["direction"]):
		print(
			(
				"ERROR: %s direction was %s, expected %s"
				% [action, emitted[0].direction, expected["direction"]]
			)
		)
		return false
	if not is_equal_approx(emitted[0].turn, expected["turn"]):
		print("ERROR: %s turn was %f, expected %f" % [action, emitted[0].turn, expected["turn"]])
		return false

	return true


## Translating and turning at once emits two intents, never one carrying both:
## exactly one of direction or turn is non-zero per emission.
static func _test_move_intent_invariant_holds() -> bool:
	var router := _router_reading({&"move_forward": 1.0, &"turn_right": 1.0})
	var emitted := _poll(router)
	router.free()

	if emitted.size() != 2:
		print("ERROR: moving and turning together produced %d intents, expected 2" % emitted.size())
		return false

	for intent in emitted:
		var translating: bool = not intent.direction.is_zero_approx()
		var turning: bool = not is_zero_approx(intent.turn)
		if translating == turning:
			print(
				(
					"ERROR: MoveIntent broke its invariant (direction=%s turn=%f)"
					% [intent.direction, intent.turn]
				)
			)
			return false

	return true


## Jump, basic attack, abilities, lock-on and defend each translate to their
## §5.4 intent with the right fields.
static func _test_router_translates_digital_actions() -> bool:
	return (
		_check_jump()
		and _check_defend()
		and _check_basic_attack_hold_and_release()
		and _check_lock_on_press_and_release()
		and _check_ability_slots()
	)


static func _check_jump() -> bool:
	var router := _router_reading({&"jump": 1.0})
	var emitted := _poll(router)
	router.free()

	if emitted.size() != 1 or not (emitted[0] is MobaIntent.JumpIntent):
		print("ERROR: jump did not produce a JumpIntent")
		return false
	return true


static func _check_defend() -> bool:
	var router := _router_reading({&"defend": 1.0})
	var emitted := _poll(router)
	router.free()

	if emitted.size() != 1 or not (emitted[0] is MobaIntent.UtilityIntent):
		print("ERROR: defend did not produce a UtilityIntent")
		return false
	if emitted[0].id != &"defend":
		print("ERROR: defend UtilityIntent carried id %s" % emitted[0].id)
		return false
	return true


## Basic attack reports held on the way down and not-held on the way up.
static func _check_basic_attack_hold_and_release() -> bool:
	var state := {&"basic_attack": 1.0}
	var router := _router_reading(state)

	var pressed := _poll(router)
	state[&"basic_attack"] = 0.0
	var released := _poll(router)
	router.free()

	if pressed.size() != 1 or not (pressed[0] is MobaIntent.BasicAttackIntent):
		print("ERROR: basic_attack press did not produce a BasicAttackIntent")
		return false
	if not pressed[0].held:
		print("ERROR: basic_attack press reported held=false")
		return false
	if released.size() != 1 or not (released[0] is MobaIntent.BasicAttackIntent):
		print("ERROR: basic_attack release did not produce a BasicAttackIntent")
		return false
	if released[0].held:
		print("ERROR: basic_attack release reported held=true")
		return false
	return true


## Lock-on produces PRESS then RELEASE. CYCLE stays unproducible.
static func _check_lock_on_press_and_release() -> bool:
	var state := {&"lock_on": 1.0}
	var router := _router_reading(state)

	var pressed := _poll(router)
	state[&"lock_on"] = 0.0
	var released := _poll(router)
	router.free()

	if pressed.size() != 1 or not (pressed[0] is MobaIntent.LockOnIntent):
		print("ERROR: lock_on press did not produce a LockOnIntent")
		return false
	if pressed[0].phase != MobaIntent.LockOnIntent.Phase.PRESS:
		print("ERROR: lock_on press was not phase PRESS")
		return false
	if released.size() != 1 or released[0].phase != MobaIntent.LockOnIntent.Phase.RELEASE:
		print("ERROR: lock_on release was not phase RELEASE")
		return false
	return true


## Each of the four ability rows carries its own slot number.
static func _check_ability_slots() -> bool:
	for slot in range(1, 5):
		var action := StringName("ability_%d" % slot)
		var router := _router_reading({action: 1.0})
		var emitted := _poll(router)
		router.free()

		if emitted.size() != 1 or not (emitted[0] is MobaIntent.AbilityIntent):
			print("ERROR: %s did not produce an AbilityIntent" % action)
			return false
		if emitted[0].slot != slot:
			print("ERROR: %s reported slot %d" % [action, emitted[0].slot])
			return false
		if emitted[0].phase != MobaIntent.AbilityIntent.Phase.PRESS:
			print("ERROR: %s did not open on PRESS" % action)
			return false

	return true


## action_primary is a mouse convenience and camera_recenter is camera, not
## combat. §5.4's mapping table lists both as non-combat, so the router emits
## nothing for either.
static func _test_router_ignores_non_combat_actions() -> bool:
	for action in [&"action_primary", &"camera_recenter"]:
		var router := _router_reading({action: 1.0})
		var emitted := _poll(router)
		router.free()

		if not emitted.is_empty():
			print("ERROR: %s produced %d intents, expected none" % [action, emitted.size()])
			return false

	return true


## A held ability gesture runs PRESS, then AIM every poll while held, then
## RELEASE. AIM repeating is the point: drag-to-aim and stick-aim both need it.
static func _test_ability_gesture_sequences_press_aim_release() -> bool:
	var state := {&"ability_1": 1.0}
	var router := _router_reading(state)

	var phases: Array = []
	var slots: Array = []

	# Press, then two further polls while still held, then release, then idle.
	for poll_index in range(3):
		_record_phases(_poll(router), phases, slots)
	state[&"ability_1"] = 0.0
	_record_phases(_poll(router), phases, slots)
	var after_release := _poll(router)
	router.free()

	var expected := [
		MobaIntent.AbilityIntent.Phase.PRESS,
		MobaIntent.AbilityIntent.Phase.AIM,
		MobaIntent.AbilityIntent.Phase.AIM,
		MobaIntent.AbilityIntent.Phase.RELEASE,
	]
	if phases != expected:
		print("ERROR: held gesture ran phases %s, expected PRESS, AIM, AIM, RELEASE" % [phases])
		return false

	for slot in slots:
		if slot != 1:
			print("ERROR: a phase of the gesture reported slot %d, expected 1" % slot)
			return false

	if not after_release.is_empty():
		print("ERROR: gesture kept emitting after RELEASE")
		return false

	return true


static func _record_phases(emitted: Array, phases: Array, slots: Array) -> void:
	for intent in emitted:
		if intent is MobaIntent.AbilityIntent:
			phases.append(intent.phase)
			slots.append(intent.slot)


## Count scheme_changed emissions while feeding a scheme tracker events.
static func _count_scheme_changes(scheme: MobaInputScheme, events: Array) -> int:
	var changes: Array = []
	scheme.scheme_changed.connect(func(value) -> void: changes.append(value))
	for event in events:
		scheme.note_event(event)
	return changes.size()


static func _joypad_button() -> InputEventJoypadButton:
	return InputEventJoypadButton.new()


static func _keyboard_key() -> InputEventKey:
	return InputEventKey.new()


## §5.4: receiving gamepad input while keyboard is active switches immediately,
## with no restart. It fires once for that change, not once per event.
static func _test_scheme_hot_swaps_exactly_once() -> bool:
	var scheme := MobaInputScheme.new()
	var started_on_keyboard := scheme.get_scheme() == MobaInputScheme.Scheme.KEYBOARD_MOUSE

	# Two gamepad events, one device change: the signal reports the change, not
	# each event.
	var changes := _count_scheme_changes(scheme, [_joypad_button(), _joypad_button()])
	var ended_on_gamepad := scheme.get_scheme() == MobaInputScheme.Scheme.GAMEPAD
	scheme.free()

	if not started_on_keyboard:
		print("ERROR: scheme did not start on KEYBOARD_MOUSE")
		return false
	if changes != 1:
		print("ERROR: gamepad input fired scheme_changed %d times, expected 1" % changes)
		return false
	if not ended_on_gamepad:
		print("ERROR: scheme did not hot-swap to GAMEPAD")
		return false

	return true


## Input alternating between two devices must not re-fire scheme_changed every
## frame. The hysteresis window exists so a consumer redrawing prompts on the
## signal does not thrash.
static func _test_scheme_does_not_storm_on_alternating_input() -> bool:
	var scheme := MobaInputScheme.new()

	var alternating: Array = []
	for index in range(12):
		alternating.append(_joypad_button() if index % 2 == 0 else _keyboard_key())

	var changes := _count_scheme_changes(scheme, alternating)
	scheme.free()

	if changes > 1:
		print("ERROR: alternating device input fired scheme_changed %d times" % changes)
		return false

	return true


## The scheme-change threshold is a named constant, distinct from and greater
## than the 0.2 movement deadzone: stick motion between the two must move the
## deadzone's needle but not swap the scheme.
static func _test_scheme_threshold_exceeds_movement_deadzone() -> bool:
	var scheme := MobaInputScheme.new()

	if scheme.scheme_change_threshold <= MobaInputScheme.MOVEMENT_DEADZONE:
		print(
			(
				"ERROR: scheme_change_threshold (%f) must exceed the movement deadzone (%f)"
				% [scheme.scheme_change_threshold, MobaInputScheme.MOVEMENT_DEADZONE]
			)
		)
		scheme.free()
		return false

	# Motion above the deadzone but below the threshold must not swap schemes:
	# a resting stick drifting past the deadzone cannot steal the scheme from a
	# keyboard still in use.
	var between := (
		MobaInputScheme.MOVEMENT_DEADZONE
		+ (scheme.scheme_change_threshold - MobaInputScheme.MOVEMENT_DEADZONE) * 0.5
	)
	var weak := InputEventJoypadMotion.new()
	weak.axis_value = between
	var weak_changes := _count_scheme_changes(scheme, [weak])

	# Motion clearly above the threshold swaps immediately.
	var strong := InputEventJoypadMotion.new()
	strong.axis_value = 1.0
	var strong_changes := _count_scheme_changes(scheme, [strong])
	scheme.free()

	if weak_changes != 0:
		print("ERROR: stick motion at %f (below the threshold) swapped the scheme" % between)
		return false
	if strong_changes != 1:
		print("ERROR: stick motion above the threshold did not swap the scheme")
		return false

	return true


## An AbilityIntent built by hand -- no device, no router -- drives the ability
## system, which is what makes the Python balance harness able to consume
## intents directly.
static func _test_synthetic_ability_intent_drives_caster() -> bool:
	MobaAbilityLibrary._reset()
	MobaAbilityLibrary._load_single_ability(
		"res://rules/tests/fixtures/abilities/".path_join(_SELF_ABILITY_FILE)
	)

	var intent := MobaIntent.AbilityIntent.new()
	intent.slot = 1
	intent.phase = MobaIntent.AbilityIntent.Phase.PRESS

	var actor := Actor.new()
	actor.owner_id = 1

	var combatant := MobaCombatant.new()
	combatant.name = "MobaCombatant"
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = _BASELINE_STAT_BLOCK.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)

	var loadout := MobaLoadout.new()
	loadout.set_action_slot(intent.slot, String(_SELF_ABILITY_ID))
	combatant.loadout = loadout
	actor.add_child(combatant)

	var state_machine := MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	var caster := MobaAbilityCaster.new()
	var context := MobaCastContext.new(actor, null)
	var result := caster.activate_slot(intent.slot, context)

	var succeeded: bool = result.success
	if not succeeded:
		print("ERROR: synthetic AbilityIntent failed to drive activate_slot: %s" % result.reason)

	caster.free()
	actor.free()
	MobaAbilityLibrary._reset()

	return succeeded


## Only the router and the scheme tracker may read the device singletons.
##
## Confining those reads is what keeps the rest of the rules device-agnostic,
## so it is checked automatically rather than left to review.
static func _test_device_reads_confined_to_two_files() -> bool:
	var pattern := RegEx.new()
	# Matches a read of either singleton, e.g. the get_action_strength call in
	# the router, without matching InputEvent* classes or Moba*Input* names.
	if pattern.compile("\\b(Input|InputMap)\\.") != OK:
		print("ERROR: could not compile the device-read pattern")
		return false

	var offenders: Array[String] = []
	for path in _gdscript_files_under("res://rules"):
		if path in _DEVICE_READERS:
			continue
		var source := FileAccess.get_file_as_string(path)
		if source.is_empty():
			continue
		if pattern.search(source) != null:
			offenders.append(path)

	if not offenders.is_empty():
		print("ERROR: files under rules/ read a device singleton but are not permitted to:")
		for path in offenders:
			print("  " + path)
		return false

	return true


static func _gdscript_files_under(root: String) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = [root]

	while not pending.is_empty():
		var directory: String = pending.pop_back()
		var handle := DirAccess.open(directory)
		if handle == null:
			continue

		handle.list_dir_begin()
		var entry := handle.get_next()
		while entry != "":
			if not entry.begins_with("."):
				var full := directory.path_join(entry)
				if handle.current_is_dir():
					pending.append(full)
				elif entry.ends_with(".gd"):
					found.append(full)
			entry = handle.get_next()
		handle.list_dir_end()

	return found
