"""Ability loading and schema validation for the balance harness.

This module loads exported abilities from rules/data/generated/ and validates
them against the ability schema.
"""

import json
from pathlib import Path
from typing import Any

import jsonschema


def load_generated_file(filename: str) -> dict[str, Any]:
    """Load a JSON file from rules/data/generated/.
    
    Args:
        filename: Name of the file to load (e.g., 'abilities.json')
    
    Returns:
        Parsed JSON content
    
    Raises:
        FileNotFoundError: If the file does not exist in rules/data/generated/
    """
    repo_root = _get_repo_root()
    file_path = repo_root / "rules" / "data" / "generated" / filename
    
    if not file_path.exists():
        raise FileNotFoundError(
            f"Generated file not found: {file_path}\n"
            f"Run the export tool or ensure conftest.py regenerated the export."
        )
    
    with open(file_path) as f:
        return json.load(f)


def load_schema_file(filename: str) -> dict[str, Any]:
    """Load a JSON schema from rules/data/schema/.
    
    Args:
        filename: Name of the schema file (e.g., 'ability.schema.json')
    
    Returns:
        Parsed JSON schema
    
    Raises:
        FileNotFoundError: If the schema file does not exist
    """
    repo_root = _get_repo_root()
    file_path = repo_root / "rules" / "data" / "schema" / filename
    
    if not file_path.exists():
        raise FileNotFoundError(f"Schema file not found: {file_path}")
    
    with open(file_path) as f:
        return json.load(f)


def load_abilities() -> list[dict[str, Any]]:
    """Load and return the list of all exported abilities.
    
    Returns:
        List of ability dictionaries from rules/data/generated/abilities.json
    
    Raises:
        FileNotFoundError: If the generated file does not exist
    """
    data = load_generated_file("abilities.json")
    if isinstance(data, dict) and "abilities" in data:
        return data["abilities"]
    if isinstance(data, list):
        return data
    raise ValueError("abilities.json has unexpected format")


def load_passives() -> list[dict[str, Any]]:
    """Load and return the list of all exported passives.
    
    Returns:
        List of passive dictionaries from rules/data/generated/passives.json
    
    Raises:
        FileNotFoundError: If the generated file does not exist
    """
    data = load_generated_file("passives.json")
    if isinstance(data, dict) and "passives" in data:
        return data["passives"]
    if isinstance(data, list):
        return data
    raise ValueError("passives.json has unexpected format")


def validate_ability(ability: dict[str, Any]) -> None:
    """Validate a single ability against the ability schema.
    
    Args:
        ability: Ability dictionary to validate
    
    Raises:
        jsonschema.ValidationError: If validation fails
    """
    schema = load_schema_file("ability.schema.json")
    jsonschema.validate(ability, schema)


def validate_all_abilities() -> list[dict[str, Any]]:
    """Load all abilities and validate each against the schema.
    
    Returns:
        List of validated abilities
    
    Raises:
        jsonschema.ValidationError: If any ability fails validation
        FileNotFoundError: If generated or schema files are missing
    """
    abilities = load_abilities()
    for ability in abilities:
        validate_ability(ability)
    return abilities


def validate_all_passives() -> list[dict[str, Any]]:
    """Load all passives and validate each against the passive schema.
    
    Returns:
        List of validated passives
    
    Raises:
        jsonschema.ValidationError: If any passive fails validation
        FileNotFoundError: If generated or schema files are missing
    """
    passives = load_passives()
    schema = load_schema_file("passive.schema.json")
    for passive in passives:
        jsonschema.validate(passive, schema)
    return passives


def validate_schemas() -> None:
    """Validate that the schema files themselves are valid JSON Schema draft-07.
    
    Raises:
        jsonschema.SchemaError: If any schema is invalid
    """
    ability_schema = load_schema_file("ability.schema.json")
    passive_schema = load_schema_file("passive.schema.json")
    
    # Validate schemas against draft-07 metaschema
    jsonschema.Draft7Validator.check_schema(ability_schema)
    jsonschema.Draft7Validator.check_schema(passive_schema)


def _get_repo_root() -> Path:
    """Get the repository root directory.
    
    Resolves from this module's location, not from cwd.
    
    Returns:
        Path to repository root
    """
    # This module is at sim/abilities.py
    # Repository root is two levels up
    return Path(__file__).parent.parent
