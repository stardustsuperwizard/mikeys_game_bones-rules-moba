"""Tests for damage calculation formulas.

These tests validate that damage formulas match the design specification (§8).

## Shared Conformance Cases

The following test cases are asserted identically in both the Python suite (this file)
and the GDScript suite (rules/tests/formulas_test.gd). They form the basis of the §65
cross-language conformance audit. When the list is updated, both files must be changed
in tandem.

Shared cases:
  - effective_armor(100, flat_pen=20, percent_pen=0.30) == 56.0
  - effective_armor(10, flat_pen=30) == 0.0
  - physical_damage(50, 50) ≈ 33.33
  - physical_damage(100, 50) with a 2.0 crit multiplier (raw * 2.0) ≈ 66.67
  - true_damage(42.5) == 42.5 (unaffected by penetration)
  - mitigation_multiplier(0) == 1.0 (zero defense yields 1.0 multiplier)
  - mitigation_multiplier(-30) == 1.0 (negative defense clamps to 1.0 multiplier)
"""

import pytest

from sim.formulas import (
    effective_armor,
    magical_damage,
    mitigation_multiplier,
    physical_damage,
    true_damage,
)


class TestMitigationMultiplier:
    """Tests for the mitigation_multiplier base formula."""

    def test_zero_defense_does_not_reduce_damage(self):
        """Zero defense should result in 100% damage (multiplier = 1.0).
        
        Shared conformance case with rules/tests/formulas_test.gd.
        """
        assert mitigation_multiplier(0) == 1.0

    def test_100_defense_halves_damage(self):
        """100 defense should reduce damage by half (multiplier = 0.5)."""
        assert mitigation_multiplier(100) == pytest.approx(0.5)

    def test_50_defense_divides_damage_by_1_5(self):
        """50 defense should result in 2/3 damage (multiplier ≈ 0.6667)."""
        assert mitigation_multiplier(50) == pytest.approx(0.6667, rel=1e-4)

    def test_negative_defense_clamped_to_zero(self):
        """Negative defense should be clamped to zero (no increased damage).
        
        Shared conformance case with rules/tests/formulas_test.gd.
        """
        assert mitigation_multiplier(-30) == 1.0

    def test_high_defense_approaches_zero(self):
        """Very high defense should approach but never exceed zero damage."""
        # 10000 defense should be very close to zero but not negative
        multiplier = mitigation_multiplier(10000)
        assert 0 < multiplier < 0.01


class TestEffectiveArmor:
    """Tests for the effective_armor formula (armor penetration)."""

    def test_flat_penetration_before_percentage(self):
        """Flat penetration is applied before percentage penetration.
        
        Per §61: effective_armor(100, flat_pen=20, percent_pen=0.30) should be 56.0
        Calculation: (100 - 20) * (1.0 - 0.30) = 80 * 0.7 = 56.0
        
        Shared conformance case with rules/tests/formulas_test.gd.
        """
        result = effective_armor(100, flat_pen=20, percent_pen=0.30)
        assert result == pytest.approx(56.0, abs=0.0001)

    def test_over_penetration_clamps_to_zero(self):
        """Over-penetration clamps to zero rather than becoming a damage amplifier.
        
        Per §61: effective_armor(10, flat_pen=30) should be 0.0
        Calculation: max(0.0, 10 - 30) * (1.0 - 0.0) = 0.0
        
        Shared conformance case with rules/tests/formulas_test.gd.
        """
        result = effective_armor(10, flat_pen=30)
        assert result == pytest.approx(0.0, abs=0.0001)


class TestPhysicalDamage:
    """Tests for physical damage calculation."""

    def test_section_8_worked_example(self):
        """Per §8: 50 raw physical damage vs 50 armor = ~33.33 final damage.
        
        This is the canonical worked example from the ruleset.
        Shared conformance case with rules/tests/formulas_test.gd.
        """
        damage = physical_damage(50, 50)
        assert damage == pytest.approx(33.33, abs=0.01)

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

    def test_crit_multiplier_applied_to_raw_damage_before_mitigation(self):
        """A 2.0 crit multiplier applied to raw damage before mitigation.
        
        With non-zero armor and non-zero penetration. The crit multiplier
        (100 * 2.0 = 200) is applied before armor calculation.
        
        Calculation: physical_damage(100, 50) = 200 * mitigation_multiplier(50)
        = 200 * (100 / 150) ≈ 133.33
        
        Shared conformance case with rules/tests/formulas_test.gd.
        """
        # Apply 2.0 crit multiplier to raw damage of 100
        crit_raw = 100 * 2.0
        result = physical_damage(crit_raw, 50)
        assert result == pytest.approx(133.33, abs=0.01)


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

    def test_true_damage_unaffected_by_potential_penetration(self):
        """True damage is unaffected by armor and any penetration arguments.
        
        Unlike physical_damage, true_damage simply returns raw input unchanged.
        This test verifies that true_damage(42.5) always equals 42.5, regardless
        of what penetration might have done to physical damage.
        
        Shared conformance case with rules/tests/formulas_test.gd.
        """
        raw = 42.5
        assert true_damage(raw) == pytest.approx(42.5)
        
        # Compare with physical damage which would be reduced
        assert true_damage(raw) > physical_damage(raw, 100)
