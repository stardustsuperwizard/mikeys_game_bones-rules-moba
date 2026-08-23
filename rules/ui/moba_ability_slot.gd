## One reusable ability slot: name, cooldown sweep, remaining seconds, charges,
## readiness state, and an empty state.
##
## The slot is bound by assignment — set_ability(combatant, ability_id) — and
## never searches the scene tree, so the same scene can be placed in a HUD row
## or a touch arc without change.
##
## Signals in, nothing out: this control only reads from MobaCombatant. It never
## mutates it and never handles activation input. Readiness and affordability
## come from can_activate(); cost is never compared to resource here.
class_name MobaAbilitySlot
extends PanelContainer

## Emitted when the focused state changes. The owner decides what focus means
## (a tooltip, a highlight); the slot renders no tooltip itself.
signal focus_changed(focused: bool)

## Shown in place of an ability name while the slot is empty.
const EMPTY_NAME_PLACEHOLDER := "—"

const _COLOR_EMPTY := Color(0.10, 0.10, 0.12, 0.60)
const _COLOR_READY := Color(0.16, 0.18, 0.22, 0.90)
const _COLOR_COOLDOWN := Color(0.12, 0.14, 0.22, 0.90)
const _COLOR_UNAFFORDABLE := Color(0.26, 0.13, 0.13, 0.90)
const _MODULATE_NORMAL := Color(1.0, 1.0, 1.0, 1.0)
const _MODULATE_DIMMED := Color(0.55, 0.55, 0.62, 1.0)

var _combatant: MobaCombatant = null
var _ability_id: StringName = &""
var _focused: bool = false
var _unaffordable: bool = false

var _background: ColorRect = null
var _sweep: TextureProgressBar = null
var _name_label: Label = null
var _cooldown_label: Label = null
var _charge_label: Label = null


func _ready() -> void:
	_ensure_nodes()
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	refresh()


## Cooldown remaining is the only per-frame poll. Affordability refreshes on
## the combatant's resource_changed signal instead.
func _process(_delta: float) -> void:
	if is_empty():
		return
	_refresh_cooldown()


## Bind this slot to one ability on one combatant. Passing an empty ability id
## or an invalid combatant renders the empty state.
func set_ability(combatant: MobaCombatant, ability_id: StringName) -> void:
	_disconnect_combatant()
	if ability_id == &"" or not is_instance_valid(combatant):
		_combatant = null
		_ability_id = &""
	else:
		_combatant = combatant
		_ability_id = ability_id
		_connect_combatant()
	refresh()


## Unbind the slot and render the empty state.
func clear() -> void:
	set_ability(null, &"")


## True when no ability is bound.
func is_empty() -> bool:
	return _ability_id == &"" or not is_instance_valid(_combatant)


## The bound ability id, or &"" when the slot is empty.
func get_ability_id() -> StringName:
	return _ability_id


## Public focus seam. Mouse enter/exit drive this; a gamepad or touch trigger
## can drive it later without the slot knowing which.
func set_focused(focused: bool) -> void:
	if _focused == focused:
		return
	_focused = focused
	_apply_state()
	focus_changed.emit(_focused)


func is_focused() -> bool:
	return _focused


## Re-render every part of the slot. Called on binding changes; per-frame
## updates use the narrower cooldown refresh.
func refresh() -> void:
	_ensure_nodes()
	if is_empty() or _get_ability() == null:
		_render_empty()
		return
	_name_label.text = _display_name()
	_refresh_affordability()
	_refresh_cooldown()


func _get_ability() -> MobaAbility:
	if not is_instance_valid(_combatant):
		return null
	return _combatant.get_ability(_ability_id)


func _display_name() -> String:
	var ability := _get_ability()
	if ability == null or ability.name == "":
		return String(_ability_id)
	return ability.name


func _render_empty() -> void:
	_unaffordable = false
	_name_label.text = EMPTY_NAME_PLACEHOLDER
	_cooldown_label.text = "0.0"
	_cooldown_label.visible = false
	_charge_label.text = ""
	_charge_label.visible = false
	_sweep.value = 0.0
	_sweep.visible = false
	_apply_state()


## Cooldown- and charge-derived rendering: the sweep, the remaining-seconds
## readout, and the charge count.
func _refresh_cooldown() -> void:
	var ability := _get_ability()
	if ability == null:
		_render_empty()
		return

	var remaining: float = _combatant.get_cooldown_remaining(_ability_id)
	var duration: float = _combatant.get_cooldown_duration(_ability_id)
	_cooldown_label.text = "%.1f" % remaining
	_cooldown_label.visible = remaining > 0.0
	_sweep.visible = remaining > 0.0
	_sweep.value = clampf(remaining / duration, 0.0, 1.0) if duration > 0.0 else 0.0

	var ledger_maximum: int = _combatant.get_max_charges(_ability_id)
	var maximum_charges: int = maxi(ability.charges, ledger_maximum)
	_charge_label.visible = maximum_charges > 1
	if maximum_charges > 1:
		var available: int = (
			_combatant.get_charges(_ability_id) if ledger_maximum > 0 else ability.charges
		)
		_charge_label.text = str(available)

	_apply_state()


## Affordability-derived rendering. Never compares cost to resource itself.
func _refresh_affordability() -> void:
	if is_empty():
		return
	var failure: int = _combatant.can_activate(_ability_id)
	_unaffordable = failure == MobaCombatant.ActivationFailure.INSUFFICIENT_RESOURCE
	_apply_state()


func _apply_state() -> void:
	var colour := _COLOR_EMPTY
	if not is_empty():
		if _unaffordable:
			colour = _COLOR_UNAFFORDABLE
		elif _sweep.visible:
			colour = _COLOR_COOLDOWN
		else:
			colour = _COLOR_READY
	if _focused:
		colour = colour.lightened(0.2)
	_background.color = colour
	modulate = _MODULATE_DIMMED if _unaffordable else _MODULATE_NORMAL


func _on_resource_changed(_current: float, _maximum: float) -> void:
	_refresh_affordability()


func _on_mouse_entered() -> void:
	set_focused(true)


func _on_mouse_exited() -> void:
	set_focused(false)


func _connect_combatant() -> void:
	if not is_instance_valid(_combatant):
		return
	if not _combatant.resource_changed.is_connected(_on_resource_changed):
		_combatant.resource_changed.connect(_on_resource_changed)


func _disconnect_combatant() -> void:
	if not is_instance_valid(_combatant):
		return
	if _combatant.resource_changed.is_connected(_on_resource_changed):
		_combatant.resource_changed.disconnect(_on_resource_changed)


## Resolves child nodes without requiring the slot to be inside the scene tree,
## so an owner can bind a freshly instantiated slot before adding it.
func _ensure_nodes() -> void:
	if _background != null:
		return
	_background = get_node_or_null(^"Background") as ColorRect
	_sweep = get_node_or_null(^"CooldownSweep") as TextureProgressBar
	_name_label = get_node_or_null(^"NameLabel") as Label
	_cooldown_label = get_node_or_null(^"CooldownLabel") as Label
	_charge_label = get_node_or_null(^"ChargeLabel") as Label
