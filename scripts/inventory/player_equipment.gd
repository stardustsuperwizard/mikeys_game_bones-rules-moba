class_name PlayerEquipment
extends EquipmentModel
## Game-specific equipment slot wiring for the universal_inventory addon.
##
## EquipmentModel.slots is a Dictionary[SlotType, EquipmentSlot] exported from
## the addon; Godot cannot reliably serialize Node references as typed
## Dictionary values through the inspector, so the mapping is built here from
## unique-named children instead of relying on that export.

func _ready() -> void:
	slots = {
		ItemBase.SlotType.HEAD: %Head,
		ItemBase.SlotType.CHEST: %Chest,
		ItemBase.SlotType.LEGS: %Legs,
		ItemBase.SlotType.FEET: %Feet,
		ItemBase.SlotType.WEAPON: %Weapon,
		ItemBase.SlotType.SHIELD: %Shield,
		ItemBase.SlotType.NECK: %Neck,
		ItemBase.SlotType.RING: %Ring,
	}
	super._ready()
