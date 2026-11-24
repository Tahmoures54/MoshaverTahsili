#!/usr/bin/env python3
"""Convert Flutter analyzer output into GitHub Actions annotations.

Supported format:
    severity • message • file:line:column • diagnostic_code

Requires Python 3.10 or newer.

Exit codes:
    0: Annotation conversion completed successfully.
    2: Invalid arguments or report could not be read.

The exit status of `flutter analyze` must be checked separately.
"""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

# Flutter analyzer output may contain ANSI terminal color sequences.
ANSI_ESCAPE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")

# Supports Unix and Windows paths:
# lib/main.dart:12:5
# C:\project\lib\main.dart:12:5
LOCATION_PATTERN = re.compile(r"^(.*):(\d+):(\d+)$")

SEVERITY_MAP = {
    "error": "error",
    "warning": "warning",
    "info": "notice",
}

Diagnostic = tuple[str, str, int, int, str, str]


def escape_property(value: str) -> str:
    """Escape GitHub workflow command properties."""
    return (
        value.replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
        .replace(":", "%3A")
        .replace(",", "%2C")
    )


def escape_message(value: str) -> str:
    """Escape GitHub workflow command message data."""
    return (
        value.replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )


def parse_diagnostic(raw_line: str) -> Diagnostic | None:
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

    location_match = LOCATION_PATTERN.fullmatch(parts[-2])

    if location_match is None:
        return None

    file_name, line_text, column_text = location_match.groups()
    file_name = file_name.strip()

    try:
        line_number = int(line_text)
        column = int(column_text)
    except ValueError:
        return None

    if not file_name or line_number < 1 or column < 1:
        return None

    # Preserve any separator embedded in the diagnostic message.
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


def emit_summary(
    counts: Counter[str],
    parsed_count: int,
    ignored_count: int,
) -> None:
    """Print a summary without claiming analyzer success."""
    print("::group::Flutter analyzer annotation summary")
    print(f"Errors: {counts['error']}")
    print(f"Warnings: {counts['warning']}")
    print(f"Info: {counts['info']}")
    print(f"Parsed diagnostics: {parsed_count}")
    print(f"Ignored lines: {ignored_count}")
    print("::endgroup::")

    if parsed_count == 0:
        message = (
            "No diagnostic lines matched the supported Flutter analyzer "
            "text format. Check the analyzer exit status and raw report."
        )
        print(f"::notice::{escape_message(message)}")


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "Usage: python3 annotate_analysis.py <analyzer-output>",
            file=sys.stderr,
        )
        return 2

    report_path = Path(sys.argv[1])

    # Local counters avoid accumulating results across repeated calls.
    counts: Counter[str] = Counter()
    parsed_count = 0
    ignored_count = 0

    try:
        # Stream the report and remove an optional UTF-8 BOM.
        with report_path.open(
            mode="r",
            encoding="utf-8-sig",
            errors="replace",
        ) as report:
            for raw_line in report:
                diagnostic = parse_diagnostic(raw_line)

                if diagnostic is None:
                    ignored_count += 1
                    continue

                emit_annotation(*diagnostic)

                counts[diagnostic[0]] += 1
                parsed_count += 1

    except (OSError, ValueError) as error:
        print(
            f"Could not read analyzer report {str(report_path)!r}: {error}",
            file=sys.stderr,
        )
        return 2

    emit_summary(counts, parsed_count, ignored_count)

    # Successful conversion does not mean Flutter analysis passed.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
