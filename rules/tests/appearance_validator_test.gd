## Test suite for MobaAppearance and MobaAppearanceValidator.
##
## Covers: appearance id legality (empty values, catalog presence),
## null appearance handling, and the appearance catalog loading.
class_name AppearanceValidatorTest

const MobaAppearance = preload("res://rules/appearance/moba_appearance.gd")
const MobaAppearanceValidator = preload("res://rules/appearance/moba_appearance_validator.gd")
const MobaAppearanceCatalog = preload("res://rules/appearance/moba_appearance_catalog.gd")


## Static entry point for headless test execution.
static func run() -> bool:
	var results: Array[bool] = []

	results.append(_test_null_appearance_legal())
	results.append(_test_empty_appearance_legal())
	results.append(_test_all_empty_ids_legal())
	results.append(_test_valid_helm_legal())
	results.append(_test_valid_chest_legal())
	results.append(_test_valid_color_scheme_legal())
	results.append(_test_all_valid_ids_legal())
	results.append(_test_unknown_helm_refused())
	results.append(_test_unknown_chest_refused())
	results.append(_test_unknown_color_scheme_refused())
	results.append(_test_mixed_valid_invalid_refused_on_helm())

	return results.all(func(result: bool) -> bool: return result)


## Report a mismatch between the expected and actual validator verdict.
static func _expect(label: String, actual: StringName, expected: StringName) -> bool:
	if actual != expected:
		printerr("ERROR: %s -- expected '%s', got '%s'" % [label, String(expected), String(actual)])
		return false
	return true


## A null appearance is treated as legal (no appearance set yet).
static func _test_null_appearance_legal() -> bool:
	return _expect("null appearance", MobaAppearanceValidator.validate(null), &"")


## An appearance with all empty ids is legal (all fields default to "none").
static func _test_empty_appearance_legal() -> bool:
	var appearance := MobaAppearance.new()
	# All fields default to "", which is legal
	return _expect(
		"appearance with all empty ids", MobaAppearanceValidator.validate(appearance), &""
	)


## An appearance created with no modifications has all empty strings and is legal.
static func _test_all_empty_ids_legal() -> bool:
	var appearance := MobaAppearance.new()
	appearance.helm_id = ""
	appearance.chest_id = ""
	appearance.color_scheme_id = ""

	return _expect(
		"appearance with explicitly empty ids", MobaAppearanceValidator.validate(appearance), &""
	)


## A valid helm id from the catalog is accepted.
static func _test_valid_helm_legal() -> bool:
	var appearance := MobaAppearance.new()
	appearance.helm_id = "basic_helm"
	appearance.chest_id = ""
	appearance.color_scheme_id = ""

	return _expect(
		"appearance with valid helm_id", MobaAppearanceValidator.validate(appearance), &""
	)


## A valid chest id from the catalog is accepted.
static func _test_valid_chest_legal() -> bool:
	var appearance := MobaAppearance.new()
	appearance.helm_id = ""
	appearance.chest_id = "basic_chest"
	appearance.color_scheme_id = ""

	return _expect(
		"appearance with valid chest_id", MobaAppearanceValidator.validate(appearance), &""
	)


## A valid color scheme id from the catalog is accepted.
static func _test_valid_color_scheme_legal() -> bool:
	var appearance := MobaAppearance.new()
	appearance.helm_id = ""
	appearance.chest_id = ""
	appearance.color_scheme_id = "crimson"

	return _expect(
		"appearance with valid color_scheme_id", MobaAppearanceValidator.validate(appearance), &""
	)


## An appearance with all valid ids is accepted.
static func _test_all_valid_ids_legal() -> bool:
	var appearance := MobaAppearance.new()
	appearance.helm_id = "iron_helm"
	appearance.chest_id = "leather_chest"
	appearance.color_scheme_id = "azure"

	return _expect(
		"appearance with all valid ids", MobaAppearanceValidator.validate(appearance), &""
	)


## An unknown helm id is refused with FAILURE_UNKNOWN_HELM.
static func _test_unknown_helm_refused() -> bool:
	var appearance := MobaAppearance.new()
	appearance.helm_id = "nonexistent_helm"
	appearance.chest_id = ""
	appearance.color_scheme_id = ""

	return _expect(
		"unknown helm_id",
		MobaAppearanceValidator.validate(appearance),
		MobaAppearanceValidator.FAILURE_UNKNOWN_HELM
	)


## An unknown chest id is refused with FAILURE_UNKNOWN_CHEST.
static func _test_unknown_chest_refused() -> bool:
	var appearance := MobaAppearance.new()
	appearance.helm_id = ""
	appearance.chest_id = "nonexistent_chest"
	appearance.color_scheme_id = ""

	return _expect(
		"unknown chest_id",
		MobaAppearanceValidator.validate(appearance),
		MobaAppearanceValidator.FAILURE_UNKNOWN_CHEST
	)


## An unknown color scheme id is refused with FAILURE_UNKNOWN_COLOR_SCHEME.
static func _test_unknown_color_scheme_refused() -> bool:
	var appearance := MobaAppearance.new()
	appearance.helm_id = ""
	appearance.chest_id = ""
	appearance.color_scheme_id = "nonexistent_scheme"

	return _expect(
		"unknown color_scheme_id",
		MobaAppearanceValidator.validate(appearance),
		MobaAppearanceValidator.FAILURE_UNKNOWN_COLOR_SCHEME
	)


## When multiple ids are invalid, the first invalid one (helm, chest, color_scheme)
## is the one reported.
static func _test_mixed_valid_invalid_refused_on_helm() -> bool:
	var appearance := MobaAppearance.new()
	appearance.helm_id = "nonexistent_helm"
	appearance.chest_id = "nonexistent_chest"
	appearance.color_scheme_id = ""

	return _expect(
		"multiple invalid ids, reports helm first",
		MobaAppearanceValidator.validate(appearance),
		MobaAppearanceValidator.FAILURE_UNKNOWN_HELM
	)
