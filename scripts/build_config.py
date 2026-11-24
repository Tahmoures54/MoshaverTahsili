#!/usr/bin/env python3
"""Report release configuration presence without exposing secret values.

Requires Python 3.10 or newer.

Usage:
    python3 tool/check_release_configuration.py
    python3 tool/check_release_configuration.py --summary
    python3 tool/check_release_configuration.py --summary --strict

Exit codes:
    0: Inspection completed; configuration may be incomplete unless strict.
    1: Strict mode requested and configuration inputs are incomplete.
    2: Invalid arguments or invalid/unreadable pubspec version.

No credential, signing-material, API, or payment validation is performed.
"""

from __future__ import annotations

import os
import re
import sys

from dataclasses import dataclass
from pathlib import Path
from typing import TextIO


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
MAX_PUBSPEC_BYTES = 1024 * 1024

# Android versionCode must be positive and must not exceed
# Google Play's documented maximum.
MAX_ANDROID_BUILD_NUMBER = 2_100_000_000

TRUE_VALUES = frozenset({"true"})

# This is intentionally a narrow parser for a top-level pubspec version.
# It does not implement arbitrary YAML syntax.
VERSION_KEY_PATTERN = re.compile(
    r"""^(?:version|'version'|"version")[ \t]*:"""
)

NUMERIC_IDENTIFIER = r"(?:0|[1-9][0-9]*)"

# SemVer prerelease identifiers:
# - purely numeric identifiers cannot have leading zeros;
# - nonnumeric identifiers can contain ASCII letters, digits, and hyphens.
PRERELEASE_IDENTIFIER = (
    rf"(?:{NUMERIC_IDENTIFIER}"
    r"|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
)

VERSION_PATTERN = re.compile(
    rf"(?P<version>"
    rf"{NUMERIC_IDENTIFIER}\."
    rf"{NUMERIC_IDENTIFIER}\."
    rf"{NUMERIC_IDENTIFIER}"
    rf"(?:-{PRERELEASE_IDENTIFIER}"
    rf"(?:\.{PRERELEASE_IDENTIFIER})*)?"
    rf")"
    r"\+(?P<build>[0-9]{1,10})"
)

ANSI_PATTERN = re.compile(
    r"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"
    r"|\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"
)
CONTROL_PATTERN = re.compile(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]")
BIDI_PATTERN = re.compile(r"[\u202A-\u202E\u2066-\u2069]")


@dataclass(frozen=True)
class Configuration:
    version: str
    build_number: str
    missing_required: tuple[str, ...]
    present_required: tuple[str, ...]
    available_ai_keys: tuple[str, ...]
    catalog_confirmed: bool

    @property
    def signing_ready(self) -> bool:
        return all(
            name in self.present_required
            for name in SIGNING_SECRETS
        )

    @property
    def bazaar_key_present(self) -> bool:
        return "BAZAAR_RSA_PUBLIC_KEY" in self.present_required

    @property
    def ai_key_present(self) -> bool:
        return bool(self.available_ai_keys)

    @property
    def configuration_inputs_complete(self) -> bool:
        return (
            not self.missing_required
            and self.ai_key_present
            and self.catalog_confirmed
        )

    @property
    def production_ready(self) -> bool:
        """Compatibility alias; this does not certify release readiness."""
        return self.configuration_inputs_complete


def boolean_text(value: bool) -> str:
    return "true" if value else "false"


def emit_diagnostic(level: str, message: str) -> None:
    """Emit a workflow diagnostic separately from machine-readable stdout."""

    if level not in {"warning", "error"}:
        raise ValueError("Unsupported diagnostic level")

    safe = ANSI_PATTERN.sub("", message)
    safe = CONTROL_PATTERN.sub("", safe)
    safe = BIDI_PATTERN.sub("", safe)

    safe = (
        safe.replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )

    print(f"::{level}::{safe}", file=sys.stderr)


def environment_value(name: str) -> str:
    """Read an environment variable without displaying its value."""
    return os.environ.get(name, "").strip()


def extract_version_scalar(line: str) -> str:
    """Accept an unquoted or simply quoted version with an optional comment."""

    match = VERSION_KEY_PATTERN.match(line)

    if match is None:
        raise ValueError("Invalid top-level version declaration.")

    raw = line[match.end():].strip()

    # Quoted values contain no YAML escapes: the accepted version alphabet
    # does not require them.
    if raw.startswith(("'", '"')):
        quote = raw[0]
        closing = raw.find(quote, 1)

        if closing < 0:
            raise ValueError("Unterminated quoted pubspec version.")

        scalar = raw[1:closing]
        remainder = raw[closing + 1:]

        if remainder:
            if not remainder[0].isspace():
                raise ValueError("Invalid trailing pubspec version content.")

            trailing = remainder.strip()

            if trailing and not trailing.startswith("#"):
                raise ValueError("Invalid trailing pubspec version content.")

        return scalar

    # YAML inline comments must be separated from a plain scalar
    # by whitespace.
    scalar = re.split(r"[ \t]+#", raw, maxsplit=1)[0].strip()
    return scalar


def read_version(path: Path | None = None) -> tuple[str, str]:
    """Read a bounded pubspec and validate versionName/versionCode."""

    if path is None:
        path = PUBSPEC_PATH

    try:
        if not path.is_file():
            raise ValueError("Required pubspec file was not found.")

        with path.open("rb") as stream:
            raw = stream.read(MAX_PUBSPEC_BYTES + 1)

    except OSError:
        # Do not include raw OS errors or file contents in diagnostics.
        raise ValueError("Could not read the required pubspec file.") from None

    if len(raw) > MAX_PUBSPEC_BYTES:
        raise ValueError("Pubspec exceeds the permitted size limit.")

    try:
        content = raw.decode("utf-8-sig", errors="strict")
    except UnicodeDecodeError:
        raise ValueError("Pubspec must contain valid UTF-8 text.") from None

    if "\x00" in content:
        raise ValueError("Pubspec contains an invalid null character.")

    declarations = [
        line
        for line in content.splitlines()
        if VERSION_KEY_PATTERN.match(line)
    ]

    if not declarations:
        raise ValueError(
            "Missing top-level pubspec version. "
            "Expected format: version: 1.2.3+45"
        )

    if len(declarations) != 1:
        raise ValueError("Pubspec contains duplicate version declarations.")

    scalar = extract_version_scalar(declarations[0])
    match = VERSION_PATTERN.fullmatch(scalar)

    if match is None:
        raise ValueError(
            "Invalid pubspec version. "
            "Expected 1.2.3+45 or 1.2.3-beta.1+45."
        )

    version = match.group("version")
    build_number = match.group("build")
    numeric_build = int(build_number)

    if not 1 <= numeric_build <= MAX_ANDROID_BUILD_NUMBER:
        raise ValueError(
            "Android build number must be between "
            f"1 and {MAX_ANDROID_BUILD_NUMBER}."
        )

    return version, build_number


def inspect_configuration() -> Configuration:
    """Inspect presence only; never return secret values."""

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


def generate_summary(config: Configuration) -> str:
    """Generate Markdown using validated versions and fixed variable names."""

    lines = [
        "## Build configuration (presence only)",
        "",
        f"- Version: `{config.version}`",
        f"- Build number: `{config.build_number}`",
        "- Production configuration inputs complete: "
        f"**{boolean_text(config.configuration_inputs_complete)}**",
        "",
        "### Signing and Bazaar configuration",
        "",
    ]

    for name in REQUIRED_SECRETS:
        status = (
            "present"
            if name in config.present_required
            else "MISSING"
        )
        lines.append(f"- `{name}`: **{status}**")

    lines.extend([
        "",
        "### AI configuration",
        "",
    ])

    for name in AI_SECRET_NAMES:
        status = (
            "present"
            if name in config.available_ai_keys
            else "absent"
        )
        lines.append(f"- `{name}`: **{status}**")

    lines.extend([
        "",
        "At least one supported AI key is required.",
        "",
        "### Bazaar catalog confirmation",
        "",
        f"- `{CATALOG_CONFIRMATION_NAME}`: "
        f"**{boolean_text(config.catalog_confirmed)}**",
        "",
        "Confirmation requires the value `true` "
        "(case-insensitive, surrounding whitespace ignored).",
    ])

    if not config.configuration_inputs_complete:
        lines.extend([
            "",
            "### Incomplete configuration",
            "",
        ])

        for name in config.missing_required:
            lines.append(f"- Missing: `{name}`")

        if not config.ai_key_present:
            lines.append(
                "- Missing: at least one of "
                "`AI_API_KEY` or `DEEPSEEK_API_KEY`"
            )

        if not config.catalog_confirmed:
            lines.append(
                f"- Not confirmed: `{CATALOG_CONFIRMATION_NAME}`"
            )

    lines.extend([
        "",
        "### Scope and limitations",
        "",
        "- No secret values are included in this report.",
        "- Presence means a nonempty value after trimming whitespace.",
        "- Presence does not validate credentials, keystore data, aliases, "
        "public keys, API connectivity, or payment behavior.",
        "- Catalog confirmation is an environment declaration, "
        "not an independent catalog verification.",
        "- `production_ready` is a compatibility output meaning only "
        "that configuration inputs are complete.",
        "- APK signature verification, release installation, "
        "device testing, and Bazaar payment tests remain separate checks.",
        "",
    ])

    return "\n".join(lines)


def print_summary(config: Configuration) -> None:
    print(generate_summary(config), end="")


def print_machine_output(config: Configuration) -> None:
    """Print stable key=value records; never print secret values."""

    records = (
        ("version", config.version),
        ("build_number", config.build_number),
        ("production_ready", boolean_text(config.production_ready)),
        ("signing_ready", boolean_text(config.signing_ready)),
        ("bazaar_key_present", boolean_text(config.bazaar_key_present)),
        ("ai_key_present", boolean_text(config.ai_key_present)),
        (
            "bazaar_catalog_confirmed",
            boolean_text(config.catalog_confirmed),
        ),
    )

    for name, value in records:
        print(f"{name}={value}")


def print_usage(stream: TextIO = sys.stdout) -> None:
    print(
        "Usage: python3 tool/check_release_configuration.py "
        "[--summary] [--strict]",
        file=stream,
    )


def main() -> int:
    arguments = sys.argv[1:]
    supported = {"--summary", "--strict", "--help", "-h"}

    if any(argument not in supported for argument in arguments):
        # Do not echo unknown arguments: they might contain secret values.
        emit_diagnostic("error", "Unsupported command-line argument.")
        print_usage(sys.stderr)
        return 2

    if "--help" in arguments or "-h" in arguments:
        print_usage()
        return 0

    summary_mode = "--summary" in arguments
    strict_mode = "--strict" in arguments

    try:
        config = inspect_configuration()
    except ValueError as error:
        emit_diagnostic("error", str(error))
        return 2

    if summary_mode:
        print_summary(config)
    else:
        print_machine_output(config)

    if not config.configuration_inputs_complete:
        emit_diagnostic(
            "error" if strict_mode else "warning",
            "Production release configuration inputs are incomplete.",
        )
        return 1 if strict_mode else 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
