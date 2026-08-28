## A standalone target frame showing a bound target's name, health, and shields.
##
## Displays the current target's name (resolved from the target actor), health bar,
## and shields overlaid on the health bar. The frame is hidden when no target is
## bound and defensively hides itself if the bound target becomes invalid or dies.
##
## Signals in, nothing out: this frame observes; it never mutates the target.
class_name MobaTargetFrame
extends Control

var _combatant: MobaCombatant = null

var _target_name: Label = null
var _health_bar: TextureProgressBar = null
var _health_label: Label = null
var _shield_bar: ProgressBar = null

var _nodes_resolved: bool = false


func _ready() -> void:
	_ensure_nodes()
	visible = false


## Defensive check during _process: the bound combatant's actor may be freed,
## or the combatant may die. Hide ourselves when that happens.
func _process(_delta: float) -> void:
	if _combatant != null and not is_instance_valid(_combatant):
		unbind()
		return

	if _combatant != null and not _combatant.is_alive():
		unbind()
		return


## Bind the frame to one combatant. Rebinding is explicit: any previous
## connections are dropped before the new ones are made, so calling bind()
## twice leaves exactly one connection per signal and produces no duplicate
## updates.
func bind(combatant: MobaCombatant) -> void:
	_ensure_nodes()
	_disconnect_combatant()
	_combatant = combatant if is_instance_valid(combatant) else null
	_connect_combatant()
	_push_current_values()
	visible = _combatant != null


## Drop the binding and hide the frame.
func unbind() -> void:
	bind(null)


## The currently bound combatant, or null.
func get_combatant() -> MobaCombatant:
	return _combatant


## Retrieve the target's actor name from the parent Actor node.
func _get_target_name() -> String:
	if not is_instance_valid(_combatant):
		return ""

	var actor := _combatant.get_parent() as Actor
	if not is_instance_valid(actor):
		return ""

	if actor.character_sheet and actor.character_sheet.display_name:
		return actor.character_sheet.display_name

	return actor.name


## Seed the bars from the combatant's current state so the frame is correct
## immediately after bind() rather than at the next signal.
func _push_current_values() -> void:
	if not is_instance_valid(_combatant):
		_render_target_name("")
		_render_bar(0.0, 0.0)
		_render_shield(0.0)
		return

	_render_target_name(_get_target_name())
	_on_health_changed(_combatant.current_health, _combatant.maximum_health)
	_on_shield_changed(_combatant.total_shield())


func _on_health_changed(current: float, maximum: float) -> void:
	_ensure_nodes()
	_render_bar(current, maximum)


func _on_shield_changed(total: float) -> void:
	_ensure_nodes()
	_render_shield(total)


func _render_target_name(name_text: String) -> void:
	if _target_name != null:
		_target_name.text = name_text


func _render_bar(current: float, maximum: float) -> void:
	if _health_bar != null:
		_health_bar.max_value = maxf(maximum, 0.0)
		_health_bar.value = clampf(current, 0.0, maxf(maximum, 0.0))
	if _health_label != null:
		_health_label.text = "%d / %d" % [roundi(current), roundi(maximum)]


func _render_shield(total: float) -> void:
	if _shield_bar != null:
		# Shield bar shows from where health ends to the full potential (health + shield)
		# If combatant is not valid, show empty
		if not is_instance_valid(_combatant):
			_shield_bar.visible = false
			return

		var max_health := _combatant.maximum_health
		if max_health <= 0.0:
			_shield_bar.visible = false
			return

		# Shield bar maximum is set to max_health, but value represents the shield amount
		# This creates an overlay effect where the shield bar starts where health ends
		_shield_bar.max_value = maxf(max_health, 0.0)
		_shield_bar.value = clampf(total, 0.0, maxf(max_health, 0.0))
		_shield_bar.visible = total > 0.0


func _connect_combatant() -> void:
	if not is_instance_valid(_combatant):
		return
	if not _combatant.health_changed.is_connected(_on_health_changed):
		_combatant.health_changed.connect(_on_health_changed)
	if not _combatant.shield_changed.is_connected(_on_shield_changed):
		_combatant.shield_changed.connect(_on_shield_changed)


func _disconnect_combatant() -> void:
	if not is_instance_valid(_combatant):
		_combatant = null
		return
	if _combatant.health_changed.is_connected(_on_health_changed):
		_combatant.health_changed.disconnect(_on_health_changed)
	if _combatant.shield_changed.is_connected(_on_shield_changed):
		_combatant.shield_changed.disconnect(_on_shield_changed)


## Resolves child nodes without requiring the frame to be inside the scene tree,
## so an owner (or a test) can bind a freshly instantiated frame before adding it.
func _ensure_nodes() -> void:
	if _nodes_resolved:
		return
	_nodes_resolved = true

	_target_name = get_node_or_null(^"VBoxContainer/NameLabel")
	_health_bar = get_node_or_null(^"VBoxContainer/HealthContainer/HealthBar")
	_health_label = get_node_or_null(^"VBoxContainer/HealthContainer/HealthLabel")
	_shield_bar = get_node_or_null(^"VBoxContainer/HealthContainer/ShieldBar")
