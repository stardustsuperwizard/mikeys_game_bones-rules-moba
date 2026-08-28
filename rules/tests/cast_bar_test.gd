## Test suite for the standalone MobaCastBar control.
##
## Covers that the bar shows ability name and progress during casting and
## channeling, that it clears immediately on all three exit paths (completion,
## cancellation, and hard crowd control break), and that rebinding to a
## different combatant or null leaves no stale visible state.
class_name CastBarTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const MobaAbility = preload("res://rules/abilities/moba_ability.gd")
const MobaLoadout = preload("res://rules/abilities/moba_loadout.gd")
const CAST_BAR_SCENE = preload("res://rules/ui/moba_cast_bar.tscn")


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_cast_shows_name_and_progress())
	all_violations.append_array(_test_channel_shows_name_and_progress())
	all_violations.append_array(_test_clears_on_cast_completion())
	all_violations.append_array(_test_clears_on_channel_completion())
	all_violations.append_array(_test_clears_on_cast_cancellation())
	all_violations.append_array(_test_clears_on_channel_break())
	all_violations.append_array(_test_clears_on_cast_hard_cc_interrupt())
	all_violations.append_array(_test_rebind_has_no_stale_state())

	if all_violations.is_empty():
		return true

	printerr("\n=== Cast Bar Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


static func _make_ability(
	id: String, cast_time: float = 0.0, channel_time: float = 0.0
) -> MobaAbility:
	var ability = MobaAbility.new()
	ability.id = id
	ability.name = "Test " + id
	ability.resource_cost = 10.0
	ability.cooldown = 0.0
	ability.charges = 1
	ability.cast_time = cast_time
	ability.channel_duration = channel_time
	return ability


static func _make_combatant() -> MobaCombatant:
	var combatant = MobaCombatant.new()
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	combatant._current_resource = combatant._runtime_stat_block.get_stat_value(
		MobaStatBlock.RESOURCE
	)

	var loadout = MobaLoadout.new()
	for index in range(1, 5):
		loadout.set_action_slot(index, "slot_%d" % index)
	combatant.loadout = loadout

	for index in range(1, 5):
		combatant.register_ability(_make_ability("slot_%d" % index))

	return combatant


## Build a combatant parented under an Actor with a real MobaStateMachine, the
## same shape crowd_control_test.gd uses. The hard-CC interrupt seam reads
## get_state_machine().current_state, so a bare combatant would never break its
## own channel and the exit path would go untested.
static func _make_combatant_with_state_machine() -> Dictionary:
	var actor := Actor.new()
	actor.owner_id = 1

	var combatant := _make_combatant()
	combatant.name = "MobaCombatant"
	actor.add_child(combatant)

	var state_machine := MobaStateMachine.new()
	state_machine.name = "MobaStateMachine"
	state_machine._load_state_table()
	actor.add_child(state_machine)

	return {"actor": actor, "combatant": combatant, "state_machine": state_machine}


static func _test_cast_shows_name_and_progress() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	combatant.register_ability(_make_ability("cast_ability", 2.0))

	var bar: MobaCastBar = CAST_BAR_SCENE.instantiate()
	bar.bind(combatant)

	# Initially not casting, bar should be hidden
	if bar.visible:
		violations.append("cast_progress: bar should be hidden when not casting")

	# Start a cast
	combatant.start_cast(&"cast_ability", combatant.get_ability(&"cast_ability"), [], 2.0)
	bar.refresh()

	# Bar should be visible
	if not bar.visible:
		violations.append("cast_progress: bar should be visible during cast")

	# Check name
	var name_label: Label = bar.get_node("VBox/NameLabel")
	if name_label.text != "Test cast_ability":
		violations.append(
			"cast_progress: name should show ability name, got '%s'" % name_label.text
		)

	# Check progress
	var progress_bar: TextureProgressBar = bar.get_node("VBox/ProgressBar")
	# The fill advances from empty to full, so it reads 0.0 at the start.
	var initial_progress: float = progress_bar.value
	if not is_equal_approx(initial_progress, 0.0):
		violations.append(
			"cast_progress: progress should be empty at cast start, got %f" % initial_progress
		)

	# Advance time and check progress increases
	combatant.tick(1.0)
	bar.refresh()
	var after_tick_progress: float = progress_bar.value
	if after_tick_progress <= initial_progress:
		violations.append("cast_progress: progress should increase as time elapses")
	if not is_equal_approx(after_tick_progress, 0.5):
		violations.append(
			(
				"cast_progress: halfway through a 2.0s cast the fill should read 0.5, got %f"
				% after_tick_progress
			)
		)

	bar.free()
	combatant.free()
	return violations


static func _test_channel_shows_name_and_progress() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	combatant.register_ability(_make_ability("channel_ability", 0.0, 2.0))

	var bar: MobaCastBar = CAST_BAR_SCENE.instantiate()
	bar.bind(combatant)

	# Initially not channeling, bar should be hidden
	if bar.visible:
		violations.append("channel_progress: bar should be hidden when not channeling")

	# Start a channel
	combatant.start_channel(&"channel_ability", combatant.get_ability(&"channel_ability"), [], 2.0)
	bar.refresh()

	# Bar should be visible
	if not bar.visible:
		violations.append("channel_progress: bar should be visible during channel")

	# Check name
	var name_label: Label = bar.get_node("VBox/NameLabel")
	if name_label.text != "Test channel_ability":
		violations.append(
			"channel_progress: name should show ability name, got '%s'" % name_label.text
		)

	# Check progress
	var progress_bar: TextureProgressBar = bar.get_node("VBox/ProgressBar")
	# The fill advances from empty to full, so it reads 0.0 at the start.
	var initial_progress: float = progress_bar.value
	if not is_equal_approx(initial_progress, 0.0):
		violations.append(
			"channel_progress: progress should be empty at channel start, got %f" % initial_progress
		)

	# Advance time and check progress increases
	combatant.tick(1.0)
	bar.refresh()
	var after_tick_progress: float = progress_bar.value
	if after_tick_progress <= initial_progress:
		violations.append("channel_progress: progress should increase as time elapses")
	if not is_equal_approx(after_tick_progress, 0.5):
		violations.append(
			(
				"channel_progress: halfway through a 2.0s channel the fill should read 0.5, got %f"
				% after_tick_progress
			)
		)

	bar.free()
	combatant.free()
	return violations


static func _test_clears_on_cast_completion() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	combatant.register_ability(_make_ability("cast_ability", 0.5))

	var bar: MobaCastBar = CAST_BAR_SCENE.instantiate()
	bar.bind(combatant)

	# Start a cast
	combatant.start_cast(&"cast_ability", combatant.get_ability(&"cast_ability"), [], 0.5)
	bar.refresh()

	if not bar.visible:
		violations.append("cast_completion: bar should be visible during cast")

	# Advance time until cast completes (more than cast_time)
	combatant.tick(0.6)
	bar.refresh()

	# Bar should be hidden after completion
	if bar.visible:
		violations.append("cast_completion: bar should be hidden after cast completes")

	var name_label: Label = bar.get_node("VBox/NameLabel")
	if name_label.text != "":
		violations.append("cast_completion: name should be cleared after completion")

	bar.free()
	combatant.free()
	return violations


static func _test_clears_on_channel_completion() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	combatant.register_ability(_make_ability("channel_ability", 0.0, 0.5))

	var bar: MobaCastBar = CAST_BAR_SCENE.instantiate()
	bar.bind(combatant)

	# Start a channel
	combatant.start_channel(&"channel_ability", combatant.get_ability(&"channel_ability"), [], 0.5)
	bar.refresh()

	if not bar.visible:
		violations.append("channel_completion: bar should be visible during channel")

	# Advance time until the channel naturally expires (more than channel_time)
	combatant.tick(0.6)
	bar.refresh()

	if combatant.is_channeling():
		violations.append("channel_completion: channel should have expired")

	# Bar should be hidden after completion
	if bar.visible:
		violations.append("channel_completion: bar should be hidden after channel completes")

	var name_label: Label = bar.get_node("VBox/NameLabel")
	if name_label.text != "":
		violations.append("channel_completion: name should be cleared after completion")

	bar.free()
	combatant.free()
	return violations


static func _test_clears_on_cast_cancellation() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	combatant.register_ability(_make_ability("cast_ability", 2.0))

	var bar: MobaCastBar = CAST_BAR_SCENE.instantiate()
	bar.bind(combatant)

	# Start a cast
	combatant.start_cast(&"cast_ability", combatant.get_ability(&"cast_ability"), [], 2.0)
	bar.refresh()

	if not bar.visible:
		violations.append("cast_cancellation: bar should be visible during cast")

	# Cancel the cast
	combatant.cancel_cast()
	bar.refresh()

	# Bar should be hidden after cancellation
	if bar.visible:
		violations.append("cast_cancellation: bar should be hidden after cancel_cast()")

	var name_label: Label = bar.get_node("VBox/NameLabel")
	if name_label.text != "":
		violations.append("cast_cancellation: name should be cleared after cancellation")

	bar.free()
	combatant.free()
	return violations


static func _test_clears_on_channel_break() -> Array[String]:
	var violations: Array[String] = []

	var data := _make_combatant_with_state_machine()
	var actor: Actor = data["actor"]
	var combatant: MobaCombatant = data["combatant"]
	var state_machine: MobaStateMachine = data["state_machine"]
	combatant.register_ability(_make_ability("channel_ability", 0.0, 2.0))

	var bar: MobaCastBar = CAST_BAR_SCENE.instantiate()
	bar.bind(combatant)

	# Start a channel, and put the state machine in ABILITY_CHANNEL so the
	# hard-CC interrupt seam sees the state it gates on.
	state_machine.try_enter(MobaState.ABILITY_CHANNEL, 2.0)
	combatant.start_channel(&"channel_ability", combatant.get_ability(&"channel_ability"), [], 2.0)
	# Tick at least once to allow break
	combatant.tick(0.1)
	bar.refresh()

	if not bar.visible:
		violations.append("channel_break: bar should be visible during channel")

	# Break the channel with a real hard crowd control application, so this
	# exercises the _apply_hard_cc() route rather than calling the break
	# directly. A STUN is hard CC and interrupts an in-progress channel.
	var spec := MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.STUN
	spec.duration = 1.0
	spec.affected_by_tenacity = false
	combatant.apply_crowd_control(spec, null)
	bar.refresh()

	if combatant.is_channeling():
		violations.append("channel_break: hard CC should have broken the channel")

	# Bar should be hidden after break
	if bar.visible:
		violations.append("channel_break: bar should be hidden after a hard CC interrupt")

	var name_label: Label = bar.get_node("VBox/NameLabel")
	if name_label.text != "":
		violations.append("channel_break: name should be cleared after break")

	bar.free()
	actor.free()
	return violations


## The same hard-CC exit path, taken while casting rather than channelling. The
## criterion names a cast or a channel, and the two run through different
## trackers, so covering only one would leave the other able to strand the bar.
static func _test_clears_on_cast_hard_cc_interrupt() -> Array[String]:
	var violations: Array[String] = []

	var data := _make_combatant_with_state_machine()
	var actor: Actor = data["actor"]
	var combatant: MobaCombatant = data["combatant"]
	var state_machine: MobaStateMachine = data["state_machine"]
	combatant.register_ability(_make_ability("cast_ability", 2.0))

	var bar: MobaCastBar = CAST_BAR_SCENE.instantiate()
	bar.bind(combatant)

	state_machine.try_enter(MobaState.ABILITY_CAST, 2.0)
	combatant.start_cast(&"cast_ability", combatant.get_ability(&"cast_ability"), [], 2.0)
	combatant.tick(0.1)
	bar.refresh()

	if not bar.visible:
		violations.append("cast_hard_cc: bar should be visible during cast")

	var spec := MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.STUN
	spec.duration = 1.0
	spec.affected_by_tenacity = false
	combatant.apply_crowd_control(spec, null)
	bar.refresh()

	if combatant.is_casting():
		violations.append("cast_hard_cc: hard CC should have interrupted the cast")

	if bar.visible:
		violations.append("cast_hard_cc: bar should be hidden after a hard CC interrupt")

	var name_label: Label = bar.get_node("VBox/NameLabel")
	if name_label.text != "":
		violations.append("cast_hard_cc: name should be cleared after the interrupt")

	bar.free()
	actor.free()
	return violations


static func _test_rebind_has_no_stale_state() -> Array[String]:
	var violations: Array[String] = []

	var combatant1 := _make_combatant()
	combatant1.register_ability(_make_ability("cast_ability_1", 2.0))

	var combatant2 := _make_combatant()
	combatant2.register_ability(_make_ability("cast_ability_2", 2.0))

	var bar: MobaCastBar = CAST_BAR_SCENE.instantiate()

	# Bind to combatant1 and start a cast
	bar.bind(combatant1)
	combatant1.start_cast(
		&"cast_ability_1", combatant1.get_ability(&"cast_ability_1"), [] as Array[Node], 2.0
	)
	bar.refresh()

	var name_label: Label = bar.get_node("VBox/NameLabel")
	if name_label.text != "Test cast_ability_1":
		violations.append("rebind: bar should show combatant1's ability name")

	if not bar.visible:
		violations.append("rebind: bar should be visible while combatant1 is casting")

	# Rebind to combatant2 (which is not casting)
	bar.bind(combatant2)
	bar.refresh()

	# Bar should be hidden and name cleared
	if bar.visible:
		violations.append("rebind: bar should be hidden for combatant2 (not casting)")

	if name_label.text != "":
		violations.append("rebind: name should be cleared after rebinding to non-casting combatant")

	# Rebind to null
	bar.bind(null)
	bar.refresh()

	if bar.visible:
		violations.append("rebind: bar should be hidden when bound to null")

	if name_label.text != "":
		violations.append("rebind: name should be cleared when bound to null")

	bar.free()
	combatant1.free()
	combatant2.free()
	return violations
