"""Tests for defense and cooldown mechanics.

These tests validate defense reduction, armor penetration, and ability haste
formulas using property-based testing with Hypothesis.
"""

import pytest
from hypothesis import given, strategies as st

from sim.formulas import (
    effective_armor,
    effective_cooldown,
    expected_crit_multiplier,
    mitigation_multiplier,
)


class TestMitigationProperties:
    """Property-based tests for mitigation mechanics."""

    def test_mitigation_multiplier_always_positive(self):
        """Mitigation multiplier should always be in range (0, 1]."""
        assert 0 < mitigation_multiplier(0) <= 1.0
        assert 0 < mitigation_multiplier(1000) <= 1.0

    def test_mitigation_multiplier_never_negative(self):
        """Mitigation multiplier should never produce negative multipliers."""
        for defense in [-1000, -1, 0, 1, 100, 10000]:
            assert mitigation_multiplier(defense) > 0

    def test_negative_defense_equals_zero_defense(self):
        """Negative defense should clamp to zero defense."""
        assert mitigation_multiplier(-1) == mitigation_multiplier(0)
        assert mitigation_multiplier(-100) == mitigation_multiplier(0)

    def test_mitigation_multiplier_decreases_with_defense(self):
        """More defense should always reduce damage multiplier."""
        assert mitigation_multiplier(0) > mitigation_multiplier(10)
        assert mitigation_multiplier(10) > mitigation_multiplier(100)
        assert mitigation_multiplier(100) > mitigation_multiplier(1000)

    def test_mitigation_at_zero_is_exactly_one(self):
        """Per the spec, mitigation_multiplier(0) must be exactly 1.0."""
        assert mitigation_multiplier(0) == 1.0

    def test_mitigation_at_negative_thirty_is_one(self):
        """Negative defense should clamp to zero, returning 1.0."""
        assert mitigation_multiplier(-30) == 1.0


class TestEffectiveArmor:
    """Tests for effective armor calculation with penetration."""

    def test_zero_penetration_no_change(self):
        """No penetration should leave armor unchanged."""
        assert effective_armor(100, flat_pen=0, percent_pen=0.0) == 100

    def test_flat_pen_reduces_armor(self):
        """Flat penetration should reduce effective armor linearly."""
        base = 100
        assert effective_armor(base, flat_pen=10) == 90
        assert effective_armor(base, flat_pen=50) == 50

    def test_percent_pen_reduces_remaining_armor(self):
        """Percent penetration applies to remaining armor after flat pen."""
        # Start with 100 armor, no flat pen, 20% percent pen
        # Result: 100 * (1 - 0.2) = 80
        assert effective_armor(100, flat_pen=0, percent_pen=0.2) == 80

    def test_combined_penetration(self):
        """Flat and percent penetration should combine correctly."""
        # 100 armor - 10 flat = 90 remaining
        # 90 * (1 - 0.2) = 72
        assert effective_armor(100, flat_pen=10, percent_pen=0.2) == 72

    def test_penetration_cannot_go_negative(self):
        """Effective armor should never be negative (clamped at 0)."""
        # Even with excessive penetration
        assert effective_armor(50, flat_pen=100, percent_pen=0.5) == 0

    def test_100_percent_penetration_nullifies_armor(self):
        """100% penetration should reduce armor to zero."""
        assert effective_armor(100, flat_pen=0, percent_pen=1.0) == 0


class TestAbilityHaste:
    """Tests for cooldown reduction via Ability Haste."""

    def test_zero_haste_no_cooldown_reduction(self):
        """Zero Ability Haste should not reduce cooldown."""
        base = 10.0
        assert effective_cooldown(base, ability_haste=0) == base

    def test_100_haste_halves_cooldown(self):
        """100 Ability Haste should reduce cooldown by half."""
        base = 10.0
        assert effective_cooldown(base, 100) == pytest.approx(5.0)

    def test_50_haste_reduces_to_two_thirds(self):
        """50 Ability Haste should reduce cooldown to 2/3 of base."""
        base = 10.0
        assert effective_cooldown(base, 50) == pytest.approx(6.6667, rel=1e-4)

    @given(
        base_cooldown=st.floats(min_value=0.01, max_value=1000),
        haste_a=st.floats(min_value=0, max_value=10000),
        haste_b=st.floats(min_value=0, max_value=10000),
    )
    def test_increasing_haste_decreases_cooldown(self, base_cooldown, haste_a, haste_b):
        """Property: Increasing Ability Haste never increases effective cooldown.
        
        This is a key property from §61 regression tests.
        """
        if haste_b >= haste_a:
            assert effective_cooldown(base_cooldown, haste_b) <= effective_cooldown(
                base_cooldown, haste_a
            )
        else:
            assert effective_cooldown(base_cooldown, haste_a) <= effective_cooldown(
                base_cooldown, haste_b
            )

    def test_very_high_haste_approaches_zero(self):
        """Extremely high Ability Haste should approach zero cooldown."""
        base = 10.0
        very_high_haste = 100000
        effective = effective_cooldown(base, very_high_haste)
        assert effective < 0.01
        assert effective > 0


class TestCriticalMultiplier:
    """Tests for expected critical strike multiplier."""

    def test_zero_crit_chance_no_multiplier(self):
        """Zero critical chance should result in 1.0x multiplier."""
        assert expected_crit_multiplier(0.0, 2.0) == 1.0

    def test_100_percent_crit_equals_crit_multiplier(self):
        """100% critical chance should equal the crit multiplier."""
        assert expected_crit_multiplier(1.0, 2.0) == 2.0
        assert expected_crit_multiplier(1.0, 2.5) == 2.5

    def test_5_percent_crit_with_2x_damage(self):
        """5% crit with 2.0x multiplier should average 1.05x."""
        # Expected = (1 - 0.05) * 1.0 + 0.05 * 2.0 = 1.05
        assert expected_crit_multiplier(0.05, 2.0) == pytest.approx(1.05)

    def test_25_percent_crit_with_2x_damage(self):
        """25% crit with 2.0x multiplier should average 1.25x."""
        # Expected = (1 - 0.25) * 1.0 + 0.25 * 2.0 = 1.25
        assert expected_crit_multiplier(0.25, 2.0) == pytest.approx(1.25)

    @given(
        crit_chance=st.floats(min_value=0.0, max_value=1.0),
        crit_mult=st.floats(min_value=1.0, max_value=10.0),
    )
    def test_multiplier_between_1_and_crit_multiplier(self, crit_chance, crit_mult):
        """Property: Expected multiplier should be between 1.0 and crit_multiplier."""
        expected = expected_crit_multiplier(crit_chance, crit_mult)
        assert 1.0 <= expected <= crit_mult
