
#!/usr/bin/env python3
"""Report release configuration presence without exposing secret values."""

from __future__ import annotations

import os
import re
import sys

from dataclasses import dataclass
from pathlib import Path


SIGNING_SECRETS = (
    "RELEASE_KEYSTORE_BASE64",
    "RELEASE_KEYSTORE_PASSWORD",
    "RELEASE_KEY_ALIAS",
    "RELEASE_KEY_PASSWORD",
)

REQUIRED_SECRETS = SIGNING_SECRETS + (
    "BAZAAR_RSA_PUBLIC_KEY",
)

AI_SECRET_NAMES = (
    "AI_API_KEY",
    "DEEPSEEK_API_KEY",
)

CATALOG_CONFIRMATION_NAME = "BAZAAR_CATALOG_CONFIRMED"

PUBSPEC_PATH = Path("pubspec.yaml")

VERSION_PATTERN = re.compile(
    r"^version:\s*([^\s+#]+)\+(\d+)\s*(?:#.*)?$",
    re.MULTILINE,
)

TRUE_VALUES = {"true"}


@dataclass(frozen=True)
class Configuration:
    version: str
    build_number: str
    missing_required: tuple[str, ...]
    present_required: tuple[str, ...]
    available_ai_keys: tuple[str, ...]
    catalog_confirmed: bool

    @property
    def ai_key_present(self) -> bool:
        return bool(self.available_ai_keys)

    @property
    def production_ready(self) -> bool:
        return (
            not self.missing_required
            and self.ai_key_present
            and self.catalog_confirmed
        )


def environment_value(name: str) -> str:
    """Read an environment variable without displaying its value."""

    return os.environ.get(name, "").strip()


def read_version() -> tuple[str, str]:
    """Read and validate Flutter package version and build number."""

    if not PUBSPEC_PATH.is_file():
        raise ValueError(
            f"Required project file not found: {PUBSPEC_PATH}"
        )

    try:
        content = PUBSPEC_PATH.read_text(
            encoding="utf-8",
            errors="strict",
        )
    except OSError as error:
        raise ValueError(
            f"Could not read {PUBSPEC_PATH}: {error}"
        ) from error

    match = VERSION_PATTERN.search(content)

    if not match:
        raise ValueError(
            "Invalid or missing pubspec version. "
            "Expected format: version: 1.2.3+45"
        )

    version, build_number = match.groups()

    if not build_number.isdigit():
        raise ValueError("Build number must contain digits only.")

    return version, build_number


def inspect_configuration() -> Configuration:
    """Inspect configuration presence only."""

    version, build_number = read_version()

    present_required = tuple(
        name
        for name in REQUIRED_SECRETS
        if environment_value(name)
    )

    missing_required = tuple(
        name
        for name in REQUIRED_SECRETS
        if name not in present_required
    )

    available_ai_keys = tuple(
        name
        for name in AI_SECRET_NAMES
        if environment_value(name)
    )

    catalog_confirmed = (
        environment_value(CATALOG_CONFIRMATION_NAME).lower()
        in TRUE_VALUES
    )

    return Configuration(
        version=version,
        build_number=build_number,
        missing_required=missing_required,
        present_required=present_required,
        available_ai_keys=available_ai_keys,
        catalog_confirmed=catalog_confirmed,
    )


def print_summary(config: Configuration) -> None:
    """Print a safe Markdown report."""

    print("## Build configuration (presence only)")
    print()

    print(f"- Version: `{config.version}`")
    print(f"- Build number: `{config.build_number}`")
    print(
        "- Production configuration inputs complete: "
        f"**{str(config.production_ready).lower()}**"
    )

    print()
    print("### Signing and Bazaar configuration")
    print()

    for name in REQUIRED_SECRETS:
        status = (
            "present"
            if name in config.present_required
            else "MISSING"
        )

        print(f"- `{name}`: **{status}**")

    print()
    print("### AI configuration")
    print()

    if config.available_ai_keys:
        for name in config.available_ai_keys:
            print(f"- `{name}`: **present**")
    else:
        print("- `AI_API_KEY` or `DEEPSEEK_API_KEY`: **MISSING**")

    print()
    print("### Bazaar catalog confirmation")
    print()

    print(
        f"- `{CATALOG_CONFIRMATION_NAME}`: "
        f"**{str(config.catalog_confirmed).lower()}**"
    )

    if config.missing_required:
        print()
        print("### Missing required configuration")
        print()

        for name in config.missing_required:
            print(f"- `{name}`")

    print()
    print(
        "No secret values are included in this report. "
        "Presence checks do not validate credentials, signing "
        "material, API connectivity, or payment behavior."
    )

    print()
    print(
        "A test build is not a production release. "
        "APK signature verification, release installation, "
        "and Bazaar payment tests must be verified separately."
    )


def print_machine_output(config: Configuration) -> None:
    """Print stable key=value output without exposing secret values."""

    print(f"version={config.version}")
    print(f"build_number={config.build_number}")
    print(
        f"production_ready={str(config.production_ready).lower()}"
    )
    print(
        f"signing_ready={str(not any(name in config.missing_required for name in SIGNING_SECRETS)).lower()}"
    )
    print(
        f"bazaar_key_present={str('BAZAAR_RSA_PUBLIC_KEY' in config.present_required).lower()}"
    )
    print(f"ai_key_present={str(config.ai_key_present).lower()}")
    print(
        f"bazaar_catalog_confirmed={str(config.catalog_confirmed).lower()}"
    )


def main() -> int:
    summary_mode = "--summary" in sys.argv[1:]
    strict_mode = "--strict" in sys.argv[1:]

    unknown_arguments = [
        arg
        for arg in sys.argv[1:]
        if arg not in {"--summary", "--strict"}
    ]

    if unknown_arguments:
        print(
            f"Unknown arguments: {', '.join(unknown_arguments)}",
            file=sys.stderr,
        )
        return 2

    try:
        config = inspect_configuration()
    except ValueError as error:
        print(f"::error::{error}")
        return 2

    if summary_mode:
        print_summary(config)
    else:
        print_machine_output(config)

    if strict_mode and not config.production_ready:
        print(
            "::error::Production release configuration is incomplete."
        )
        return 1

    if not config.production_ready:
        print(
            "::warning::Production release configuration is incomplete."
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
