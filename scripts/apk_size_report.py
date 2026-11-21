
#!/usr/bin/env python3
"""Measure actual Android APK/AAB artifacts and generate size reports."""

from __future__ import annotations

import hashlib
import json
import sys
import zipfile

from collections import defaultdict
from pathlib import Path
from typing import Any


CHUNK_SIZE = 1024 * 1024

ARTIFACT_EXTENSIONS = {".apk", ".aab"}

SECTION_NAMES = {
    "native": "Native libraries",
    "dex": "Android bytecode",
    "debug_symbols": "Debug symbols",
    "obfuscation_metadata": "Obfuscation metadata",
    "assets_resources": "Assets and resources",
    "signing_metadata": "Signing metadata",
    "other": "Other files",
}


def sha256_file(path: Path) -> str:
    """Calculate SHA-256 without loading the complete artifact into memory."""

    digest = hashlib.sha256()

    with path.open("rb") as file:
        while chunk := file.read(CHUNK_SIZE):
            digest.update(chunk)

    return digest.hexdigest()


def classify_entry(name: str) -> tuple[str, str | None]:
    """Classify an APK/AAB ZIP entry."""

    normalized = name.replace("\\", "/")
    parts = normalized.split("/")

    # APK native libraries:
    # lib/arm64-v8a/libflutter.so
    # lib/x86_64/libapp.so
    #
    # AAB native libraries:
    # base/lib/arm64-v8a/libflutter.so
    # base/lib/x86_64/libapp.so

    if len(parts) >= 3 and parts[0] == "lib":
        return "native", parts[1]

    if len(parts) >= 4 and parts[0] == "base" and parts[1] == "lib":
        return "native", parts[2]

    # DEX files can be located at the root of an APK
    # or inside an AAB module.
    if name.endswith(".dex"):
        return "dex", None

    if name.startswith(
        "BUNDLE-METADATA/com.android.tools.build.debugsymbols/"
    ):
        return "debug_symbols", None

    if name.startswith(
        "BUNDLE-METADATA/com.android.tools.build.obfuscation/"
    ):
        return "obfuscation_metadata", None

    if (
        name.startswith(("assets/", "res/", "base/assets/", "base/res/"))
        or name == "resources.arsc"
        or name == "base/resources.pb"
        or name == "resources.pb"
    ):
        return "assets_resources", None

    if (
        name.startswith(("META-INF/", "base/META-INF/"))
        or name.endswith((".RSA", ".SF", ".MF"))
    ):
        return "signing_metadata", None

    return "other", None


def new_section() -> dict[str, int]:
    return {
        "compressed_bytes": 0,
        "uncompressed_bytes": 0,
        "entries": 0,
    }


def analyze_artifact(path: Path) -> dict[str, Any]:
    """Analyze one APK or AAB archive."""

    groups: dict[str, dict[str, int]] = defaultdict(new_section)
    native_abis: dict[str, dict[str, int]] = defaultdict(new_section)

    with zipfile.ZipFile(path, "r") as archive:
        bad_entry = archive.testzip()

        if bad_entry is not None:
            raise ValueError(
                f"Archive integrity check failed at entry: {bad_entry}"
            )

        for entry in archive.infolist():
            if entry.is_dir():
                continue

            group, abi = classify_entry(entry.filename)

            section = groups[group]

            section["compressed_bytes"] += entry.compress_size
            section["uncompressed_bytes"] += entry.file_size
            section["entries"] += 1

            if group == "native" and abi:
                abi_section = native_abis[abi]

                abi_section["compressed_bytes"] += entry.compress_size
                abi_section["uncompressed_bytes"] += entry.file_size
                abi_section["entries"] += 1

    sections = dict(sorted(groups.items()))

    largest_section = max(
        sections.items(),
        key=lambda item: item[1]["compressed_bytes"],
        default=("none", new_section()),
    )

    total_compressed = sum(
        item["compressed_bytes"] for item in sections.values()
    )

    total_uncompressed = sum(
        item["uncompressed_bytes"] for item in sections.values()
    )

    file_size = path.stat().st_size

    return {
        "file": path.name,
        "format": path.suffix.lower().lstrip("."),
        "file_bytes": file_size,
        "file_mib": round(file_size / 1048576, 3),
        "sha256": sha256_file(path),
        "archive": {
            "compressed_entry_bytes": total_compressed,
            "uncompressed_entry_bytes": total_uncompressed,
            "compression_difference_bytes": (
                total_uncompressed - total_compressed
            ),
        },
        "largest_section": {
            "name": largest_section[0],
            "compressed_bytes": largest_section[1]["compressed_bytes"],
            "uncompressed_bytes": largest_section[1]["uncompressed_bytes"],
        },
        "native_abis": dict(sorted(native_abis.items())),
        "sections": sections,
    }


def format_kib(value: int) -> str:
    return f"{value / 1024:.1f}"


def generate_summary(results: list[dict[str, Any]]) -> str:
    """Create a Markdown report with actual measured sizes."""

    lines = [
        "## Actual Android artifact sizes",
        "",
        "| File | Format | Size (MiB) | Largest section | Compressed (KiB) |",
        "|---|---|---:|---|---:|",
    ]

    for item in results:
        largest = item["largest_section"]

        lines.append(
            f"| `{item['file']}` "
            f"| {item['format'].upper()} "
            f"| {item['file_bytes'] / 1048576:.2f} "
            f"| `{largest['name']}` "
            f"| {format_kib(largest['compressed_bytes'])} |"
        )

    lines.extend([
        "",
        "### Section breakdown",
        "",
    ])

    for item in results:
        lines.extend([
            f"#### `{item['file']}`",
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

        if item["native_abis"]:
            lines.extend([
                "",
                "**Native ABI breakdown**",
                "",
                "| ABI | Compressed (KiB) | Uncompressed (KiB) | Entries |",
                "|---|---:|---:|---:|",
            ])

            for abi, section in item["native_abis"].items():
                lines.append(
                    f"| `{abi}` "
                    f"| {format_kib(section['compressed_bytes'])} "
                    f"| {format_kib(section['uncompressed_bytes'])} "
                    f"| {section['entries']} |"
                )

        lines.append("")

    lines.extend([
        "### Interpretation",
        "",
        "- APK/AAB file size is the actual artifact size measured on disk.",
        "- ZIP compressed and uncompressed totals describe archive entries; "
        "they are not necessarily identical to the delivered download size.",
        "- Native libraries are reported by ABI where recognizable.",
        "- Debug symbols and obfuscation metadata are separated from "
        "ordinary application content.",
        "- AAB delivery size depends on the device-specific splits generated "
        "by Google Play or the relevant distribution service.",
        "- An APK containing multiple ABIs may be larger than a device-specific "
        "split APK.",
        "",
        "SHA-256 hashes and full measurements are available in `sizes.json`.",
        "",
        "These measurements do not prove installation, runtime behavior, "
        "physical-device compatibility, or payment functionality.",
    ])

    return "\n".join(lines) + "\n"


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

    if not source.exists() or not source.is_dir():
        print(
            f"Artifact directory does not exist: {source}",
            file=sys.stderr,
        )
        return 2

    try:
        destination.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        print(
            f"Could not create report directory: {error}",
            file=sys.stderr,
        )
        return 2

    artifact_paths = sorted(
        path
        for path in source.iterdir()
        if path.is_file() and path.suffix.lower() in ARTIFACT_EXTENSIONS
    )

    if not artifact_paths:
        print(
            f"No APK/AAB files found in: {source}",
            file=sys.stderr,
        )
        return 1

    results = []
    failures = []

    for path in artifact_paths:
        try:
            result = analyze_artifact(path)
            results.append(result)

            print(
                f"Measured {path.name}: "
                f"{result['file_mib']:.2f} MiB "
                f"(SHA-256: {result['sha256']})"
            )

        except (OSError, zipfile.BadZipFile, ValueError, RuntimeError) as error:
            failures.append({
                "file": path.name,
                "error": str(error),
            })

            print(
                f"::error::Could not analyze {path.name}: {error}"
            )

    if results:
        sizes_path = destination / "sizes.json"
        summary_path = destination / "summary.md"

        try:
            sizes_path.write_text(
                json.dumps(
                    {
                        "artifacts": results,
                        "failures": failures,
                    },
                    indent=2,
                    ensure_ascii=False,
                ) + "\n",
                encoding="utf-8",
            )

            summary = generate_summary(results)

            if failures:
                summary += "\n### Artifact analysis failures\n\n"

                for failure in failures:
                    summary += (
                        f"- `{failure['file']}`: "
                        f"{failure['error']}\n"
                    )

            summary_path.write_text(
                summary,
                encoding="utf-8",
            )

        except OSError as error:
            print(
                f"::error::Could not write artifact reports: {error}"
            )
            return 2

        print(summary)

    if failures:
        print(
            f"::error::{len(failures)} artifact(s) could not be analyzed."
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
