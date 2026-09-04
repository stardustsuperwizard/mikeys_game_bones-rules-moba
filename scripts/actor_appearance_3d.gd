## Placeholder appearance rendering for an actor's 3D body (#377).
##
## Reads the three catalog ids an Actor carries in `appearance` -- populated at
## spawn by WorldManager._spawn_actor() and LobbyManager._spawn_avatar() -- and
## hangs the matching placeholder piece scenes off the body, tinted with the
## matching colour scheme. On top of that it adds a team signal whose colour is
## computed from `Actor.team` and from nothing else.
##
## The geometry is deliberately crude: distinct primitive shapes, each labelled
## with its own id. What this proves is the plumbing -- that a choice made at
## creation reaches a renderer and puts the right piece on the right body -- not
## that a helmet looks like a helmet. Real art is a later swap of the scenes the
## catalog points at, needing no change here, in rules/, or in a saved character.
##
## Owned by ActorBody3D, which creates one child of this type per body and calls
## apply() once the actor's spawn data is in place.
class_name ActorAppearance3D
extends Node3D

## The node name ActorBody3D gives its instance of this component.
const NODE_NAME := "Appearance"

## The game-side id -> scene/colour mapping. Loaded lazily so a body that never
## wears anything (every world and bot actor) pays nothing for it.
const CATALOG_PATH := "res://resources/appearance/appearance_catalog.tres"

## Optional placement markers authored on a body. A body without them still
## renders; the fallback offsets below stand in for a head and a torso.
const HELM_MARKER := ^"HelmAttachment"
const CHEST_MARKER := ^"ChestAttachment"
const HELM_FALLBACK_OFFSET := Vector3(0, 1.95, 0)
const CHEST_FALLBACK_OFFSET := Vector3(0, 1.15, 0)

## The team signal: one fixed colour per side, indexed by Actor.team, plus a
## loud fallback for a team value that is neither.
##
## These are not appearance colours and are deliberately not reachable from the
## catalog. A player who dresses in the opposing side's colour scheme still flies
## their own team's signal, because nothing a player can write is read here.
const TEAM_SIGNAL_COLORS: Array[Color] = [
	Color(0.15, 0.55, 1, 1),  # MobaMatchState.TEAM_A
	Color(1, 0.35, 0.1, 1),  # MobaMatchState.TEAM_B
]
const TEAM_SIGNAL_UNKNOWN_COLOR := Color(1, 0, 1, 1)
const TEAM_SIGNAL_NAME := "TeamSignal"
const TEAM_SIGNAL_OFFSET := Vector3(0, 2.65, 0)

## The catalog this component reads. Injectable so a test can supply its own
## rather than editing the shipped resource.
var catalog: AppearanceCatalog = null


## The colour of the team signal for a team id, derived from that id alone.
##
## Static and taking an int, so there is no instance state, no appearance, and
## no colour a client can write anywhere in reach of the answer.
static func team_signal_color(team: int) -> Color:
	if team < 0 or team >= TEAM_SIGNAL_COLORS.size():
		return TEAM_SIGNAL_UNKNOWN_COLOR
	return TEAM_SIGNAL_COLORS[team]


## Render `actor`'s appearance and team signal onto the body this hangs off.
##
## An actor with no appearance -- every world and bot actor, which have no build
## to choose one with -- is left exactly as its scene authored it, flat colour
## and all. The team signal rides with the pieces rather than being drawn for
## those actors too, so nothing about their existing look changes; what it may
## never do is be skipped for an actor that *does* carry an appearance.
func apply(actor: Actor) -> void:
	_clear()

	if actor == null or actor.appearance == null:
		return

	if catalog == null:
		catalog = load(CATALOG_PATH) as AppearanceCatalog
	if catalog == null:
		push_error("ActorAppearance3D: no appearance catalog at %s" % CATALOG_PATH)
		return

	var tint := catalog.get_scheme_color(actor.appearance.color_scheme_id, actor.color)
	_attach(
		catalog.get_helm_scene(actor.appearance.helm_id), HELM_MARKER, HELM_FALLBACK_OFFSET, tint
	)
	_attach(
		catalog.get_chest_scene(actor.appearance.chest_id),
		CHEST_MARKER,
		CHEST_FALLBACK_OFFSET,
		tint
	)

	_attach_team_signal(actor.team)


## Everything this component rendered last time, so apply() is repeatable and
## leaves nothing of a previous appearance behind.
func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


## Instantiate one piece scene at its slot's marker position and tint it.
func _attach(piece_scene: PackedScene, marker: NodePath, fallback: Vector3, tint: Color) -> void:
	if piece_scene == null:
		return

	var piece := piece_scene.instantiate() as Node3D
	if piece == null:
		push_error("ActorAppearance3D: piece scene %s is not a Node3D" % piece_scene.resource_path)
		return

	piece.position = _marker_position(marker, fallback)
	add_child(piece)
	_tint(piece, tint)


## The local position of a body's placement marker, or `fallback` when the body
## authors none. This component sits at the body's origin, so a marker's own
## local position transfers directly.
func _marker_position(marker: NodePath, fallback: Vector3) -> Vector3:
	var body := get_parent() as Node3D
	if body == null:
		return fallback

	var node := body.get_node_or_null(marker) as Node3D
	if node == null:
		return fallback

	return node.position


## Tint every mesh in a piece with the colour scheme's colour.
##
## Label3D is not a MeshInstance3D and is deliberately left alone: the id text is
## what makes a piece readable, and tinting it would make one scheme's pieces
## unreadable against their own geometry.
func _tint(node: Node, tint: Color) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null:
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		mesh_instance.material_override = material

	for child in node.get_children():
		_tint(child, tint)


## The team signal itself: a ring above the actor, coloured from `team` alone.
func _attach_team_signal(team: int) -> void:
	var color := team_signal_color(team)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color

	var ring := TorusMesh.new()
	ring.inner_radius = 0.34
	ring.outer_radius = 0.5

	var signal_node := MeshInstance3D.new()
	signal_node.name = TEAM_SIGNAL_NAME
	signal_node.mesh = ring
	signal_node.material_override = material
	signal_node.position = TEAM_SIGNAL_OFFSET
	add_child(signal_node)
