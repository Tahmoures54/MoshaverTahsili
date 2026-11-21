
#!/usr/bin/env python3
"""Check tracked secret material and Android manifest security defaults."""

from __future__ import annotations

import re
import subprocess
import sys
import xml.etree.ElementTree as ET

from pathlib import Path


ANDROID_NS = "http://schemas.android.com/apk/res/android"
ANDROID = f"{{{ANDROID_NS}}}"

MANIFEST_PATH = Path(
    "android/app/src/main/AndroidManifest.xml"
)

ENV_EXAMPLE_NAMES = {
    ".env.example",
}

SIGNING_EXTENSIONS = {
    ".jks",
    ".keystore",
    ".p12",
    ".pfx",
    ".pem",
    ".key",
}

BINARY_EXTENSIONS = {
    ".ttf",
    ".otf",
    ".jar",
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".gif",
    ".ico",
    ".pdf",
    ".zip",
    ".gz",
    ".so",
    ".a",
    ".dll",
    ".exe",
    ".class",
    ".dex",
    ".apk",
    ".aab",
}

UNNECESSARY_PERMISSIONS = {
    "android.permission.READ_CONTACTS",
    "android.permission.WRITE_CONTACTS",
    "android.permission.READ_SMS",
    "android.permission.SEND_SMS",
    "android.permission.RECEIVE_SMS",
    "android.permission.READ_CALL_LOG",
    "android.permission.WRITE_CALL_LOG",
    "android.permission.CALL_PHONE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_BACKGROUND_LOCATION",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.READ_MEDIA_VIDEO",
    "android.permission.READ_MEDIA_AUDIO",
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.BODY_SENSORS",
    "android.permission.ACTIVITY_RECOGNITION",
}

SECRET_PATTERNS = (
    re.compile(
        r"\bsk-[A-Za-z0-9_-]{20,}\b"
    ),
    re.compile(
        r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"
    ),
    re.compile(
        r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"
    ),
    re.compile(
        r"\bAKIA[0-9A-Z]{16}\b"
    ),
    re.compile(
        r"\bAIza[0-9A-Za-z_-]{30,}\b"
    ),
    re.compile(
        r"-----BEGIN "
        r"(?:RSA |EC |DSA |OPENSSH )?"
        r"PRIVATE KEY-----"
    ),
)

MAX_TEXT_FILE_SIZE = 10 * 1024 * 1024


class SecurityCheckError(Exception):
    """Raised when repository security checks cannot be completed."""


def get_repository_root() -> Path:
    """Find the Git repository root."""

    try:
        result = subprocess.run(
            [
                "git",
                "rev-parse",
                "--show-toplevel",
            ],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as error:
        raise SecurityCheckError(
            "Git executable was not found."
        ) from error
    except subprocess.CalledProcessError as error:
        raise SecurityCheckError(
            "The current directory is not inside a Git repository."
        ) from error

    return Path(result.stdout.strip()).resolve()


def get_tracked_files(root: Path) -> list[str]:
    """Read tracked paths safely, including unusual filenames."""

    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(root),
                "ls-files",
                "-z",
            ],
            check=True,
            capture_output=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        raise SecurityCheckError(
            "Could not retrieve tracked Git files."
        ) from error

    return [
        item.decode(
            "utf-8",
            errors="surrogateescape",
        )
        for item in result.stdout.split(b"\0")
        if item
    ]


def is_environment_file(name: str) -> bool:
    """Detect tracked .env files while allowing the example template."""

    filename = Path(name).name

    if filename == ".env":
        return True

    if not filename.startswith(".env."):
        return False

    return filename not in ENV_EXAMPLE_NAMES


def inspect_tracked_file(
    root: Path,
    name: str,
    errors: list[str],
) -> None:
    """Inspect one tracked file without printing its contents."""

    relative_path = Path(name)
    suffix = relative_path.suffix.lower()

    if is_environment_file(name):
        errors.append(
            f"Tracked environment file: {name}"
        )

    if suffix in SIGNING_EXTENSIONS:
        errors.append(
            f"Tracked signing or private-key material: {name}"
        )

    if suffix in BINARY_EXTENSIONS:
        return

    path = root / relative_path

    # Deleted tracked files are not available for content inspection.
    if not path.exists():
        return

    if not path.is_file():
        return

    try:
        if path.stat().st_size > MAX_TEXT_FILE_SIZE:
            return

        content = path.read_bytes()

    except OSError:
        errors.append(
            f"Could not inspect tracked file: {name}"
        )
        return

    # Avoid interpreting binary content as text.
    if b"\0" in content:
        return

    text = content.decode(
        "utf-8",
        errors="replace",
    )

    for pattern in SECRET_PATTERNS:
        if pattern.search(text):
            errors.append(
                "Potential secret material detected in "
                f"{name}; inspect privately."
            )
            break


def get_manifest_permissions(
    root: Path,
    errors: list[str],
) -> tuple[ET.Element | None, set[str]]:
    """Parse the Android manifest and collect declared permissions."""

    path = root / MANIFEST_PATH

    if not path.is_file():
        errors.append(
            f"Android manifest not found: {MANIFEST_PATH.as_posix()}"
        )
        return None, set()

    try:
        tree = ET.parse(path)
    except (ET.ParseError, OSError):
        errors.append(
            "Android manifest could not be parsed as valid XML."
        )
        return None, set()

    manifest = tree.getroot()

    if manifest.tag != "manifest":
        errors.append(
            "Android manifest has an unexpected root element."
        )
        return None, set()

    permissions = set()

    for element in manifest:
        if element.tag not in {
            "uses-permission",
            "uses-permission-sdk-23",
            "uses-permission-sdk-m",
        }:
            continue

        permission = element.get(ANDROID + "name")

        if permission:
            permissions.add(permission)

    return manifest, permissions


def inspect_android_manifest(
    root: Path,
    errors: list[str],
) -> None:
    """Enforce required Android permissions and security defaults."""

    manifest, permissions = get_manifest_permissions(
        root,
        errors,
    )

    if manifest is None:
        return

    if "android.permission.INTERNET" not in permissions:
        errors.append(
            "Android INTERNET permission is missing."
        )

    for permission in sorted(
        permissions & UNNECESSARY_PERMISSIONS
    ):
        errors.append(
            f"Review unnecessary or sensitive Android permission: {permission}"
        )

    application = manifest.find("application")

    if application is None:
        errors.append(
            "Android application element is missing."
        )
        return

    cleartext = application.get(
        ANDROID + "usesCleartextTraffic"
    )

    if cleartext != "false":
        errors.append(
            "Android usesCleartextTraffic must explicitly be false."
        )

    allow_backup = application.get(
        ANDROID + "allowBackup"
    )

    if allow_backup != "false":
        errors.append(
            "Android allowBackup must explicitly be false."
        )


def main() -> int:
    errors: list[str] = []

    try:
        root = get_repository_root()
        tracked_files = get_tracked_files(root)

        for name in tracked_files:
            inspect_tracked_file(
                root,
                name,
                errors,
            )

        inspect_android_manifest(
            root,
            errors,
        )

    except SecurityCheckError as error:
        print(
            f"Security check could not complete: {error}",
            file=sys.stderr,
        )
        return 2

    if errors:
        print(
            "Repository security checks FAILED:",
            file=sys.stderr,
        )

        for error in errors:
            print(
                f"- {error}",
                file=sys.stderr,
            )

        print(
            f"\nTotal findings: {len(errors)}",
            file=sys.stderr,
        )

        return 1

    print(
        "Tracked-source secret and Android manifest checks passed."
    )
    print(
        "This check does not guarantee detection of every secret format."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
