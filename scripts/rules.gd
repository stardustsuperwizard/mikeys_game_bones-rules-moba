# Game-specific rules engine for Sword and Planet.
# Provides static methods for combat and interaction that the Bones framework
# delegates to via AttackAction and OpenAction.
class_name Rules
extends Object

# Fallback damage for an actor with no MobaCombatant -- a prop or a test
# double, not a combatant. Anything with a MobaCombatant resolves through the
# ruleset instead and never reaches this constant.
const BASE_ATTACK_DAMAGE := 1

# The node name MobaCombatant is authored into every actor scene. It must match
# exactly: get_node_or_null() returns null for a near-miss rather than erroring,
# so a wrong name here reads as "this actor is not a combatant" and silently
# routes every attack down the BASE_ATTACK_DAMAGE fallback above.
const COMBATANT_NODE := "MobaCombatant"


static func attack(attacker: Actor, target: Actor) -> ActionResult:
	var attacker_combatant := attacker.get_node_or_null(COMBATANT_NODE) as MobaCombatant
	var target_combatant := target.get_node_or_null(COMBATANT_NODE) as MobaCombatant

	# If both actors have a MobaCombatant child, delegate to the rules module
	if attacker_combatant != null and target_combatant != null:
		var armor_pen_flat = attacker_combatant.get_stat(MobaStatBlock.ARMOR_PEN_FLAT)
		var armor_pen_percent = attacker_combatant.get_stat(MobaStatBlock.ARMOR_PEN_PERCENT)

		var damage_packet := MobaDamage.new(
			_basic_attack_damage(attacker_combatant),
			MobaDamage.DamageType.PHYSICAL,
			attacker_combatant,
			true,
			armor_pen_flat,
			armor_pen_percent
		)
		target_combatant.apply_damage(damage_packet)
	else:
		# Fallback to the existing behavior
		target.take_damage(BASE_ATTACK_DAMAGE)

	return ActionResult.new(true)


# Raw basic-attack damage for a combatant, through the same MobaFormulas call
# MobaCombatant._apply_basic_attack_hit() uses. Computing it any other way here
# would make an Actor-driven attack and a ruleset-driven attack disagree about
# what the same weapon hits for -- a second basic-attack formula, which is
# exactly the duplication ruleset section 65 warns about.
static func _basic_attack_damage(combatant: MobaCombatant) -> float:
	var attack_damage: float = combatant.get_stat(MobaStatBlock.ATTACK_DAMAGE)
	var loadout := combatant.loadout
	var weapon: MobaWeapon = loadout.get_weapon() if loadout != null else null
	if weapon == null:
		return attack_damage
	return MobaFormulas.basic_attack_damage(weapon.damage, attack_damage)


static func open(_actor: Actor, door: Door) -> ActionResult:
	door.set_open(true)
	return ActionResult.new(true)
