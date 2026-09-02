## Character build definition: primary + secondary Discipline, stat allocation, loadout.
##
## A build specifies how a character is equipped for a match: their primary and
## secondary Discipline (restricting which abilities are usable), their stat point
## allocation (on top of a baseline), and their loadout (weapon + action + passive slots).
##
## The build is validated by MobaBuildValidator.validate() before submission.
class_name MobaCharacterBuild
extends Resource

## Character display name.
@export var character_name: String = ""

## Primary combat Discipline, defining which abilities are available.
@export var primary_discipline: MobaAbility.Discipline = MobaAbility.Discipline.WARRIOR

## Secondary combat Discipline, defining which abilities are available.
## Must differ from primary_discipline.
@export var secondary_discipline: MobaAbility.Discipline = MobaAbility.Discipline.GUARDIAN

## Stat point allocation keyed by MobaStatBlock stat StringName constants.
## Values are non-negative int representing points added on top of the baseline.
## Validated and applied by MobaBuildValidator.
##
## Typed rather than a bare Dictionary so the key and value types are enforced
## where the data is authored. Untyped, a .tres holding a non-int value made
## MobaBuildValidator._check_stat_allocation() abort mid-loop on the assignment
## and fall out of validate() returning &"" -- reporting an unreadable build as
## legal, which is the one answer this gate must never give. The negative,
## per-stat-cap and pool checks all assume an int is what they are comparing.
@export var stat_allocation: Dictionary[StringName, int] = {}

## Combat loadout: weapon + 4 action slots + 1 passive slot.
@export var loadout: MobaLoadout = null


## Get an effective MobaStatBlock by applying this build's stat allocation to a baseline.
##
## Duplicates the baseline, adds the allocation to each stat, and returns a new instance.
## Does not mutate the baseline or any other state.
func get_effective_stat_block(baseline: MobaStatBlock) -> MobaStatBlock:
	var result = baseline.duplicate()

	# Apply stat allocation on top of baseline
	for stat_name in stat_allocation:
		var points: int = stat_allocation[stat_name]
		match stat_name:
			MobaStatBlock.HEALTH:
				result.health += points
			MobaStatBlock.HEALTH_REGEN:
				result.health_regen += float(points)
			MobaStatBlock.RESOURCE:
				result.resource += points
			MobaStatBlock.RESOURCE_REGEN:
				result.resource_regen += float(points)
			MobaStatBlock.ATTACK_DAMAGE:
				result.attack_damage += points
			MobaStatBlock.ATTACK_SPEED:
				result.attack_speed += float(points)
			MobaStatBlock.ATTACK_RANGE:
				result.attack_range += float(points)
			MobaStatBlock.ARMOR:
				result.armor += points
			MobaStatBlock.MAGIC_RESISTANCE:
				result.magic_resistance += points
			MobaStatBlock.MOVEMENT_SPEED:
				result.movement_speed += float(points)
			MobaStatBlock.CRIT_CHANCE:
				result.crit_chance += float(points)
			MobaStatBlock.CRIT_DAMAGE:
				result.crit_damage += float(points)
			MobaStatBlock.ABILITY_HASTE:
				result.ability_haste += points
			MobaStatBlock.ARMOR_PEN_FLAT:
				result.armor_pen_flat += points
			MobaStatBlock.ARMOR_PEN_PERCENT:
				result.armor_pen_percent += float(points)
			MobaStatBlock.MAGIC_PEN_FLAT:
				result.magic_pen_flat += points
			MobaStatBlock.MAGIC_PEN_PERCENT:
				result.magic_pen_percent += float(points)
			MobaStatBlock.LIFESTEAL:
				result.lifesteal += float(points)
			MobaStatBlock.OMNIVAMP:
				result.omnivamp += float(points)
			MobaStatBlock.TENACITY:
				result.tenacity += float(points)

	return result
