"""Combat formulas for Sword and Planet.

This module implements all combat math used by the balance harness. These formulas
must match the implementations in GDScript exactly to within floating-point tolerance.

See:
  - §8 (Damage Mitigation) for physical_damage and magical_damage formulas
  - §61 (Armor/Magic Penetration and Ability Haste Formulas) for effective_armor
    and effective_cooldown
  - §7 (Damage Types) for true damage mechanics
"""


def mitigation_multiplier(defense: float) -> float:
    """Calculate the damage multiplier for a given defense value.
    
    Per §8, the formula is: Multiplier = 100 / (100 + Defense)
    
    This produces diminishing returns while ensuring additional defense
    always provides value.
    
    Args:
        defense: Armor or Magic Resistance value (negative values are clamped to 0)
    
    Returns:
        Damage multiplier (0.0 to 1.0)
    
    Example:
        >>> mitigation_multiplier(0)
        1.0
        >>> mitigation_multiplier(100)
        0.5
        >>> mitigation_multiplier(50)
        pytest.approx(0.6667, rel=1e-4)
    
    Note:
        Negative defense values are clamped to zero. This prevents defense below
        zero from increasing damage taken. A future release may support negative
        defense with a different formula if needed.
    """
    # Clamp negative defense to zero
    defense = max(0.0, defense)
    return 100.0 / (100.0 + defense)


def effective_armor(target_armor: float, flat_pen: float = 0.0, percent_pen: float = 0.0) -> float:
    """Calculate effective armor after penetration.
    
    Per §61, penetration is applied in two stages:
    1. Flat penetration is subtracted first
    2. Percent penetration is applied to the remaining armor
    
    This follows standard MOBA convention (e.g., League of Legends).
    
    Args:
        target_armor: Base armor value
        flat_pen: Flat armor penetration (default 0)
        percent_pen: Percent armor penetration as a fraction (default 0, e.g., 0.2 for 20%)
    
    Returns:
        Effective armor after applying penetration
    
    Example:
        >>> effective_armor(100, flat_pen=10, percent_pen=0.2)
        72.0  # (100 - 10) * (1.0 - 0.2) = 90 * 0.8
    """
    reduced = max(0.0, target_armor - flat_pen)
    # Clamped at zero to match MobaFormulas.effective_defense(): over-penetration
    # (percent_pen above 1.0) must never turn into negative defense, which
    # mitigation_multiplier would read as a damage amplifier.
    return max(0.0, reduced * (1.0 - percent_pen))


def physical_damage(
    raw_damage: float,
    target_armor: float,
    attacker_flat_pen: float = 0.0,
    attacker_percent_pen: float = 0.0
) -> float:
    """Calculate physical damage dealt after armor mitigation.
    
    Per §8, final damage is: Raw Damage × Multiplier
    where Multiplier = mitigation_multiplier(effective_armor)
    
    Armor penetration is applied per §61 before computing the multiplier.
    
    Args:
        raw_damage: Damage before mitigation
        target_armor: Target's armor (or base armor if penetration provided)
        attacker_flat_pen: Attacker's flat armor penetration (default 0)
        attacker_percent_pen: Attacker's percent armor penetration (default 0)
    
    Returns:
        Final damage after armor mitigation
    
    Example:
        >>> physical_damage(100, 0)
        100.0
        >>> physical_damage(100, 100)
        50.0
        >>> physical_damage(50, 50)
        pytest.approx(33.33, rel=1e-4)
    """
    eff_armor = effective_armor(target_armor, attacker_flat_pen, attacker_percent_pen)
    return raw_damage * mitigation_multiplier(eff_armor)


def magical_damage(
    raw_damage: float,
    target_resistance: float,
    attacker_flat_pen: float = 0.0,
    attacker_percent_pen: float = 0.0
) -> float:
    """Calculate magical damage dealt after resistance mitigation.
    
    Per §8, magical damage follows the same formula as physical damage,
    using Magic Resistance instead of Armor.
    
    Args:
        raw_damage: Damage before mitigation
        target_resistance: Target's magic resistance
        attacker_flat_pen: Attacker's flat magic penetration (default 0)
        attacker_percent_pen: Attacker's percent magic penetration (default 0)
    
    Returns:
        Final damage after resistance mitigation
    """
    eff_resistance = effective_armor(target_resistance, attacker_flat_pen, attacker_percent_pen)
    return raw_damage * mitigation_multiplier(eff_resistance)


def true_damage(raw_damage: float) -> float:
    """Calculate true damage (ignores all defenses).
    
    Per §7, True Damage ignores Armor and Magic Resistance.
    
    True Damage should be uncommon because excessive access to it makes
    defensive statistics less valuable.
    
    Args:
        raw_damage: Damage value
    
    Returns:
        Final damage (same as input, no mitigation)
    """
    return raw_damage


def effective_cooldown(base_cooldown: float, ability_haste: float = 0.0) -> float:
    """Calculate cooldown after Ability Haste reduction.
    
    Per §61, the formula is: Cooldown = Base Cooldown × (100 / (100 + Ability Haste))
    
    This is the standard MOBA-genre haste formula. Ability Haste is a percent-CDR-equivalent
    stat that avoids the awkwardness of stacking flat percentage cooldown reduction.
    
    Args:
        base_cooldown: Base cooldown in seconds
        ability_haste: Ability Haste value (default 0)
    
    Returns:
        Effective cooldown after haste (in seconds)
    
    Example:
        >>> effective_cooldown(10.0, 0)
        10.0
        >>> effective_cooldown(10.0, 100)
        5.0
        >>> effective_cooldown(10.0, 50)
        pytest.approx(6.667, rel=1e-4)
    
    Note:
        Increasing Ability Haste always decreases cooldown (or keeps it the same if haste is 0).
    """
    return base_cooldown * (100.0 / (100.0 + ability_haste))


def expected_crit_multiplier(crit_chance: float, crit_multiplier: float) -> float:
    """Calculate expected damage multiplier from critical strikes.

    The expected value combines the probability of a critical hit with its damage multiplier:

    Expected = (1 - crit_chance) × 1.0 + crit_chance × crit_multiplier
             = 1.0 + crit_chance × (crit_multiplier - 1.0)

    This is used for computing average damage output over many attacks.

    Args:
        crit_chance: Probability of critical strike (0.0 to 1.0)
        crit_multiplier: Damage multiplier on critical (typically 2.0 for 200%)

    Returns:
        Expected damage multiplier

    Example:
        >>> expected_crit_multiplier(0.0, 2.0)
        1.0
        >>> expected_crit_multiplier(0.05, 2.0)
        1.05
        >>> expected_crit_multiplier(1.0, 2.0)
        2.0
    """
    return (1.0 - crit_chance) + crit_chance * crit_multiplier


def sustain_healing(damage_dealt: float, sustain_pct: float) -> float:
    """Calculate healing from lifesteal and omnivamp based on damage dealt.

    Sustain healing (lifesteal + omnivamp) is applied as a fraction of the
    damage dealt, where damage_dealt includes both shield absorption and
    health reduction. This formula ensures overkill scenarios do not grant
    bonus healing: a hit dealing 10 health damage yields 10% of 10, not 10% of
    the raw or pre-mitigation amount.

    Args:
        damage_dealt: Actual damage absorbed (shield + health), post-mitigation
        sustain_pct: Combined sustain percentage (lifesteal + omnivamp as fraction)

    Returns:
        Healing amount (damage_dealt * sustain_pct)

    Example:
        >>> sustain_healing(40.0, 0.10)
        4.0
        >>> sustain_healing(0.0, 0.10)
        0.0
    """
    return max(damage_dealt, 0.0) * sustain_pct


def clamped_heal(current_health: float, max_health: float, amount: float) -> float:
    """Calculate the actual healing applied, clamped to maximum health.

    Applies healing without exceeding the target's maximum health, ensuring
    healing at max health results in 0.0 applied (not negative) and preventing
    overheal from "wasting" resources. The returned amount is what actually
    went to health, accounting for the current_health cap.

    Args:
        current_health: Target's current health before healing
        max_health: Target's maximum health
        amount: Proposed healing amount (will be clamped)

    Returns:
        Actual healing applied (never negative, never exceeds max_health - current_health)

    Example:
        >>> clamped_heal(480.0, 500.0, 100.0)
        20.0
        >>> clamped_heal(500.0, 500.0, 100.0)
        0.0
        >>> clamped_heal(100.0, 500.0, -10.0)
        0.0
    """
    # Clamp the amount: at minimum 0.0, at maximum the remaining space to max_health
    min_clamp = 0.0
    max_clamp = max(0.0, max_health - current_health)
    return min(max(amount, min_clamp), max_clamp)
