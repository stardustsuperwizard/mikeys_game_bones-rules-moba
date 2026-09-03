## Character appearance specification: helmet, chest piece, and color scheme.
##
## Carries three validated, catalog-backed appearance choice identifiers
## (helm, chest, color_scheme). Each id is a StringName that must either be
## empty (a legal "none"/"default" value) or present in the appearance catalog.
##
## MobaAppearance itself is a plain-value resource with no node, no scene tree,
## and no geometric or material data; it holds only the three id StringNames.
## The mapping from ids to renderable geometry is the game's responsibility
## and is out of scope for the rules module.
class_name MobaAppearance
extends Resource

## Helmet appearance id. Empty string is a legal "none" value.
@export var helm_id: StringName = ""

## Chest piece appearance id. Empty string is a legal "none" value.
@export var chest_id: StringName = ""

## Color scheme appearance id. Empty string is a legal "none" value.
@export var color_scheme_id: StringName = ""
