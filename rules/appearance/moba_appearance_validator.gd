## Pure function validator for character appearances.
##
## Decides whether an appearance is legal, returning a typed reason constant
## on refusal. All methods are static, take plain resource arguments, and touch
## no node and no scene tree — the same "pure" bar MobaFormulas documents,
## enabling unit testing and deterministic validation.
class_name MobaAppearanceValidator

## Failure reasons returned as StringName (mirroring MobaAbilityAction convention)
const FAILURE_UNKNOWN_HELM = &"unknown_helm"
const FAILURE_UNKNOWN_CHEST = &"unknown_chest"
const FAILURE_UNKNOWN_COLOR_SCHEME = &"unknown_color_scheme"


## Validate an appearance.
##
## Returns &"" when legal (or when appearance is null), otherwise exactly
## one of the FAILURE_* constants. A null appearance is treated as valid
## (it represents "not set yet").
static func validate(appearance: MobaAppearance) -> StringName:
	if appearance == null:
		return &""

	# Validate helm id
	if not MobaAppearanceCatalog.is_helm_legal(appearance.helm_id):
		return FAILURE_UNKNOWN_HELM

	# Validate chest id
	if not MobaAppearanceCatalog.is_chest_legal(appearance.chest_id):
		return FAILURE_UNKNOWN_CHEST

	# Validate color scheme id
	if not MobaAppearanceCatalog.is_color_scheme_legal(appearance.color_scheme_id):
		return FAILURE_UNKNOWN_COLOR_SCHEME

	return &""
