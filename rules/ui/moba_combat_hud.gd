## Combat HUD for one MobaCombatant: health and resource bars, a fixed row of
## four action slots, a visually separated passive grouping, and a tooltip for
## whichever slot currently holds focus.
##
## The HUD is bound by assignment — bind(combatant) — and never searches the
## scene tree for the player, so the same scene works for a local player, a
## spectated combatant, or a test fixture.
##
## Signals in, nothing out: this layer only observes MobaCombatant. It never
## calls a mutator and handles no input beyond the hover that sets slot focus.
## No rules logic lives here; every value comes from a signal or a public
## getter.
class_name MobaCombatHUD
extends CanvasLayer

## Number of positional action slots, slot 1 leftmost.
const ACTION_SLOT_COUNT := 4

## Shown in the tooltip's status line while no ability is bound to the slot.
const EMPTY_TOOLTIP_STATUS := "Empty slot"

var _combatant: MobaCombatant = null
var _focused_slot: MobaAbilitySlot = null

var _health_bar: TextureProgressBar = null
var _health_label: Label = null
var _resource_bar: TextureProgressBar = null
var _resource_label: Label = null
var _action_slots: Array[MobaAbilitySlot] = []
var _passive_slot: MobaAbilitySlot = null
var _tooltip: Control = null
var _tooltip_name: Label = null
var _tooltip_status: Label = null

var _nodes_resolved: bool = false


func _ready() -> void:
	_ensure_nodes()
	_refresh_tooltip()


## The bound combatant can be freed at any time (Actor.die() calls
## queue_free()), so the binding is dropped as soon as it goes invalid rather
## than being read again next frame.
func _process(_delta: float) -> void:
	if _combatant != null and not is_instance_valid(_combatant):
		unbind()
		return


## Bind the HUD to one combatant. Rebinding is explicit: any previous
## connections are dropped before the new ones are made, so calling bind()
## twice leaves exactly one connection per signal and produces no duplicate
## updates.
func bind(combatant: MobaCombatant) -> void:
	_ensure_nodes()
	_disconnect_combatant()
	_combatant = combatant if is_instance_valid(combatant) else null
	_connect_combatant()
	_refresh_slots()
	_push_current_values()
	_refresh_tooltip()


## Drop the binding and render the empty state. Used when the combatant is
## freed or dies.
func unbind() -> void:
	bind(null)


## The currently bound combatant, or null.
func get_combatant() -> MobaCombatant:
	return _combatant


## The slot that currently holds focus, or null. The tooltip is driven from
## this state alone, so a later gamepad or touch trigger only has to call
## MobaAbilitySlot.set_focused() to open it.
func get_focused_slot() -> MobaAbilitySlot:
	return _focused_slot


## The four action slots in fixed positional order, slot 1 first.
func get_action_slots() -> Array[MobaAbilitySlot]:
	_ensure_nodes()
	return _action_slots.duplicate()


## The slot-shaped element of the passive grouping. Renders empty when no
## passive is selected.
func get_passive_slot() -> MobaAbilitySlot:
	_ensure_nodes()
	return _passive_slot


## True while the focused-slot tooltip is on screen.
func is_tooltip_visible() -> bool:
	_ensure_nodes()
	return _tooltip != null and _tooltip.visible


func _refresh_slots() -> void:
	for index in _action_slots.size():
		var slot := _action_slots[index]
		if slot == null:
			continue
		if _combatant == null:
			slot.clear()
		else:
			slot.set_ability(_combatant, _combatant.get_action_slot_ability_id(index + 1))
	if _passive_slot == null:
		return
	if _combatant == null:
		_passive_slot.clear()
	else:
		_passive_slot.set_ability(_combatant, _combatant.get_passive_slot_id())


## Seed the bars from the combatant's current state so the HUD is correct
## immediately after bind() rather than at the next signal.
func _push_current_values() -> void:
	if not is_instance_valid(_combatant):
		_render_bar(_health_bar, _health_label, 0.0, 0.0)
		_render_bar(_resource_bar, _resource_label, 0.0, 0.0)
		return
	_on_health_changed(_combatant._current_health, _combatant.get_stat(MobaStatBlock.HEALTH))
	_on_resource_changed(_combatant.current_resource, _combatant.maximum_resource)


func _on_health_changed(current: float, maximum: float) -> void:
	_ensure_nodes()
	_render_bar(_health_bar, _health_label, current, maximum)
	_refresh_tooltip()


func _on_resource_changed(current: float, maximum: float) -> void:
	_ensure_nodes()
	_render_bar(_resource_bar, _resource_label, current, maximum)
	_refresh_tooltip()


func _render_bar(bar: TextureProgressBar, label: Label, current: float, maximum: float) -> void:
	if bar != null:
		bar.max_value = maxf(maximum, 0.0)
		bar.value = clampf(current, 0.0, maxf(maximum, 0.0))
	if label != null:
		label.text = "%d / %d" % [roundi(current), roundi(maximum)]


func _on_slot_focus_changed(focused: bool, slot: MobaAbilitySlot) -> void:
	if focused:
		if _focused_slot != null and _focused_slot != slot and is_instance_valid(_focused_slot):
			_focused_slot.set_focused(false)
		_focused_slot = slot
	elif _focused_slot == slot:
		_focused_slot = null
	_refresh_tooltip()


## The tooltip renders from the focused-slot state only. Hover reaches it by
## setting focus on a slot, never by touching this panel directly.
func _refresh_tooltip() -> void:
	if _tooltip == null:
		return
	if _focused_slot == null or not is_instance_valid(_focused_slot):
		_tooltip.visible = false
		return
	_tooltip.visible = true
	if _tooltip_name != null:
		_tooltip_name.text = _tooltip_title(_focused_slot)
	if _tooltip_status != null:
		_tooltip_status.text = _tooltip_body(_focused_slot)


func _tooltip_title(slot: MobaAbilitySlot) -> String:
	var ability := _slot_ability(slot)
	if ability == null:
		return MobaAbilitySlot.EMPTY_NAME_PLACEHOLDER
	if ability.name == "":
		return String(slot.get_ability_id())
	return ability.name


## What the ability is currently doing for the player: its readiness right now,
## plus a summary read straight off the MobaAbility resource.
func _tooltip_body(slot: MobaAbilitySlot) -> String:
	var ability := _slot_ability(slot)
	if ability == null:
		return EMPTY_TOOLTIP_STATUS

	var ability_id := slot.get_ability_id()
	var lines: Array[String] = [_readiness_line(ability_id)]

	var charges_maximum: int = maxi(ability.charges, _combatant.get_max_charges(ability_id))
	if charges_maximum > 1:
		lines.append("Charges: %d / %d" % [_combatant.get_charges(ability_id), charges_maximum])
	if ability.base_damage > 0.0:
		lines.append("Damage: %d" % roundi(ability.base_damage))
	if ability.resource_cost > 0.0:
		lines.append("Cost: %d" % roundi(ability.resource_cost))
	if ability.cooldown > 0.0:
		lines.append("Cooldown: %.1fs" % ability.cooldown)

	return "\n".join(lines)


func _readiness_line(ability_id: StringName) -> String:
	var remaining: float = _combatant.get_cooldown_remaining(ability_id)
	if remaining > 0.0:
		return "Recharging: %.1fs" % remaining
	match _combatant.can_activate(ability_id):
		MobaCombatant.ActivationFailure.OK:
			return "Ready"
		MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE:
			return "Not enough resource"
		MobaCombatant.ActivationFailure.NO_CHARGES:
			return "No charges"
		MobaCombatant.ActivationFailure.ON_COOLDOWN:
			return "On cooldown"
		_:
			return "Unavailable"


func _slot_ability(slot: MobaAbilitySlot) -> MobaAbility:
	if slot == null or not is_instance_valid(slot) or slot.is_empty():
		return null
	if not is_instance_valid(_combatant):
		return null
	return _combatant.get_ability(slot.get_ability_id())


func _connect_combatant() -> void:
	if not is_instance_valid(_combatant):
		return
	if not _combatant.health_changed.is_connected(_on_health_changed):
		_combatant.health_changed.connect(_on_health_changed)
	if not _combatant.resource_changed.is_connected(_on_resource_changed):
		_combatant.resource_changed.connect(_on_resource_changed)


func _disconnect_combatant() -> void:
	if not is_instance_valid(_combatant):
		_combatant = null
		return
	if _combatant.health_changed.is_connected(_on_health_changed):
		_combatant.health_changed.disconnect(_on_health_changed)
	if _combatant.resource_changed.is_connected(_on_resource_changed):
		_combatant.resource_changed.disconnect(_on_resource_changed)


## Resolves child nodes without requiring the HUD to be inside the scene tree,
## so an owner (or a test) can bind a freshly instantiated HUD before adding it.
func _ensure_nodes() -> void:
	if _nodes_resolved:
		return
	_nodes_resolved = true

	_health_bar = get_node_or_null(^"Layout/BottomBar/Bars/HealthRow/HealthBar")
	_health_label = get_node_or_null(^"Layout/BottomBar/Bars/HealthRow/HealthLabel")
	_resource_bar = get_node_or_null(^"Layout/BottomBar/Bars/ResourceRow/ResourceBar")
	_resource_label = get_node_or_null(^"Layout/BottomBar/Bars/ResourceRow/ResourceLabel")

	_action_slots.clear()
	for index in ACTION_SLOT_COUNT:
		var slot: MobaAbilitySlot = get_node_or_null(
			NodePath("Layout/BottomBar/SlotRow/ActionSlots/Slot%d" % (index + 1))
		)
		if slot == null:
			continue
		_action_slots.append(slot)
		_bind_focus_seam(slot)

	_passive_slot = get_node_or_null(^"Layout/BottomBar/SlotRow/PassiveGroup/PassiveSlot")
	if _passive_slot != null:
		_bind_focus_seam(_passive_slot)

	_tooltip = get_node_or_null(^"Layout/BottomBar/Tooltip")
	_tooltip_name = get_node_or_null(^"Layout/BottomBar/Tooltip/TooltipText/TooltipName")
	_tooltip_status = get_node_or_null(^"Layout/BottomBar/Tooltip/TooltipText/TooltipStatus")


func _bind_focus_seam(slot: MobaAbilitySlot) -> void:
	var callable := _on_slot_focus_changed.bind(slot)
	if not slot.focus_changed.is_connected(callable):
		slot.focus_changed.connect(callable)
