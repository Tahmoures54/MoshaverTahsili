#!/usr/bin/env python3
"""Publish CI failure diagnostics as GitHub annotations and a job summary.

Requires Python 3.10 or newer.

Exit codes:
    0: Diagnostic reporting completed, including recoverable I/O failures.
    2: Invalid command-line arguments.

This script does not determine whether tests or builds succeeded.
Preserve and check the original command's exit status separately.
"""

from __future__ import annotations

import os
import re
import stat
import sys
from pathlib import Path
from typing import Iterable, TextIO


# Limits apply separately to each report unless otherwise noted.
MAX_SUMMARY_LINES = 160
MAX_SUMMARY_LINE_LENGTH = 2000
MAX_SUMMARY_SECTION_BYTES = 128 * 1024

MAX_ANNOTATIONS_PER_FILE = 20
MAX_ANNOTATION_LENGTH = 900

# For large reports, read only the end of the file.
MAX_REPORT_BYTES = 8 * 1024 * 1024

# Total permitted size of the GitHub step summary, including existing content.
MAX_SUMMARY_BYTES = 900 * 1024

CONTEXT_BEFORE = 2
CONTEXT_AFTER = 7
TAIL_LINES = 20


# These patterns identify potential failures, not definitive test results.
# Avoid broad terms such as "Error", "Expected" or "Gradle task" alone.
FAILURE_PATTERN = re.compile(
    r"\bThe following\b.*\b(?:exception|assertion)\b"
    r"|\b[A-Za-z_][A-Za-z0-9_]*(?:Exception|Error)\b"
    r"|\bException\b"
    r"|\bError\s*:"
    r"|\bFAILED\b"
    r"|\bFAILURE\s*:"
    r"|\bBUILD FAILED\b"
    r"|\bExpected\s*:"
    r"|\bActual\s*:"
    r"|\bWhich\s*:"
    r"|\btest description\s*:"
    r"|\bwas thrown\b"
    r"|\bassertion\b"
    r"|\bBad state\b"
    r"|\bLooking up a deactivated widget\b"
    r"|\bsetState\b.*\b(?:after dispose|during build)\b"
    r"|\btimed out\b"
    r"|\btimeout\b"
    r"|\bFailed to\b"
    r"|\bUncaught\b"
    r"|\bStack trace\b"
    r"|\bNull check operator\b"
    r"|\bExecution failed for task\b"
    r"|\bSome tests failed\b"
    r"|\bTest failed\b",
    re.IGNORECASE,
)


# Remove common ANSI CSI sequences and OSC terminal commands.
ANSI_PATTERN = re.compile(
    r"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"
    r"|\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"
)

# Preserve tabs and line breaks; remove other terminal control characters.
CONTROL_PATTERN = re.compile(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]")

# Remove bidirectional display controls from published logs.
BIDI_PATTERN = re.compile(r"[\u202A-\u202E\u2066-\u2069]")


SECRET_KEY_PATTERN = (
    r"api[_-]?key"
    r"|access[_-]?token"
    r"|refresh[_-]?token"
    r"|client[_-]?secret"
    r"|authorization"
    r"|password"
    r"|passwd"
    r"|pwd"
)

SECRET_ASSIGNMENT_PATTERN = re.compile(
    rf"""(?ix)
    (?P<prefix>
        ["']?
        \b(?:{SECRET_KEY_PATTERN})\b
        ["']?
        \s*[:=]\s*
    )
    (?:
        "[^"\r\n]*"
        |
        '[^'\r\n]*'
        |
        [^\s'",;}}\]&]+
    )
    """
)

SECRET_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (
        re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"),
        "[REDACTED_GITHUB_TOKEN]",
    ),
    (
        re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
        "[REDACTED_GITHUB_TOKEN]",
    ),
    (
        re.compile(
            r"(?i)\b(Bearer\s+)[A-Za-z0-9._~+/=-]+"
        ),
        r"\1[REDACTED]",
    ),
    (
        re.compile(
            r"(?i)\b(Basic\s+)[A-Za-z0-9+/=]{8,}"
        ),
        r"\1[REDACTED]",
    ),
    (
        # Credentials embedded in URLs.
        re.compile(
            r"(?i)(\b[a-z][a-z0-9+.-]*://)"
            r"[^/\s:@]+:[^/\s@]+@"
        ),
        r"\1[REDACTED]@",
    ),
]

PRIVATE_KEY_PATTERN = re.compile(
    r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"
    r".*?"
    r"(?:-----END (?:[A-Z0-9]+ )*PRIVATE KEY-----|\Z)",
    re.DOTALL,
)


SOURCE_FILES = {
    "app-integration.txt": "integration_test/app_test.dart",
    "secure-storage-integration.txt": (
        "integration_test/secure_storage_test.dart"
    ),
}


def redact_secrets(value: str) -> str:
    """Best-effort redaction; this is not a complete secret scanner."""

    value = PRIVATE_KEY_PATTERN.sub(
        "[REDACTED_PRIVATE_KEY]",
        value,
    )

    for pattern, replacement in SECRET_PATTERNS:
        value = pattern.sub(replacement, value)

    return SECRET_ASSIGNMENT_PATTERN.sub(
        lambda match: (
            match.group("prefix") + "[REDACTED]"
        ),
        value,
    )


def sanitize_text(value: str) -> str:
    """Remove terminal formatting and redact common sensitive values."""

    value = ANSI_PATTERN.sub("", value)
    value = CONTROL_PATTERN.sub("", value)
    value = BIDI_PATTERN.sub("", value)

    return redact_secrets(value)


def clean_line(value: str) -> str:
    return sanitize_text(value).rstrip("\r\n")


def escape_annotation_message(value: str) -> str:
    """Escape GitHub workflow command message data."""

    return (
        value.replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )


def escape_annotation_property(value: str) -> str:
    """Escape GitHub workflow command properties."""

    return (
        escape_annotation_message(value)
        .replace(":", "%3A")
        .replace(",", "%2C")
    )


def emit_workflow_message(level: str, message: str) -> None:
    """Publish a sanitized, escaped workflow command."""

    if level not in {"notice", "warning", "error"}:
        raise ValueError(f"Unsupported annotation level: {level}")

    safe_message = escape_annotation_message(
        sanitize_text(message)
    )

    print(f"::{level}::{safe_message}")


def truncate_text(value: str, limit: int) -> str:
    if len(value) <= limit:
        return value

    suffix = " … [truncated]"

    if limit <= len(suffix):
        return suffix[:limit]

    return value[: limit - len(suffix)] + suffix


def read_report(path: Path) -> list[str] | None:
    """Read a bounded report, retaining its tail when it is too large."""

    try:
        with path.open("rb") as report:
            file_info = os.fstat(report.fileno())

            if not stat.S_ISREG(file_info.st_mode):
                emit_workflow_message(
                    "warning",
                    f"Diagnostic path is not a regular file: {path}",
                )
                return None

            truncated = file_info.st_size > MAX_REPORT_BYTES

            if truncated:
                report.seek(file_info.st_size - MAX_REPORT_BYTES)

            # Bound memory use even if the report grows while being read.
            raw = report.read(MAX_REPORT_BYTES)

    except FileNotFoundError:
        emit_workflow_message(
            "warning",
            f"Diagnostic report does not exist: {path}",
        )
        return None
    except (OSError, ValueError) as error:
        emit_workflow_message(
            "warning",
            f"Could not read diagnostic report {path}: {error}",
        )
        return None

    if truncated:
        # The bounded tail can begin halfway through a UTF-8 character
        # or log line. Discard that initial incomplete line.
        newline_index = raw.find(b"\n")

        if newline_index >= 0:
            raw = raw[newline_index + 1 :]
        else:
            # A single extremely long line: keep the bounded data.
            pass

        emit_workflow_message(
            "warning",
            f"Report {path.name} exceeds {MAX_REPORT_BYTES} bytes. "
            "Only its bounded tail was processed; earlier diagnostics "
            "may have been omitted.",
        )

    text = raw.decode("utf-8-sig", errors="replace")

    # Sanitize the complete text first so multiline private keys
    # can be redacted before splitting it into lines.
    text = sanitize_text(text)

    return [
        line.rstrip("\r\n")
        for line in text.splitlines()
    ]


def select_diagnostic_lines(
    lines: list[str],
) -> tuple[list[int], list[int]]:
    """Select failure context while preserving the final log lines."""

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

    tail_start = max(0, len(lines) - TAIL_LINES)
    tail_indexes = list(range(tail_start, len(lines)))

    context_indexes = sorted(
        index
        for index in selected
        if index < tail_start
    )

    context_budget = max(
        0,
        MAX_SUMMARY_LINES - len(tail_indexes),
    )

    return (
        context_indexes[:context_budget] + tail_indexes,
        failure_indexes,
    )


def markdown_fence(lines: Iterable[str]) -> str:
    """Choose a fence longer than any backtick sequence in its content."""

    longest = 0

    for line in lines:
        for match in re.finditer(r"`+", line):
            longest = max(longest, len(match.group(0)))

    return "`" * max(3, longest + 1)


def fenced_block(lines: list[str]) -> str:
    fence = markdown_fence(lines)

    return (
        f"{fence}text\n"
        + "\n".join(lines)
        + f"\n{fence}\n"
    )


def build_summary_section(
    report_name: str,
    lines: list[str],
    selected_indexes: list[int],
) -> str:
    """Build a bounded section with the file name inside a safe fence."""

    safe_name = truncate_text(
        clean_line(report_name).replace("\r", " ").replace("\n", " "),
        300,
    )

    selected_lines: list[str] = []
    previous_index: int | None = None

    for index in selected_indexes:
        if previous_index is not None and index > previous_index + 1:
            selected_lines.append("[... omitted log lines ...]")

        selected_lines.append(
            truncate_text(
                lines[index],
                MAX_SUMMARY_LINE_LENGTH,
            )
        )

        previous_index = index

    if not lines:
        selected_lines.append("[Report is empty]")

    prefix = "\n### Diagnostic report\n\n"
    name_lines = [f"Report: {safe_name}", ""]

    section = prefix + fenced_block(name_lines + selected_lines)

    if len(section.encode("utf-8")) <= MAX_SUMMARY_SECTION_BYTES:
        return section

    # Preserve the tail when reducing the section further.
    omitted_notice = "[Earlier summary content omitted due to size limit]"

    while selected_lines:
        selected_lines.pop(0)

        section = prefix + fenced_block(
            name_lines + [omitted_notice] + selected_lines
        )

        if len(section.encode("utf-8")) <= MAX_SUMMARY_SECTION_BYTES:
            return section

    return prefix + fenced_block(name_lines + [omitted_notice])


class SummaryWriter:
    """Append complete Markdown blocks without aborting annotation output."""

    def __init__(self, destination: str | None) -> None:
        self.stream: TextIO | None = None
        self.bytes_written = 0
        self.limit_warning_emitted = False

        if not destination:
            return

        try:
            path = Path(destination)
            path.parent.mkdir(parents=True, exist_ok=True)

            self.stream = path.open(
                "a",
                encoding="utf-8",
                newline="\n",
            )

            self.bytes_written = os.fstat(
                self.stream.fileno()
            ).st_size

        except (OSError, ValueError) as error:
            self.close()

            emit_workflow_message(
                "warning",
                f"Could not open GitHub job summary: {error}",
            )

    def write(self, block: str) -> bool:
        if self.stream is None:
            return False

        block_size = len(block.encode("utf-8"))

        if self.bytes_written + block_size > MAX_SUMMARY_BYTES:
            if not self.limit_warning_emitted:
                emit_workflow_message(
                    "warning",
                    "GitHub job summary size limit reached. "
                    "Some summary sections were omitted; "
                    "annotations will continue.",
                )
                self.limit_warning_emitted = True

            return False

        try:
            self.stream.write(block)
            self.stream.flush()
            self.bytes_written += block_size
            return True

        except (OSError, ValueError) as error:
            emit_workflow_message(
                "warning",
                f"Could not write GitHub job summary: {error}. "
                "Annotations will continue.",
            )
            self.close()
            return False

    def close(self) -> None:
        stream = self.stream
        self.stream = None

        if stream is None:
            return

        try:
            stream.close()
        except (OSError, ValueError) as error:
            emit_workflow_message(
                "warning",
                f"Could not close GitHub job summary: {error}",
            )


def emit_annotations(
    report_name: str,
    lines: list[str],
    failure_indexes: list[int],
) -> int:
    """Emit bounded annotations for potential failure indicators."""

    source_file = SOURCE_FILES.get(report_name)
    emitted = 0

    for index in failure_indexes:
        if emitted >= MAX_ANNOTATIONS_PER_FILE:
            break

        message = lines[index].strip()

        if not message:
            continue

        # Add report context before escaping the complete message.
        message = truncate_text(
            clean_line(f"[{report_name}] {message}"),
            MAX_ANNOTATION_LENGTH,
        )

        safe_message = escape_annotation_message(message)

        if source_file:
            # This maps the report to its test file, not a known
            # source-code line. Do not invent a line number.
            print(
                "::error "
                f"file={escape_annotation_property(source_file)}"
                f"::{safe_message}"
            )
        else:
            print(f"::error::{safe_message}")

        emitted += 1

    remaining = len(failure_indexes) - emitted

    if remaining > 0:
        emit_workflow_message(
            "warning",
            f"{remaining} additional potential failure indicators "
            f"were omitted from annotations in {report_name}.",
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

    summary = SummaryWriter(
        os.environ.get("GITHUB_STEP_SUMMARY")
    )

    total_reports = 0
    total_failures = 0
    total_annotations = 0
    unavailable_reports = 0

    try:
        summary.write(
            "\n## Failure diagnostics\n\n"
            "Failure indicators are heuristic matches, "
            "not authoritative test or build results. "
            "For oversized reports, only a bounded tail is processed.\n"
        )

        for name in sys.argv[1:]:
            path = Path(name)
            lines = read_report(path)

            if lines is None:
                unavailable_reports += 1
                continue

            total_reports += 1

            selected_indexes, failure_indexes = (
                select_diagnostic_lines(lines)
            )

            total_failures += len(failure_indexes)

            summary.write(
                build_summary_section(
                    path.name,
                    lines,
                    selected_indexes,
                )
            )

            total_annotations += emit_annotations(
                path.name,
                lines,
                failure_indexes,
            )

            emit_workflow_message(
                "notice",
                f"Processed {path.name}: "
                f"{len(failure_indexes)} potential failure indicators, "
                f"{len(selected_indexes)} selected log lines.",
            )

        final_summary = (
            "\n### Diagnostic summary\n\n"
            f"- Reports processed: {total_reports}\n"
            f"- Missing or unreadable reports: {unavailable_reports}\n"
            f"- Potential failure indicators: {total_failures}\n"
            f"- Error annotations emitted: {total_annotations}\n"
            "\nSecret redaction is best-effort. "
            "Do not intentionally log credentials or private data.\n"
        )

        if total_reports == 0:
            final_summary += (
                "\nNo readable diagnostic reports were available.\n"
            )

        summary.write(final_summary)

    finally:
        summary.close()

    if total_reports == 0:
        emit_workflow_message(
            "notice",
            "No readable diagnostic reports were processed.",
        )

    # Reporting success is independent of the original CI command result.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
