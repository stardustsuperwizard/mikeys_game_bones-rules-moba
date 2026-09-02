class_name SpawnPoint
extends Resource

@export var actor_scene: PackedScene
@export var character_sheet: CharacterSheet
@export var color: Color = Color.WHITE
@export var transform: Transform3D = Transform3D.IDENTITY
@export var authority_id: int = 0
# Which team this spawn point belongs to: 0 is Team A, 1 is Team B. Deliberately just
# a flag, not a faction/relationship system -- nothing today needs more than "which of two sides."
@export var team: int = 0
