"""Character data models for balance simulation."""

from dataclasses import dataclass


@dataclass
class Character:
    """Minimal character model for balance testing.
    
    This dataclass represents a combatant in simulation. It holds the stats
    needed to compute damage, cooldowns, and other combat outcomes.
    
    Keep this deliberately small initially. It will grow as new combat
    mechanics are added.
    """
    health: float = 500
    max_health: float = 500

    resource: float = 250
    max_resource: float = 250

    attack_damage: float = 50
    attack_speed: float = 1.0

    armor: float = 30
    magic_resistance: float = 25

    crit_chance: float = 0.05
    crit_multiplier: float = 2.0

    movement_speed: float = 5.0
    
    ability_haste: float = 0.0
