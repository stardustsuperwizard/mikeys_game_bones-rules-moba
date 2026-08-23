## Transient per-hit damage packet carrying all information required for damage resolution.
##
## MobaDamage is a RefCounted value object that encapsulates a damage event:
## the raw amount, damage type (PHYSICAL/MAGICAL/TRUE), the source, and the
## attacker's penetration stats. It is constructed by Rules.attack() and passed
## to MobaCombatant.apply_damage() for resolution.
class_name MobaDamage
extends RefCounted

## Damage type enum per §7.
enum DamageType {
	PHYSICAL,  # Mitigated by Armor
	MAGICAL,  # Mitigated by Magic Resistance
	TRUE,  # Bypasses all defenses
}

## Raw damage before crit and mitigation.
var amount: float

## Type of damage (PHYSICAL, MAGICAL, or TRUE).
var damage_type: int = DamageType.PHYSICAL

## The attacking MobaCombatant, or null for unattributed damage.
##
## Typed as Variant rather than MobaCombatant only because GDScript cannot
## reference a class that references this one back. It is a MobaCombatant by
## contract at every construction site, and apply_damage() reads the
## attacker's crit statistics off it -- so passing an Actor here silently
## disables crit rather than failing loudly. Reach the Actor through
## source.get_parent() when attribution needs the scene-tree node.
var source

## Whether this damage can trigger a critical strike.
var can_crit: bool = true

## Flat armor/magic penetration from the attacker.
var flat_pen: float = 0.0

## Percent armor/magic penetration from the attacker (as a fraction, e.g., 0.2 for 20%).
var percent_pen: float = 0.0


## Convenient constructor for MobaDamage.
func _init(
	p_amount: float,
	p_damage_type: int = DamageType.PHYSICAL,
	p_source = null,
	p_can_crit: bool = true,
	p_flat_pen: float = 0.0,
	p_percent_pen: float = 0.0
) -> void:
	amount = p_amount
	damage_type = p_damage_type
	source = p_source
	can_crit = p_can_crit
	flat_pen = p_flat_pen
	percent_pen = p_percent_pen
