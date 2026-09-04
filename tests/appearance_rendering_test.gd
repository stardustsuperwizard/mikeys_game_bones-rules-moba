# Headless integration test for #377: the appearance ids a character carries
# reach a renderer and put the right placeholder piece on the right body, and the
# team signal stays readable off Actor.team no matter what the player wore.
#
# Run with:
#   godot --headless --path . --script tests/appearance_rendering_test.gd
#
# Covers, in order:
#   - the game-side AppearanceCatalog registers exactly the ids
#     rules/data/appearance/catalog.json defines -- no extra, none missing, so a
#     later art swap cannot silently drop an id a saved character still names;
#   - every piece scene is primitive geometry plus a Label3D carrying its own id,
#     with no imported model or texture referenced anywhere in it;
#   - two pieces in one slot differ by primitive shape, not merely by colour or
#     scale, so a colour scheme cannot make them look like each other;
#   - a match actor spawned with an appearance wears the matching pieces on its
#     body, tinted with the matching colour scheme;
#   - a lobby avatar wears the same pieces, so the character in the lobby is the
#     character that walks into the arena;
#   - an actor with no appearance -- every enemy and world actor -- renders
#     exactly as it does today, a flat colour-tinted capsule and nothing else;
#   - two actors with identical appearances and different teams are still told
#     apart by the team signal;
#   - the team signal is unforgeable: an actor deliberately dressed in whichever
#     catalogue scheme sits closest to the OPPOSING side's signal colour still
#     flies its own side's, because the signal is read off Actor.team alone.
#
# The last check is where the risk in this Feature lives. Everything else is
# plumbing that fails loudly; a team signal quietly derived from a
# client-writable field fails only in the one match where somebody tries it.
#
# This test is NOT wired into tests/test_bootstrap.gd: it loads game scenes, a
# WorldManager and a LobbyManager, matching the precedent set by
# tests/appearance_replication_test.gd and tests/build_spawn_integration_test.gd.
extends SceneTree

const _PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const _PLAYER_SPAWN_POINT := preload("res://resources/player_spawn_point.tres")
const _ENEMY_SPAWN_POINT := preload("res://resources/enemy_spawn_point.tres")
const _LOBBY_SPAWN_POINT := preload("res://resources/lobby_player_spawn_point.tres")
const _FALLBACK_BUILD := preload("res://rules/data/builds/melee_bruiser_build.tres")
const _CATALOG := preload("res://resources/appearance/appearance_catalog.tres")

# Catalog ids, taken from rules/data/appearance/catalog.json.
const _HELM := &"iron_helm"
const _CHEST := &"leather_chest"
const _SCHEME := &"emerald"

# One peer id per check, for the same reason appearance_replication_test.gd
# keeps them apart: PeerIdentityRegistry is an autoload and outlives every
# WorldManager built here.
const _PEER_MATCH := 51
const _PEER_LOBBY := 52

const _EXPECTED_CHECKS: Array[String] = [
	"the game-side catalog registers exactly the rules catalog's ids",
	"every piece scene is labelled primitive geometry",
	"pieces in one slot differ by primitive shape",
	"a match actor wears its chosen pieces, tinted by its scheme",
	"a lobby avatar wears its chosen pieces, tinted by its scheme",
	"an actor with no appearance is left exactly as its scene authored it",
	"identical appearances on different teams are told apart by the signal",
	"an adversarial colour scheme cannot forge the team signal",
]

var _failures: Array[String] = []
var _completed: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	_test_catalog_ids_match_the_rules_catalog()
	_test_piece_scenes_are_labelled_primitives()
	_test_slot_pieces_differ_by_shape()
	_test_match_actor_wears_its_pieces()
	_test_lobby_avatar_wears_its_pieces()
	_test_actor_without_appearance_is_unchanged()
	_test_team_signal_separates_identical_appearances()
	_test_adversarial_scheme_cannot_forge_the_team_signal()

	_finish()


# --- helpers ---------------------------------------------------------------


## A MobaAppearance built from three catalog ids.
func _make_appearance(helm: StringName, chest: StringName, scheme: StringName) -> MobaAppearance:
	var appearance := MobaAppearance.new()
	appearance.helm_id = helm
	appearance.chest_id = chest
	appearance.color_scheme_id = scheme
	return appearance


## A legal WARRIOR/GUARDIAN build carrying an appearance, shaped like the one
## tests/appearance_replication_test.gd submits.
func _make_legal_build(character_name: String, appearance: MobaAppearance) -> MobaCharacterBuild:
	var loadout := MobaLoadout.new()
	loadout.set_action_slot(1, "whirlwind")
	loadout.set_action_slot(2, "shield_bash")
	loadout.weapon = _FALLBACK_BUILD.loadout.weapon

	var build := MobaCharacterBuild.new()
	build.character_name = character_name
	build.primary_discipline = MobaAbility.Discipline.WARRIOR
	build.secondary_discipline = MobaAbility.Discipline.GUARDIAN
	build.stat_allocation = {}
	build.appearance = appearance
	build.loadout = loadout
	return build


## An Actor instantiated straight from player.tscn, dressed and teamed before it
## enters the tree -- the same order spawn initialization uses, which is what
## makes ActorBody3D._ready() see the appearance.
func _make_dressed_actor(appearance: MobaAppearance, team: int) -> Actor:
	var actor := _PLAYER_SCENE.instantiate() as Actor
	actor.appearance = appearance
	actor.team = team
	root.add_child(actor)
	return actor


## The appearance component ActorBody3D owns, or null when it has none.
func _renderer_of(actor: Actor) -> ActorAppearance3D:
	return actor.get_node_or_null("Body/%s" % ActorAppearance3D.NODE_NAME) as ActorAppearance3D


## Every descendant of a node, itself excluded.
func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


## The Label3D carrying `text` anywhere under `node`, or null.
func _find_label(node: Node, text: String) -> Label3D:
	for candidate in _descendants(node):
		var label := candidate as Label3D
		if label != null and label.text == text:
			return label
	return null


## The MeshInstance3D nodes anywhere under `node`.
func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for candidate in _descendants(node):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance != null:
			found.append(mesh_instance)
	return found


## The team signal node the renderer drew, or null when it drew none.
func _team_signal_of(actor: Actor) -> MeshInstance3D:
	var renderer := _renderer_of(actor)
	if renderer == null:
		return null
	var node_name := ActorAppearance3D.TEAM_SIGNAL_NAME
	return renderer.get_node_or_null(NodePath(node_name)) as MeshInstance3D


## The colour a team signal is actually drawn in, or a magenta that matches no
## team colour when the signal is missing or unmaterialised.
func _team_signal_color(actor: Actor) -> Color:
	var signal_node := _team_signal_of(actor)
	if signal_node == null:
		return Color(0, 0, 0, 0)
	var material := signal_node.material_override as StandardMaterial3D
	if material == null:
		return Color(0, 0, 0, 0)
	return material.albedo_color


## Report the piece named by `piece_id` being absent, unparented from the body,
## or tinted with something other than `expected`, or "" when it is correct.
func _piece_problem(actor: Actor, piece_id: StringName, expected: Color) -> String:
	var renderer := _renderer_of(actor)
	if renderer == null:
		return "the body has no %s component at all" % ActorAppearance3D.NODE_NAME

	var label := _find_label(renderer, String(piece_id))
	if label == null:
		return "no piece on the body is labelled '%s'" % piece_id

	var body := actor.get_node_or_null("Body")
	if body == null or not body.is_ancestor_of(label):
		return "the '%s' piece was not attached under the actor's body" % piece_id

	return _tint_problem(label.get_parent(), piece_id, expected)


## Report a piece's meshes being missing or tinted with anything other than
## `expected`, or "" when every one of them carries the scheme's colour.
func _tint_problem(piece: Node, piece_id: StringName, expected: Color) -> String:
	var meshes := _mesh_instances(piece)
	if meshes.is_empty():
		return "the '%s' piece carries no mesh to see" % piece_id

	for mesh_instance in meshes:
		var material := mesh_instance.material_override as StandardMaterial3D
		if material == null:
			return "the '%s' piece was never tinted" % piece_id
		if material.albedo_color != expected:
			return (
				"the '%s' piece is tinted %s, expected the scheme's %s"
				% [piece_id, material.albedo_color, expected]
			)

	return ""


# --- checks ----------------------------------------------------------------


## The two catalogs name the same ids. Sorted comparison, because the game-side
## catalog is a Dictionary and its key order is not the JSON file's.
func _test_catalog_ids_match_the_rules_catalog() -> void:
	var slots := {
		"helm": [MobaAppearanceCatalog.get_helm_ids(), _CATALOG.helm_scenes.keys()],
		"chest": [MobaAppearanceCatalog.get_chest_ids(), _CATALOG.chest_scenes.keys()],
		"colour scheme":
		[MobaAppearanceCatalog.get_color_scheme_ids(), _CATALOG.color_schemes.keys()],
	}

	var problems: Array[String] = []
	for slot: String in slots:
		var rules_ids: Array = []
		for id: Variant in slots[slot][0]:
			rules_ids.append(String(id))
		var game_ids: Array = []
		for id: Variant in slots[slot][1]:
			game_ids.append(String(id))
		rules_ids.sort()
		game_ids.sort()
		if rules_ids != game_ids:
			problems.append(
				(
					"the %s ids disagree: rules has %s, the game catalog has %s"
					% [slot, rules_ids, game_ids]
				)
			)

	if not problems.is_empty():
		_fail("; ".join(problems))
		return

	_pass("the game-side catalog registers exactly the rules catalog's ids")


## Each piece scene is primitives and a Label3D naming its own id, and refers to
## no imported asset -- the .tscn holds no ext_resource line at all.
func _test_piece_scenes_are_labelled_primitives() -> void:
	var allowed := [
		"Node3D",
		"MeshInstance3D",
		"Label3D",
		"CSGBox3D",
		"CSGCylinder3D",
		"CSGSphere3D",
		"CSGTorus3D",
		"CSGPolygon3D",
		"CSGCombiner3D",
	]

	var problems: Array[String] = []
	for piece_id: String in _all_piece_ids():
		var scene := _piece_scene(piece_id)
		if scene == null:
			problems.append("'%s' has no scene registered" % piece_id)
			continue

		var text := FileAccess.get_file_as_string(scene.resource_path)
		if "[ext_resource" in text:
			problems.append("'%s' references an external asset" % piece_id)

		var instance := scene.instantiate()
		root.add_child(instance)
		for node: Node in [instance] + _descendants(instance):
			if node.get_class() not in allowed:
				problems.append("'%s' contains a %s" % [piece_id, node.get_class()])
			var mesh_instance := node as MeshInstance3D
			if mesh_instance != null and mesh_instance.mesh is not PrimitiveMesh:
				problems.append("'%s' uses a non-primitive mesh" % piece_id)
		if _find_label(instance, piece_id) == null:
			problems.append("'%s' does not display its own id" % piece_id)
		instance.queue_free()

	if not problems.is_empty():
		_fail("; ".join(problems))
		return

	_pass("every piece scene is labelled primitive geometry")


## Within a slot, no two pieces use the same primitive mesh type: tint them the
## same colour and they are still tellable apart.
func _test_slot_pieces_differ_by_shape() -> void:
	var problems: Array[String] = []

	for slot: String in ["helm", "chest"]:
		var seen := {}
		var ids: Array = (
			_CATALOG.helm_scenes.keys() if slot == "helm" else _CATALOG.chest_scenes.keys()
		)
		for piece_id: String in ids:
			var instance := _piece_scene(piece_id).instantiate()
			root.add_child(instance)
			var shapes: Array[String] = []
			for mesh_instance in _mesh_instances(instance):
				if mesh_instance.mesh != null:
					shapes.append(mesh_instance.mesh.get_class())
			shapes.sort()
			var key := ",".join(shapes)
			if seen.has(key):
				problems.append(
					"%s pieces '%s' and '%s' are both %s" % [slot, seen[key], piece_id, key]
				)
			seen[key] = piece_id
			instance.queue_free()

	if not problems.is_empty():
		_fail("; ".join(problems))
		return

	_pass("pieces in one slot differ by primitive shape")


## The match path: a build accepted by the server dresses the actor spawned for
## that peer, through the same WorldManager scenes/main.tscn drives.
func _test_match_actor_wears_its_pieces() -> void:
	var world_manager := WorldManager.new()
	world_manager.player_spawn_point = _PLAYER_SPAWN_POINT
	root.add_child(world_manager)

	var build := _make_legal_build("Dressed Dana", _make_appearance(_HELM, _CHEST, _SCHEME))
	world_manager.spawn_player_for_peer(_PEER_MATCH)
	if not world_manager.submit_build(_PEER_MATCH, build).success:
		_fail_cleanup("setup: a legal build was refused", [world_manager])
		return

	# Respawn, so the accepted build is what spawn initialization reads.
	var placeholder: Actor = world_manager._peer_actors.get(_PEER_MATCH)
	if placeholder != null:
		placeholder.queue_free()
	world_manager._peer_actors.erase(_PEER_MATCH)
	world_manager.spawn_player_for_peer(_PEER_MATCH)

	var actor: Actor = world_manager._peer_actors.get(_PEER_MATCH)
	if actor == null:
		_fail_cleanup("no actor spawned for the peer", [world_manager])
		return
	if actor.get_parent() == null:
		world_manager.add_child(actor)

	var expected: Color = _CATALOG.color_schemes[String(_SCHEME)]
	var problems: Array[String] = []
	for piece_id: StringName in [_HELM, _CHEST]:
		var problem := _piece_problem(actor, piece_id, expected)
		if problem != "":
			problems.append(problem)
	if not problems.is_empty():
		_fail_cleanup("; ".join(problems), [world_manager])
		return

	_pass("a match actor wears its chosen pieces, tinted by its scheme")
	world_manager.queue_free()


## The lobby path: the same pieces on the avatar scenes/lobby/lobby.tscn spawns.
func _test_lobby_avatar_wears_its_pieces() -> void:
	var world_manager := WorldManager.new()
	world_manager.player_spawn_point = _PLAYER_SPAWN_POINT
	root.add_child(world_manager)
	world_manager.spawn_player_for_peer(_PEER_LOBBY)

	var build := _make_legal_build("Lobby Lou", _make_appearance(_HELM, _CHEST, _SCHEME))
	if not world_manager.submit_build(_PEER_LOBBY, build).success:
		_fail_cleanup("setup: a legal build was refused", [world_manager])
		return

	var lobby_manager := LobbyManager.new()
	lobby_manager.avatar_spawn_point = _LOBBY_SPAWN_POINT
	root.add_child(lobby_manager)
	lobby_manager.spawn_avatar_for_peer(_PEER_LOBBY)

	var avatar: Actor = lobby_manager._peer_avatars.get(_PEER_LOBBY)
	if avatar == null:
		_fail_cleanup("no lobby avatar spawned", [world_manager, lobby_manager])
		return
	if avatar.get_parent() == null:
		lobby_manager.add_child(avatar)

	var expected: Color = _CATALOG.color_schemes[String(_SCHEME)]
	var problems: Array[String] = []
	for piece_id: StringName in [_HELM, _CHEST]:
		var problem := _piece_problem(avatar, piece_id, expected)
		if problem != "":
			problems.append(problem)
	if not problems.is_empty():
		_fail_cleanup("; ".join(problems), [world_manager, lobby_manager])
		return

	_pass("a lobby avatar wears its chosen pieces, tinted by its scheme")
	world_manager.queue_free()
	lobby_manager.queue_free()


## World and bot content has no build and therefore no appearance, and must come
## out of a spawn looking exactly as it does today: one flat colour-tinted mesh,
## no pieces, and no team signal added over the top of it.
func _test_actor_without_appearance_is_unchanged() -> void:
	var world_manager := WorldManager.new()
	world_manager.player_spawn_point = _PLAYER_SPAWN_POINT
	root.add_child(world_manager)

	var enemy := world_manager.spawn(_ENEMY_SPAWN_POINT, _ENEMY_SPAWN_POINT.authority_id)
	if enemy == null:
		_fail_cleanup("the bot actor did not spawn", [world_manager])
		return
	world_manager.add_child(enemy)

	var renderer := _renderer_of(enemy)
	if renderer != null and not renderer.get_children().is_empty():
		_fail_cleanup(
			(
				"an actor with no appearance had %d node(s) rendered onto it"
				% renderer.get_child_count()
			),
			[world_manager]
		)
		return

	var mesh_instance := enemy.get_node_or_null("Body/MeshInstance3D") as MeshInstance3D
	var material := mesh_instance.material_override as StandardMaterial3D if mesh_instance else null
	if material == null or material.albedo_color != enemy.color:
		_fail_cleanup("the flat colour-tinted capsule was not preserved", [world_manager])
		return

	_pass("an actor with no appearance is left exactly as its scene authored it")
	world_manager.queue_free()


## Same helm, same chest, same scheme, opposite sides: the team signal is what
## still tells them apart.
func _test_team_signal_separates_identical_appearances() -> void:
	var team_a := _make_dressed_actor(_make_appearance(_HELM, _CHEST, _SCHEME), 0)
	var team_b := _make_dressed_actor(_make_appearance(_HELM, _CHEST, _SCHEME), 1)

	var color_a := _team_signal_color(team_a)
	var color_b := _team_signal_color(team_b)

	if color_a != ActorAppearance3D.team_signal_color(0):
		_fail_cleanup("team A's signal is %s, not its team colour" % color_a, [team_a, team_b])
		return
	if color_b != ActorAppearance3D.team_signal_color(1):
		_fail_cleanup("team B's signal is %s, not its team colour" % color_b, [team_a, team_b])
		return
	if color_a == color_b:
		_fail_cleanup("both teams' signals are %s -- indistinguishable" % color_a, [team_a, team_b])
		return

	_pass("identical appearances on different teams are told apart by the signal")
	team_a.queue_free()
	team_b.queue_free()


## The adversarial case: dress a team A actor in whichever catalogue scheme sits
## closest to team B's signal colour and check the signal is unmoved. The scheme
## is chosen by measuring, not by hand, so adding a scheme cannot quietly leave
## the nastiest one untested.
func _test_adversarial_scheme_cannot_forge_the_team_signal() -> void:
	var enemy_signal := ActorAppearance3D.team_signal_color(1)
	var adversarial := _closest_scheme_to(enemy_signal)
	if adversarial == &"":
		_fail("the catalog registers no colour scheme to test with")
		return

	var actor := _make_dressed_actor(_make_appearance(_HELM, _CHEST, adversarial), 0)
	var scheme_color: Color = _CATALOG.color_schemes[String(adversarial)]

	# The scheme really did apply -- otherwise "the signal is unaffected" would
	# pass for an actor wearing nothing at all.
	var problem := _piece_problem(actor, _HELM, scheme_color)
	if problem != "":
		_fail_cleanup("the adversarial scheme never applied: %s" % problem, [actor])
		return

	var signal_color := _team_signal_color(actor)
	if signal_color != ActorAppearance3D.team_signal_color(0):
		_fail_cleanup(
			(
				"wearing '%s', team A's signal reads %s instead of %s"
				% [adversarial, signal_color, ActorAppearance3D.team_signal_color(0)]
			),
			[actor]
		)
		return

	_pass("an adversarial colour scheme cannot forge the team signal")
	actor.queue_free()


# --- catalog helpers -------------------------------------------------------


## Every helm and chest id the game-side catalog registers.
func _all_piece_ids() -> Array:
	var ids: Array = []
	ids.append_array(_CATALOG.helm_scenes.keys())
	ids.append_array(_CATALOG.chest_scenes.keys())
	return ids


## The scene registered for a helm or chest id, whichever slot holds it.
func _piece_scene(piece_id: String) -> PackedScene:
	var scene := _CATALOG.get_helm_scene(StringName(piece_id))
	if scene != null:
		return scene
	return _CATALOG.get_chest_scene(StringName(piece_id))


## The colour-scheme id whose colour is nearest `target` in RGB.
func _closest_scheme_to(target: Color) -> StringName:
	var closest: StringName = &""
	var best := INF
	for scheme_id: String in _CATALOG.color_schemes:
		var color: Color = _CATALOG.color_schemes[scheme_id]
		var distance := Vector3(color.r, color.g, color.b).distance_to(
			Vector3(target.r, target.g, target.b)
		)
		if distance < best:
			best = distance
			closest = StringName(scheme_id)
	return closest


# --- reporting -------------------------------------------------------------


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
		print("\nAll %d appearance rendering checks passed." % _EXPECTED_CHECKS.size())
		quit(0)
		return

	for failure in _failures:
		printerr("FAIL %s" % failure)
	quit(1)
