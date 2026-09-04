# Headless integration test for #375: a build's appearance reaches every spawned
# Actor, in the arena and in the lobby, as a replicated reference made of plain
# String ids.
#
# Run with:
#   godot --headless --path . --script tests/appearance_replication_test.gd
#
# Covers, in order:
#   - WorldManager._encode_build() carries the three appearance ids as plain
#     Strings, and the payload holds no Object anywhere;
#   - the appearance round-trips through encode + var_to_bytes + decode with its
#     ids intact, which is the check that fails if a MobaAppearance is ever put
#     in the payload directly;
#   - the actor spawned for a peer with an accepted build carries that build's
#     appearance;
#   - a spawn with no build -- world and bot content -- leaves Actor.appearance
#     at its default null, the way color and loadout are already left alone;
#   - PeerIdentityRegistry._copy_accepted() deep-copies the appearance, so
#     editing the submitted object afterwards cannot reach authoritative state;
#   - a refused resubmission carrying a different appearance leaves the
#     previously accepted appearance on the next spawn;
#   - LobbyManager applies the peer's registered appearance to the lobby avatar;
#   - LobbyManager._encode_build_for_inspection() carries the same three ids as
#     plain Strings;
#   - LobbyBuildInspector renders a human-readable line per id, and clears all
#     three when the inspected peer is not present.
#
# The "plain String" checks are the multiplayer half, and the reason they are
# asserted rather than eyeballed. SceneMultiplayer.allow_object_decoding is off,
# so a Resource anywhere in a spawn or RPC payload encodes as null and is gone on
# arrival -- working perfectly in single-player and giving every remote peer the
# scene's default appearance instead of the character standing there.
#
# This test is NOT wired into tests/test_bootstrap.gd: it loads game scenes, a
# WorldManager and a LobbyManager, matching the precedent set by
# tests/build_spawn_integration_test.gd and tests/lobby_manager_test.gd.
extends SceneTree

const _PLAYER_SPAWN_POINT := preload("res://resources/player_spawn_point.tres")
const _ENEMY_SPAWN_POINT := preload("res://resources/enemy_spawn_point.tres")
const _LOBBY_SPAWN_POINT := preload("res://resources/lobby_player_spawn_point.tres")
const _FALLBACK_BUILD := preload("res://rules/data/builds/melee_bruiser_build.tres")
const _PANEL_SCENE := preload("res://scenes/lobby/build_inspector_panel.tscn")

# Catalog ids, taken from rules/data/appearance/catalog.json. Authored values
# rather than invented ones, because MobaBuildValidator now validates the
# appearance on submission and an unknown id would be refused.
const _HELM := &"iron_helm"
const _CHEST := &"leather_chest"
const _SCHEME := &"azure"

# The second, deliberately different appearance a refused resubmission carries.
const _OTHER_HELM := &"basic_helm"
const _OTHER_CHEST := &"basic_chest"
const _OTHER_SCHEME := &"crimson"

# One peer id per check. PeerIdentityRegistry is an autoload and outlives every
# WorldManager built here, so a shared id would let one check pass on state an
# earlier one left behind.
const _PEER_SPAWN := 41
const _PEER_SNAPSHOT := 42
const _PEER_REFUSAL := 43
const _PEER_LOBBY := 44
const _PEER_INSPECT := 45

const _EXPECTED_CHECKS: Array[String] = [
	"spawn payload carries appearance ids as plain strings",
	"appearance survives the spawn payload intact",
	"accepted build's appearance reaches the spawned actor",
	"a spawn with no build leaves the actor's appearance unset",
	"accepted appearance is deep-copied from the submitter's",
	"a refused resubmission leaves the accepted appearance in place",
	"lobby avatar carries the peer's registered appearance",
	"inspection payload carries appearance ids as plain strings",
	"the panel renders and clears a line per appearance id",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	_test_spawn_payload_ids_are_plain_strings()
	_test_appearance_survives_spawn_payload()
	_test_appearance_reaches_spawned_actor()
	_test_buildless_spawn_has_no_appearance()
	_test_accepted_appearance_is_deep_copied()
	_test_refusal_preserves_accepted_appearance()
	_test_lobby_avatar_carries_appearance()
	_test_inspection_payload_ids_are_plain_strings()
	await _test_panel_renders_appearance()

	_finish()


## A WorldManager with no MultiplayerSpawner, so spawn() falls through to
## _spawn_actor() -- the same function the spawner calls in the real scene.
func _make_world_manager() -> WorldManager:
	var world_manager := WorldManager.new()
	world_manager.player_spawn_point = _PLAYER_SPAWN_POINT
	root.add_child(world_manager)
	return world_manager


## A LobbyManager with no MultiplayerSpawner, matching lobby_manager_test.gd.
func _make_lobby_manager() -> LobbyManager:
	var lobby_manager := LobbyManager.new()
	lobby_manager.avatar_spawn_point = _LOBBY_SPAWN_POINT
	root.add_child(lobby_manager)
	return lobby_manager


## Spawn a player actor for a peer through the real WorldManager path and parent
## it, so _ready() runs exactly as a spawned actor's does.
func _spawn_player(world_manager: WorldManager, peer_id: int) -> Actor:
	world_manager.spawn_player_for_peer(peer_id)
	var actor: Actor = world_manager._peer_actors.get(peer_id)
	if actor != null and actor.get_parent() == null:
		world_manager.add_child(actor)
	return actor


## Free a peer's actor and respawn it, so the accepted build is what spawn
## initialization reads.
func _respawn_player(world_manager: WorldManager, peer_id: int) -> Actor:
	var existing: Actor = world_manager._peer_actors.get(peer_id)
	if existing != null:
		existing.queue_free()
	world_manager._peer_actors.erase(peer_id)
	return _spawn_player(world_manager, peer_id)


## Spawn a lobby avatar and parent it, the way a spawner-driven avatar is.
func _spawn_avatar(lobby_manager: LobbyManager, peer_id: int) -> Actor:
	lobby_manager.spawn_avatar_for_peer(peer_id)
	var actor: Actor = lobby_manager._peer_avatars.get(peer_id)
	if actor != null and actor.get_parent() == null:
		lobby_manager.add_child(actor)
	return actor


## A legal WARRIOR/GUARDIAN build, shaped like build_spawn_integration_test.gd's,
## carrying an appearance built from catalog ids.
func _make_legal_build(
	character_name: String, helm: StringName, chest: StringName, scheme: StringName
) -> MobaCharacterBuild:
	var loadout := MobaLoadout.new()
	loadout.set_action_slot(1, "whirlwind")
	loadout.set_action_slot(2, "shield_bash")
	loadout.weapon = _FALLBACK_BUILD.loadout.weapon

	var appearance := MobaAppearance.new()
	appearance.helm_id = helm
	appearance.chest_id = chest
	appearance.color_scheme_id = scheme

	var build := MobaCharacterBuild.new()
	build.character_name = character_name
	build.primary_discipline = MobaAbility.Discipline.WARRIOR
	build.secondary_discipline = MobaAbility.Discipline.GUARDIAN
	build.stat_allocation = {}
	build.appearance = appearance
	build.loadout = loadout

	return build


## The three ids an appearance carries, as plain Strings, for comparison and for
## reporting a mismatch as a readable triple.
func _ids_of(appearance: MobaAppearance) -> Array[String]:
	if appearance == null:
		return ["<null appearance>"]
	return [
		String(appearance.helm_id), String(appearance.chest_id), String(appearance.color_scheme_id)
	]


## Report every appearance key in a payload whose value is not a plain String,
## as one joined message, or "" when all three are.
##
## typeof() rather than `is String`: a Resource that reached the payload would
## answer `is String` with false but so would an int, and the point is to pin the
## exact wire-safe type each key is specified to hold.
func _typing_problems(payload: Dictionary, label: String) -> String:
	var problems: Array[String] = []

	for key in ["helm_id", "chest_id", "color_scheme_id"]:
		if not payload.has(key):
			problems.append("%s is missing '%s'" % [label, key])
			continue

		var value: Variant = payload[key]
		if value is Object:
			problems.append("%s['%s'] is an Object -- it will not survive the wire" % [label, key])
		elif typeof(value) != TYPE_STRING:
			problems.append(
				"%s['%s'] is type %d, expected a plain String" % [label, key, typeof(value)]
			)

	return "; ".join(problems)


## The path of the first Object found anywhere in a payload, or "" if it is plain
## data all the way down. Recursive: a Resource nested inside an Array or a
## sub-Dictionary is dropped on the wire just as surely as a top-level one.
func _find_object(value: Variant, path: String = "payload") -> String:
	if value is Object:
		return path

	if value is Dictionary:
		for key in value:
			var found := _find_object(value[key], "%s.%s" % [path, key])
			if found != "":
				return found
	elif value is Array:
		for i in range(value.size()):
			var found := _find_object(value[i], "%s[%d]" % [path, i])
			if found != "":
				return found

	return ""


## The spawn payload's appearance keys are plain Strings, and nothing anywhere in
## it is an Object.
func _test_spawn_payload_ids_are_plain_strings() -> void:
	var world_manager := _make_world_manager()
	var build := _make_legal_build("Payload Pat", _HELM, _CHEST, _SCHEME)

	var payload: Dictionary = world_manager._encode_build(build)

	var problems := _typing_problems(payload, "_encode_build()")
	if problems != "":
		_fail_cleanup(problems, [world_manager])
		return

	var offender := _find_object(payload, "build")
	if offender != "":
		_fail_cleanup(
			"spawn payload holds an object at '%s' -- it will not survive the wire" % offender,
			[world_manager]
		)
		return

	_pass("spawn payload carries appearance ids as plain strings")
	world_manager.queue_free()


## Encode, put it through the same var_to_bytes the network layer uses, decode,
## and find the same three ids.
func _test_appearance_survives_spawn_payload() -> void:
	var world_manager := _make_world_manager()
	var build := _make_legal_build("Traveller Tam", _HELM, _CHEST, _SCHEME)

	var wire: Variant = bytes_to_var(var_to_bytes(world_manager._encode_build(build)))
	if not wire is Dictionary:
		_fail_cleanup("spawn payload did not survive var_to_bytes as a Dictionary", [world_manager])
		return

	var decoded: MobaCharacterBuild = world_manager._decode_build(wire as Dictionary)
	if decoded.appearance == null:
		_fail_cleanup("the appearance was lost in the spawn payload", [world_manager])
		return

	if _ids_of(decoded.appearance) != _ids_of(build.appearance):
		_fail_cleanup(
			(
				"decoded appearance is %s, expected %s"
				% [_ids_of(decoded.appearance), _ids_of(build.appearance)]
			),
			[world_manager]
		)
		return

	_pass("appearance survives the spawn payload intact")
	world_manager.queue_free()


## The user-visible half: the actor spawned for the peer carries the appearance
## the server accepted, past the transport boundary the check above stops at.
func _test_appearance_reaches_spawned_actor() -> void:
	var world_manager := _make_world_manager()
	if _spawn_player(world_manager, _PEER_SPAWN) == null:
		_fail_cleanup("setup: player actor did not spawn", [world_manager])
		return

	var build := _make_legal_build("Dressed Dana", _HELM, _CHEST, _SCHEME)
	var result := world_manager.submit_build(_PEER_SPAWN, build)
	if not result.success:
		_fail_cleanup(
			"setup: legal build was refused -- '%s'" % String(result.reason), [world_manager]
		)
		return

	var actor := _respawn_player(world_manager, _PEER_SPAWN)
	if actor == null:
		_fail_cleanup("actor did not respawn after a build was accepted", [world_manager])
		return

	if actor.appearance == null:
		_fail_cleanup("the spawned actor has no appearance at all", [world_manager])
		return

	if _ids_of(actor.appearance) != _ids_of(build.appearance):
		_fail_cleanup(
			(
				"spawned actor's appearance is %s, expected the submitted %s"
				% [_ids_of(actor.appearance), _ids_of(build.appearance)]
			),
			[world_manager]
		)
		return

	_pass("accepted build's appearance reaches the spawned actor")
	world_manager.queue_free()


## World and bot content is spawned with no build at all, and must come out of
## spawn() exactly as its scene authored it -- appearance included.
func _test_buildless_spawn_has_no_appearance() -> void:
	var world_manager := _make_world_manager()

	# Exactly how _ready() spawns world content: no build argument.
	var enemy := world_manager.spawn(_ENEMY_SPAWN_POINT, _ENEMY_SPAWN_POINT.authority_id)
	if enemy == null:
		_fail_cleanup("bot actor did not spawn", [world_manager])
		return
	world_manager.add_child(enemy)

	if enemy.appearance != null:
		_fail_cleanup(
			"a bot spawned with the appearance %s, expected none" % [_ids_of(enemy.appearance)],
			[world_manager]
		)
		return

	_pass("a spawn with no build leaves the actor's appearance unset")
	world_manager.queue_free()


## What validated is what gets stored. A caller that kept its MobaAppearance
## could otherwise swap the helm the server accepted for one it never checked.
func _test_accepted_appearance_is_deep_copied() -> void:
	var world_manager := _make_world_manager()
	if _spawn_player(world_manager, _PEER_SNAPSHOT) == null:
		_fail_cleanup("setup: player actor did not spawn", [world_manager])
		return

	var submitted := _make_legal_build("Snapshot Sal", _HELM, _CHEST, _SCHEME)
	if not world_manager.submit_build(_PEER_SNAPSHOT, submitted).success:
		_fail_cleanup("setup: legal build was refused", [world_manager])
		return

	# Edit the submitter's own appearance object after acceptance. A shallow
	# duplicate() of the build would carry this sub-Resource across as a
	# reference, so these three writes would land in authoritative state.
	submitted.appearance.helm_id = &"tampered_helm"
	submitted.appearance.chest_id = &"tampered_chest"
	submitted.appearance.color_scheme_id = &"tampered_scheme"

	var stored := world_manager.get_peer_build(_PEER_SNAPSHOT)
	if stored.appearance == null:
		_fail_cleanup("the stored build kept no appearance", [world_manager])
		return

	if _ids_of(stored.appearance) != [String(_HELM), String(_CHEST), String(_SCHEME)]:
		_fail_cleanup(
			"stored appearance followed a post-acceptance edit: %s" % [_ids_of(stored.appearance)],
			[world_manager]
		)
		return

	_pass("accepted appearance is deep-copied from the submitter's")
	world_manager.queue_free()


## A refused submission must not cost the peer the appearance it already had --
## the same guarantee build_spawn_integration_test.gd pins for the build as a
## whole, read at the actor the next spawn produces.
func _test_refusal_preserves_accepted_appearance() -> void:
	var world_manager := _make_world_manager()
	if _spawn_player(world_manager, _PEER_REFUSAL) == null:
		_fail_cleanup("setup: player actor did not spawn", [world_manager])
		return

	var accepted := _make_legal_build("Keeper Kai", _HELM, _CHEST, _SCHEME)
	if not world_manager.submit_build(_PEER_REFUSAL, accepted).success:
		_fail_cleanup("setup: legal build was refused", [world_manager])
		return

	# A different appearance on a build that is illegal for an unrelated reason:
	# aimed_shot is MARKSMAN, outside the WARRIOR/GUARDIAN pair. The appearance
	# itself is legal, so what is under test is the refusal path leaving the
	# stored appearance alone rather than half-applying the new one.
	var illegal := _make_legal_build("Usurper Uma", _OTHER_HELM, _OTHER_CHEST, _OTHER_SCHEME)
	illegal.loadout.set_action_slot(3, "aimed_shot")

	var refusal := world_manager.submit_build(_PEER_REFUSAL, illegal)
	if refusal.success:
		_fail_cleanup("an illegal build was accepted", [world_manager])
		return
	if refusal.reason != MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES:
		_fail_cleanup(
			(
				"illegal build refused with '%s', expected '%s'"
				% [
					String(refusal.reason),
					String(MobaBuildValidator.FAILURE_ABILITY_OUTSIDE_DISCIPLINES),
				]
			),
			[world_manager]
		)
		return

	var actor := _respawn_player(world_manager, _PEER_REFUSAL)
	if actor == null:
		_fail_cleanup("actor did not respawn after a refused submission", [world_manager])
		return

	# _ids_of() reports a null appearance as its own triple, so the one comparison
	# covers both "the refusal blanked it" and "the refusal applied the new one".
	if _ids_of(actor.appearance) != [String(_HELM), String(_CHEST), String(_SCHEME)]:
		_fail_cleanup(
			(
				"after a refusal the spawned appearance is %s, expected the accepted %s"
				% [_ids_of(actor.appearance), [String(_HELM), String(_CHEST), String(_SCHEME)]]
			),
			[world_manager]
		)
		return

	_pass("a refused resubmission leaves the accepted appearance in place")
	world_manager.queue_free()


## The lobby avatar is dressed the same way the match actor is, so the character
## standing in the lobby is the character that walks into the arena.
func _test_lobby_avatar_carries_appearance() -> void:
	var world_manager := _make_world_manager()
	if _spawn_player(world_manager, _PEER_LOBBY) == null:
		_fail_cleanup("setup: player actor did not spawn", [world_manager])
		return

	var build := _make_legal_build("Lobby Lou", _HELM, _CHEST, _SCHEME)
	if not world_manager.submit_build(_PEER_LOBBY, build).success:
		_fail_cleanup("setup: legal build was refused", [world_manager])
		return

	var lobby_manager := _make_lobby_manager()
	var avatar := _spawn_avatar(lobby_manager, _PEER_LOBBY)
	if avatar == null:
		_fail_cleanup("lobby avatar did not spawn", [world_manager, lobby_manager])
		return

	if avatar.appearance == null:
		_fail_cleanup("the lobby avatar has no appearance at all", [world_manager, lobby_manager])
		return

	if _ids_of(avatar.appearance) != _ids_of(build.appearance):
		_fail_cleanup(
			(
				"lobby avatar's appearance is %s, expected the registered %s"
				% [_ids_of(avatar.appearance), _ids_of(build.appearance)]
			),
			[world_manager, lobby_manager]
		)
		return

	_pass("lobby avatar carries the peer's registered appearance")
	world_manager.queue_free()
	lobby_manager.queue_free()


## The inspection reply keeps the same discipline as the spawn payload: three
## plain Strings, and no Resource anywhere.
func _test_inspection_payload_ids_are_plain_strings() -> void:
	var registry := root.get_node_or_null(^"/root/PeerIdentityRegistry")
	if registry == null:
		_fail("setup: PeerIdentityRegistry autoload not found")
		return

	var lobby_manager := _make_lobby_manager()
	var avatar := _spawn_avatar(lobby_manager, _PEER_INSPECT)
	if avatar == null:
		_fail_cleanup("setup: lobby avatar did not spawn", [lobby_manager])
		return

	var build := _make_legal_build("Inspected Ines", _HELM, _CHEST, _SCHEME)
	var submission: ActionResult = registry.submit_build(
		_PEER_INSPECT, avatar, build, _PEER_INSPECT
	)
	if not submission.success:
		_fail_cleanup(
			"setup: legal build was refused (%s)" % String(submission.reason), [lobby_manager]
		)
		return

	# Through _resolve_inspect_build(), not the encoder directly, so the check
	# covers the payload a requesting peer would actually receive.
	var payload := lobby_manager._resolve_inspect_build(_PEER_INSPECT)
	if payload.is_empty():
		_fail_cleanup("a present peer resolved to an empty inspection result", [lobby_manager])
		return

	# The keyed type check and the whole-payload object sweep are reported
	# together: two early returns here would put this function over gdlint's
	# max-returns, and a payload that fails either is broken the same way.
	var problems := _typing_problems(payload, "_encode_build_for_inspection()")
	var offender := _find_object(payload, "inspection")
	if offender != "":
		problems += "; inspection payload holds an object at '%s'" % offender
	if problems != "":
		_fail_cleanup(problems, [lobby_manager])
		return

	if (
		payload["helm_id"] != String(_HELM)
		or payload["chest_id"] != String(_CHEST)
		or payload["color_scheme_id"] != String(_SCHEME)
	):
		_fail_cleanup(
			(
				"inspection payload reports %s, expected %s"
				% [
					[payload["helm_id"], payload["chest_id"], payload["color_scheme_id"]],
					[String(_HELM), String(_CHEST), String(_SCHEME)],
				]
			),
			[lobby_manager]
		)
		return

	_pass("inspection payload carries appearance ids as plain strings")
	lobby_manager.queue_free()


## The panel shows a readable line for each id, and clears all three when the
## inspected peer turns out not to be present -- a stale helm left on screen
## under "That player is no longer in the lobby" would read as that player's.
func _test_panel_renders_appearance() -> void:
	var lobby_manager := _make_lobby_manager()
	var panel := _PANEL_SCENE.instantiate() as LobbyBuildInspector
	root.add_child(panel)
	await process_frame

	var build := _make_legal_build("Rendered Rhys", _HELM, _CHEST, _SCHEME)
	panel._display_build(lobby_manager._encode_build_for_inspection(build))

	var labels := {
		"helm": panel._helm_label,
		"chest": panel._chest_label,
		"colour scheme": panel._color_scheme_label,
	}

	var missing: Array[String] = []
	for name: String in labels:
		if labels[name] == null:
			missing.append("the %s label was never resolved from the scene" % name)
	if not missing.is_empty():
		_fail_cleanup("; ".join(missing), [lobby_manager, panel])
		return

	# Capitalize() is what turns an id into the displayed name, so the assertion
	# is on the displayed form rather than on the raw id.
	var expected := {
		"helm": String(_HELM).capitalize(),
		"chest": String(_CHEST).capitalize(),
		"colour scheme": String(_SCHEME).capitalize(),
	}

	var wrong: Array[String] = []
	for name: String in labels:
		var text: String = labels[name].text
		if not text.contains(expected[name]):
			wrong.append(
				"the %s line reads '%s', expected it to name %s" % [name, text, expected[name]]
			)
	if not wrong.is_empty():
		_fail_cleanup("; ".join(wrong), [lobby_manager, panel])
		return

	panel._show_not_present()
	var stale: Array[String] = []
	for name: String in labels:
		if labels[name].text != "":
			stale.append("the %s line still reads '%s'" % [name, labels[name].text])
	if not stale.is_empty():
		_fail_cleanup("; ".join(stale), [lobby_manager, panel])
		return

	_pass("the panel renders and clears a line per appearance id")
	lobby_manager.queue_free()
	panel.queue_free()


func _pass(check: String) -> void:
	_completed.append(check)
	print("PASS %s" % check)


func _fail(message: String) -> void:
	_failures.append(message)


func _fail_cleanup(message: String, resources: Array) -> void:
	_fail(message)
	for resource in resources:
		if resource is Node:
			(resource as Node).queue_free()


func _finish() -> void:
	for check in _EXPECTED_CHECKS:
		if check not in _completed:
			_failures.append("check never ran: %s" % check)

	if _failures.is_empty():
		print("\nAll %d appearance replication checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
