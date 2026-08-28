## Standalone status tray listing every active buff, debuff, and hard crowd
## control effect on one combatant, each with its remaining duration and, for
## stacked stat modifiers, its stack count.
##
## The tray is bound by assignment — bind(combatant) — and never searches the
## scene tree, so the same scene can be placed in a HUD or elsewhere without
## change.
##
## Signals in, nothing out: this control only reads MobaEffectContainer and
## MobaCombatant state through their public signals and getters. It never calls
## remove_modifiers_from() or any other mutator.
##
## No rules logic: an entry is a debuff because MobaEffectContainer.is_debuff()
## says so, never because its amount is negative or its stat sounds unpleasant.
## §17 of the ruleset authors debuffs with positive amounts (+15 % Damage
## Taken), so a sign heuristic would be both wrong and a rule computed in UI.
##
## Buffs and debuffs are signal-driven: effect_applied, effect_refreshed,
## effect_stacks_changed, and effect_expired maintain the set of live modifier
## identities. Because MobaEffectContainer exposes no way to enumerate its
## entries, a tray bound to a combatant that already carries effects only shows
## the ones applied after the binding.
##
## Crowd control is polled once per frame instead, matching the pattern
## MobaAbilitySlot._process() uses for its cooldown sweep: the rules side emits
## no crowd control signal, and this task adds none.
##
## Order is the tray's own bookkeeping, not the rules'. Neither the container
## nor the combatant records when an effect was applied, so the tray hands out
## a monotonic number the first time it observes an entry and sorts by that.
## Sorting by remaining duration would make the row reshuffle every frame as
## timers count down, which is exactly what the ordering requirement forbids.
class_name MobaStatusTray
extends Control

## The three visually distinguished kinds of entry.
enum Category {
	BUFF,
	DEBUFF,
	CROWD_CONTROL,
}

## Placeholder background colour per category. Colours only — no art here.
const CATEGORY_COLORS := {
	Category.BUFF: Color(0.12, 0.42, 0.20, 0.90),
	Category.DEBUFF: Color(0.45, 0.13, 0.36, 0.90),
	Category.CROWD_CONTROL: Color(0.55, 0.33, 0.07, 0.90),
}

## Placeholder category marker glyph, so the categories stay distinguishable
## without relying on colour alone.
const CATEGORY_MARKERS := {
	Category.BUFF: "+",
	Category.DEBUFF: "-",
	Category.CROWD_CONTROL: "!",
}

## Shown in place of a countdown for an active entry with no remaining
## duration. MobaEffectContainer reports 0.0 for a permanent modifier and
## erases a timed one the moment it reaches zero, so an active entry at 0.0 is
## permanent rather than about to expire.
const PERMANENT_DURATION_TEXT := "∞"

## Key prefix for a stat-modifier entry, keyed by (source_ability_id, stat).
const MODIFIER_KEY_PREFIX := &"modifier"

## Key prefix for a crowd control entry, keyed by MobaCrowdControlSpec.CCType.
const CROWD_CONTROL_KEY_PREFIX := &"crowd_control"

const _ENTRY_MIN_SIZE := Vector2(96, 64)

var _combatant: MobaCombatant = null
var _effect_container: MobaEffectContainer = null

var _entries: HBoxContainer = null

## Entry key -> _EntryView for every entry currently rendered.
var _views: Dictionary = {}

## Entry key -> the monotonic number recorded when the entry was first seen.
var _order: Dictionary = {}

## Hands out the next application-order number.
var _next_order: int = 0

## Modifier identities believed active, maintained from the container signals.
var _modifier_keys: Dictionary = {}

## Crowd control types believed active, maintained by the per-frame poll.
var _crowd_control_keys: Dictionary = {}

## Entry keys in rendered order, left to right.
var _rendered_keys: Array = []


## The nodes making up one rendered entry, resolved once at creation so the
## per-frame update never walks the tree.
class _EntryView:
	var category: int = 0
	var root: PanelContainer = null
	var background: ColorRect = null
	var category_label: Label = null
	var name_label: Label = null
	var duration_label: Label = null
	var stack_label: Label = null


func _ready() -> void:
	_ensure_nodes()
	refresh()


## Polling crowd control and advancing the displayed countdowns is the only
## per-frame work. Buff and debuff membership arrives on signals.
func _process(_delta: float) -> void:
	refresh()


## Bind this tray to one combatant. Rebinding is explicit: the previous
## combatant's connections are dropped and its entries discarded before the new
## ones are made, so calling bind() twice leaves exactly one connection per
## signal and no stale entries from the previous binding.
func bind(combatant: MobaCombatant) -> void:
	_ensure_nodes()
	_disconnect_container()
	_clear_entries()
	_combatant = combatant if is_instance_valid(combatant) else null
	_effect_container = _combatant.get_effect_container() if _combatant != null else null
	_connect_container()
	refresh()


## Drop the binding and render the empty state.
func unbind() -> void:
	bind(null)


## The currently bound combatant, or null.
func get_combatant() -> MobaCombatant:
	return _combatant


## Re-render every entry: poll crowd control, drop entries that are no longer
## active, and refresh the remaining durations and stack counts of the rest.
func refresh() -> void:
	_ensure_nodes()
	_poll_crowd_control()
	_render(_collect_active_keys())


## How many entries the tray is currently rendering.
func get_entry_count() -> int:
	return _rendered_keys.size()


## Entry keys in rendered order, left to right.
func get_entry_keys() -> Array:
	return _rendered_keys.duplicate()


## The root node of one rendered entry, or null when the key is not rendered.
func get_entry_node(key: Array) -> Control:
	if key not in _views:
		return null
	return (_views[key] as _EntryView).root


## The Category of one rendered entry, or -1 when the key is not rendered.
func get_entry_category(key: Array) -> int:
	if key not in _views:
		return -1
	return (_views[key] as _EntryView).category


## The entry key identifying one stat modifier: its source ability and stat.
static func modifier_key(source_ability_id: StringName, stat: StringName) -> Array:
	return [MODIFIER_KEY_PREFIX, source_ability_id, stat]


## The entry key identifying one crowd control type.
static func crowd_control_key(cc_type: int) -> Array:
	return [CROWD_CONTROL_KEY_PREFIX, cc_type]


## Record the application order of a newly observed entry. An identity seen
## again — a refresh, a stack, or a REPLACE_IF_STRONGER swap — keeps the number
## it already has, so a re-application never moves an entry along the row.
func _record_order(key: Array) -> void:
	if key in _order:
		return
	_order[key] = _next_order
	_next_order += 1


## Poll each crowd control type once. A type that newly reports active is
## recorded in application order here, since the rules side emits no signal.
func _poll_crowd_control() -> void:
	if not is_instance_valid(_combatant):
		_crowd_control_keys.clear()
		return

	for cc_type in MobaCrowdControlSpec.CCType.values():
		var key := crowd_control_key(cc_type)
		if _combatant.has_crowd_control(cc_type):
			if key not in _crowd_control_keys:
				_crowd_control_keys[key] = true
				_record_order(key)
		elif key in _crowd_control_keys:
			_forget(key)


## The active entry keys, sorted by recorded application order. Modifier
## identities are confirmed against the container so a missed signal cannot
## strand an entry on screen.
func _collect_active_keys() -> Array:
	var keys: Array = []

	for key in _modifier_keys.keys():
		if _effect_container != null and _effect_container.has_modifier(key[1], key[2]):
			keys.append(key)
		else:
			_forget(key)

	for key in _crowd_control_keys:
		keys.append(key)

	keys.sort_custom(_compare_order)
	return keys


func _compare_order(left: Array, right: Array) -> bool:
	return int(_order.get(left, 0)) < int(_order.get(right, 0))


## Create, update, and position one node per active key. Position follows the
## sorted key list, so an entry only moves when another entry ahead of it goes
## away — never because a countdown advanced.
func _render(keys: Array) -> void:
	for index in keys.size():
		var key: Array = keys[index]
		var view: _EntryView = _views.get(key)
		if view == null:
			view = _create_view(key)
			_views[key] = view
			_entries.add_child(view.root)
		_update_view(view, key)
		_entries.move_child(view.root, index)

	_rendered_keys = keys


func _create_view(key: Array) -> _EntryView:
	var view := _EntryView.new()

	view.root = PanelContainer.new()
	view.root.name = "Entry%d" % int(_order.get(key, 0))
	view.root.custom_minimum_size = _ENTRY_MIN_SIZE
	view.root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	view.background = ColorRect.new()
	view.background.name = "Background"
	view.background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.root.add_child(view.background)

	var box := VBoxContainer.new()
	box.name = "VBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.root.add_child(box)

	view.category_label = _make_label("CategoryLabel")
	box.add_child(view.category_label)
	view.name_label = _make_label("NameLabel")
	box.add_child(view.name_label)
	view.duration_label = _make_label("DurationLabel")
	box.add_child(view.duration_label)
	view.stack_label = _make_label("StackLabel")
	box.add_child(view.stack_label)

	return view


func _make_label(label_name: String) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	return label


func _update_view(view: _EntryView, key: Array) -> void:
	if key[0] == CROWD_CONTROL_KEY_PREFIX:
		_update_crowd_control_view(view, int(key[1]))
	else:
		_update_modifier_view(view, key[1], key[2])


func _update_modifier_view(
	view: _EntryView, source_ability_id: StringName, stat: StringName
) -> void:
	var category := (
		Category.DEBUFF if _effect_container.is_debuff(source_ability_id, stat) else Category.BUFF
	)
	_set_category(view, category)
	view.name_label.text = String(source_ability_id)
	_set_duration(view, _effect_container.get_remaining_duration(source_ability_id, stat))
	_set_stacks(view, _effect_container.get_stacks(source_ability_id, stat))


func _update_crowd_control_view(view: _EntryView, cc_type: int) -> void:
	_set_category(view, Category.CROWD_CONTROL)
	view.name_label.text = _crowd_control_name(cc_type)
	_set_duration(view, _combatant.get_crowd_control_remaining(cc_type))
	# Crowd control does not stack: one entry per type, per MobaCrowdControlTracker.
	_set_stacks(view, 1)


func _set_category(view: _EntryView, category: int) -> void:
	view.category = category
	view.background.color = CATEGORY_COLORS[category]
	view.category_label.text = CATEGORY_MARKERS[category]


func _set_duration(view: _EntryView, remaining: float) -> void:
	if remaining <= 0.0:
		view.duration_label.text = PERMANENT_DURATION_TEXT
		return
	view.duration_label.text = "%.1f" % remaining


func _set_stacks(view: _EntryView, stacks: int) -> void:
	view.stack_label.visible = stacks > 1
	view.stack_label.text = "x%d" % stacks if stacks > 1 else ""


func _crowd_control_name(cc_type: int) -> String:
	var names: Array = MobaCrowdControlSpec.CCType.keys()
	if cc_type < 0 or cc_type >= names.size():
		return String.num_int64(cc_type)
	return String(names[cc_type])


## Drop one entry entirely: its membership, its recorded order, and its node.
## The node is removed before being freed so the row is correct immediately,
## without waiting for the deletion queue to run.
func _forget(key: Array) -> void:
	_modifier_keys.erase(key)
	_crowd_control_keys.erase(key)
	_order.erase(key)

	if key not in _views:
		return

	var view: _EntryView = _views[key]
	_views.erase(key)
	_rendered_keys.erase(key)
	if view.root != null:
		if view.root.get_parent() != null:
			view.root.get_parent().remove_child(view.root)
		view.root.queue_free()


## Discard every entry and reset the ordering counter. Used when the binding
## changes, so nothing from the previous combatant survives it.
func _clear_entries() -> void:
	for key in _views.keys():
		_forget(key)

	_modifier_keys.clear()
	_crowd_control_keys.clear()
	_order.clear()
	_rendered_keys.clear()
	_next_order = 0


func _on_effect_applied(source_ability_id: StringName, stat: StringName) -> void:
	var key := modifier_key(source_ability_id, stat)
	_modifier_keys[key] = true
	_record_order(key)
	refresh()


func _on_effect_refreshed(_source_ability_id: StringName, _stat: StringName) -> void:
	# The countdown is read back from the container, so re-rendering is all a
	# refreshed duration needs to show at full again.
	refresh()


func _on_effect_stacks_changed(
	_source_ability_id: StringName, _stat: StringName, _stacks: int
) -> void:
	refresh()


func _on_effect_expired(source_ability_id: StringName, stat: StringName) -> void:
	_forget(modifier_key(source_ability_id, stat))
	refresh()


func _connect_container() -> void:
	if _effect_container == null:
		return
	_effect_container.effect_applied.connect(_on_effect_applied)
	_effect_container.effect_refreshed.connect(_on_effect_refreshed)
	_effect_container.effect_stacks_changed.connect(_on_effect_stacks_changed)
	_effect_container.effect_expired.connect(_on_effect_expired)


func _disconnect_container() -> void:
	if _effect_container == null or not is_instance_valid(_effect_container):
		_effect_container = null
		return

	if _effect_container.effect_applied.is_connected(_on_effect_applied):
		_effect_container.effect_applied.disconnect(_on_effect_applied)
	if _effect_container.effect_refreshed.is_connected(_on_effect_refreshed):
		_effect_container.effect_refreshed.disconnect(_on_effect_refreshed)
	if _effect_container.effect_stacks_changed.is_connected(_on_effect_stacks_changed):
		_effect_container.effect_stacks_changed.disconnect(_on_effect_stacks_changed)
	if _effect_container.effect_expired.is_connected(_on_effect_expired):
		_effect_container.effect_expired.disconnect(_on_effect_expired)

	_effect_container = null


## Resolves child nodes without requiring the tray to be inside the scene tree,
## so an owner (or a test) can bind a freshly instantiated tray before adding it.
func _ensure_nodes() -> void:
	if _entries != null:
		return
	_entries = get_node_or_null(^"Entries")
