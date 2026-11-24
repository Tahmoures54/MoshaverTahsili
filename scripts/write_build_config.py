#!/usr/bin/env python3
"""Prepare Flutter compiler inputs outside the repository.

Requires Python 3.10+.

Security scope:
    - Configuration values are never printed.
    - Output must be outside the current Git repository.
    - Existing symlink components in the output path are rejected.
    - Atomic replacement uses a private temporary file.
    - POSIX file permissions are restricted to 0600.

Limitations:
    - Compiler defines are not a secure secret store.
    - Windows confidentiality depends on directory/file ACLs.
    - Use a trusted output directory. This is not a sandbox against
      concurrent malicious changes to the filesystem.
    - The output may still be inside another Git repository.

Exit codes:
    0: Configuration prepared.
    1: Configuration or filesystem error.
    2: Invalid command-line usage.
    130: Interrupted.
"""

from __future__ import annotations

import json
import os
import re
import stat
import subprocess
import sys
import tempfile

from pathlib import Path
from urllib.parse import urlsplit


DEFAULT_API_ENDPOINT = "https://api.avalai.ir/v1"
DEFAULT_AI_MODEL = "deepseek-chat"

PUBSPEC_PATH = Path("pubspec.yaml")

GIT_TIMEOUT_SECONDS = 30
MAX_PUBSPEC_SIZE = 1024 * 1024

# Require a top-level version field with an explicit build number.
# Supports examples such as:
#   version: 1.2.3+45
#   version: "1.2.3-beta.1+45"
VERSION_LINE_PATTERN = re.compile(
    r"^version[ \t]*:[ \t]*(?P<value>.*)$"
)

VERSION_VALUE_PATTERN = re.compile(
    r"(?P<version>"
    r"(?:0|[1-9][0-9]*)"
    r"\.(?:0|[1-9][0-9]*)"
    r"\.(?:0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r")"
    r"\+(?P<build>[0-9]+)"
)

TRUE_VALUES = {"true", "1", "yes", "on"}
FALSE_VALUES = {"false", "0", "no", "off"}


class ConfigurationError(Exception):
    """Build configuration could not be prepared."""


def repository_root() -> Path:
    """Resolve the current Git repository root without logging output."""

    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            stdin=subprocess.DEVNULL,
            check=True,
            capture_output=True,
            timeout=GIT_TIMEOUT_SECONDS,
        )
    except FileNotFoundError:
        raise ConfigurationError(
            "Git executable was not found."
        ) from None
    except subprocess.TimeoutExpired:
        raise ConfigurationError(
            "Git repository discovery timed out."
        ) from None
    except (OSError, subprocess.CalledProcessError):
        raise ConfigurationError(
            "Could not determine the Git repository root."
        ) from None

    output = result.stdout

    if output.endswith(b"\n"):
        output = output[:-1]

    if os.name == "nt" and output.endswith(b"\r"):
        output = output[:-1]

    if not output:
        raise ConfigurationError(
            "Git returned an empty repository root."
        )

    try:
        return Path(os.fsdecode(output)).resolve(strict=True)
    except (OSError, RuntimeError, ValueError):
        raise ConfigurationError(
            "Could not resolve the Git repository root."
        ) from None


def read_app_version(root: Path) -> tuple[str, str]:
    """Read one explicit top-level version field from pubspec.yaml."""

    pubspec = root / PUBSPEC_PATH

    try:
        mode = pubspec.lstat().st_mode

        if not stat.S_ISREG(mode):
            raise ConfigurationError(
                "pubspec.yaml must be a regular, non-symlink file."
            )

        with pubspec.open("rb") as stream:
            content = stream.read(MAX_PUBSPEC_SIZE + 1)

        if len(content) > MAX_PUBSPEC_SIZE:
            raise ConfigurationError(
                "pubspec.yaml exceeds the inspection size limit."
            )

        text = content.decode("utf-8-sig")

    except ConfigurationError:
        raise
    except (OSError, UnicodeError):
        raise ConfigurationError(
            "Could not read pubspec.yaml as UTF-8."
        ) from None

    values = []

    for line in text.splitlines():
        match = VERSION_LINE_PATTERN.fullmatch(line)

        if match:
            values.append(match.group("value").strip())

    if len(values) != 1:
        raise ConfigurationError(
            "pubspec.yaml must contain exactly one "
            "top-level version field."
        )

    value = values[0]

    if value.startswith(("'", '"')):
        quote = value[0]
        closing = value.find(quote, 1)

        if closing == -1:
            raise ConfigurationError(
                "Invalid quoted pubspec version."
            )

        remainder = value[closing + 1:].strip()

        if remainder and not remainder.startswith("#"):
            raise ConfigurationError(
                "Unexpected content after pubspec version."
            )

        value = value[1:closing]

    else:
        # YAML plain-scalar comments require preceding whitespace.
        value = re.split(
            r"[ \t]+#",
            value,
            maxsplit=1,
        )[0].strip()

    match = VERSION_VALUE_PATTERN.fullmatch(value)

    if match is None:
        raise ConfigurationError(
            "Invalid pubspec version. "
            "Expected x.y.z+build or x.y.z-prerelease+build."
        )

    return match.group("version"), match.group("build")


def environment_value(*names: str) -> str:
    """Return the first non-empty environment value."""

    for name in names:
        value = os.environ.get(name, "").strip()

        if value:
            return value

    return ""


def parse_boolean(name: str, default: bool = False) -> bool:
    """Reject misspelled booleans instead of silently treating them as false."""

    value = os.environ.get(name, "").strip().lower()

    if not value:
        return default

    if value in TRUE_VALUES:
        return True

    if value in FALSE_VALUES:
        return False

    raise ConfigurationError(
        f"{name} must be true/false, 1/0, yes/no, or on/off."
    )


def validate_endpoint(endpoint: str) -> None:
    """Require an HTTPS URL with a host and no embedded credentials."""

    if (
        any(character.isspace() for character in endpoint)
        or any(ord(character) < 32 for character in endpoint)
        or "\x7f" in endpoint
        or "\\" in endpoint
    ):
        raise ConfigurationError(
            "AI API endpoint contains invalid characters."
        )

    try:
        parsed = urlsplit(endpoint)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError:
        raise ConfigurationError(
            "AI API endpoint is not a valid URL."
        ) from None

    if parsed.scheme.lower() != "https" or not hostname:
        raise ConfigurationError(
            "AI API endpoint must be an HTTPS URL with a hostname."
        )

    if parsed.username is not None or parsed.password is not None:
        raise ConfigurationError(
            "AI API endpoint must not contain embedded credentials."
        )

    # A base endpoint should not carry query credentials or fragments.
    if "?" in endpoint or "#" in endpoint:
        raise ConfigurationError(
            "AI API endpoint must not contain a query or fragment."
        )

    if port is not None and port < 1:
        raise ConfigurationError(
            "AI API endpoint contains an invalid port."
        )


def validate_output_path(
    requested_path: str,
    root: Path,
) -> Path:
    """Require an absolute output path outside the repository."""

    if not requested_path.strip() or "\0" in requested_path:
        raise ConfigurationError(
            "Output path cannot be empty or contain NUL characters."
        )

    try:
        output = Path(requested_path).expanduser()

        if not output.is_absolute():
            raise ConfigurationError(
                "Output path must be absolute."
            )

        if any(part == ".." for part in output.parts):
            raise ConfigurationError(
                "Output path must not contain parent-directory traversal."
            )

        current = Path(output.anchor)

        for index, part in enumerate(output.parts[1:]):
            current = current / part

            try:
                metadata = current.lstat()
            except FileNotFoundError:
                continue

            if stat.S_ISLNK(metadata.st_mode):
                raise ConfigurationError(
                    "Output path must not contain symlinks."
                )

            last = index == len(output.parts[1:]) - 1

            if last:
                if not stat.S_ISREG(metadata.st_mode):
                    raise ConfigurationError(
                        "Existing output must be a regular file."
                    )
            elif not stat.S_ISDIR(metadata.st_mode):
                raise ConfigurationError(
                    "Output parent path must contain only directories."
                )

        output = output.resolve(strict=False)

        if output == root or root in output.parents:
            raise ConfigurationError(
                "Build configuration must be stored outside "
                "the repository."
            )

        if output == Path(output.anchor):
            raise ConfigurationError(
                "Output path must identify a file."
            )

        return output

    except ConfigurationError:
        raise
    except (OSError, RuntimeError, ValueError):
        raise ConfigurationError(
            "Could not validate the configuration output path."
        ) from None


def build_configuration(root: Path) -> dict[str, object]:
    """Build compiler configuration without printing its values."""

    version, build_number = read_app_version(root)

    api_key = environment_value(
        "AI_API_KEY",
        "DEEPSEEK_API_KEY",
    )

    endpoint = environment_value(
        "AI_API_ENDPOINT",
        "DEEPSEEK_API_ENDPOINT",
    ) or DEFAULT_API_ENDPOINT

    model = environment_value(
        "AI_MODEL",
        "DEEPSEEK_MODEL",
    ) or DEFAULT_AI_MODEL

    validate_endpoint(endpoint)

    if any(
        ord(character) < 32 or ord(character) == 127
        for character in model
    ):
        raise ConfigurationError(
            "AI model name contains control characters."
        )

    return {
        "APP_VERSION": version,
        "APP_BUILD_NUMBER": build_number,
        "AI_API_KEY": api_key,
        "AI_API_ENDPOINT": endpoint,
        "AI_MODEL": model,
        "BAZAAR_RSA_PUBLIC_KEY": environment_value(
            "BAZAAR_RSA_PUBLIC_KEY",
        ),
        "BAZAAR_CATALOG_CONFIRMED": parse_boolean(
            "BAZAAR_CATALOG_CONFIRMED",
        ),
    }


def write_private_json(
    output: Path,
    root: Path,
    config: dict[str, object],
) -> None:
    """Atomically replace output using a private temporary file."""

    temporary_path: Path | None = None
    descriptor: int | None = None

    try:
        output.parent.mkdir(
            mode=0o700,
            parents=True,
            exist_ok=True,
        )

        # Recheck after directory creation.
        output = validate_output_path(str(output), root)

        descriptor, temporary_name = tempfile.mkstemp(
            dir=output.parent,
            prefix=".build-config-",
            suffix=".tmp",
        )

        temporary_path = Path(temporary_name)

        if os.name == "posix":
            os.fchmod(descriptor, 0o600)

        stream = os.fdopen(
            descriptor,
            mode="w",
            encoding="utf-8",
            newline="\n",
        )
        descriptor = None

        with stream:
            json.dump(
                config,
                stream,
                ensure_ascii=False,
                separators=(",", ":"),
            )

            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())

        # Reject newly introduced symlinks before replacement.
        output = validate_output_path(str(output), root)

        os.replace(temporary_path, output)
        temporary_path = None

        # Atomic replacement preserves the temporary file's POSIX mode.
        # No post-write chmod is needed.

    except ConfigurationError:
        raise
    except (OSError, ValueError, TypeError):
        raise ConfigurationError(
            "Could not securely write build configuration."
        ) from None

    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass

        if temporary_path is not None:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                # Never include the temporary filename in logs.
                print(
                    "::warning::Temporary configuration cleanup failed. "
                    "Check the private output directory.",
                    file=sys.stderr,
                )


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "Usage: python3 tool/prepare_build_config.py "
            "<absolute-output-path>",
            file=sys.stderr,
        )
        return 2

    try:
        root = repository_root()

        output = validate_output_path(
            sys.argv[1],
            root,
        )

        config = build_configuration(root)

        write_private_json(
            output,
            root,
            config,
        )

        print(
            "Build configuration prepared outside the source tree."
        )

        if os.name != "posix":
            print(
                "::warning::File confidentiality depends on "
                "the output directory's Windows ACLs."
            )

        if not config["AI_API_KEY"]:
            print(
                "::warning::AI API key is not configured. "
                "AI requests may not work in this build."
            )

        if not config["BAZAAR_RSA_PUBLIC_KEY"]:
            print(
                "::warning::Bazaar RSA public key is not configured."
            )

        if not config["BAZAAR_CATALOG_CONFIRMED"]:
            print(
                "::warning::Bazaar catalog has not been confirmed."
            )

        if config["AI_API_KEY"]:
            print(
                "::warning::Compiler defines can be extracted "
                "from the application. Keep production API "
                "secrets on a backend."
            )

        return 0

    except ConfigurationError as error:
        print(
            f"::error::{error}",
            file=sys.stderr,
        )
        return 1

    except KeyboardInterrupt:
        print(
            "Build configuration preparation interrupted.",
            file=sys.stderr,
        )
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
