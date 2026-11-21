
#!/usr/bin/env python3
"""Convert Flutter analyzer output into GitHub Actions annotations."""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

# Flutter analyzer output may contain ANSI terminal color sequences.
ANSI_ESCAPE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")

# Examples:
# lib/main.dart:12:5
# C:\project\lib\main.dart:12:5
LOCATION_PATTERN = re.compile(r"^(.*):(\d+):(\d+)$")

SEVERITY_MAP = {
    "error": "error",
    "warning": "warning",
    "info": "notice",
}

COUNTS = Counter()


def escape_property(value: str) -> str:
    """Escape GitHub workflow command properties."""
    return (
        value
        .replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
        .replace(":", "%3A")
        .replace(",", "%2C")
    )


def escape_message(value: str) -> str:
    """Escape GitHub workflow command message data."""
    return (
        value
        .replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )


def parse_diagnostic(raw_line: str) -> tuple[str, str, int, int, str, str] | None:
    """Parse one Flutter analyzer diagnostic line."""

    line = ANSI_ESCAPE.sub("", raw_line).strip()

    if not line:
        return None

    parts = [part.strip() for part in line.split(" • ")]

    # Expected format:
    # severity • message • file:line:column • diagnostic_code
    if len(parts) < 4:
        return None

    severity = parts[0].lower()

    if severity not in SEVERITY_MAP:
        return None

    location_match = LOCATION_PATTERN.match(parts[-2])

    if not location_match:
        return None

    file_name, line_number, column = location_match.groups()

    try:
        line_number = int(line_number)
        column = int(column)
    except ValueError:
        return None

    if line_number < 1 or column < 1 or not file_name:
        return None

    # Preserve the complete message, including any embedded separator.
    message = " • ".join(parts[1:-2]).strip()
    diagnostic_code = parts[-1].strip()

    if not message:
        message = "Flutter analyzer reported a diagnostic."

    return (
        severity,
        file_name,
        line_number,
        column,
        message,
        diagnostic_code,
    )


def emit_annotation(
    severity: str,
    file_name: str,
    line_number: int,
    column: int,
    message: str,
    diagnostic_code: str,
) -> None:
    """Print a GitHub Actions annotation."""

    level = SEVERITY_MAP[severity]

    properties = (
        f"file={escape_property(file_name)},"
        f"line={line_number},"
        f"col={column}"
    )

    annotation_message = message

    if diagnostic_code:
        annotation_message += f" ({diagnostic_code})"

    print(
        f"::{level} {properties}::"
        f"{escape_message(annotation_message)}"
    )


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "Usage: python tool/flutter_analyzer_annotations.py <analyzer-output>",
            file=sys.stderr,
        )
        return 2

    report_path = Path(sys.argv[1])

    if not report_path.is_file():
        print(
            f"Analyzer report not found: {report_path}",
            file=sys.stderr,
        )
        return 2

    try:
        content = report_path.read_text(
            encoding="utf-8",
            errors="replace",
        )
    except OSError as error:
        print(
            f"Could not read analyzer report: {error}",
            file=sys.stderr,
        )
        return 2

    parsed_count = 0
    ignored_count = 0

    for raw_line in content.splitlines():
        diagnostic = parse_diagnostic(raw_line)

        if diagnostic is None:
            ignored_count += 1
            continue

        (
            severity,
            file_name,
            line_number,
            column,
            message,
            diagnostic_code,
        ) = diagnostic

        emit_annotation(
            severity,
            file_name,
            line_number,
            column,
            message,
            diagnostic_code,
        )

        COUNTS[severity] += 1
        parsed_count += 1

    print(
        "::group::Flutter analyzer annotation summary"
    )

    print(f"Errors: {COUNTS['error']}")
    print(f"Warnings: {COUNTS['warning']}")
    print(f"Info: {COUNTS['info']}")
    print(f"Parsed diagnostics: {parsed_count}")
    print(f"Ignored lines: {ignored_count}")

    print("::endgroup::")

    if parsed_count == 0:
        print(
            "::notice::Flutter analyzer produced no parseable diagnostic lines."
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
