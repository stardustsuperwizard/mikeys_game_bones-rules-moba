# Game-specific rules engine for Sword and Planet.
# Provides static methods for combat and interaction that the Bones framework
# delegates to via AttackAction and OpenAction.
class_name Rules
extends Object

# Placeholder damage value. Full combat resolution (attacker stats, weapons,
# resistances) is out of scope for the current milestone.
const BASE_ATTACK_DAMAGE := 1

static func attack(attacker: Actor, target: Actor) -> ActionResult:
	var attacker_combatant := attacker.get_node_or_null("Combatant") as MobaCombatant
	var target_combatant := target.get_node_or_null("Combatant") as MobaCombatant
	
	# If both actors have a Combatant child, delegate to the rules module
	if attacker_combatant != null and target_combatant != null:
		var damage := attacker_combatant.get_stat(MobaStatBlock.ATTACK_DAMAGE)
		target_combatant.apply_damage(damage)
	else:
		# Fallback to the existing behavior
		target.take_damage(BASE_ATTACK_DAMAGE)
	
	return ActionResult.new(true)

static func open(actor: Actor, door: Door) -> ActionResult:
	door.set_open(true)
	return ActionResult.new(true)
