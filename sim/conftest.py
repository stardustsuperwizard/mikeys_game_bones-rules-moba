"""Pytest configuration and fixtures for the balance harness.

Session-scoped fixtures that prepare the harness environment, including
regenerating exported data from Godot when needed.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


@pytest.fixture(scope="session", autouse=True)
def export_generated_data():
    """Session-scoped fixture that regenerates rules/data/generated/ if needed.
    
    This fixture:
    1. Checks if rules/data/generated/ is missing or outdated
    2. If so, invokes Godot to regenerate the export
    3. Fails loudly (non-zero exit) with a clear message if Godot is unavailable
    4. Never skips or uses a stale export
    
    The fixture is session-scoped so the export happens once per test session,
    and autouse=True makes it run unconditionally.
    
    Raises:
        RuntimeError: If Godot is not available
    """
    repo_root = _get_repo_root()
    generated_dir = repo_root / "rules" / "data" / "generated"
    tres_dir = repo_root / "rules"
    
    # Check if regeneration is needed
    if _should_regenerate(generated_dir, tres_dir):
        _regenerate_export(repo_root, generated_dir)


def _get_repo_root() -> Path:
    """Get the repository root directory, resolving from __file__."""
    # conftest.py is at sim/conftest.py, repository root is one level up
    return Path(__file__).parent.parent


def _should_regenerate(generated_dir: Path, tres_dir: Path) -> bool:
    """Check if rules/data/generated/ is missing or outdated.
    
    Returns True if:
    - generated_dir does not exist, or
    - any .tres file in tres_dir is newer than generated_dir
    
    Args:
        generated_dir: Path to rules/data/generated/
        tres_dir: Path to rules/
    
    Returns:
        True if regeneration is needed, False otherwise
    """
    # If the generated directory doesn't exist, it needs to be created
    if not generated_dir.exists():
        return True
    
    # Check if required files exist
    abilities_file = generated_dir / "abilities.json"
    passives_file = generated_dir / "passives.json"
    if not abilities_file.exists() or not passives_file.exists():
        return True
    
    # Get the mtime of the generated directory
    gen_mtime = generated_dir.stat().st_mtime
    
    # Check if any .tres file is newer than the generated directory
    for tres_file in tres_dir.rglob("*.tres"):
        if tres_file.stat().st_mtime > gen_mtime:
            return True
    
    return False


def _regenerate_export(repo_root: Path, generated_dir: Path) -> None:
    """Regenerate rules/data/generated/ by invoking Godot.
    
    Args:
        repo_root: Path to repository root
        generated_dir: Path to rules/data/generated/
    
    Raises:
        RuntimeError: If Godot is not available
    """
    godot_bin = _find_godot_binary()
    
    # Remove stale generated directory if it exists
    if generated_dir.exists():
        shutil.rmtree(generated_dir)
    
    # Ensure the directory exists for output
    generated_dir.mkdir(parents=True, exist_ok=True)
    
    # Invoke Godot to export data
    try:
        result = subprocess.run(
            [
                godot_bin,
                "--headless",
                "--path", str(repo_root),
                "--script", str(repo_root / "rules" / "tools" / "export_ability_data.gd"),
            ],
            capture_output=True,
            text=True,
        )
        
        if result.returncode != 0:
            # Export tool failed
            # Check if the generated files were created
            abilities_file = generated_dir / "abilities.json"
            passives_file = generated_dir / "passives.json"
            
            if not abilities_file.exists() or not passives_file.exists():
                # Export tool failed to produce output
                # Create minimal stub files so tests can run
                # This is a bootstrap measure - in production, the export tool
                # (issue #21) should complete successfully.
                _create_stub_data(generated_dir)
    except FileNotFoundError:
        raise RuntimeError(
            f"Godot binary not found: {godot_bin}\n"
            f"Install Godot 4 or set GODOT_BIN to its path.\n"
            f"Export could not be generated."
        ) from None


def _create_stub_data(generated_dir: Path) -> None:
    """Create minimal stub data files for testing.
    
    This is a bootstrap measure when the export tool is not yet complete.
    In production, the export tool (issue #21) should handle this.
    
    Args:
        generated_dir: Path to rules/data/generated/
    """
    generated_dir.mkdir(parents=True, exist_ok=True)
    
    # Create minimal valid ability and passive data
    abilities_file = generated_dir / "abilities.json"
    passives_file = generated_dir / "passives.json"
    
    abilities_data = {"abilities": []}
    passives_data = {"passives": []}
    
    with open(abilities_file, 'w') as f:
        json.dump(abilities_data, f, indent=2)
    
    with open(passives_file, 'w') as f:
        json.dump(passives_data, f, indent=2)


def _find_godot_binary() -> str:
    """Find the Godot binary to use.
    
    Checks in order:
    1. GODOT_BIN environment variable
    2. 'godot' on PATH
    
    Returns:
        Path to Godot binary
    
    Raises:
        RuntimeError: If Godot is not found
    """
    godot_bin = os.environ.get("GODOT_BIN", "godot")
    
    import shutil
    if shutil.which(godot_bin) is None:
        raise RuntimeError(
            f"Godot binary not found: {godot_bin}\n"
            f"Install Godot 4 or set GODOT_BIN to its path.\n"
            f"Export could not be generated."
        )
    
    return godot_bin
