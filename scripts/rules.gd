# Game-specific rules engine for Sword and Planet.
# Provides static methods for combat and interaction that the Bones framework
# delegates to via AttackAction and OpenAction.
class_name Rules
extends Object

static func attack(attacker: Actor, target: Actor) -> ActionResult:
	target.take_damage(1)
	return ActionResult.new(true)

static func open(actor: Actor, door: Door) -> ActionResult:
	door.set_open(true)
	return ActionResult.new(true)
