## A read-only panel showing another present player's submitted character build:
## Disciplines, weapon, the four action slots, the passive slot, and the stat
## allocation, as the server reported them.
##
## Read-only in the strict sense. Nothing here writes to a build, and nothing
## here reaches a MobaCombatant: the panel renders one Dictionary the server
## sent and owns no game state of its own. Editing a build is
## scripts/character_creation.gd's own, unrelated screen.
##
## Follows scripts/character_creation.gd's standard for this family of game-flow
## UI: every interactive control is focusable for gamepad and keyboard
## navigation and sized for touch, and no affordance depends on a hover state --
## the peer buttons and the close button are the only interactive controls, and
## both are reachable by focus alone.
class_name LobbyBuildInspector
extends Control

## Discipline enum constant strings for display (indexed by enum value).
##
## A small duplicate of the array scripts/character_creation.gd keeps for the
## same purpose. That file carries no class_name -- it is a screen script, not a
## shared type -- so there is nothing to import the mapping from, and copying six
## strings is the expected shape here rather than a defect to fix by giving an
## unrelated screen a global name.
const DISCIPLINE_NAMES := ["Warrior", "Guardian", "Slayer", "Marksman", "Mystic", "Adventurer"]

## The minimum size every interactive control is given, so a control is a usable
## touch target rather than a mouse-sized one. Matches character_creation.gd's
## own constant of the same name and purpose.
const TOUCH_TARGET_SIZE := Vector2(60, 60)

var _character_name_label: Label
var _primary_discipline_label: Label
var _secondary_discipline_label: Label
var _weapon_label: Label
var _action_slot_labels: Array[Label] = []
var _passive_slot_label: Label
var _stats_container: VBoxContainer
var _detail_container: VBoxContainer
var _peers_container: VBoxContainer
var _close_button: Button

# The lobby this panel inspects through, set by bind_lobby().
var _lobby_manager: LobbyManager


func _ready() -> void:
	_resolve_controls()

	# Found by path rather than exported so the scene stays instantiable on its
	# own; binding is a separate step so the wiring is exercised the same way
	# whether the lobby is found here or handed over directly.
	bind_lobby(get_node_or_null(^"../../LobbyManager") as LobbyManager)

	# The panel stays on screen: it carries the only affordance for selecting a
	# peer, so hiding it would leave the request path unreachable in a running
	# game. Only the read-out for one build is hidden until a reply arrives.
	if _detail_container != null:
		_detail_container.hide()


## Point this panel at a lobby, connecting the signals it needs and rebuilding
## the peer list. Safe to call again with a different lobby, or with null.
func bind_lobby(lobby_manager: LobbyManager) -> void:
	if _lobby_manager == lobby_manager:
		refresh_peer_list()
		return

	if _lobby_manager != null and is_instance_valid(_lobby_manager):
		_lobby_manager.build_inspection_received.disconnect(_on_build_inspection_received)
		_lobby_manager.child_entered_tree.disconnect(_on_lobby_presence_changed)
		_lobby_manager.child_exiting_tree.disconnect(_on_lobby_presence_changed)

	_lobby_manager = lobby_manager

	if _lobby_manager != null:
		_lobby_manager.build_inspection_received.connect(_on_build_inspection_received)

		# Presence changes after _ready(), on both routes: the host spawns remote
		# avatars as peers connect, and a client receives them through the
		# spawner. Watching the lobby's children covers both, where connecting to
		# multiplayer.peer_connected alone would miss the replicated case. Without
		# this the list is whatever existed for one frame at startup -- on a host,
		# only its own avatar, which is never offered.
		_lobby_manager.child_entered_tree.connect(_on_lobby_presence_changed)
		_lobby_manager.child_exiting_tree.connect(_on_lobby_presence_changed)

	refresh_peer_list()


# A child entering or leaving the lobby is a peer arriving or going. Deferred
# because child_exiting_tree fires while the departing avatar is still parented,
# so refreshing now would re-list the peer that is on its way out.
func _on_lobby_presence_changed(_child: Node) -> void:
	refresh_peer_list.call_deferred()


## Rebuild the "inspect this peer" list from the lobby avatars currently present.
##
## Sourced from the avatars already in the scene tree, which every peer has:
## presence is what the lobby replicates, so a client can enumerate who is here
## without build data being pushed to it. This is what keeps inspection a pull.
func refresh_peer_list() -> void:
	if _peers_container == null:
		return

	for child in _peers_container.get_children():
		if child.name != "PeersLabel":
			_peers_container.remove_child(child)
			child.queue_free()

	for avatar in _inspectable_avatars():
		_peers_container.add_child(_make_peer_button(avatar))


## Ask the server for a peer's build. The answer arrives asynchronously on
## LobbyManager.build_inspection_received, never as a return value here.
func inspect_peer(peer_id: int) -> void:
	if _lobby_manager == null:
		return

	_lobby_manager.try_inspect_build(peer_id)


# The lobby avatars this panel offers to inspect: every one present except this
# peer's own. Read off the avatars themselves rather than from a replicated
# roster, for the reason refresh_peer_list() gives.
func _inspectable_avatars() -> Array[Actor]:
	var avatars: Array[Actor] = []
	if _lobby_manager == null:
		return avatars

	var local_id := 1
	if _lobby_manager.multiplayer != null:
		local_id = _lobby_manager.multiplayer.get_unique_id()

	var seen: Array[int] = []
	for child in _lobby_manager.get_children():
		var actor := child as Actor
		if actor != null and actor.owner_id != local_id and actor.owner_id not in seen:
			seen.append(actor.owner_id)
			avatars.append(actor)

	return avatars


# One focusable, touch-sized button per inspectable peer. A Button is used
# precisely because it is operable by focus plus ui_accept on a gamepad, by
# Enter on a keyboard, and by a tap -- none of which is a hover.
func _make_peer_button(avatar: Actor) -> Button:
	var button := Button.new()
	button.text = _avatar_display_name(avatar)
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = TOUCH_TARGET_SIZE
	button.pressed.connect(inspect_peer.bind(avatar.owner_id))
	return button


# The name the avatar already displays above itself in the lobby, so the roster
# and the world agree on who a player is. The peer id is a fallback for an
# avatar with no sheet applied, not the normal case: a character here is the
# player's own, named and kept, and identifying them by connection number is a
# worse answer whenever a real name exists.
func _avatar_display_name(avatar: Actor) -> String:
	var sheet := avatar.character_sheet
	if sheet != null and sheet.character_name != "":
		return sheet.character_name

	return "Peer %d" % avatar.owner_id


# Resolve the authored controls once, and enforce the focus/touch standard in
# code as well as in the scene, so a control added to the scene later cannot
# quietly ship un-focusable.
func _resolve_controls() -> void:
	var box := get_node_or_null(^"Panel/VBoxContainer")
	if box == null:
		return

	_peers_container = box.get_node_or_null(^"PeersContainer")
	_detail_container = box.get_node_or_null(^"DetailContainer")
	if _detail_container == null:
		return

	_character_name_label = _detail_container.get_node_or_null(^"CharacterNameLabel")
	_weapon_label = _detail_container.get_node_or_null(^"WeaponLabel")
	_passive_slot_label = _detail_container.get_node_or_null(^"PassiveLabel")
	_stats_container = _detail_container.get_node_or_null(^"StatsContainer")
	_close_button = _detail_container.get_node_or_null(^"CloseButton")

	var disciplines := _detail_container.get_node_or_null(^"DisciplinesContainer")
	if disciplines != null:
		_primary_discipline_label = disciplines.get_node_or_null(^"PrimaryDisciplineLabel")
		_secondary_discipline_label = disciplines.get_node_or_null(^"SecondaryDisciplineLabel")

	var actions := _detail_container.get_node_or_null(^"ActionsContainer")
	if actions != null:
		for i in range(4):
			var label := actions.get_node_or_null("Action%dLabel" % (i + 1)) as Label
			if label != null:
				_action_slot_labels.append(label)

	if _close_button != null:
		_close_button.focus_mode = Control.FOCUS_ALL
		_close_button.custom_minimum_size = TOUCH_TARGET_SIZE
		_close_button.pressed.connect(_on_close_pressed)


# The reply to try_inspect_build(), from the server or from this host's own
# local resolve. An empty payload is the explicit "that peer is not present"
# answer, which is rendered rather than left as a panel that never opens.
func _on_build_inspection_received(encoded_build: Dictionary) -> void:
	if encoded_build.is_empty():
		_show_not_present()
	else:
		_display_build(encoded_build)

	if _detail_container != null:
		_detail_container.show()

	# Put focus somewhere reachable the moment the panel opens, so a gamepad or
	# keyboard user is never left with focus on a control behind the panel.
	if _close_button != null:
		_close_button.grab_focus()


func _display_build(encoded_build: Dictionary) -> void:
	if _character_name_label != null:
		_character_name_label.text = str(encoded_build.get("character_name", ""))

	if _primary_discipline_label != null:
		var primary: int = encoded_build.get("primary_discipline", -1)
		_primary_discipline_label.text = "Primary: %s" % _discipline_name(primary)

	if _secondary_discipline_label != null:
		var secondary: int = encoded_build.get("secondary_discipline", -1)
		_secondary_discipline_label.text = "Secondary: %s" % _discipline_name(secondary)

	if _weapon_label != null:
		var weapon_path: String = encoded_build.get("weapon_path", "")
		_weapon_label.text = "Weapon: %s" % _weapon_name(weapon_path)

	var action_slots: PackedStringArray = encoded_build.get("action_slots", PackedStringArray())
	for i in range(_action_slot_labels.size()):
		var ability_id := "" if i >= action_slots.size() else action_slots[i]
		_action_slot_labels[i].text = "Action %d: %s" % [i + 1, _ability_name(ability_id)]

	if _passive_slot_label != null:
		var passive_id: String = encoded_build.get("passive_slot", "")
		_passive_slot_label.text = "Passive: %s" % _ability_name(passive_id)

	_display_stat_allocation(encoded_build.get("stat_allocation", {}))


# Discipline enum int -> display string, tolerating a value outside the array
# rather than indexing past its end.
func _discipline_name(discipline: int) -> String:
	if discipline < 0 or discipline >= DISCIPLINE_NAMES.size():
		return "Unknown"
	return DISCIPLINE_NAMES[discipline]


# A weapon's display name comes from its authored file name, because MobaWeapon
# carries no name field of its own -- it is damage, speed, range and nothing
# else. The path is what _encode_build_for_inspection() sends, so this is the
# only naming information the panel actually has.
func _weapon_name(weapon_path: String) -> String:
	if weapon_path == "":
		return "None"
	return weapon_path.get_file().get_basename().capitalize()


# Ability id -> display name through the shared library, which is the one place
# that mapping lives. An id the library does not know still renders as itself
# rather than blanking the slot.
func _ability_name(ability_id: String) -> String:
	if ability_id == "":
		return "None"

	var ability := MobaAbilityLibrary.get_ability(StringName(ability_id))
	if ability != null and ability.name != "":
		return ability.name

	return ability_id.capitalize()


func _display_stat_allocation(stat_allocation: Dictionary) -> void:
	if _stats_container == null:
		return

	for child in _stats_container.get_children():
		if child.name != "StatsLabel":
			_stats_container.remove_child(child)
			child.queue_free()

	# Keys arrive as StringName (MobaCharacterBuild types the allocation
	# Dictionary[StringName, int]) and are formatted through str(), not iterated
	# as String, which would not match the key type.
	# Every submitted entry is rendered, including an explicit 0. The Issue asks
	# for the full allocation, and dropping a zero would show a build the player
	# did not submit -- a stat they deliberately left at baseline reads the same
	# as one they never allocated at all.
	for stat_name in stat_allocation:
		var value: int = stat_allocation[stat_name]
		var stat_label := Label.new()
		stat_label.text = "%s: %s" % [str(stat_name).capitalize(), _signed(value)]
		_stats_container.add_child(stat_label)


# A signed allocation reads as a delta on the baseline, except at 0, where "+0"
# would be noise.
func _signed(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return "%d" % value


func _show_not_present() -> void:
	if _character_name_label != null:
		_character_name_label.text = "That player is no longer in the lobby."

	for label in _action_slot_labels:
		label.text = ""

	if _primary_discipline_label != null:
		_primary_discipline_label.text = ""
	if _secondary_discipline_label != null:
		_secondary_discipline_label.text = ""
	if _weapon_label != null:
		_weapon_label.text = ""
	if _passive_slot_label != null:
		_passive_slot_label.text = ""

	_display_stat_allocation({})


func _on_close_pressed() -> void:
	if _detail_container != null:
		_detail_container.hide()

	# Hand focus back to the list the panel was opened from, so closing does not
	# strand a gamepad or keyboard user on a control that just disappeared.
	if _peers_container != null:
		for child in _peers_container.get_children():
			var button := child as Button
			if button != null:
				button.grab_focus()
				return
