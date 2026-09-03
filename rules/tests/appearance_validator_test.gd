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
	results.append(_test_malformed_catalog_is_reported_and_recovers())

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


## A malformed catalog is reported and left detectable, and the catalog recovers.
##
## The class advertises safe-by-construction loading, so the failure path is
## worth holding to the same bar as the success path: bad data must set
## load_failed rather than crash or quietly answer "legal", and every legality
## query must refuse while the catalog is unusable rather than guess.
##
## The test restores the real catalog before returning, and asserts the restore
## worked, so it cannot leave later suites reading a poisoned static cache.
static func _test_malformed_catalog_is_reported_and_recovers() -> bool:
	var passed := true

	# A root missing the required category keys.
	MobaAppearanceCatalog.reset_for_testing()
	if MobaAppearanceCatalog._parse_catalog({"helms": ["basic_helm"]}):
		printerr("ERROR: catalog missing 'chests'/'color_schemes' was accepted")
		passed = false
	if not MobaAppearanceCatalog.load_failed:
		printerr("ERROR: malformed catalog did not set load_failed")
		passed = false

	# Reproduce the state a corrupt catalog.json on disk actually leaves behind:
	# the load ran (_loaded) and failed (load_failed). _parse_catalog() alone does
	# not set _loaded, so without this the next query would simply reload the good
	# file from disk and never see the failed state at all.
	#
	# This asserts the outcome -- an unusable catalog never calls an id legal --
	# not any one mechanism enforcing it. Two do: the explicit load_failed guard,
	# whose real job is the diagnostic it pushes, and the emptied cache behind it.
	# Removing either alone still refuses, which is the point of having both.
	MobaAppearanceCatalog._loaded = true
	if MobaAppearanceCatalog.is_helm_legal(&"basic_helm"):
		printerr("ERROR: helm reported legal while the catalog was unusable")
		passed = false

	# A root that is not a dictionary at all.
	MobaAppearanceCatalog.reset_for_testing()
	if MobaAppearanceCatalog._parse_catalog([]):
		printerr("ERROR: non-dictionary catalog root was accepted")
		passed = false

	# The real catalog reloads cleanly afterwards.
	MobaAppearanceCatalog.reset_for_testing()
	if MobaAppearanceCatalog.load_failed:
		printerr("ERROR: reset_for_testing() left load_failed set")
		passed = false
	if not MobaAppearanceCatalog.is_helm_legal(&"basic_helm"):
		printerr("ERROR: catalog did not recover after reset_for_testing()")
		passed = false

	return passed
