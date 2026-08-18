# Game-specific rules engine for Sword and Planet.
# Provides static methods for combat and interaction that the Bones framework
# delegates to via AttackAction and OpenAction.
class_name Rules
extends Object

# Placeholder damage value. Full combat resolution (attacker stats, weapons,
# resistances) is out of scope for the current milestone.
const BASE_ATTACK_DAMAGE := 1

static func attack(attacker: Actor, target: Actor) -> ActionResult:
	target.take_damage(BASE_ATTACK_DAMAGE)
	return ActionResult.new(true)

static func open(actor: Actor, door: Door) -> ActionResult:
	door.set_open(true)
	return ActionResult.new(true)
