"""Tests for the aim-assist magnetism formula and device multiplier table.

These tests validate that the scalar magnetism model matches the design
specification (§55) and MobaAimAssist's implementation.

## Shared Conformance Cases

The following test cases are asserted identically in both the Python suite (this file)
and the GDScript suite (rules/tests/aim_assist_test.gd). They form the basis of the §65
cross-language conformance audit. When the list is updated, both files must be changed
in tandem.

Shared cases:
  - effective_magnetism(1.0, 1.5) == 1.0 (clamp fires when the product exceeds 1.0)
  - effective_magnetism(0.5, 1.0) == 0.5 (no clamp for an in-range shipped value)
  - effective_magnetism(0.0, multiplier) == 0.0 for every loaded device multiplier
    (free aim is unaffected by device)
  - The loaded device multipliers equal mouse 0.23, gamepad 0.67, touch 1.0
  - Every loaded device multiplier is ≤ 1.0
"""

import pytest

from sim.formulas import effective_magnetism, load_device_multipliers


class TestEffectiveMagnetism:
    """Tests for the effective_magnetism clamp formula."""

    def test_clamp_fires_when_product_exceeds_one(self):
        """A device multiplier above 1.0 combined with high magnetism clamps to 1.0.

        Shared conformance case with rules/tests/aim_assist_test.gd.
        """
        assert effective_magnetism(1.0, 1.5) == 1.0

    def test_clamp_fires_past_one_with_different_inputs(self):
        """A different combination that also exceeds 1.0 still clamps to 1.0."""
        assert effective_magnetism(0.8, 2.0) == 1.0

    def test_clamp_does_not_fire_for_in_range_shipped_value(self):
        """A product within [0.0, 1.0] passes through unchanged (no clamp).

        Shared conformance case with rules/tests/aim_assist_test.gd.
        """
        assert effective_magnetism(0.5, 1.0) == pytest.approx(0.5)

    def test_clamp_does_not_fire_for_any_in_range_shipped_multiplier(self):
        """Every real device multiplier, combined with a moderate magnetism,
        stays within [0.0, 1.0] and is not altered by the clamp.
        """
        multipliers = load_device_multipliers()
        for device, multiplier in multipliers.items():
            result = effective_magnetism(0.5, multiplier)
            expected = 0.5 * multiplier
            assert result == pytest.approx(expected), (
                f"Clamp should not fire for device={device}"
            )

    def test_free_aim_unaffected_by_every_device_multiplier(self):
        """Free aim (magnetism 0.0) yields 0.0 regardless of device multiplier.

        Shared conformance case with rules/tests/aim_assist_test.gd.
        """
        multipliers = load_device_multipliers()
        for device, multiplier in multipliers.items():
            assert effective_magnetism(0.0, multiplier) == 0.0, (
                f"Free aim should be unaffected by device={device}"
            )

    def test_negative_ability_magnetism_clamps_to_zero(self):
        """A negative product clamps to 0.0, matching MobaAimAssist's clamp() call."""
        assert effective_magnetism(-0.5, 1.0) == 0.0


class TestDeviceMultiplierTable:
    """Tests for the per-device multiplier table loaded from rules/data/aim_assist.json."""

    def test_loaded_multipliers_match_shipped_values(self):
        """The loaded table matches the shipped mouse/gamepad/touch values exactly.

        Shared conformance case with rules/tests/aim_assist_test.gd.
        """
        multipliers = load_device_multipliers()
        assert multipliers["mouse"] == pytest.approx(0.23)
        assert multipliers["gamepad"] == pytest.approx(0.67)
        assert multipliers["touch"] == pytest.approx(1.0)

    def test_ratios_preserve_section_55(self):
        """Ratios relative to touch match §55's original gamepad-anchored ratios,
        even though aim_assist.json anchors on touch (1.0) instead of gamepad (1.0)
        to keep the clamp from firing on in-range shipped data.

        Shared conformance case with rules/tests/aim_assist_test.gd.
        """
        multipliers = load_device_multipliers()
        assert multipliers["gamepad"] / multipliers["touch"] == pytest.approx(0.67, abs=1e-4)
        assert multipliers["mouse"] / multipliers["touch"] == pytest.approx(0.23, abs=1e-4)

    def test_every_multiplier_is_at_most_one(self):
        """Every loaded device multiplier is ≤ 1.0.

        Shared conformance case with rules/tests/aim_assist_test.gd.
        """
        multipliers = load_device_multipliers()
        for device, multiplier in multipliers.items():
            assert multiplier <= 1.0, f"{device} multiplier {multiplier} exceeds 1.0"

    def test_comment_key_excluded(self):
        """The hand-authored _comment key is not treated as a device multiplier."""
        multipliers = load_device_multipliers()
        assert "_comment" not in multipliers
