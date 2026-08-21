## Resource containing all baseline combat statistics for a character.
## Defines stats per the MOBA ruleset §6, with baseline values as defaults.
## Stat names are accessed via StringName constants to ensure type safety at the call site.
class_name MobaStatBlock
extends Resource

# Stat name constants - use these instead of bare strings
const HEALTH := &"health"
const HEALTH_REGEN := &"health_regen"
const RESOURCE := &"resource"
const RESOURCE_REGEN := &"resource_regen"
const ATTACK_DAMAGE := &"attack_damage"
const ATTACK_SPEED := &"attack_speed"
const ATTACK_RANGE := &"attack_range"
const ARMOR := &"armor"
const MAGIC_RESISTANCE := &"magic_resistance"
const MOVEMENT_SPEED := &"movement_speed"
const CRIT_CHANCE := &"crit_chance"
const CRIT_DAMAGE := &"crit_damage"
const ABILITY_HASTE := &"ability_haste"
const ARMOR_PEN_FLAT := &"armor_pen_flat"
const ARMOR_PEN_PERCENT := &"armor_pen_percent"
const MAGIC_PEN_FLAT := &"magic_pen_flat"
const MAGIC_PEN_PERCENT := &"magic_pen_percent"
const LIFESTEAL := &"lifesteal"
const OMNIVAMP := &"omnivamp"
const TENACITY := &"tenacity"

# All valid stat names for enumeration
const _VALID_STATS := [
	HEALTH,
	HEALTH_REGEN,
	RESOURCE,
	RESOURCE_REGEN,
	ATTACK_DAMAGE,
	ATTACK_SPEED,
	ATTACK_RANGE,
	ARMOR,
	MAGIC_RESISTANCE,
	MOVEMENT_SPEED,
	CRIT_CHANCE,
	CRIT_DAMAGE,
	ABILITY_HASTE,
	ARMOR_PEN_FLAT,
	ARMOR_PEN_PERCENT,
	MAGIC_PEN_FLAT,
	MAGIC_PEN_PERCENT,
	LIFESTEAL,
	OMNIVAMP,
	TENACITY,
]

# Core stats - §6 baseline values
@export var health: int = 500
@export var health_regen: float = 5.0
@export var resource: int = 250
@export var resource_regen: float = 3.0
@export var attack_damage: int = 50
@export var attack_speed: float = 1.0
@export var attack_range: float = 2.0
@export var armor: int = 30
@export var magic_resistance: int = 25
@export var movement_speed: float = 5.0

# Percentage stats (stored as fractions: 0.05 = 5%)
@export var crit_chance: float = 0.05
@export var crit_damage: float = 2.0
@export var lifesteal: float = 0.0
@export var omnivamp: float = 0.0
@export var tenacity: float = 0.0

# Penetration stats
@export var ability_haste: int = 0
@export var armor_pen_flat: int = 0
@export var armor_pen_percent: float = 0.0
@export var magic_pen_flat: int = 0
@export var magic_pen_percent: float = 0.0


## Get the value of a stat by its StringName key.
## Returns the stat's value as a float.
## Asserts if an unknown stat name is requested.
func get_stat_value(stat: StringName) -> float:
	match stat:
		HEALTH:
			return float(health)
		HEALTH_REGEN:
			return health_regen
		RESOURCE:
			return float(resource)
		RESOURCE_REGEN:
			return resource_regen
		ATTACK_DAMAGE:
			return float(attack_damage)
		ATTACK_SPEED:
			return attack_speed
		ATTACK_RANGE:
			return attack_range
		ARMOR:
			return float(armor)
		MAGIC_RESISTANCE:
			return float(magic_resistance)
		MOVEMENT_SPEED:
			return movement_speed
		CRIT_CHANCE:
			return crit_chance
		CRIT_DAMAGE:
			return crit_damage
		ABILITY_HASTE:
			return float(ability_haste)
		ARMOR_PEN_FLAT:
			return float(armor_pen_flat)
		ARMOR_PEN_PERCENT:
			return armor_pen_percent
		MAGIC_PEN_FLAT:
			return float(magic_pen_flat)
		MAGIC_PEN_PERCENT:
			return magic_pen_percent
		LIFESTEAL:
			return lifesteal
		OMNIVAMP:
			return omnivamp
		TENACITY:
			return tenacity
		_:
			assert(false, "Unknown stat: %s" % stat)
			return 0.0


## Get all valid stat names for enumeration.
## Useful for tests and iteration.
static func get_valid_stats() -> Array[StringName]:
	return _VALID_STATS
