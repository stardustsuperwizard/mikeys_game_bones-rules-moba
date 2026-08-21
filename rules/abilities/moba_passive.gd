## Authored data Resource for a passive ability (§62 schema).
## Passives are always-on traits tied to learned (not equipped) abilities.
## occupies_equipped_slot is intentionally omitted per the implementation contract.
class_name MobaPassive
extends Resource

## Discipline enum shared with MobaAbility.
enum Discipline {
	WARRIOR,
	GUARDIAN,
	SLAYER,
	MARKSMAN,
	MYSTIC,
	ADVENTURER,
}

## Stacking enum matching MobaStatModifier for the passive's own effect.
enum Stacking {
	REFRESH,
	STACK,
	IGNORE,
	REPLACE_IF_STRONGER,
}

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

## Unique snake_case identifier. Validated against ^[a-z][a-z0-9_]*$.
@export var id: String = "":
	set(value):
		assert(value == "" or _is_valid_id(value),
				"MobaPassive.id must match ^[a-z][a-z0-9_]*$: " + value)
		id = value

@export var name: String = ""
@export var discipline: Discipline = Discipline.WARRIOR

# ---------------------------------------------------------------------------
# Trigger
# ---------------------------------------------------------------------------

## Event that activates this passive (e.g. "on_basic_attack_hit").
@export var trigger: String = ""

# ---------------------------------------------------------------------------
# Effect (inline stat modifier)
# ---------------------------------------------------------------------------

@export var effect: MobaStatModifier = null

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _is_valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	if not (value[0].unicode_at(0) >= 97 and value[0].unicode_at(0) <= 122):
		return false
	for ch in value:
		var code := ch.unicode_at(0)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true
