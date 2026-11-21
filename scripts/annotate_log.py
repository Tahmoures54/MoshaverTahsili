
#!/usr/bin/env python3
"""Expose CI failure diagnostics as safe GitHub annotations and job summary."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from typing import Iterable

# Maximum amount of diagnostic output per report.
MAX_SUMMARY_LINES = 160
MAX_ANNOTATIONS_PER_FILE = 20
MAX_ANNOTATION_LENGTH = 900
CONTEXT_BEFORE = 2
CONTEXT_AFTER = 7
TAIL_LINES = 20

# Common failure indicators from Flutter, Dart, Android and integration tests.
FAILURE_PATTERN = re.compile(
    r"The following"
    r"|Exception"
    r"|Error"
    r"|FAILED"
    r"|Expected"
    r"|Actual"
    r"|Which"
    r"|test description"
    r"|was thrown"
    r"|assertion"
    r"|Bad state"
    r"|Looking up"
    r"|setState"
    r"|dispose"
    r"|timeout"
    r"|Failed to"
    r"|Uncaught"
    r"|Stack trace"
    r"|NoSuchMethod"
    r"|Null check operator"
    r"|LateInitializationError"
    r"|SocketException"
    r"|PlatformException"
    r"|MissingPluginException"
    r"|Gradle task"
    r"|BUILD FAILED"
    r"|ProcessException",
    re.IGNORECASE,
)

# Remove common ANSI terminal escape sequences.
ANSI_PATTERN = re.compile(
    r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"
)

# Conservative redaction for common credential formats.
SECRET_PATTERNS = [
    (
        re.compile(
            r"(?i)\b(gh[pousr]_[A-Za-z0-9_]{20,})\b"
        ),
        "[REDACTED_GITHUB_TOKEN]",
    ),
    (
        re.compile(
            r"(?i)\bgithub_pat_[A-Za-z0-9_]{20,}\b"
        ),
        "[REDACTED_GITHUB_TOKEN]",
    ),
    (
        re.compile(
            r"(?i)\b(Bearer\s+)[A-Za-z0-9._~+/=-]{12,}",
        ),
        r"\1[REDACTED]",
    ),
    (
        re.compile(
            r"(?i)\b(api[_-]?key|access[_-]?token|"
            r"refresh[_-]?token|client[_-]?secret)"
            r"(\s*[:=]\s*)['\"]?([^\s'\",;]{8,})",
        ),
        r"\1\2[REDACTED]",
    ),
    (
        re.compile(
            r"(?i)\b(password|passwd|pwd)"
            r"(\s*[:=]\s*)['\"]?([^\s'\",;]{4,})",
        ),
        r"\1\2[REDACTED]",
    ),
]


def redact_secrets(value: str) -> str:
    """Redact common secret patterns before publishing diagnostics."""

    for pattern, replacement in SECRET_PATTERNS:
        value = pattern.sub(replacement, value)

    return value


def clean_line(value: str) -> str:
    """Remove terminal formatting and redact sensitive values."""

    value = ANSI_PATTERN.sub("", value)
    value = redact_secrets(value)

    return value.rstrip("\r\n")


def escape_annotation_message(value: str) -> str:
    """Escape GitHub Actions annotation message data."""

    return (
        value
        .replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )


def select_diagnostic_lines(
    lines: list[str],
) -> tuple[list[int], list[int]]:
    """
    Select useful failure context and actual failure indicators.

    Returns:
        selected: ordered unique line indexes for the job summary.
        failures: line indexes matching the failure pattern.
    """

    failure_indexes = [
        index
        for index, line in enumerate(lines)
        if FAILURE_PATTERN.search(line)
    ]

    selected: set[int] = set()

    for index in failure_indexes:
        start = max(0, index - CONTEXT_BEFORE)
        end = min(len(lines), index + CONTEXT_AFTER + 1)

        selected.update(range(start, end))

    # Always include the final log lines for context.
    tail_start = max(0, len(lines) - TAIL_LINES)
    selected.update(range(tail_start, len(lines)))

    ordered = sorted(selected)

    return ordered[:MAX_SUMMARY_LINES], failure_indexes


def read_report(path: Path) -> list[str] | None:
    """Read and sanitize a report without aborting the whole job."""

    if not path.exists():
        print(
            f"::warning::Diagnostic report does not exist: "
            f"{escape_annotation_message(str(path))}"
        )
        return None

    if not path.is_file():
        print(
            f"::warning::Diagnostic path is not a regular file: "
            f"{escape_annotation_message(str(path))}"
        )
        return None

    try:
        raw = path.read_text(
            encoding="utf-8",
            errors="replace",
        )
    except OSError as error:
        print(
            f"::warning::Could not read diagnostic report "
            f"{escape_annotation_message(path.name)}: "
            f"{escape_annotation_message(str(error))}"
        )
        return None

    return [clean_line(line) for line in raw.splitlines()]


def markdown_fence(lines: Iterable[str]) -> str:
    """Choose a Markdown fence longer than any fence in the log."""

    longest = 0

    for line in lines:
        for match in re.finditer(r"`+", line):
            longest = max(longest, len(match.group(0)))

    return "`" * max(3, longest + 1)


def write_summary_section(
    summary,
    file_name: str,
    selected_lines: list[str],
) -> None:
    """Append a safely fenced report section to the GitHub job summary."""

    fence = markdown_fence(selected_lines)

    summary.write(f"\n### {file_name}\n\n")
    summary.write(f"{fence}text\n")

    for line in selected_lines:
        summary.write(line + "\n")

    summary.write(f"{fence}\n")


def emit_annotations(
    report_name: str,
    lines: list[str],
    failure_indexes: list[int],
) -> int:
    """Emit annotations for actual failure indicators only."""

    if report_name == "app-integration.txt":
        source_file = "integration_test/app_test.dart"
    elif report_name == "secure-storage-integration.txt":
        source_file = "integration_test/secure_storage_test.dart"
    else:
        source_file = ""

    emitted = 0

    for index in failure_indexes[:MAX_ANNOTATIONS_PER_FILE]:
        message = lines[index].strip()

        if not message:
            continue

        message = message[:MAX_ANNOTATION_LENGTH]
        message = escape_annotation_message(message)

        if source_file:
            print(
                f"::error file={source_file},line=1::"
                f"{message}"
            )
        else:
            print(f"::error::{message}")

        emitted += 1

    remaining = len(failure_indexes) - emitted

    if remaining > 0:
        print(
            f"::warning::"
            f"{remaining} additional failure indicators "
            f"were omitted from annotations in {report_name}."
        )

    return emitted


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "Usage: python3 tool/ci_failure_report.py "
            "<report-file> [report-file ...]",
            file=sys.stderr,
        )
        return 2

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    summary = None

    if summary_path:
        try:
            summary_file = Path(summary_path)
            summary_file.parent.mkdir(
                parents=True,
                exist_ok=True,
            )
            summary = summary_file.open(
                "a",
                encoding="utf-8",
            )
        except OSError as error:
            print(
                f"::warning::Could not open GitHub job summary: {error}"
            )

    total_reports = 0
    total_failures = 0
    total_annotations = 0
    missing_reports = 0

    try:
        if summary:
            summary.write("\n## Failure diagnostics\n")

        for name in sys.argv[1:]:
            path = Path(name)
            lines = read_report(path)

            if lines is None:
                missing_reports += 1
                continue

            total_reports += 1

            selected_indexes, failure_indexes = (
                select_diagnostic_lines(lines)
            )

            selected_lines = [
                lines[index]
                for index in selected_indexes
            ]

            total_failures += len(failure_indexes)

            if summary:
                write_summary_section(
                    summary,
                    path.name,
                    selected_lines,
                )

            total_annotations += emit_annotations(
                path.name,
                lines,
                failure_indexes,
            )

            print(
                f"::notice::Processed {path.name}: "
                f"{len(failure_indexes)} failure indicators, "
                f"{len(selected_lines)} summary lines."
            )

        if summary:
            summary.write("\n### Diagnostic summary\n\n")
            summary.write(f"- Reports processed: {total_reports}\n")
            summary.write(f"- Missing or unreadable reports: {missing_reports}\n")
            summary.write(f"- Failure indicators: {total_failures}\n")
            summary.write(f"- GitHub annotations: {total_annotations}\n")

            if total_reports == 0:
                summary.write(
                    "\nNo readable diagnostic reports were available.\n"
                )

    finally:
        if summary:
            summary.close()

    if total_reports == 0:
        print(
            "::notice::No readable diagnostic reports were processed."
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
