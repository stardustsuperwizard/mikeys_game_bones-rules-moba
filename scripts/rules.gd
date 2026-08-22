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
		var attack_damage = attacker_combatant.get_stat(MobaStatBlock.ATTACK_DAMAGE)
		var armor_pen_flat = attacker_combatant.get_stat(MobaStatBlock.ARMOR_PEN_FLAT)
		var armor_pen_percent = attacker_combatant.get_stat(MobaStatBlock.ARMOR_PEN_PERCENT)

		var damage_packet := MobaDamage.new(
			attack_damage,
			MobaDamage.DamageType.PHYSICAL,
			attacker,
			true,
			armor_pen_flat,
			armor_pen_percent
		)
		target_combatant.apply_damage(damage_packet)
	else:
		# Fallback to the existing behavior
		target.take_damage(BASE_ATTACK_DAMAGE)

	return ActionResult.new(true)


static func open(_actor: Actor, door: Door) -> ActionResult:
	door.set_open(true)
	return ActionResult.new(true)
