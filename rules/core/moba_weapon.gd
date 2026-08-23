## Weapon definition for MOBA combat. Carries basic attack properties.
class_name MobaWeapon
extends Resource

## Damage dealt per attack.
@export var damage: float = 0.0

## Type of damage (PHYSICAL, MAGICAL, or TRUE). Uses MobaDamage.DamageType.
@export var damage_type: int = MobaDamage.DamageType.PHYSICAL

## Attacks per second.
@export var attack_speed: float = 1.0

## Attack range in metres.
@export var attack_range: float = 1.0

## Delay before damage is applied, in seconds.
@export var wind_up: float = 0.0

## Delay after damage, during which the next attack cannot start, in seconds.
@export var recovery: float = 0.0

## Speed of projectiles, if any. Zero means melee. In metres per second.
@export var projectile_speed: float = 0.0
