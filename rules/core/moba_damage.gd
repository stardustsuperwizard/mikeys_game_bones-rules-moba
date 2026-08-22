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
	MAGICAL,   # Mitigated by Magic Resistance
	TRUE,      # Bypasses all defenses
}


## Raw damage before crit and mitigation.
var amount: float


## Type of damage (PHYSICAL, MAGICAL, or TRUE).
var damage_type: int = DamageType.PHYSICAL


## Source of the damage (typically the attacker Actor or ability).
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
