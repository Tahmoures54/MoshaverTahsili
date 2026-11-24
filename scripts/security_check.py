#!/usr/bin/env python3
"""Check tracked working-tree files and Android source security defaults.

Usage:
    python3 tool/check_security.py

Scope:
    - Inspect tracked files in the current working tree.
    - Reject tracked environment and signing/private-key files.
    - Detect selected credential and private-key patterns.
    - Validate the main Android source manifest.
    - Validate directly referenced main-source network security configs.

Limitations:
    - Does not scan Git history, staged blobs, or untracked files.
    - Does not validate the final merged release manifest.
    - Recognized binary files are excluded from content scanning.
    - Secret detection is best-effort.

Exit codes:
    0: Checks passed within the stated scope.
    1: Security or inspection findings.
    2: Repository inspection could not be started/completed.
    130: Interrupted by the user.
"""

from __future__ import annotations

import os
import re
import stat
import subprocess
import sys
import xml.etree.ElementTree as ET

from pathlib import Path


ANDROID_NS = "http://schemas.android.com/apk/res/android"
ANDROID = f"{{{ANDROID_NS}}}"

MANIFEST_PATH = Path(
    "android/app/src/main/AndroidManifest.xml"
)

MAIN_RES_PATH = Path(
    "android/app/src/main/res"
)

GIT_TIMEOUT_SECONDS = 30

MAX_TEXT_FILE_SIZE = 10 * 1024 * 1024
MAX_XML_FILE_SIZE = 1024 * 1024

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
    ".woff",
    ".woff2",
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

# Project policy: these permissions are prohibited unless this list
# is deliberately changed after reviewing the application's needs.
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
        r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"
    ),
    re.compile(
        r"\bAIza[0-9A-Za-z_-]{30,}\b"
    ),
    re.compile(
        r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"
    ),
)

NETWORK_CONFIG_REFERENCE = re.compile(
    r"@xml/([a-z][a-z0-9_]*)"
)

XML_DECLARATION_PATTERN = re.compile(
    r"<!\s*(?:DOCTYPE|ENTITY)\b",
    re.IGNORECASE,
)


class SecurityCheckError(Exception):
    """Repository-level inspection failure."""


class FileInspectionError(Exception):
    """A file cannot be inspected safely."""


class ScanStats:
    def __init__(self) -> None:
        self.text_files_scanned = 0
        self.binary_files_excluded = 0


def display_path(value: str | Path) -> str:
    """Escape unusual filenames and terminal control characters."""

    return ascii(str(value))


def run_git(
    args: list[str],
    cwd: Path | None = None,
) -> bytes:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            check=True,
            capture_output=True,
            timeout=GIT_TIMEOUT_SECONDS,
        )
    except FileNotFoundError:
        raise SecurityCheckError(
            "Git executable was not found."
        ) from None
    except subprocess.TimeoutExpired:
        raise SecurityCheckError(
            "Git repository inspection timed out."
        ) from None
    except (OSError, subprocess.CalledProcessError):
        raise SecurityCheckError(
            "Git repository inspection failed. "
            "Run this script inside a valid Git repository."
        ) from None

    return result.stdout


def get_repository_root() -> Path:
    output = run_git(
        ["rev-parse", "--show-toplevel"]
    )

    # Remove the single terminator, not whitespace belonging to a path.
    if output.endswith(b"\n"):
        output = output[:-1]

    if os.name == "nt" and output.endswith(b"\r"):
        output = output[:-1]

    if not output:
        raise SecurityCheckError(
            "Git returned an empty repository root."
        )

    try:
        return Path(os.fsdecode(output)).resolve(strict=True)
    except (OSError, RuntimeError):
        raise SecurityCheckError(
            "Could not resolve the Git repository root."
        ) from None


def get_tracked_files(root: Path) -> list[str]:
    output = run_git(
        ["ls-files", "--cached", "-z"],
        cwd=root,
    )

    # Deduplicate paths that can appear multiple times during conflicts.
    return sorted({
        os.fsdecode(item)
        for item in output.split(b"\0")
        if item
    })


def checked_file_path(
    root: Path,
    relative_path: Path,
) -> Path:
    """Reject symlinks, missing files, and paths outside the repository.

    This protects normal inspection from following symlinks.
    It is not a sandbox against concurrent malicious filesystem changes.
    """

    if (
        relative_path.is_absolute()
        or not relative_path.parts
        or any(
            part in {"", ".", ".."}
            for part in relative_path.parts
        )
    ):
        raise FileInspectionError(
            "Unsafe repository-relative path."
        )

    current = root

    try:
        for index, part in enumerate(relative_path.parts):
            current = current / part
            mode = current.lstat().st_mode

            if stat.S_ISLNK(mode):
                raise FileInspectionError(
                    "Symlink paths are not inspected."
                )

            last = index == len(relative_path.parts) - 1

            if not last and not stat.S_ISDIR(mode):
                raise FileInspectionError(
                    "A parent path is not a directory."
                )

            if last and not stat.S_ISREG(mode):
                raise FileInspectionError(
                    "Path is not a regular file; "
                    "submodule contents are not scanned."
                )

        resolved = current.resolve(strict=True)
        resolved.relative_to(root)

    except FileInspectionError:
        raise
    except FileNotFoundError:
        raise FileInspectionError(
            "Tracked or required file is missing."
        ) from None
    except (OSError, RuntimeError, ValueError):
        raise FileInspectionError(
            "Could not safely resolve the file."
        ) from None

    return current


def read_bounded_file(
    root: Path,
    relative_path: Path,
    limit: int,
) -> bytes:
    path = checked_file_path(root, relative_path)

    try:
        # O_NOFOLLOW additionally protects the final path component
        # on platforms that provide it.
        flags = (
            os.O_RDONLY
            | getattr(os, "O_BINARY", 0)
            | getattr(os, "O_NOFOLLOW", 0)
        )

        descriptor = os.open(path, flags)

        try:
            with os.fdopen(descriptor, "rb") as stream:
                descriptor = -1

                metadata = os.fstat(stream.fileno())

                if not stat.S_ISREG(metadata.st_mode):
                    raise FileInspectionError(
                        "Opened path is not a regular file."
                    )

                if metadata.st_size > limit:
                    raise FileInspectionError(
                        f"File exceeds the {limit}-byte inspection limit."
                    )

                content = stream.read(limit + 1)

        finally:
            if descriptor != -1:
                os.close(descriptor)

    except FileInspectionError:
        raise
    except OSError:
        raise FileInspectionError(
            "Could not read the file."
        ) from None

    if len(content) > limit:
        raise FileInspectionError(
            f"File exceeds the {limit}-byte inspection limit."
        )

    return content


def is_environment_file(name: str) -> bool:
    filename = Path(name).name.lower()

    return (
        filename == ".env"
        or (
            filename.startswith(".env.")
            and filename not in ENV_EXAMPLE_NAMES
        )
    )


def inspect_tracked_file(
    root: Path,
    name: str,
    findings: list[str],
    stats: ScanStats,
) -> None:
    relative_path = Path(name)
    suffix = relative_path.suffix.lower()
    label = display_path(name)

    if is_environment_file(name):
        findings.append(
            f"Project policy prohibits tracked environment files: {label}"
        )

    if suffix in SIGNING_EXTENSIONS:
        findings.append(
            "Project policy prohibits tracked signing/key files "
            f"(including public-only PEM files): {label}"
        )

    # Validate even excluded paths so symlinks, missing files, and
    # submodules cannot silently bypass the scope declaration.
    try:
        checked_file_path(root, relative_path)
    except FileInspectionError as error:
        findings.append(
            f"Could not inspect {label}: {error}"
        )
        return

    if suffix in BINARY_EXTENSIONS:
        stats.binary_files_excluded += 1
        return

    try:
        content = read_bounded_file(
            root,
            relative_path,
            MAX_TEXT_FILE_SIZE,
        )
    except FileInspectionError as error:
        findings.append(
            f"Could not inspect {label}: {error}"
        )
        return

    if b"\0" in content:
        findings.append(
            "Unrecognized binary or NUL-containing file cannot "
            f"be scanned as text: {label}"
        )
        return

    # Byte-preserving decoding keeps ASCII token patterns detectable
    # even in files containing invalid UTF-8.
    text = content.decode(
        "utf-8",
        errors="surrogateescape",
    )

    stats.text_files_scanned += 1

    for pattern in SECRET_PATTERNS:
        if pattern.search(text):
            findings.append(
                f"Potential secret material detected in {label}; "
                "inspect privately."
            )
            break


def parse_xml_file(
    root: Path,
    relative_path: Path,
    findings: list[str],
) -> ET.Element | None:
    label = display_path(relative_path)

    try:
        content = read_bounded_file(
            root,
            relative_path,
            MAX_XML_FILE_SIZE,
        )
    except FileInspectionError as error:
        findings.append(
            f"Could not inspect XML file {label}: {error}"
        )
        return None

    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError:
        findings.append(
            f"XML file must use UTF-8 encoding: {label}"
        )
        return None

    if XML_DECLARATION_PATTERN.search(text):
        findings.append(
            f"DOCTYPE and ENTITY declarations are prohibited: {label}"
        )
        return None

    try:
        return ET.fromstring(text)
    except (ET.ParseError, ValueError):
        # Never print parser errors containing source content.
        findings.append(
            f"Could not parse valid XML: {label}"
        )
        return None


def inspect_network_config_file(
    root: Path,
    relative_path: Path,
    findings: list[str],
) -> None:
    config = parse_xml_file(
        root,
        relative_path,
        findings,
    )

    if config is None:
        return

    label = display_path(relative_path)

    if config.tag != "network-security-config":
        findings.append(
            f"Unexpected network security config root: {label}"
        )
        return

    base_configs = config.findall("base-config")

    # Strict project policy: do not depend on target-SDK defaults.
    if (
        len(base_configs) != 1
        or base_configs[0].get("cleartextTrafficPermitted") != "false"
    ):
        findings.append(
            "Network security config must contain exactly one "
            "base-config with cleartextTrafficPermitted=\"false\": "
            f"{label}"
        )

    for element in config.iter():
        cleartext = element.get("cleartextTrafficPermitted")

        if cleartext is not None and cleartext != "false":
            findings.append(
                "Network security config must not enable cleartext "
                f"or use an unresolved cleartext value: {label}"
            )
            break


def inspect_network_security_config(
    root: Path,
    reference: str,
    findings: list[str],
) -> None:
    match = NETWORK_CONFIG_REFERENCE.fullmatch(reference)

    if match is None:
        findings.append(
            "networkSecurityConfig must reference a local "
            "@xml/resource in the main Android source set."
        )
        return

    filename = match.group(1) + ".xml"
    default_path = MAIN_RES_PATH / "xml" / filename
    candidates = {default_path}

    resource_directory = root / MAIN_RES_PATH

    try:
        if resource_directory.is_symlink():
            raise FileInspectionError(
                "Android resource directory must not be a symlink."
            )

        if not resource_directory.is_dir():
            raise FileInspectionError(
                "Android main resource directory is missing."
            )

        # Inspect matching resource qualifiers such as xml-v24.
        for directory in resource_directory.iterdir():
            if not (
                directory.name == "xml"
                or directory.name.startswith("xml-")
            ):
                continue

            if directory.is_symlink():
                findings.append(
                    "Symlink Android XML resource directory is prohibited: "
                    f"{display_path(directory.relative_to(root))}"
                )
                continue

            if not directory.is_dir():
                continue

            candidate = directory / filename

            if candidate.exists() or candidate.is_symlink():
                candidates.add(candidate.relative_to(root))

    except (OSError, FileInspectionError):
        findings.append(
            "Could not safely enumerate Android main XML resources."
        )
        return

    for relative_path in sorted(candidates):
        inspect_network_config_file(
            root,
            relative_path,
            findings,
        )


def inspect_android_manifest(
    root: Path,
    findings: list[str],
) -> None:
    manifest = parse_xml_file(
        root,
        MANIFEST_PATH,
        findings,
    )

    if manifest is None:
        return

    if manifest.tag != "manifest":
        findings.append(
            "Android manifest has an unexpected root element."
        )
        return

    permissions: set[str] = set()

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

    # INTERNET must be declared without an SDK-specific tag or
    # maxSdkVersion restriction.
    has_internet = any(
        element.tag == "uses-permission"
        and element.get(ANDROID + "name")
        == "android.permission.INTERNET"
        and element.get(ANDROID + "maxSdkVersion") is None
        for element in manifest
    )

    if not has_internet:
        findings.append(
            "Android INTERNET permission must be declared using "
            "uses-permission without maxSdkVersion."
        )

    for permission in sorted(
        permissions & UNNECESSARY_PERMISSIONS
    ):
        findings.append(
            "Android permission prohibited by project policy: "
            f"{permission}"
        )

    applications = manifest.findall("application")

    if len(applications) != 1:
        findings.append(
            "Android manifest must contain exactly one application."
        )
        return

    application = applications[0]

    if application.get(ANDROID + "usesCleartextTraffic") != "false":
        findings.append(
            "Android usesCleartextTraffic must explicitly be false."
        )

    if application.get(ANDROID + "allowBackup") != "false":
        findings.append(
            "Android allowBackup must explicitly be false."
        )

    # Absence is allowed in the source manifest. The final release
    # manifest must still be checked after merging.
    debuggable = application.get(ANDROID + "debuggable")

    if debuggable not in {None, "false"}:
        findings.append(
            "Main Android manifest must not enable debuggable "
            "or use an unresolved debuggable value."
        )

    test_only = application.get(ANDROID + "testOnly")

    if test_only not in {None, "false"}:
        findings.append(
            "Main Android manifest must not enable testOnly "
            "or use an unresolved testOnly value."
        )

    network_config = application.get(
        ANDROID + "networkSecurityConfig"
    )

    if network_config is not None:
        inspect_network_security_config(
            root,
            network_config,
            findings,
        )


def main() -> int:
    findings: list[str] = []
    stats = ScanStats()

    try:
        root = get_repository_root()
        tracked_files = get_tracked_files(root)

        if not tracked_files:
            raise SecurityCheckError(
                "No tracked files were found; refusing an empty scan."
            )

        for name in tracked_files:
            inspect_tracked_file(
                root,
                name,
                findings,
                stats,
            )

        inspect_android_manifest(
            root,
            findings,
        )

    except SecurityCheckError as error:
        print(
            f"Security check could not complete: {error}",
            file=sys.stderr,
            flush=True,
        )
        return 2

    except KeyboardInterrupt:
        print(
            "Security check interrupted.",
            file=sys.stderr,
            flush=True,
        )
        return 130

    print(
        "Scope: tracked working-tree files and main Android "
        "source configuration.",
        flush=True,
    )

    print(
        f"Text files scanned: {stats.text_files_scanned}; "
        "recognized binary files excluded from content scanning: "
        f"{stats.binary_files_excluded}.",
        flush=True,
    )

    if findings:
        print(
            "Repository security checks FAILED:",
            file=sys.stderr,
            flush=True,
        )

        for finding in findings:
            print(
                f"- {finding}",
                file=sys.stderr,
                flush=True,
            )

        print(
            f"Total findings: {len(findings)}",
            file=sys.stderr,
            flush=True,
        )

        return 1

    print(
        "Repository security checks passed within the stated scope.",
        flush=True,
    )

    print(
        "Not checked: untracked files, staged blobs, Git history, "
        "binary contents, or final merged release configuration.",
        flush=True,
    )

    print(
        "Secret detection is best-effort; a passing result is not "
        "a guarantee that the repository contains no secrets.",
        flush=True,
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
