"""Tests for sustain (lifesteal, omnivamp, and healing) formulas.

These tests validate the sustain healing calculations and clamped healing
formulas, mirroring the same test cases in rules/tests/sustain_test.gd.

Shared cases between GDScript and Python:
  - sustain_healing(40.0, 0.10) == 4.0
  - sustain_healing(0.0, 0.10) == 0.0
  - clamped_heal(480.0, 500.0, 100.0) == 20.0
  - clamped_heal(500.0, 500.0, 100.0) == 0.0
  - clamped_heal(100.0, 500.0, -10.0) == 0.0
"""

import pytest

from sim.formulas import (
    clamped_heal,
    sustain_healing,
)


class TestSustainHealing:
    """Tests for the sustain_healing formula."""

    def test_worked_example_40_damage_10_percent(self):
        """Worked example: 40 damage dealt, 10% lifesteal → exactly 4.0 healing.

        Shared conformance case with rules/tests/sustain_test.gd.
        """
        assert sustain_healing(40.0, 0.10) == pytest.approx(4.0)

    def test_zero_damage_yields_zero_heal(self):
        """Zero damage dealt should yield zero healing regardless of sustain %.

        Shared conformance case with rules/tests/sustain_test.gd.
        """
        assert sustain_healing(0.0, 0.10) == pytest.approx(0.0)

    def test_negative_damage_clamps_to_zero(self):
        """Negative damage (which should never happen) clamps to 0.0."""
        assert sustain_healing(-10.0, 0.10) == pytest.approx(0.0)

    def test_high_sustain_percentage(self):
        """High sustain percentage: 100 damage dealt, 50% sustain → 50.0 healing."""
        assert sustain_healing(100.0, 0.50) == pytest.approx(50.0)

    def test_fractional_damage_and_sustain(self):
        """Fractional values: 38.5 damage, 10% sustain → 3.85 healing."""
        assert sustain_healing(38.5, 0.10) == pytest.approx(3.85)

    def test_overkill_scenario(self):
        """Overkill: 10 damage dealt (from 200 raw, 10 health remaining), 10% sustain → 1.0 healing."""
        assert sustain_healing(10.0, 0.10) == pytest.approx(1.0)


class TestClampedHeal:
    """Tests for the clamped_heal formula."""

    def test_normal_heal_with_capacity(self):
        """Normal case: 480 current / 500 max, heal 100 → applies 20.

        Shared conformance case with rules/tests/sustain_test.gd.
        """
        assert clamped_heal(480.0, 500.0, 100.0) == pytest.approx(20.0)

    def test_heal_at_full_health(self):
        """At full health: 500 current / 500 max, heal 100 → applies 0.0.

        Shared conformance case with rules/tests/sustain_test.gd.
        """
        assert clamped_heal(500.0, 500.0, 100.0) == pytest.approx(0.0)

    def test_negative_heal_clamps_to_zero(self):
        """Negative heal: 100 current / 500 max, heal -10 → applies 0.0.

        Shared conformance case with rules/tests/sustain_test.gd.
        """
        assert clamped_heal(100.0, 500.0, -10.0) == pytest.approx(0.0)

    def test_exact_to_full_health(self):
        """Exact heal to full: 490 current / 500 max, heal 10 → applies 10."""
        assert clamped_heal(490.0, 500.0, 10.0) == pytest.approx(10.0)

    def test_overheal_boundary(self):
        """Overheal: 490 current / 500 max, heal 20 → applies 10 (caps at max)."""
        assert clamped_heal(490.0, 500.0, 20.0) == pytest.approx(10.0)

    def test_zero_heal_amount(self):
        """Zero heal: 400 current / 500 max, heal 0 → applies 0.0."""
        assert clamped_heal(400.0, 500.0, 0.0) == pytest.approx(0.0)

    def test_large_heal_from_low_health(self):
        """Large heal from low health: 1 current / 500 max, heal 1000 → applies 499."""
        assert clamped_heal(1.0, 500.0, 1000.0) == pytest.approx(499.0)

    def test_fractional_values(self):
        """Fractional values: 250.5 current / 500.0 max, heal 100.5 → applies 100.5."""
        assert clamped_heal(250.5, 500.0, 100.5) == pytest.approx(100.5)

    def test_at_zero_health(self):
        """At zero health: 0 current / 500 max, heal 50 → applies 50."""
        assert clamped_heal(0.0, 500.0, 50.0) == pytest.approx(50.0)
