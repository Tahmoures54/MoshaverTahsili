#!/usr/bin/env python3
"""Prepare private Android signing configuration without logging secrets.

Requires Python 3.10+.

Expected layout:
    tool/prepare_android_signing.py
    android/app/upload-keystore.jks
    android/key.properties

Required environment variables:
    RELEASE_KEYSTORE_PASSWORD
    RELEASE_KEY_PASSWORD
    RELEASE_KEY_ALIAS

Security scope:
    - Signing files must be untracked and ignored by Git.
    - Android directory and signing files must not be symlinks.
    - Temporary signing files must also be ignored by Git.
    - Writes use atomic replacement.
    - On POSIX, generated file permissions are restricted to 0600.
    - Configuration values are never logged.

Limitations:
    - Keystore passwords, alias existence, and certificate validity
      are not verified by this script.
    - Git history is not inspected.
    - Windows confidentiality depends on filesystem ACLs.
    - Use a trusted checkout; these checks are not a sandbox against
      concurrent malicious filesystem changes.

Exit codes:
    0: Signing configuration prepared.
    1: Validation or filesystem error.
    2: Invalid command-line usage.
    130: Interrupted.
"""

from __future__ import annotations

import os
import re
import stat
import subprocess
import sys
import tempfile

from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent

ANDROID_DIRECTORY = REPOSITORY_ROOT / "android"

KEYSTORE_FILENAME = "upload-keystore.jks"
KEYSTORE_PATH = ANDROID_DIRECTORY / "app" / KEYSTORE_FILENAME
OUTPUT_PATH = ANDROID_DIRECTORY / "key.properties"

GIT_TIMEOUT_SECONDS = 30

REQUIRED_ENVIRONMENT_VARIABLES = (
    "RELEASE_KEYSTORE_PASSWORD",
    "RELEASE_KEY_PASSWORD",
    "RELEASE_KEY_ALIAS",
)

ALIAS_PATTERN = re.compile(r"[A-Za-z0-9_.-]{1,128}")


class SigningConfigurationError(Exception):
    """Android signing configuration could not be prepared."""


def run_git(args: list[str]) -> subprocess.CompletedProcess[bytes]:
    """Run Git without printing captured output."""

    try:
        return subprocess.run(
            ["git", *args],
            cwd=REPOSITORY_ROOT,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            timeout=GIT_TIMEOUT_SECONDS,
            check=False,
        )
    except FileNotFoundError:
        raise SigningConfigurationError(
            "Git executable was not found."
        ) from None
    except subprocess.TimeoutExpired:
        raise SigningConfigurationError(
            "Git inspection timed out."
        ) from None
    except OSError:
        raise SigningConfigurationError(
            "Could not run Git inspection."
        ) from None


def validate_repository() -> None:
    """Ensure this script's project directory is the Git root."""

    result = run_git(["rev-parse", "--show-toplevel"])

    if result.returncode != 0:
        raise SigningConfigurationError(
            "The project must be inside a valid Git working tree."
        )

    raw_root = result.stdout

    if raw_root.endswith(b"\n"):
        raw_root = raw_root[:-1]

    if os.name == "nt" and raw_root.endswith(b"\r"):
        raw_root = raw_root[:-1]

    if not raw_root:
        raise SigningConfigurationError(
            "Git returned an empty repository root."
        )

    try:
        git_root = Path(os.fsdecode(raw_root)).resolve(strict=True)
    except (OSError, RuntimeError, ValueError):
        raise SigningConfigurationError(
            "Could not resolve the Git repository root."
        ) from None

    if git_root != REPOSITORY_ROOT:
        raise SigningConfigurationError(
            "The script must be located in the repository's tool directory."
        )


def require_untracked_and_ignored(path: Path) -> None:
    """Require a project path to be untracked and ignored by Git."""

    try:
        relative = path.relative_to(REPOSITORY_ROOT).as_posix()
    except ValueError:
        raise SigningConfigurationError(
            "Signing paths must belong to the project directory."
        ) from None

    tracked = run_git([
        "ls-files",
        "--cached",
        "-z",
        "--",
        relative,
    ])

    if tracked.returncode != 0:
        raise SigningConfigurationError(
            "Could not inspect tracked signing files."
        )

    if tracked.stdout:
        raise SigningConfigurationError(
            "A signing or temporary configuration file is tracked by Git. "
            "Remove it from the index before continuing."
        )

    ignored = run_git([
        "check-ignore",
        "--quiet",
        "--",
        relative,
    ])

    if ignored.returncode == 1:
        raise SigningConfigurationError(
            "Signing files and .key-properties-*.tmp files "
            "must be ignored by Git."
        )

    if ignored.returncode != 0:
        raise SigningConfigurationError(
            "Could not inspect Git ignore rules."
        )


def validate_android_directory() -> None:
    """Require an existing Android directory, not a symlink."""

    try:
        mode = ANDROID_DIRECTORY.lstat().st_mode
    except OSError:
        raise SigningConfigurationError(
            "Could not inspect the Android directory."
        ) from None

    if not stat.S_ISDIR(mode):
        raise SigningConfigurationError(
            "Android directory must be an existing, non-symlink directory."
        )


def validate_output_file() -> None:
    """Reject an existing output that is not a regular file."""

    validate_android_directory()

    try:
        metadata = OUTPUT_PATH.lstat()
    except FileNotFoundError:
        return
    except OSError:
        raise SigningConfigurationError(
            "Could not inspect the signing configuration output."
        ) from None

    if not stat.S_ISREG(metadata.st_mode):
        raise SigningConfigurationError(
            "Existing key.properties must be a regular, non-symlink file."
        )


def validate_keystore() -> None:
    """Require a non-empty regular keystore file."""

    validate_android_directory()

    try:
        metadata = KEYSTORE_PATH.lstat()
    except FileNotFoundError:
        raise SigningConfigurationError(
            "Release keystore is missing. "
            "Expected android/upload-keystore.jks."
        ) from None
    except OSError:
        raise SigningConfigurationError(
            "Could not inspect the release keystore."
        ) from None

    if not stat.S_ISREG(metadata.st_mode):
        raise SigningConfigurationError(
            "Release keystore must be a regular, non-symlink file."
        )

    if metadata.st_size <= 0:
        raise SigningConfigurationError(
            "Release keystore file is empty."
        )


def read_required_environment() -> dict[str, str]:
    """Read signing values without trimming passwords."""

    values: dict[str, str] = {}

    for name in REQUIRED_ENVIRONMENT_VARIABLES:
        value = os.environ.get(name)

        if value is None or value == "":
            raise SigningConfigurationError(
                f"Required environment variable is missing: {name}"
            )

        if "\0" in value:
            raise SigningConfigurationError(
                f"Invalid NUL character in {name}."
            )

        # Surrogate code points can represent invalid environment bytes.
        if any(0xD800 <= ord(character) <= 0xDFFF for character in value):
            raise SigningConfigurationError(
                f"Invalid Unicode value in {name}."
            )

        values[name] = value

    if ALIAS_PATTERN.fullmatch(values["RELEASE_KEY_ALIAS"]) is None:
        raise SigningConfigurationError(
            "Release key alias must contain 1–128 characters "
            "using letters, numbers, underscore, dot, or hyphen."
        )

    return values


def escape_properties_value(value: str) -> str:
    """Encode a Java properties value using ASCII and Unicode escapes.

    Non-BMP characters are encoded as UTF-16 surrogate pairs so that
    Java Properties.load(InputStream) reconstructs the original value.
    """

    special = {
        "\\": "\\\\",
        "\t": "\\t",
        "\n": "\\n",
        "\r": "\\r",
        "\f": "\\f",
        " ": "\\ ",
        "=": "\\=",
        ":": "\\:",
        "#": "\\#",
        "!": "\\!",
    }

    escaped: list[str] = []

    for character in value:
        if character in special:
            escaped.append(special[character])
            continue

        codepoint = ord(character)

        if 0x20 <= codepoint <= 0x7E:
            escaped.append(character)
        elif codepoint <= 0xFFFF:
            escaped.append(f"\\u{codepoint:04X}")
        else:
            adjusted = codepoint - 0x10000
            high = 0xD800 + (adjusted >> 10)
            low = 0xDC00 + (adjusted & 0x3FF)

            escaped.append(f"\\u{high:04X}\\u{low:04X}")

    return "".join(escaped)


def build_properties(values: dict[str, str]) -> str:
    """Build signing properties without logging their contents."""

    entries = (
        ("storePassword", values["RELEASE_KEYSTORE_PASSWORD"]),
        ("keyPassword", values["RELEASE_KEY_PASSWORD"]),
        ("keyAlias", values["RELEASE_KEY_ALIAS"]),
        # Absolute path works regardless of Gradle's resolution base.
        ("storeFile", KEYSTORE_PATH.as_posix()),
    )

    return "".join(
        f"{key}={escape_properties_value(value)}\n"
        for key, value in entries
    )


def write_private_file(content: str) -> None:
    """Atomically write key.properties with a private temporary file."""

    temporary_path: Path | None = None
    descriptor: int | None = None

    try:
        validate_output_file()
        require_untracked_and_ignored(OUTPUT_PATH)

        descriptor, temporary_name = tempfile.mkstemp(
            dir=ANDROID_DIRECTORY,
            prefix=".key-properties-",
            suffix=".tmp",
        )

        temporary_path = Path(temporary_name)

        # Check the temporary file before placing secrets inside it.
        require_untracked_and_ignored(temporary_path)

        if os.name == "posix":
            os.fchmod(descriptor, 0o600)

        stream = os.fdopen(
            descriptor,
            mode="w",
            encoding="ascii",
            newline="\n",
        )
        descriptor = None

        with stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())

        # Recheck before replacement.
        validate_output_file()
        require_untracked_and_ignored(OUTPUT_PATH)

        os.replace(temporary_path, OUTPUT_PATH)
        temporary_path = None

        # Replacement preserves the temporary file's POSIX 0600 mode.

    except SigningConfigurationError:
        raise
    except (OSError, UnicodeError, ValueError):
        raise SigningConfigurationError(
            "Could not securely write Android signing configuration."
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
                print(
                    "::warning::Temporary signing file cleanup failed. "
                    "Inspect the Android directory securely.",
                    file=sys.stderr,
                )


def main() -> int:
    if len(sys.argv) != 1:
        print(
            "Usage: python3 tool/prepare_android_signing.py",
            file=sys.stderr,
        )
        return 2

    try:
        validate_repository()
        validate_android_directory()

        require_untracked_and_ignored(KEYSTORE_PATH)
        require_untracked_and_ignored(OUTPUT_PATH)

        validate_keystore()
        validate_output_file()

        values = read_required_environment()
        content = build_properties(values)

        write_private_file(content)

        print(
            "Private Android signing configuration prepared. "
            "Signing values were not logged."
        )

        if os.name != "posix":
            print(
                "::warning::Signing file confidentiality depends "
                "on filesystem ACLs."
            )

        return 0

    except SigningConfigurationError as error:
        print(
            f"::error::{error}",
            file=sys.stderr,
        )
        return 1

    except KeyboardInterrupt:
        print(
            "Android signing configuration preparation interrupted.",
            file=sys.stderr,
        )
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
