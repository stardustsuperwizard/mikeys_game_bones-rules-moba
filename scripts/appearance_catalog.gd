## Game-side appearance catalog: the id -> placeholder scene / colour mapping.
##
## #374 owns the id vocabulary in rules/data/appearance/catalog.json. This
## resource is the game's answer to it: one PackedScene per helm id and per
## chest id, one Color per colour-scheme id, keyed by exactly those ids.
##
## It lives in resources/ rather than rules/ deliberately. A renderable scene is
## game content, and rules/ keeps a one-way dependency arrow -- the game depends
## on the rules, never the reverse -- so the module that defines the ids must not
## learn what they look like.
##
## Replacing the placeholder geometry with real art is a change to the scenes
## this points at, never to the keys: nothing here renames, adds, or drops an id,
## so a saved character keeps meaning what it meant when it was saved.
class_name AppearanceCatalog
extends Resource

## Helm id (String) -> the placeholder PackedScene worn in the helm slot.
@export var helm_scenes: Dictionary = {}

## Chest id (String) -> the placeholder PackedScene worn in the chest slot.
@export var chest_scenes: Dictionary = {}

## Colour-scheme id (String) -> the Color a wearer's pieces are tinted with.
@export var color_schemes: Dictionary = {}


## The placeholder scene for a helm id, or null when the id is empty or unknown.
##
## Keys are looked up as plain Strings because that is how a Dictionary written
## into a .tres stores them, while an appearance carries StringName ids.
func get_helm_scene(helm_id: StringName) -> PackedScene:
	return helm_scenes.get(String(helm_id)) as PackedScene


## The placeholder scene for a chest id, or null when the id is empty or unknown.
func get_chest_scene(chest_id: StringName) -> PackedScene:
	return chest_scenes.get(String(chest_id)) as PackedScene


## The colour for a colour-scheme id, or `fallback` when the id is empty or
## unknown -- an actor that chose no scheme keeps the flat colour it spawned with.
func get_scheme_color(color_scheme_id: StringName, fallback: Color) -> Color:
	var key := String(color_scheme_id)
	if not color_schemes.has(key):
		return fallback
	return color_schemes[key]
