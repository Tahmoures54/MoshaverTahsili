
#!/usr/bin/env python3
"""Prepare private Android signing configuration without logging secrets."""

from __future__ import annotations

import os
import re
import sys
import tempfile

from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent

ANDROID_DIRECTORY = REPOSITORY_ROOT / "android"
KEYSTORE_FILENAME = "upload-keystore.jks"
KEYSTORE_PATH = ANDROID_DIRECTORY / KEYSTORE_FILENAME
OUTPUT_PATH = ANDROID_DIRECTORY / "key.properties"

REQUIRED_ENVIRONMENT_VARIABLES = (
    "RELEASE_KEYSTORE_PASSWORD",
    "RELEASE_KEY_PASSWORD",
    "RELEASE_KEY_ALIAS",
)

ALIAS_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,128}$")


class SigningConfigurationError(Exception):
    """Raised when Android signing configuration is invalid."""


def escape_properties_value(value: str) -> str:
    """Escape a Java properties value."""

    escaped = (
        value
        .replace("\\", "\\\\")
        .replace("\t", "\\t")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\f", "\\f")
        .replace("=", "\\=")
        .replace(":", "\\:")
        .replace("#", "\\#")
        .replace("!", "\\!")
    )

    # Leading spaces have special meaning in Java properties.
    escaped = escaped.replace(" ", "\\ ")

    return escaped


def read_required_environment() -> dict[str, str]:
    """Read and validate required signing environment variables."""

    values: dict[str, str] = {}

    for name in REQUIRED_ENVIRONMENT_VARIABLES:
        value = os.environ.get(name)

        if value is None or value == "":
            raise SigningConfigurationError(
                f"Required environment variable is missing: {name}"
            )

        values[name] = value

    alias = values["RELEASE_KEY_ALIAS"]

    if not ALIAS_PATTERN.fullmatch(alias):
        raise SigningConfigurationError(
            "Release key alias contains unsupported characters."
        )

    for name, value in values.items():
        if "\0" in value:
            raise SigningConfigurationError(
                f"Invalid null character in {name}."
            )

    return values


def validate_keystore() -> None:
    """Ensure the expected release keystore exists and is non-empty."""

    if not KEYSTORE_PATH.is_file():
        raise SigningConfigurationError(
            f"Release keystore not found: {KEYSTORE_PATH}"
        )

    try:
        if KEYSTORE_PATH.stat().st_size <= 0:
            raise SigningConfigurationError(
                "Release keystore file is empty."
            )
    except OSError as error:
        raise SigningConfigurationError(
            "Could not inspect release keystore."
        ) from error


def build_properties(values: dict[str, str]) -> str:
    """Create the Java properties content."""

    entries = (
        (
            "storePassword",
            values["RELEASE_KEYSTORE_PASSWORD"],
        ),
        (
            "keyPassword",
            values["RELEASE_KEY_PASSWORD"],
        ),
        (
            "keyAlias",
            values["RELEASE_KEY_ALIAS"],
        ),
        (
            "storeFile",
            KEYSTORE_FILENAME,
        ),
    )

    return "".join(
        f"{key}={escape_properties_value(value)}\n"
        for key, value in entries
    )


def write_private_file(content: str) -> None:
    """Atomically write key.properties with restrictive permissions."""

    temporary_path: Path | None = None

    try:
        ANDROID_DIRECTORY.mkdir(
            parents=True,
            exist_ok=True,
        )

        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=ANDROID_DIRECTORY,
            prefix=".key-properties-",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)

            try:
                os.chmod(temporary_path, 0o600)
            except OSError as error:
                raise SigningConfigurationError(
                    "Could not restrict temporary signing file permissions."
                ) from error

            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())

        os.replace(
            temporary_path,
            OUTPUT_PATH,
        )

        temporary_path = None

        try:
            os.chmod(OUTPUT_PATH, 0o600)
        except OSError as error:
            raise SigningConfigurationError(
                "Could not restrict key.properties permissions."
            ) from error

    except OSError as error:
        raise SigningConfigurationError(
            "Could not write Android signing configuration."
        ) from error

    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass


def main() -> int:
    try:
        values = read_required_environment()
        validate_keystore()

        content = build_properties(values)
        write_private_file(content)

        print(
            "Private Android signing configuration prepared."
        )

        print(
            "Signing values were not logged."
        )

        return 0

    except SigningConfigurationError as error:
        print(
            f"::error::{error}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
