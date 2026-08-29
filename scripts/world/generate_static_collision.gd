class_name GenerateStaticCollision
extends Node3D
## Walks every MeshInstance3D under this node at startup and gives it
## trimesh collision, for purely-visual imported scenes (asset-pack demo
## scenes, etc.) that ship with no collision of their own.

func _ready() -> void:
	_add_collision(self)

func _add_collision(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		node.create_trimesh_collision()
	for child in node.get_children():
		_add_collision(child)
