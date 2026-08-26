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
static func effective_defense(
	defense: float, flat_pen: float = 0.0, percent_pen: float = 0.0
) -> float:
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
static func physical_damage(
	raw: float, armor: float, flat_pen: float = 0.0, percent_pen: float = 0.0
) -> float:
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
static func magical_damage(
	raw: float, resistance: float, flat_pen: float = 0.0, percent_pen: float = 0.0
) -> float:
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


## Calculate basic attack damage before mitigation.
##
## Per §9, a basic attack's raw damage is the equipped weapon's damage with
## the attacking combatant's Attack Damage statistic as scaling input.
##
## Args:
##     weapon_damage: The equipped weapon's damage value
##     attack_damage: The attacking combatant's Attack Damage stat
##
## Returns:
##     Raw basic attack damage, before apply_damage()'s mitigation pipeline
static func basic_attack_damage(weapon_damage: float, attack_damage: float) -> float:
	return weapon_damage + attack_damage


## Calculate crowd control duration after Tenacity reduction.
##
## Per §14, the formula is: Effective Duration = Base Duration × (1.0 - Tenacity)
##
## Tenacity is a percent-reduction stat that shortens the duration of crowd control effects.
## A Tenacity value of 0.25 (25%) means the effect lasts 75% of its base duration.
## This function takes no `affected_by_tenacity` flag—deciding whether to call it is
## the caller's responsibility.
##
## Args:
##     base_duration: Base duration in seconds
##     tenacity: Tenacity value as a fraction (e.g., 0.25 for 25% reduction)
##
## Returns:
##     Effective duration after Tenacity reduction (in seconds)
##
## Known extension point (§60): diminishing returns on repeated crowd control
## is deliberately not implemented here. Adding it means scaling `base_duration`
## by the target's recent crowd control history before the Tenacity reduction
## below, which needs per-target state this pure function does not and should
## not carry -- the caller would supply an already-scaled `base_duration`.
static func crowd_control_duration(base_duration: float, tenacity: float) -> float:
	return base_duration * (1.0 - tenacity)


## Calculate healing from lifesteal and omnivamp based on damage dealt.
##
## Sustain healing (lifesteal + omnivamp) is applied as a fraction of the
## damage dealt, where damage_dealt includes both shield absorption and
## health reduction. This formula ensures overkill scenarios do not grant
## bonus healing: a hit dealing 10 health damage yields 10% of 10, not 10% of
## the raw or pre-mitigation amount.
##
## Args:
##     damage_dealt: Actual damage absorbed (shield + health), post-mitigation
##     sustain_pct: Combined sustain percentage (lifesteal + omnivamp as fraction)
##
## Returns:
##     Healing amount (damage_dealt * sustain_pct)
static func sustain_healing(damage_dealt: float, sustain_pct: float) -> float:
	return maxf(damage_dealt, 0.0) * sustain_pct


## Calculate the actual healing applied, clamped to maximum health.
##
## Applies healing without exceeding the target's maximum health, ensuring
## healing at max health results in 0.0 applied (not negative) and preventing
## overheal from "wasting" resources. The returned amount is what actually
## went to health, accounting for the current_health cap.
##
## Args:
##     current_health: Target's current health before healing
##     max_health: Target's maximum health
##     amount: Proposed healing amount (will be clamped)
##
## Returns:
##     Actual healing applied (never negative, never exceeds max_health - current_health)
static func clamped_heal(current_health: float, max_health: float, amount: float) -> float:
	return clampf(amount, 0.0, maxf(0.0, max_health - current_health))
