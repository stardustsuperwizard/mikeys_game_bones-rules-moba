"""Tests for damage calculation formulas.

These tests validate that damage formulas match the design specification (§8).
"""

import pytest

from sim.formulas import (
    magical_damage,
    mitigation_multiplier,
    physical_damage,
    true_damage,
)


class TestMitigationMultiplier:
    """Tests for the mitigation_multiplier base formula."""

    def test_zero_defense_does_not_reduce_damage(self):
        """Zero defense should result in 100% damage (multiplier = 1.0)."""
        assert mitigation_multiplier(0) == 1.0

    def test_100_defense_halves_damage(self):
        """100 defense should reduce damage by half (multiplier = 0.5)."""
        assert mitigation_multiplier(100) == pytest.approx(0.5)

    def test_50_defense_divides_damage_by_1_5(self):
        """50 defense should result in 2/3 damage (multiplier ≈ 0.6667)."""
        assert mitigation_multiplier(50) == pytest.approx(0.6667, rel=1e-4)

    def test_negative_defense_clamped_to_zero(self):
        """Negative defense should be clamped to zero (no increased damage)."""
        assert mitigation_multiplier(-30) == 1.0

    def test_high_defense_approaches_zero(self):
        """Very high defense should approach but never exceed zero damage."""
        # 10000 defense should be very close to zero but not negative
        multiplier = mitigation_multiplier(10000)
        assert 0 < multiplier < 0.01


class TestPhysicalDamage:
    """Tests for physical damage calculation."""

    def test_section_8_worked_example(self):
        """Per §8: 50 raw physical damage vs 50 armor = ~33.33 final damage.
        
        This is the canonical worked example from the ruleset.
        """
        damage = physical_damage(50, 50)
        assert damage == pytest.approx(33.33, rel=1e-3)

    def test_zero_armor_no_reduction(self):
        """Zero armor should not reduce damage."""
        assert physical_damage(100, 0) == pytest.approx(100)

    def test_100_armor_halves_damage(self):
        """100 armor should halve damage."""
        assert physical_damage(100, 100) == pytest.approx(50)

    def test_negative_armor_clamped_to_zero(self):
        """Negative armor should be clamped to zero (no bonus damage)."""
        assert physical_damage(100, -50) == pytest.approx(100)

    def test_armor_scales_with_damage(self):
        """Armor reduction should scale linearly with raw damage."""
        # If 50 raw vs 50 armor → 33.33, then 100 raw vs 50 armor → 66.67
        assert physical_damage(100, 50) == pytest.approx(66.6667, rel=1e-4)


class TestMagicalDamage:
    """Tests for magical damage calculation."""

    def test_follows_same_formula_as_physical(self):
        """Magical damage should follow the same formula as physical damage."""
        raw = 100
        resistance = 50
        
        phys = physical_damage(raw, resistance)
        mag = magical_damage(raw, resistance)
        
        assert phys == mag

    def test_zero_resistance_no_reduction(self):
        """Zero resistance should not reduce damage."""
        assert magical_damage(100, 0) == pytest.approx(100)

    def test_100_resistance_halves_damage(self):
        """100 resistance should halve damage."""
        assert magical_damage(100, 100) == pytest.approx(50)


class TestTrueDamage:
    """Tests for true damage (ignores all defenses)."""

    def test_true_damage_never_reduced(self):
        """True damage should be immune to any defense stat."""
        raw = 100
        
        # True damage should always equal the raw input
        assert true_damage(raw) == raw
        
        # True damage should be more than mitigated physical damage
        assert true_damage(raw) > physical_damage(raw, 50)

    def test_true_damage_zero_input(self):
        """True damage with zero input should be zero."""
        assert true_damage(0) == 0
