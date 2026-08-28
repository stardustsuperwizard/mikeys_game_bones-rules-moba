## Test suite for the standalone MobaStatusTray control.
##
## Covers that the tray renders one entry per active buff, debuff, and hard
## crowd control effect with its remaining duration and stack count, that the
## three categories are visually distinguishable, that re-applying an effect
## visibly resets its countdown under both the REFRESH and STACK policies, that
## a stacking buff stops at max_stacks, that entries keep their order as
## timers run down and neighbours expire, and that rebinding leaves exactly one
## live set of connections and no stale entries.
class_name StatusTrayTest

const MobaStatBlock = preload("res://rules/core/moba_stat_block.gd")
const MobaCombatant = preload("res://rules/core/moba_combatant.gd")
const STATUS_TRAY_SCENE = preload("res://rules/ui/moba_status_tray.tscn")
const _BASELINE_STAT_BLOCK = preload("res://rules/data/stat_blocks/baseline.tres")

const _CONTAINER_SIGNALS := [
	&"effect_applied",
	&"effect_refreshed",
	&"effect_stacks_changed",
	&"effect_expired",
]


static func run() -> bool:
	var all_violations: Array[String] = []

	all_violations.append_array(_test_shows_each_active_effect())
	all_violations.append_array(_test_stack_count_matches_container())
	all_violations.append_array(_test_categories_are_visually_distinct())
	all_violations.append_array(_test_reapplication_resets_displayed_duration())
	all_violations.append_array(_test_stacking_buff_caps_at_max_stacks())
	all_violations.append_array(_test_order_is_stable())
	all_violations.append_array(_test_rebind_leaves_one_binding())

	if all_violations.is_empty():
		return true

	printerr("\n=== Status Tray Test Violations ===")
	for violation in all_violations:
		printerr("FAIL " + violation)

	return false


## Build a standalone combatant fixture that never enters the scene tree.
static func _make_combatant() -> MobaCombatant:
	var combatant := MobaCombatant.new()
	combatant.stat_block = _BASELINE_STAT_BLOCK
	combatant._runtime_stat_block = combatant.stat_block.duplicate()
	combatant._current_health = combatant._runtime_stat_block.get_stat_value(MobaStatBlock.HEALTH)
	return combatant


## A combatant parented under an Actor with a real MobaStateMachine, the shape
## crowd_control_test.gd uses. Hard CC is refused outright without a state
## machine, so a bare combatant could never produce a crowd control entry.
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

	return {"actor": actor, "combatant": combatant}


static func _make_modifier(
	stat: String,
	amount: float,
	duration: float,
	stacking: int = MobaStatModifier.Stacking.REFRESH,
	max_stacks: int = 1
) -> MobaStatModifier:
	var modifier := MobaStatModifier.new()
	modifier.stat = stat
	modifier.amount = amount
	modifier.duration = duration
	modifier.stacking = stacking
	modifier.max_stacks = max_stacks
	return modifier


static func _apply_stun(combatant: MobaCombatant, duration: float) -> void:
	var spec := MobaCrowdControlSpec.new()
	spec.type = MobaCrowdControlSpec.CCType.STUN
	spec.duration = duration
	spec.affected_by_tenacity = false
	combatant.apply_crowd_control(spec, null)


static func _label_text(tray: MobaStatusTray, key: Array, label_name: String) -> String:
	var entry := tray.get_entry_node(key)
	if entry == null:
		return "<no entry>"
	var label := entry.get_node_or_null(NodePath("VBox/%s" % label_name)) as Label
	if label == null:
		return "<no label>"
	return label.text


static func _background_color(tray: MobaStatusTray, key: Array) -> Color:
	var entry := tray.get_entry_node(key)
	if entry == null:
		return Color(0, 0, 0, 0)
	return (entry.get_node("Background") as ColorRect).color


## How many of the container's signal connections lead back to this tray.
static func _tray_connection_count(container: MobaEffectContainer, tray: MobaStatusTray) -> int:
	var total := 0
	for signal_name in _CONTAINER_SIGNALS:
		for connection in container.get_signal_connection_list(signal_name):
			var callable: Callable = connection["callable"]
			if callable.get_object() == tray:
				total += 1
	return total


## One entry per active buff, debuff, and hard CC effect, each showing its
## remaining duration, and each countdown advancing as time passes.
static func _test_shows_each_active_effect() -> Array[String]:
	var violations: Array[String] = []

	var fixture := _make_combatant_with_state_machine()
	var actor: Actor = fixture["actor"]
	var combatant: MobaCombatant = fixture["combatant"]

	var tray: MobaStatusTray = STATUS_TRAY_SCENE.instantiate()
	tray.bind(combatant)

	if tray.get_entry_count() != 0:
		violations.append("active_effects: tray should start empty")

	combatant.apply_stat_modifier(_make_modifier("attack_damage", 10.0, 4.0), &"war_cry", false)
	combatant.apply_stat_modifier(_make_modifier("armor", 15.0, 6.0), &"sunder", true)
	_apply_stun(combatant, 3.0)
	tray.refresh()

	var buff_key := MobaStatusTray.modifier_key(&"war_cry", MobaStatBlock.ATTACK_DAMAGE)
	var debuff_key := MobaStatusTray.modifier_key(&"sunder", MobaStatBlock.ARMOR)
	var cc_key := MobaStatusTray.crowd_control_key(MobaCrowdControlSpec.CCType.STUN)

	if tray.get_entry_count() != 3:
		violations.append("active_effects: expected 3 entries, got %d" % tray.get_entry_count())

	if tray.get_entry_category(buff_key) != MobaStatusTray.Category.BUFF:
		violations.append("active_effects: war_cry should render as a buff")
	if tray.get_entry_category(debuff_key) != MobaStatusTray.Category.DEBUFF:
		violations.append("active_effects: sunder should render as a debuff")
	if tray.get_entry_category(cc_key) != MobaStatusTray.Category.CROWD_CONTROL:
		violations.append("active_effects: the stun should render as crowd control")

	if _label_text(tray, buff_key, "DurationLabel") != "4.0":
		violations.append(
			(
				"active_effects: buff duration should read 4.0, got '%s'"
				% _label_text(tray, buff_key, "DurationLabel")
			)
		)
	if _label_text(tray, debuff_key, "DurationLabel") != "6.0":
		violations.append(
			(
				"active_effects: debuff duration should read 6.0, got '%s'"
				% _label_text(tray, debuff_key, "DurationLabel")
			)
		)
	if _label_text(tray, cc_key, "DurationLabel") != "3.0":
		violations.append(
			(
				"active_effects: crowd control duration should read 3.0, got '%s'"
				% _label_text(tray, cc_key, "DurationLabel")
			)
		)

	combatant.tick(1.0)
	tray.refresh()

	if _label_text(tray, buff_key, "DurationLabel") != "3.0":
		violations.append(
			(
				"active_effects: buff duration should count down to 3.0, got '%s'"
				% _label_text(tray, buff_key, "DurationLabel")
			)
		)
	if _label_text(tray, cc_key, "DurationLabel") != "2.0":
		violations.append(
			(
				"active_effects: crowd control duration should count down to 2.0, got '%s'"
				% _label_text(tray, cc_key, "DurationLabel")
			)
		)

	# An expired effect leaves no entry behind.
	combatant.tick(5.5)
	tray.refresh()

	if tray.get_entry_node(buff_key) != null:
		violations.append("active_effects: an expired buff should leave no entry")
	if tray.get_entry_node(cc_key) != null:
		violations.append("active_effects: expired crowd control should leave no entry")

	tray.free()
	actor.free()
	return violations


## The stack label tracks MobaEffectContainer.get_stacks() rather than counting
## applications itself, and stacking never splits one identity into two entries.
static func _test_stack_count_matches_container() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	var tray: MobaStatusTray = STATUS_TRAY_SCENE.instantiate()
	tray.bind(combatant)

	var modifier := _make_modifier("attack_damage", 5.0, 6.0, MobaStatModifier.Stacking.STACK, 3)
	combatant.apply_stat_modifier(modifier, &"bloodlust", false)
	combatant.apply_stat_modifier(modifier, &"bloodlust", false)
	tray.refresh()

	var key := MobaStatusTray.modifier_key(&"bloodlust", MobaStatBlock.ATTACK_DAMAGE)

	if tray.get_entry_count() != 1:
		violations.append(
			"stack_count: stacking should stay one entry, got %d" % tray.get_entry_count()
		)

	var stacks := container.get_stacks(&"bloodlust", MobaStatBlock.ATTACK_DAMAGE)
	if stacks != 2:
		violations.append("stack_count: container should report 2 stacks, got %d" % stacks)

	if _label_text(tray, key, "StackLabel") != "x%d" % stacks:
		violations.append(
			(
				"stack_count: stack label should read x%d, got '%s'"
				% [stacks, _label_text(tray, key, "StackLabel")]
			)
		)

	tray.free()
	combatant.free()
	return violations


## Buff, debuff, and crowd control render with different placeholder colours and
## different category markers, so the three read apart without art.
static func _test_categories_are_visually_distinct() -> Array[String]:
	var violations: Array[String] = []

	var fixture := _make_combatant_with_state_machine()
	var actor: Actor = fixture["actor"]
	var combatant: MobaCombatant = fixture["combatant"]

	var tray: MobaStatusTray = STATUS_TRAY_SCENE.instantiate()
	tray.bind(combatant)

	combatant.apply_stat_modifier(_make_modifier("attack_damage", 10.0, 5.0), &"war_cry", false)
	combatant.apply_stat_modifier(_make_modifier("armor", 15.0, 5.0), &"sunder", true)
	_apply_stun(combatant, 5.0)
	tray.refresh()

	var buff_key := MobaStatusTray.modifier_key(&"war_cry", MobaStatBlock.ATTACK_DAMAGE)
	var debuff_key := MobaStatusTray.modifier_key(&"sunder", MobaStatBlock.ARMOR)
	var cc_key := MobaStatusTray.crowd_control_key(MobaCrowdControlSpec.CCType.STUN)

	var colors := [
		_background_color(tray, buff_key),
		_background_color(tray, debuff_key),
		_background_color(tray, cc_key),
	]
	var markers := [
		_label_text(tray, buff_key, "CategoryLabel"),
		_label_text(tray, debuff_key, "CategoryLabel"),
		_label_text(tray, cc_key, "CategoryLabel"),
	]

	for first in colors.size():
		for second in range(first + 1, colors.size()):
			if colors[first] == colors[second]:
				violations.append("categories: entries %d and %d share a colour" % [first, second])
			if markers[first] == markers[second]:
				violations.append("categories: entries %d and %d share a marker" % [first, second])

	tray.free()
	actor.free()
	return violations


## Re-applying an already-active effect resets the displayed countdown to full,
## under REFRESH and under STACK. The two take different branches in
## MobaEffectContainer, so covering one would leave the other able to strand a
## half-spent timer on screen.
static func _test_reapplication_resets_displayed_duration() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_check_reapplication_resets(MobaStatModifier.Stacking.REFRESH, 1, "refresh")
	)
	violations.append_array(
		_check_reapplication_resets(MobaStatModifier.Stacking.STACK, 3, "stack")
	)

	return violations


static func _check_reapplication_resets(
	stacking: int, max_stacks: int, label: String
) -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var tray: MobaStatusTray = STATUS_TRAY_SCENE.instantiate()
	tray.bind(combatant)

	var modifier := _make_modifier("attack_damage", 5.0, 4.0, stacking, max_stacks)
	combatant.apply_stat_modifier(modifier, &"rally", false)
	tray.refresh()

	var key := MobaStatusTray.modifier_key(&"rally", MobaStatBlock.ATTACK_DAMAGE)

	if _label_text(tray, key, "DurationLabel") != "4.0":
		violations.append(
			(
				"%s_reset: duration should start at 4.0, got '%s'"
				% [label, _label_text(tray, key, "DurationLabel")]
			)
		)

	combatant.tick(2.0)
	tray.refresh()

	if _label_text(tray, key, "DurationLabel") != "2.0":
		violations.append(
			(
				"%s_reset: duration should count down to 2.0, got '%s'"
				% [label, _label_text(tray, key, "DurationLabel")]
			)
		)

	combatant.apply_stat_modifier(modifier, &"rally", false)

	if _label_text(tray, key, "DurationLabel") != "4.0":
		violations.append(
			(
				"%s_reset: re-application should reset the timer to 4.0, got '%s'"
				% [label, _label_text(tray, key, "DurationLabel")]
			)
		)

	if tray.get_entry_count() != 1:
		violations.append(
			(
				"%s_reset: re-application should not add an entry, got %d"
				% [label, tray.get_entry_count()]
			)
		)

	tray.free()
	combatant.free()
	return violations


## Five applications of a three-stack buff show one entry that climbs to
## max_stacks and stops there.
static func _test_stacking_buff_caps_at_max_stacks() -> Array[String]:
	var violations: Array[String] = []

	var combatant := _make_combatant()
	var container := combatant.get_effect_container()

	var tray: MobaStatusTray = STATUS_TRAY_SCENE.instantiate()
	tray.bind(combatant)

	var max_stacks := 3
	var modifier := _make_modifier(
		"attack_damage", 5.0, 6.0, MobaStatModifier.Stacking.STACK, max_stacks
	)
	for _application in 5:
		combatant.apply_stat_modifier(modifier, &"frenzy", false)
	tray.refresh()

	var key := MobaStatusTray.modifier_key(&"frenzy", MobaStatBlock.ATTACK_DAMAGE)

	if tray.get_entry_count() != 1:
		violations.append(
			"stack_cap: five applications should show one entry, got %d" % tray.get_entry_count()
		)

	var stacks := container.get_stacks(&"frenzy", MobaStatBlock.ATTACK_DAMAGE)
	if stacks != max_stacks:
		violations.append("stack_cap: container should cap at %d, got %d" % [max_stacks, stacks])

	if _label_text(tray, key, "StackLabel") != "x%d" % max_stacks:
		violations.append(
			(
				"stack_cap: stack label should stop at x%d, got '%s'"
				% [max_stacks, _label_text(tray, key, "StackLabel")]
			)
		)

	tray.free()
	combatant.free()
	return violations


## Entries hold their application order while their timers run down, while a
## neighbour expires, and while a later effect is added. Sorting by remaining
## duration would fail the first check: the longest-lived entry is applied first
## here on purpose.
static func _test_order_is_stable() -> Array[String]:
	var violations: Array[String] = []

	var fixture := _make_combatant_with_state_machine()
	var actor: Actor = fixture["actor"]
	var combatant: MobaCombatant = fixture["combatant"]

	var tray: MobaStatusTray = STATUS_TRAY_SCENE.instantiate()
	tray.bind(combatant)

	combatant.apply_stat_modifier(_make_modifier("attack_damage", 10.0, 10.0), &"first", false)
	combatant.apply_stat_modifier(_make_modifier("armor", 5.0, 2.0), &"second", true)
	_apply_stun(combatant, 5.0)
	tray.refresh()

	var first_key := MobaStatusTray.modifier_key(&"first", MobaStatBlock.ATTACK_DAMAGE)
	var second_key := MobaStatusTray.modifier_key(&"second", MobaStatBlock.ARMOR)
	var cc_key := MobaStatusTray.crowd_control_key(MobaCrowdControlSpec.CCType.STUN)

	var expected: Array = [first_key, second_key, cc_key]
	if tray.get_entry_keys() != expected:
		violations.append("order: entries should render in application order")

	# Halfway through, the shortest timer is in the middle and the longest is
	# first: any duration-based sort would reorder here.
	combatant.tick(1.0)
	tray.refresh()

	if tray.get_entry_keys() != expected:
		violations.append("order: entries should not reorder as their timers count down")

	# The middle entry expires; the survivors keep their relative order.
	combatant.tick(1.5)
	tray.refresh()

	if tray.get_entry_keys() != [first_key, cc_key]:
		violations.append("order: survivors should keep their order when an entry expires")

	# A later effect joins at the end rather than displacing anything.
	combatant.apply_stat_modifier(_make_modifier("armor", 8.0, 3.0), &"third", false)
	tray.refresh()

	var third_key := MobaStatusTray.modifier_key(&"third", MobaStatBlock.ARMOR)
	if tray.get_entry_keys() != [first_key, cc_key, third_key]:
		violations.append("order: a newly applied effect should append to the end")

	tray.free()
	actor.free()
	return violations


## Rebinding to another combatant, and then to null, leaves exactly one live set
## of connections and no entries from the previous binding.
static func _test_rebind_leaves_one_binding() -> Array[String]:
	var violations: Array[String] = []

	var first := _make_combatant()
	var second := _make_combatant()
	var first_container := first.get_effect_container()
	var second_container := second.get_effect_container()

	var tray: MobaStatusTray = STATUS_TRAY_SCENE.instantiate()

	tray.bind(first)
	tray.bind(first)
	if _tray_connection_count(first_container, tray) != _CONTAINER_SIGNALS.size():
		violations.append(
			(
				"rebind: binding twice should leave one connection per signal, got %d"
				% _tray_connection_count(first_container, tray)
			)
		)

	first.apply_stat_modifier(_make_modifier("attack_damage", 10.0, 5.0), &"war_cry", false)
	tray.refresh()
	if tray.get_entry_count() != 1:
		violations.append("rebind: the first combatant's buff should render")

	tray.bind(second)

	if _tray_connection_count(first_container, tray) != 0:
		violations.append("rebind: the previous combatant should keep no connections")
	if _tray_connection_count(second_container, tray) != _CONTAINER_SIGNALS.size():
		violations.append("rebind: the new combatant should have one connection per signal")
	if tray.get_entry_count() != 0:
		violations.append("rebind: entries from the previous combatant should be gone")

	# The old combatant's effects must not reach the tray any more.
	first.apply_stat_modifier(_make_modifier("armor", 10.0, 5.0), &"sunder", true)
	tray.refresh()
	if tray.get_entry_count() != 0:
		violations.append("rebind: the unbound combatant should no longer feed the tray")

	second.apply_stat_modifier(_make_modifier("armor", 10.0, 5.0), &"aegis", false)
	tray.refresh()
	if tray.get_entry_count() != 1:
		violations.append("rebind: the newly bound combatant's buff should render")

	tray.unbind()

	if _tray_connection_count(second_container, tray) != 0:
		violations.append("rebind: unbinding should drop every connection")
	if tray.get_entry_count() != 0:
		violations.append("rebind: unbinding should leave no entries")
	if tray.get_combatant() != null:
		violations.append("rebind: unbinding should clear the bound combatant")

	tray.free()
	first.free()
	second.free()
	return violations
