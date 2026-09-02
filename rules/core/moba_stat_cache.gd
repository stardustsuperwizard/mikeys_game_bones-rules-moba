## Caches the effect-container modifier bonuses for one MobaCombatant and
## applies them to a base stat in the project's pinned order.
##
## Caches the (flat, percent) bonus pair per stat, NOT the final value: the base
## is always re-read live from the combatant, so a direct mutation of its
## runtime stat block (as several existing test suites do) is never masked by a
## stale cached result. get_stat() is on the damage path and the movement path,
## so it is the container's modifier list -- not the stat block -- that is only
## scanned when it actually changes; any container mutation clears the whole
## cache through invalidate().
##
## Split out of MobaCombatant to keep that file under the project's
## max-file-lines gate (see .gdlintrc and #325). Like MobaDeathHandler, this is
## a private implementation detail of MobaCombatant: get_stat() remains the
## public seam callers use, and this class only talks back to its combatant
## through public methods.
class_name MobaStatCache
extends RefCounted

## Minimum attack speed, so a stacked slow can never reach zero or invert.
const MINIMUM_ATTACK_SPEED := 0.01

## The combatant whose stats this cache serves.
var _combatant: MobaCombatant = null

## Per-stat cache of the modifier bonuses (flat, percent), keyed by stat name.
var _bonuses: Dictionary = {}


func _init(p_combatant: MobaCombatant) -> void:
	_combatant = p_combatant


## Drop every cached modifier bonus pair.
func invalidate() -> void:
	_bonuses.clear()


## The current effective value of a stat: the base value with every active
## modifier in the effect container applied.
##
## Modifier order is pinned: (base + sum(flat)) * (1 + sum(percent)).
## Percentages sum additively among themselves.
func modified(stat: StringName) -> float:
	var bonus: Dictionary
	if stat in _bonuses:
		bonus = _bonuses[stat]
	else:
		var container := _combatant.get_effect_container()
		bonus = {
			"flat": container.get_flat_bonus(stat), "percent": container.get_percent_bonus(stat)
		}
		_bonuses[stat] = bonus

	var base: float = _combatant.get_base_stat(stat)
	var value: float = (base + bonus["flat"]) * (1.0 + bonus["percent"])
	if stat == MobaStatBlock.ATTACK_SPEED:
		value = maxf(value, MINIMUM_ATTACK_SPEED)

	return value
