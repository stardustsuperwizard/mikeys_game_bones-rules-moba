## Authored data Resource for a single active ability (§57 + §58 schema).
## All balance numbers come from inspector-authored .tres files loaded from rules/data/.
## No runtime logic lives here — see the ability pipeline in #27.
class_name MobaAbility
extends Resource

# ---------------------------------------------------------------------------
# Enums (typed so an invalid value is unrepresentable in the inspector).
# ---------------------------------------------------------------------------

enum Discipline {
	WARRIOR,
	GUARDIAN,
	SLAYER,
	MARKSMAN,
	MYSTIC,
	ADVENTURER,
}

## Includes CHANNELED per §58 (distinct from cast_time: it applies effect while held).
enum TargetingType {
	SELF,
	TARGETED,
	SKILLSHOT,
	GROUND,
	AREA,
	TOGGLE,
	CHANNELED,
}

## Target allegiance filter for multi-target abilities.
enum TargetAllegiance {
	HOSTILE,  ## Ability targets enemies
	FRIENDLY,  ## Ability targets allies
	ANY,  ## Ability targets everyone
}

enum AimAssist {
	FREE,
	SOFT_LOCK,
	HARD_LOCK,
	NONE,
}

enum DamageType {
	PHYSICAL,
	MAGICAL,
	TRUE,
	NONE,
}

enum OnCancel {
	FULL_REFUND,
	PARTIAL_REFUND,
	NO_REFUND,
	COOLDOWN_STILL_APPLIES,
}

enum OnChannelBreak {
	NO_EFFECT_REMAINING,
	PARTIAL_EFFECT_ALREADY_APPLIED,
}

# ---------------------------------------------------------------------------
# Identity fields
# ---------------------------------------------------------------------------

## Unique snake_case identifier. Validated against ^[a-z][a-z0-9_]*$.
@export var id: String = "":
	set(value):
		assert(
			value == "" or _is_valid_ability_id(value),
			"MobaAbility.id must match ^[a-z][a-z0-9_]*$: " + value
		)
		id = value

## Human-readable display name.
@export var name: String = ""

## Combat discipline this ability belongs to.
@export var discipline: Discipline = Discipline.WARRIOR

# ---------------------------------------------------------------------------
# Targeting / delivery
# ---------------------------------------------------------------------------

@export var targeting_type: TargetingType = TargetingType.TARGETED
@export var aim_assist: AimAssist = AimAssist.NONE

## Half-angle of the aim cone in degrees (used with SKILLSHOT / CHANNELED).
@export_range(0.0, 180.0) var aim_cone_degrees: float = 0.0

## Snap strength for soft-lock aim assist. 0.0 = no snap, 1.0 = full snap.
@export_range(0.0, 1.0) var magnetism: float = 0.0

## Radius in world units within which a target can be acquired.
@export var acquisition_range: float = 0.0

## Whether an AREA/GROUND ability includes the caster among its affected targets.
@export var affects_caster: bool = false

## Target allegiance filter for multi-target abilities (AREA/GROUND).
@export var target_allegiance: TargetAllegiance = TargetAllegiance.HOSTILE

# ---------------------------------------------------------------------------
# Damage
# ---------------------------------------------------------------------------

@export var damage_type: DamageType = DamageType.NONE
@export var base_damage: float = 0.0

## Scaling coefficients keyed by stat name (e.g. {"attack_damage": 0.6}).
@export var scaling: Dictionary = {}

# ---------------------------------------------------------------------------
# Healing and shielding
# ---------------------------------------------------------------------------

## Instant self-heal on cast.
@export var heal_amount: float = 0.0

## Self-shield capacity on cast (uses ability's duration field for shield duration).
@export var shield_amount: float = 0.0

# ---------------------------------------------------------------------------
# Resource and cooldown
# ---------------------------------------------------------------------------

@export var resource_cost: float = 0.0
@export var cooldown: float = 0.0

# ---------------------------------------------------------------------------
# Timing
# ---------------------------------------------------------------------------

## Delay before the effect resolves (§9).
@export var cast_time: float = 0.0

## Duration of the channel window for CHANNELED abilities (§58).
@export var channel_duration: float = 0.0

## Interval between ticks while channeling (seconds). 0 = continuous.
@export var channel_tick_interval: float = 0.0

## Range in world units.
@export var range: float = 0.0
@export var projectile_speed: float = 0.0
@export var area_radius: float = 0.0

## Duration of the ability's persistent effect (if any), in seconds.
@export var duration: float = 0.0

# ---------------------------------------------------------------------------
# Charges and usability
# ---------------------------------------------------------------------------

@export_range(1, 99) var charges: int = 1
@export var usable_in_air: bool = false

## False only when the ability genuinely cannot be executed with drag-to-aim (§57).
## Treat as a design smell; no default loadout should contain a touch_viable: false ability.
@export var touch_viable: bool = true

# ---------------------------------------------------------------------------
# Crowd control (inline editable)
# ---------------------------------------------------------------------------

## Optional crowd control applied by this ability. Leave null if none.
@export var crowd_control: MobaCrowdControlSpec = null

# ---------------------------------------------------------------------------
# Buffs / debuffs
# ---------------------------------------------------------------------------

@export var buffs: Array[MobaStatModifier] = []
@export var debuffs: Array[MobaStatModifier] = []

## Maximum number of buff/debuff stacks this ability can apply.
@export_range(1, 100) var max_stacks: int = 1

# ---------------------------------------------------------------------------
# Interrupt / cancellation rules (§59)
# ---------------------------------------------------------------------------

@export var cancellable_by_movement: bool = false
@export var cancellable_by_hard_cc: bool = true

## Fraction of resource_cost returned on cancel (0.0 = none, 1.0 = full).
## Used by the runtime when on_cancel == PARTIAL_REFUND.
@export_range(0.0, 1.0) var refund_resource_on_cancel: float = 0.0

## Coarse cancellation policy. When PARTIAL_REFUND, refund_resource_on_cancel
## provides the exact fraction; the runtime ignores that field for other values.
@export var on_cancel: OnCancel = OnCancel.NO_REFUND

## What happens to effect delivery when a channel is broken mid-way (§58).
@export var on_channel_break: OnChannelBreak = OnChannelBreak.NO_EFFECT_REMAINING

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


static func _is_valid_ability_id(value: String) -> bool:
	if value.is_empty():
		return false
	if (
		not value[0].to_lower() == value[0]
		or not value[0].unicode_at(0) >= 97
		or not value[0].unicode_at(0) <= 122
	):
		return false
	for ch in value:
		var code := ch.unicode_at(0)
		var is_lower_alpha := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		var is_underscore := code == 95
		if not (is_lower_alpha or is_digit or is_underscore):
			return false
	return true
