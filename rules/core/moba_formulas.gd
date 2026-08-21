## Combat formulas for the MOBA ruleset.
##
## This class provides static, node-free implementations of every §8, §15, and §61 formula,
## numerically mirroring sim/formulas.py. All methods are static, take plain values, and
## return plain values.
##
## All percentages are fractions (e.g., 0.30 for 30%), not whole numbers.
## No rounding occurs in this file—all returns are float.
class_name MobaFormulas


## Calculate the damage multiplier for a given defense value.
##
## Per §8, the formula is: Multiplier = 100 / (100 + Defense)
##
## Negative defense values are clamped to zero—this prevents defense below zero
## from increasing damage taken.
##
## Args:
##     defense: Armor or Magic Resistance value (negative values are clamped to 0)
##
## Returns:
##     Damage multiplier (0.0 to 1.0)
static func mitigation_multiplier(defense: float) -> float:
	var clamped_defense = maxf(0.0, defense)
	return 100.0 / (100.0 + clamped_defense)


## Calculate effective defense/resistance after penetration.
##
## Per §61, penetration is applied in two stages:
## 1. Flat penetration is subtracted first
## 2. Percent penetration is applied to the remaining defense
##
## The result is clamped at zero—over-penetration never becomes a damage amplifier.
##
## Args:
##     defense: Base defense value
##     flat_pen: Flat defense penetration (default 0)
##     percent_pen: Percent defense penetration as a fraction (default 0, e.g., 0.2 for 20%)
##
## Returns:
##     Effective defense after applying penetration
static func effective_defense(defense: float, flat_pen: float = 0.0, percent_pen: float = 0.0) -> float:
	var reduced = maxf(0.0, defense - flat_pen)
	var result = reduced * (1.0 - percent_pen)
	return maxf(0.0, result)


## Calculate physical damage dealt after armor mitigation.
##
## Per §8, final damage is: Raw Damage × Multiplier
## where Multiplier = mitigation_multiplier(effective_armor)
##
## Armor penetration is applied per §61 before computing the multiplier.
##
## Args:
##     raw: Damage before mitigation
##     armor: Target's armor (or base armor if penetration provided)
##     flat_pen: Attacker's flat armor penetration (default 0)
##     percent_pen: Attacker's percent armor penetration (default 0)
##
## Returns:
##     Final damage after armor mitigation
static func physical_damage(raw: float, armor: float, flat_pen: float = 0.0, percent_pen: float = 0.0) -> float:
	var eff_armor = effective_defense(armor, flat_pen, percent_pen)
	return raw * mitigation_multiplier(eff_armor)


## Calculate magical damage dealt after resistance mitigation.
##
## Per §8, magical damage follows the same formula as physical damage,
## using Magic Resistance instead of Armor.
##
## Args:
##     raw: Damage before mitigation
##     resistance: Target's magic resistance
##     flat_pen: Attacker's flat magic penetration (default 0)
##     percent_pen: Attacker's percent magic penetration (default 0)
##
## Returns:
##     Final damage after resistance mitigation
static func magical_damage(raw: float, resistance: float, flat_pen: float = 0.0, percent_pen: float = 0.0) -> float:
	var eff_resistance = effective_defense(resistance, flat_pen, percent_pen)
	return raw * mitigation_multiplier(eff_resistance)


## Calculate true damage (ignores all defenses).
##
## Per §7, True Damage ignores Armor and Magic Resistance.
##
## Args:
##     raw: Damage value
##
## Returns:
##     Final damage (same as input, no mitigation)
static func true_damage(raw: float) -> float:
	return raw


## Calculate cooldown after Ability Haste reduction.
##
## Per §61, the formula is: Cooldown = Base Cooldown × (100 / (100 + Ability Haste))
##
## This is the standard MOBA-genre haste formula. Ability Haste is a percent-CDR-equivalent
## stat that avoids the awkwardness of stacking flat percentage cooldown reduction.
##
## Args:
##     base_cooldown: Base cooldown in seconds
##     ability_haste: Ability Haste value (default 0)
##
## Returns:
##     Effective cooldown after haste (in seconds)
static func effective_cooldown(base_cooldown: float, ability_haste: float = 0.0) -> float:
	return base_cooldown * (100.0 / (100.0 + ability_haste))


## Calculate expected damage multiplier from critical strikes.
##
## The expected value combines the probability of a critical hit with its damage multiplier:
## Expected = (1 - crit_chance) × 1.0 + crit_chance × crit_damage
##          = 1.0 + crit_chance × (crit_damage - 1.0)
##
## This is used for computing average damage output over many attacks.
##
## Args:
##     crit_chance: Probability of critical strike (0.0 to 1.0)
##     crit_damage: Damage multiplier on critical (typically 2.0 for 200%)
##
## Returns:
##     Expected damage multiplier
static func expected_crit_multiplier(crit_chance: float, crit_damage: float) -> float:
	return (1.0 - crit_chance) + crit_chance * crit_damage


## Check if a roll results in a critical hit.
##
## This is a pure crit helper that takes an already-drawn roll rather than drawing one.
## This allows the caller to control RNG seeding for deterministic testing.
##
## Args:
##     roll: Already-drawn random roll (typically 0.0 to 1.0)
##     crit_chance: Probability of critical strike as a fraction (e.g., 0.20 for 20%)
##
## Returns:
##     true if roll < crit_chance, false otherwise
static func is_critical(roll: float, crit_chance: float) -> bool:
	return roll < crit_chance


## Apply critical damage multiplier to raw damage.
##
## Args:
##     raw: Raw damage value
##     crit_damage: Critical damage multiplier (typically 2.0 for 200%)
##
## Returns:
##     raw × crit_damage
static func apply_crit(raw: float, crit_damage: float) -> float:
	return raw * crit_damage
