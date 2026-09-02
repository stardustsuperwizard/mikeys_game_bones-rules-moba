## Resolves one MobaDamage packet against a single MobaCombatant.
##
## Owns the pinned resolution order that MobaCombatant.apply_damage() used to
## carry inline: crit roll, damage-type routing, penetration and mitigation,
## shield consumption, health reduction, then attacker sustain. The order is
## the contract; this class exists to hold it in one readable place rather
## than as the longest function in the combatant.
##
## Split out of MobaCombatant to keep that file under the project's
## max-file-lines gate (see .gdlintrc and #325). Like MobaDeathHandler, this is
## a private implementation detail of MobaCombatant: apply_damage() remains the
## sole public seam callers use, and this class only talks back to its
## combatant through public methods -- including write_health() and
## consume_shields(), which exist for this resolver to call.
class_name MobaDamageResolver
extends RefCounted

## The combatant taking the damage this resolver resolves.
var _combatant: MobaCombatant = null


func _init(p_combatant: MobaCombatant) -> void:
	_combatant = p_combatant


## Resolve a damage packet against the combatant.
##
## Returns early and emits nothing if the combatant is not alive (DEAD state).
## Otherwise, resolution order (pinned per Architecture Constraints):
## 1. Raw amount
## 2. Crit roll and multiplier (if can_crit)
## 3. Damage-type routing (PHYSICAL/MAGICAL/TRUE)
## 4. Penetration against target's defense
## 5. Mitigation multiplier
## 6. Final amount
## 7. Shield consumption (shortest-remaining-duration first, before health)
##
## Emits damage_resolved once per packet (if not dead).
func resolve(damage: MobaDamage) -> void:
	# Refuse damage on dead combatants: this is what makes "two lethal hits in one
	# physics frame" fire death exactly once (the first hit transitions to DEAD,
	# the second is refused by the alive check here, not by comparing health magnitude).
	if not _combatant.is_alive():
		return

	var raw: float = damage.amount
	var was_crit: bool = false

	# Step 2: Crit roll and multiplier.
	#
	# Crit is the ATTACKER's statistic, so it is read off damage.source -- not
	# off the combatant, which is the one taking the hit. Unattributed damage
	# (source is null, or is not a MobaCombatant) has no attacker to roll for
	# and therefore never crits.
	var attacker := damage.source as MobaCombatant
	var final: float = raw
	if damage.can_crit and attacker != null:
		var crit_chance: float = attacker.get_stat(MobaStatBlock.CRIT_CHANCE)
		var crit_damage: float = attacker.get_stat(MobaStatBlock.CRIT_DAMAGE)
		var crit_roll: float = MobaRules.roll_crit()

		if MobaFormulas.is_critical(crit_roll, crit_chance):
			was_crit = true
			final = MobaFormulas.apply_crit(raw, crit_damage)

	final = _mitigate(damage, final)

	# Step 7: Shield consumption (shortest-remaining-duration first)
	var pre_shield_final := final
	final = _combatant.consume_shields(final)
	var post_shield_final := final

	# Populate post-resolution fields on the damage packet for listeners
	damage.final_amount = final
	damage.was_crit = was_crit

	# Compute shield_absorbed and health_applied for lifesteal/omnivamp calculation
	var shield_absorbed := pre_shield_final - post_shield_final
	var current_health_before_hit := _combatant.current_health
	var health_applied := minf(post_shield_final, maxf(0.0, current_health_before_hit))
	var damage_dealt := shield_absorbed + health_applied

	# Reduce health
	_combatant.write_health(current_health_before_hit - final)

	_apply_sustain(damage, attacker, damage_dealt)
	_log(damage, attacker, raw, final, was_crit)

	# Emit damage_resolved
	_combatant.damage_resolved.emit(
		raw, final, damage.damage_type, was_crit, damage.source, shield_absorbed
	)


## Steps 3-6: route by damage type, applying penetration and mitigation
## against the combatant's matching defense. TRUE damage ignores both.
func _mitigate(damage: MobaDamage, amount: float) -> float:
	match damage.damage_type:
		MobaDamage.DamageType.PHYSICAL:
			var armor: float = _combatant.get_stat(MobaStatBlock.ARMOR)
			return MobaFormulas.physical_damage(amount, armor, damage.flat_pen, damage.percent_pen)

		MobaDamage.DamageType.MAGICAL:
			var resistance: float = _combatant.get_stat(MobaStatBlock.MAGIC_RESISTANCE)
			return MobaFormulas.magical_damage(
				amount, resistance, damage.flat_pen, damage.percent_pen
			)

	# TRUE damage ignores all defenses and penetration
	return MobaFormulas.true_damage(amount)


## Heal the attacker for lifesteal (basic attacks only) plus omnivamp, against
## the damage actually dealt to shields and health.
func _apply_sustain(damage: MobaDamage, attacker: MobaCombatant, damage_dealt: float) -> void:
	if attacker == null or damage_dealt <= 0.0:
		return

	var lifesteal_pct := 0.0
	if damage.is_basic_attack:
		lifesteal_pct = attacker.get_stat(MobaStatBlock.LIFESTEAL)

	var omnivamp_pct := attacker.get_stat(MobaStatBlock.OMNIVAMP)
	var heal_pct := lifesteal_pct + omnivamp_pct

	if heal_pct > 0.0:
		attacker.apply_healing(MobaFormulas.sustain_healing(damage_dealt, heal_pct))


func _log(
	damage: MobaDamage, attacker: MobaCombatant, raw: float, final: float, was_crit: bool
) -> void:
	var attacker_name := "unattributed"
	if attacker != null and attacker.get_parent() != null:
		attacker_name = String(attacker.get_parent().name)

	var target_name := String(_combatant.name)
	if _combatant.get_parent() != null:
		target_name = String(_combatant.get_parent().name)

	print(
		(
			"[MobaCombat] %s -> %s: %.1f raw / %.1f final (%s%s)"
			% [
				attacker_name,
				target_name,
				raw,
				final,
				MobaDamage.DamageType.keys()[damage.damage_type],
				", CRIT" if was_crit else ""
			]
		)
	)
