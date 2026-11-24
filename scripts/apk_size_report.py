#!/usr/bin/env python3
"""Measure Android APK/AAB artifacts and generate JSON/Markdown reports.

Requires Python 3.10 or newer.

Exit codes:
    0: All discovered artifacts were analyzed and reports were written.
    1: No artifacts found, or at least one artifact could not be analyzed.
    2: Invalid arguments, directory access failure, or report write failure.

Only files directly inside the artifact directory are discovered.
Symlinks are excluded. Measurements are not installation or runtime tests.
"""

from __future__ import annotations

import hashlib
import html
import json
import os
import re
import stat
import sys
import tempfile
import zipfile
import zlib

from collections import defaultdict
from pathlib import Path
from typing import Any, BinaryIO


CHUNK_SIZE = 1024 * 1024
MIB = 1024 * 1024

ARTIFACT_EXTENSIONS = {".apk", ".aab"}

# Safety limits for archive inspection and CRC validation.
MAX_ARTIFACT_BYTES = 4 * 1024 * MIB
MAX_ARCHIVE_ENTRIES = 100_000
MAX_UNCOMPRESSED_BYTES = 8 * 1024 * MIB
MAX_ENTRY_UNCOMPRESSED_BYTES = 2 * 1024 * MIB

SECTION_NAMES = {
    "native": "Native libraries",
    "dex": "Android bytecode",
    "debug_symbols": "Debug symbols",
    "obfuscation_metadata": "Obfuscation metadata",
    "assets_resources": "Assets and resources",
    "signing_metadata": "ZIP signing metadata",
    "other": "Other files",
}

ABI_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")

ANSI_PATTERN = re.compile(
    r"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"
    r"|\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"
)
CONTROL_PATTERN = re.compile(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]")
BIDI_PATTERN = re.compile(r"[\u202A-\u202E\u2066-\u2069]")


def clean_text(value: object) -> str:
    text = ANSI_PATTERN.sub("", str(value))
    text = CONTROL_PATTERN.sub("", text)
    return BIDI_PATTERN.sub("", text)


def emit_error(message: str) -> None:
    safe = (
        clean_text(message)
        .replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )
    print(f"::error::{safe}")


def markdown_text(value: object) -> str:
    """Render untrusted names/errors as text, not Markdown syntax."""

    text = clean_text(value).replace("\r", " ").replace("\n", " ")

    # Limit display length; JSON preserves the complete original value.
    if len(text) > 1000:
        text = text[:980] + " … [truncated]"

    text = html.escape(text, quote=True)

    for character in "\\`*_{}[]()!#|~":
        text = text.replace(character, f"&#{ord(character)};")

    return text


def sha256_stream(stream: BinaryIO) -> str:
    digest = hashlib.sha256()
    stream.seek(0)

    while chunk := stream.read(CHUNK_SIZE):
        digest.update(chunk)

    return digest.hexdigest()


def sha256_file(path: Path) -> str:
    """Calculate SHA-256 without loading the whole file into memory."""

    with path.open("rb") as stream:
        return sha256_stream(stream)


def classify_entry(name: str) -> tuple[str, str | None]:
    """Classify APK entries and entries in any AAB module."""

    normalized = name.replace("\\", "/")
    parts = normalized.split("/")
    upper = normalized.upper()

    if normalized.startswith(
        "BUNDLE-METADATA/com.android.tools.build.debugsymbols/"
    ):
        return "debug_symbols", None

    if normalized.startswith(
        "BUNDLE-METADATA/com.android.tools.build.obfuscation/"
    ):
        return "obfuscation_metadata", None

    # APK: lib/<abi>/<library>.so
    # AAB: <module>/lib/<abi>/<library>.so
    abi: str | None = None

    if len(parts) == 3 and parts[0] == "lib":
        abi = parts[1]
    elif len(parts) == 4 and parts[1] == "lib":
        abi = parts[2]

    if (
        abi
        and ABI_PATTERN.fullmatch(abi)
        and normalized.lower().endswith(".so")
    ):
        return "native", abi

    if normalized.lower().endswith(".dex"):
        return "dex", None

    # Classify only recognized signing files, not all META-INF content.
    meta_parts: list[str] | None = None

    if parts and parts[0].upper() == "META-INF":
        meta_parts = parts[1:]
    elif len(parts) >= 2 and parts[1].upper() == "META-INF":
        meta_parts = parts[2:]

    if meta_parts and len(meta_parts) == 1:
        filename = meta_parts[0].upper()

        if (
            filename == "MANIFEST.MF"
            or filename.endswith((".SF", ".RSA", ".DSA", ".EC"))
            or filename.startswith("SIG-")
        ):
            return "signing_metadata", None

    if (
        parts[0] in {"assets", "res"}
        or (
            len(parts) >= 2
            and parts[1] in {"assets", "res"}
        )
        or upper in {"RESOURCES.ARSC", "RESOURCES.PB"}
        or (
            len(parts) == 2
            and parts[1].lower() in {"resources.arsc", "resources.pb"}
        )
    ):
        return "assets_resources", None

    return "other", None


def new_section() -> dict[str, int]:
    return {
        "compressed_bytes": 0,
        "uncompressed_bytes": 0,
        "entries": 0,
    }


def add_entry(section: dict[str, int], entry: zipfile.ZipInfo) -> None:
    section["compressed_bytes"] += entry.compress_size
    section["uncompressed_bytes"] += entry.file_size
    section["entries"] += 1


def file_signature(info: os.stat_result) -> tuple[int, ...]:
    return (
        info.st_dev,
        info.st_ino,
        info.st_size,
        info.st_mtime_ns,
        info.st_ctime_ns,
    )


def analyze_artifact(path: Path) -> dict[str, Any]:
    """Validate CRCs, classify ZIP payloads, and hash one artifact."""

    groups: dict[str, dict[str, int]] = defaultdict(new_section)
    native_abis: dict[str, dict[str, int]] = defaultdict(new_section)

    with path.open("rb") as stream:
        initial_info = os.fstat(stream.fileno())

        if not stat.S_ISREG(initial_info.st_mode):
            raise ValueError("Artifact is not a regular file")

        if initial_info.st_size > MAX_ARTIFACT_BYTES:
            raise ValueError(
                f"Artifact exceeds {MAX_ARTIFACT_BYTES} bytes"
            )

        with zipfile.ZipFile(stream, "r") as archive:
            entries = archive.infolist()

            if len(entries) > MAX_ARCHIVE_ENTRIES:
                raise ValueError(
                    f"Archive exceeds {MAX_ARCHIVE_ENTRIES} entries"
                )

            declared_total = 0

            # Check limits before decompressing anything.
            for entry in entries:
                if entry.flag_bits & 1:
                    raise ValueError(
                        f"Encrypted entry is unsupported: {entry.filename}"
                    )

                if (
                    entry.file_size < 0
                    or entry.compress_size < 0
                ):
                    raise ValueError("Invalid negative ZIP entry size")

                if entry.file_size > MAX_ENTRY_UNCOMPRESSED_BYTES:
                    raise ValueError(
                        "Entry exceeds uncompressed size limit: "
                        f"{entry.filename}"
                    )

                declared_total += entry.file_size

                if declared_total > MAX_UNCOMPRESSED_BYTES:
                    raise ValueError(
                        "Archive exceeds total uncompressed size limit"
                    )

            actual_total = 0

            for entry in entries:
                actual_entry_size = 0

                # Reading to EOF performs zipfile's CRC validation.
                # Explicit counters also bound decompressed output.
                with archive.open(entry, "r") as member:
                    while chunk := member.read(CHUNK_SIZE):
                        actual_entry_size += len(chunk)
                        actual_total += len(chunk)

                        if (
                            actual_entry_size
                            > MAX_ENTRY_UNCOMPRESSED_BYTES
                            or actual_total > MAX_UNCOMPRESSED_BYTES
                        ):
                            raise ValueError(
                                "Decompressed data exceeds safety limits"
                            )

                if actual_entry_size != entry.file_size:
                    raise ValueError(
                        f"Entry size mismatch: {entry.filename}"
                    )

                if entry.is_dir():
                    # Standard directory entries have no payload.
                    if entry.file_size or entry.compress_size:
                        raise ValueError(
                            "Non-empty directory entry is unsupported: "
                            f"{entry.filename}"
                        )
                    continue

                group, abi = classify_entry(entry.filename)
                add_entry(groups[group], entry)

                if group == "native" and abi:
                    add_entry(native_abis[abi], entry)

        digest = sha256_stream(stream)
        final_info = os.fstat(stream.fileno())

        if file_signature(initial_info) != file_signature(final_info):
            raise ValueError("Artifact changed during analysis")

        if file_signature(path.stat()) != file_signature(final_info):
            raise ValueError("Artifact path changed during analysis")

    sections = dict(sorted(groups.items()))

    total_compressed = sum(
        section["compressed_bytes"]
        for section in sections.values()
    )
    total_uncompressed = sum(
        section["uncompressed_bytes"]
        for section in sections.values()
    )

    file_size = initial_info.st_size
    non_payload_bytes = file_size - total_compressed

    if non_payload_bytes < 0:
        raise ValueError(
            "Compressed entry totals exceed artifact file size"
        )

    largest_name, largest = max(
        sections.items(),
        key=lambda item: item[1]["compressed_bytes"],
        default=("none", new_section()),
    )

    return {
        "file": path.name,
        "format": path.suffix.lower().lstrip("."),
        "file_bytes": file_size,
        "file_mib": round(file_size / MIB, 3),
        "sha256": digest,
        "integrity": {
            "crc_verified": True,
            "entries_checked": len(entries),
        },
        "archive": {
            "compressed_entry_bytes": total_compressed,
            "uncompressed_entry_bytes": total_uncompressed,
            "compression_difference_bytes": (
                total_uncompressed - total_compressed
            ),
            "non_payload_bytes": non_payload_bytes,
        },
        "largest_section": {
            "name": largest_name,
            "compressed_bytes": largest["compressed_bytes"],
            "uncompressed_bytes": largest["uncompressed_bytes"],
        },
        "native_abis": dict(sorted(native_abis.items())),
        "sections": sections,
    }


def format_kib(value: int) -> str:
    return f"{value / 1024:.1f}"


def generate_summary(
    results: list[dict[str, Any]],
    failures: list[dict[str, str]] | None = None,
) -> str:
    failures = failures or []

    lines = [
        "## Actual Android artifact sizes",
        "",
        "| File | Format | Size (MiB) | Largest section | "
        "Section compressed (KiB) |",
        "|---|---|---:|---|---:|",
    ]

    for item in results:
        largest = item["largest_section"]
        label = SECTION_NAMES.get(largest["name"], largest["name"])

        lines.append(
            f"| {markdown_text(item['file'])} "
            f"| {item['format'].upper()} "
            f"| {item['file_bytes'] / MIB:.2f} "
            f"| {markdown_text(label)} "
            f"| {format_kib(largest['compressed_bytes'])} |"
        )

    if not results:
        lines.extend(["", "No artifacts were successfully analyzed."])

    if results:
        lines.extend(["", "### Section breakdown", ""])

    for item in results:
        lines.extend([
            f"#### {markdown_text(item['file'])}",
            "",
            "| Section | Compressed (KiB) | Uncompressed (KiB) | Entries |",
            "|---|---:|---:|---:|",
        ])

        for name, section in sorted(
            item["sections"].items(),
            key=lambda pair: pair[1]["compressed_bytes"],
            reverse=True,
        ):
            lines.append(
                f"| {SECTION_NAMES.get(name, name)} "
                f"| {format_kib(section['compressed_bytes'])} "
                f"| {format_kib(section['uncompressed_bytes'])} "
                f"| {section['entries']} |"
            )

        lines.extend([
            "",
            "Bytes outside compressed entry payloads: "
            f"**{format_kib(item['archive']['non_payload_bytes'])} KiB**.",
            "",
        ])

        if item["native_abis"]:
            lines.extend([
                "**Native ABI breakdown**",
                "",
                "| ABI | Compressed (KiB) | Uncompressed (KiB) | Entries |",
                "|---|---:|---:|---:|",
            ])

            for abi, section in item["native_abis"].items():
                lines.append(
                    f"| {markdown_text(abi)} "
                    f"| {format_kib(section['compressed_bytes'])} "
                    f"| {format_kib(section['uncompressed_bytes'])} "
                    f"| {section['entries']} |"
                )

            lines.append("")

    if failures:
        lines.extend([
            "### Artifact analysis failures",
            "",
            "| File | Error |",
            "|---|---|",
        ])

        for failure in failures:
            lines.append(
                f"| {markdown_text(failure['file'])} "
                f"| {markdown_text(failure['error'])} |"
            )

        lines.append("")

    lines.extend([
        "### Interpretation",
        "",
        "- Artifact size is the file's logical byte length, not filesystem "
        "allocated space.",
        "- ZIP totals describe stored entry payloads, not installed size "
        "or guaranteed download size.",
        "- Non-payload bytes include ZIP headers, directory records, "
        "padding, comments, and potentially APK signing blocks.",
        "- ZIP signing metadata does not include APK v2/v3 signing blocks; "
        "those are not ordinary ZIP entries.",
        "- CRC checks detect archive corruption but do not verify Android "
        "signatures or publisher authenticity.",
        "- Native libraries and resources are classified across AAB modules.",
        "- AAB download size depends on device-specific splits.",
        "- These measurements do not prove installation, runtime behavior, "
        "device compatibility, or payment functionality.",
        "",
        "SHA-256 hashes and complete measurements are in `sizes.json`.",
        "",
    ])

    return "\n".join(lines)


def atomic_write_text(path: Path, content: str) -> None:
    """Replace one report atomically using a temporary sibling file."""

    temporary_path: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())

        os.replace(temporary_path, path)
        temporary_path = None

    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "Usage: python3 tool/measure_android_artifacts.py "
            "<artifact-directory> <report-directory>",
            file=sys.stderr,
        )
        return 2

    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])

    try:
        if not source.is_dir():
            raise ValueError(
                f"Artifact directory does not exist: {source}"
            )

        artifact_paths = sorted(
            (
                path
                for path in source.iterdir()
                if not path.is_symlink()
                and path.is_file()
                and path.suffix.lower() in ARTIFACT_EXTENSIONS
            ),
            key=lambda path: path.name,
        )

        destination.mkdir(parents=True, exist_ok=True)

    except (OSError, ValueError) as error:
        emit_error(f"Could not prepare artifact measurement: {error}")
        return 2

    results: list[dict[str, Any]] = []
    failures: list[dict[str, str]] = []

    if not artifact_paths:
        message = f"No APK/AAB files found in: {source}"
        emit_error(message)
        failures.append({"file": "(discovery)", "error": message})

    for path in artifact_paths:
        try:
            result = analyze_artifact(path)
            results.append(result)

            print(
                f"Measured {markdown_text(path.name)}: "
                f"{result['file_bytes'] / MIB:.2f} MiB "
                f"(SHA-256: {result['sha256']})"
            )

        except (
            OSError,
            EOFError,
            zipfile.BadZipFile,
            zipfile.LargeZipFile,
            ValueError,
            RuntimeError,
            NotImplementedError,
            zlib.error,
        ) as error:
            failures.append({
                "file": path.name,
                "error": str(error),
            })

            emit_error(f"Could not analyze {path.name}: {error}")

    report = {
        "schema_version": 1,
        "status": "failed" if failures else "ok",
        "limits": {
            "max_artifact_bytes": MAX_ARTIFACT_BYTES,
            "max_archive_entries": MAX_ARCHIVE_ENTRIES,
            "max_uncompressed_bytes": MAX_UNCOMPRESSED_BYTES,
            "max_entry_uncompressed_bytes": (
                MAX_ENTRY_UNCOMPRESSED_BYTES
            ),
        },
        "artifacts": results,
        "failures": failures,
    }

    summary = generate_summary(results, failures)

    try:
        # Each replacement is atomic independently; these two writes
        # are not a single transaction.
        atomic_write_text(
            destination / "sizes.json",
            json.dumps(
                report,
                indent=2,
                ensure_ascii=True,
            ) + "\n",
        )

        atomic_write_text(
            destination / "summary.md",
            summary,
        )

    except (OSError, ValueError) as error:
        emit_error(f"Could not write artifact reports: {error}")
        return 2

    # Print only a fixed completion message. Arbitrary report content
    # should not be interpreted as workflow commands in stdout.
    print(
        f"Artifact reports written: "
        f"{len(results)} succeeded, {len(failures)} failure(s)."
    )

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
