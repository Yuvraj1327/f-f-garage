"""The SQL enums, the Python enums and the Dart enums must list identical values.

This is the guard for "keep the database schema, API contracts and Flutter
models consistent": adding a value in one place without the others fails here.
"""

import re
from enum import StrEnum
from pathlib import Path

import pytest

from app.domain import enums

REPO_ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = sorted((REPO_ROOT / "supabase" / "migrations").glob("*.sql"))
DART_ENUMS = REPO_ROOT / "mobile" / "lib" / "data" / "models" / "enums.dart"


def _snake_to_pascal(name: str) -> str:
    return "".join(part.capitalize() for part in name.split("_"))


def sql_enums() -> dict[str, list[str]]:
    """{PascalCaseName: [values in declared order]} from CREATE TYPE ... AS ENUM."""
    found: dict[str, list[str]] = {}
    pattern = re.compile(r"create\s+type\s+public\.(\w+)\s+as\s+enum\s*\((.*?)\)\s*;", re.S | re.I)
    for migration in MIGRATIONS:
        for name, body in pattern.findall(migration.read_text()):
            found[_snake_to_pascal(name)] = re.findall(r"'([a-z_]+)'", body)
    # Values added later keep their declared order: ALTER TYPE ... ADD VALUE appends.
    add_value = re.compile(
        r"alter\s+type\s+public\.(\w+)\s+add\s+value\s+(?:if\s+not\s+exists\s+)?'([a-z_]+)'", re.I
    )
    for migration in MIGRATIONS:
        for name, value in add_value.findall(migration.read_text()):
            values = found[_snake_to_pascal(name)]
            if value not in values:
                values.append(value)
    return found


def python_enums() -> dict[str, list[str]]:
    return {
        name: [member.value for member in obj]
        for name, obj in vars(enums).items()
        if isinstance(obj, type) and issubclass(obj, StrEnum) and obj is not StrEnum
    }


def dart_enums() -> dict[str, list[str]]:
    """Reads `enum Name { camelName('api_value'), ... ;` blocks."""
    source = DART_ENUMS.read_text()
    found: dict[str, list[str]] = {}
    for name, body in re.findall(r"enum\s+(\w+)\b[^{]*\{(.*?);", source, re.S):
        found[name] = re.findall(r"\w+\('([a-z_]+)'\)", body)
    return found


APP_CONFIG_DART = REPO_ROOT / "mobile" / "lib" / "core" / "config" / "app_config.dart"


def sql_driver_email_domain() -> str:
    pattern = re.compile(
        r"function\s+public\.driver_email_domain\(\).*?select\s+'([^']+)'::text", re.S | re.I
    )
    for migration in MIGRATIONS:
        match = pattern.search(migration.read_text())
        if match:
            return match.group(1)
    raise AssertionError("public.driver_email_domain() not found in the migrations")


def test_driver_email_domain_is_identical_in_sql_python_and_dart() -> None:
    from app.core.config import Settings

    sql_domain = sql_driver_email_domain()
    python_domain = Settings.model_fields["driver_email_domain"].default
    dart_match = re.search(r"defaultDriverEmailDomain\s*=\s*'([^']+)'", APP_CONFIG_DART.read_text())
    assert dart_match, "defaultDriverEmailDomain not found in app_config.dart"
    assert sql_domain == python_domain == dart_match.group(1)


def test_sql_defines_every_expected_enum() -> None:
    assert set(sql_enums()) == {
        "UserRole",
        "VehicleType",
        "ExtraChargeType",
        "BookingStatus",
        "PaymentStatus",
    }


@pytest.mark.parametrize("name", sorted(sql_enums()))
def test_python_enum_matches_sql(name: str) -> None:
    assert python_enums().get(name) == sql_enums()[name]


def test_no_python_enum_is_missing_from_sql() -> None:
    assert set(python_enums()) == set(sql_enums())


@pytest.mark.parametrize("name", sorted(sql_enums()))
def test_dart_enum_matches_sql(name: str) -> None:
    assert dart_enums().get(name) == sql_enums()[name]


# Dart enums for text columns guarded by CHECK constraints (not SQL enum types). Their values
# must appear in the migration that defines the column.
CHECKED_TEXT_ENUMS = {
    "CatalogTab": ["mechanic", "package", "repair", "engine"],
    "PartsPolicy": ["service_only", "parts_included", "parts_extra"],
    "ExtraStatus": ["proposed", "approved", "declined", "withdrawn"],
    "PaymentKind": ["advance", "balance"],
}


def test_no_dart_enum_is_missing_from_sql() -> None:
    assert set(dart_enums()) - set(CHECKED_TEXT_ENUMS) == set(sql_enums())


@pytest.mark.parametrize(("name", "values"), sorted(CHECKED_TEXT_ENUMS.items()))
def test_text_column_enums_match_dart_and_the_check_constraints(
    name: str, values: list[str]
) -> None:
    source = DART_ENUMS.read_text()
    block = re.search(rf"enum\s+{name}\b[^{{]*\{{(.*?);", source, re.S)
    assert block, f"{name} not found in enums.dart"
    assert re.findall(r"\w+\('([a-z_]+)'", block.group(1)) == values
    sql = "\n".join(m.read_text() for m in MIGRATIONS)
    for value in values:
        assert f"'{value}'" in sql, f"{value!r} is not in any migration"
