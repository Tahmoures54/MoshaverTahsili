#!/usr/bin/env python3
"""Run Flutter Android builds with redacted, uploadable diagnostics.

Usage:
    python3 tool/build_android.py apk --release
    python3 tool/build_android.py apk --release --split-per-abi
    python3 tool/build_android.py appbundle --release

Security:
    Redaction is best-effort, not a guarantee that logs contain no secrets.
    Use a trusted Flutter installation and workspace.
    Review reports before sharing them outside your trusted CI environment.

Exit codes:
    0: Build succeeded.
    1: Build or wrapper failed.
    2: Invalid arguments.
    124: Build timed out.
    130: Interrupted by SIGINT.
    143: Interrupted by SIGTERM.
"""

from __future__ import annotations

import os
import queue
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time

from pathlib import Path
from typing import TextIO


REPORT_DIRECTORY = Path("build/reports/android")

BUILD_TIMEOUT_SECONDS = 60 * 60
TERMINATION_GRACE_SECONDS = 10

MAX_REPORT_BYTES = 10 * 1024 * 1024
MAX_LINE_CHARACTERS = 64 * 1024
OUTPUT_QUEUE_SIZE = 64

MAX_ANNOTATIONS = 30
MAX_ANNOTATION_LENGTH = 900

SUPPORTED_TARGETS = {"apk", "appbundle"}

SECRET_ENVIRONMENT_VARIABLES = (
    "AI_API_KEY",
    "DEEPSEEK_API_KEY",
    "AI_API_ENDPOINT",
    "DEEPSEEK_API_ENDPOINT",
    "AI_MODEL",
    "DEEPSEEK_MODEL",
    "BAZAAR_RSA_PUBLIC_KEY",
    "RELEASE_KEYSTORE_BASE64",
    "RELEASE_KEYSTORE_PASSWORD",
    "RELEASE_KEY_ALIAS",
    "RELEASE_KEY_PASSWORD",
    "EXPECTED_RELEASE_CERT_SHA256",
)

ERROR_PATTERN = re.compile(
    r"^\s*(?:"
    r"e:|"
    r"error:|"
    r"FAILURE:|"
    r"\*?\s*What went wrong|"
    r"Could not|"
    r"Execution failed|"
    r"Gradle task .* failed|"
    r"Exception:|"
    r"BUILD FAILED"
    r")",
    re.IGNORECASE,
)

BEARER_PATTERN = re.compile(
    r"(?i)\bBearer\s+[A-Za-z0-9._~+/\-=]+"
)

CREDENTIAL_PATTERN = re.compile(
    r"""(?ix)
    (
        ["']?
        (?:api[_-]?key|access[_-]?token|refresh[_-]?token|
           client[_-]?secret|password|passwd)
        ["']?
        \s*[:=]\s*
    )
    (
        ["'][^"']*["']
        |
        [^\s,;]+
    )
    """
)

ANSI_PATTERN = re.compile(
    r"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"
    r"|\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"
)

CONTROL_PATTERN = re.compile(
    r"[\x00-\x08\x0B-\x1F\x7F]"
)

BIDI_PATTERN = re.compile(
    r"[\u202A-\u202E\u2066-\u2069]"
)

PRIVATE_KEY_BEGIN_PATTERN = re.compile(
    r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"
)

PRIVATE_KEY_END_PATTERN = re.compile(
    r"-----END (?:[A-Z0-9]+ )*PRIVATE KEY-----"
)


class BuildInterrupted(Exception):
    """A termination signal interrupted the build."""

    def __init__(self, signum: int) -> None:
        super().__init__("Build interrupted.")
        self.signum = signum


class BuildTimedOut(Exception):
    """The build exceeded its time limit."""


def sanitize_text(value: str) -> str:
    """Remove terminal escapes, control characters, and bidi controls."""

    value = ANSI_PATTERN.sub("", value)
    value = CONTROL_PATTERN.sub("", value)
    return BIDI_PATTERN.sub("", value)


def load_secrets() -> list[str]:
    """Load known secrets, including short and multiline fragments."""

    values: set[str] = set()

    for name in SECRET_ENVIRONMENT_VARIABLES:
        raw = os.environ.get(name, "")

        if not raw:
            continue

        for fragment in raw.splitlines():
            fragment = sanitize_text(fragment)

            if fragment:
                values.add(fragment)

            stripped = fragment.strip()

            if stripped:
                values.add(stripped)

    return sorted(values, key=len, reverse=True)


class Redactor:
    """Redact known values and complete multiline private-key blocks."""

    def __init__(self) -> None:
        self.secrets = load_secrets()
        self.in_private_key = False

    def redact(self, raw_line: str) -> str:
        line = sanitize_text(raw_line)

        begins_key = bool(PRIVATE_KEY_BEGIN_PATTERN.search(line))
        ends_key = bool(PRIVATE_KEY_END_PATTERN.search(line))

        # Check boundaries before replacing known secret fragments.
        if self.in_private_key or begins_key:
            self.in_private_key = not ends_key
            return "[REDACTED: PRIVATE KEY CONTENT]"

        for secret in self.secrets:
            line = line.replace(secret, "[REDACTED]")

        line = BEARER_PATTERN.sub(
            "Bearer [REDACTED]",
            line,
        )

        return CREDENTIAL_PATTERN.sub(
            lambda match: match.group(1) + "[REDACTED]",
            line,
        )


def github_escape_message(value: str) -> str:
    """Escape message data in a GitHub Actions workflow command."""

    return (
        value
        .replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )


def emit_annotation(kind: str, message: str) -> None:
    """Only call with wrapper-generated or already-redacted messages."""

    stream = sys.stderr if kind == "error" else sys.stdout

    print(
        f"::{kind}::{github_escape_message(message)}",
        file=stream,
        flush=True,
    )


def validate_arguments(args: list[str]) -> str:
    if not args:
        raise ValueError(
            "Missing build target. Use apk or appbundle."
        )

    target = args[0].strip().lower()

    if target not in SUPPORTED_TARGETS:
        raise ValueError(
            "Unsupported target. Supported targets: apk, appbundle."
        )

    args[0] = target
    return target


def build_label(target: str, args: list[str]) -> str:
    if target == "apk":
        variant = (
            "split"
            if "--split-per-abi" in args
            else "universal"
        )
    else:
        variant = "bundle"

    if "--debug" in args:
        mode = "debug"
    elif "--profile" in args:
        mode = "profile"
    elif "--release" in args:
        mode = "release"
    else:
        mode = "default"

    return f"{target}-{variant}-{mode}"


def create_report(label: str) -> tuple[Path, TextIO]:
    """Create a unique report without overwriting previous builds."""

    try:
        REPORT_DIRECTORY.mkdir(parents=True, exist_ok=True)

        descriptor, filename = tempfile.mkstemp(
            prefix=f"build-{label}-",
            suffix=".txt",
            dir=REPORT_DIRECTORY,
        )

    except OSError:
        raise RuntimeError(
            "Could not create the Android build report."
        ) from None

    try:
        output = os.fdopen(
            descriptor,
            "w",
            encoding="utf-8",
            newline="\n",
        )
    except BaseException:
        os.close(descriptor)
        try:
            Path(filename).unlink()
        except OSError:
            pass
        raise

    return Path(filename), output


def print_build_header(target: str, args: list[str]) -> None:
    """Print option names only, never arbitrary argument values."""

    options = [
        option.removeprefix("--")
        for option in (
            "--release",
            "--debug",
            "--profile",
            "--split-per-abi",
            "--obfuscate",
        )
        if option in args
    ]

    description = ", ".join(options) or "default options"

    print(
        f"Running Flutter Android build: {target} ({description})",
        flush=True,
    )


class ReportWriter:
    """Bound the volume of both stored and echoed subprocess output."""

    LIMIT_MESSAGE = (
        "[OUTPUT OMITTED: diagnostic size limit reached; "
        "the build continues]"
    )

    def __init__(self, output: TextIO) -> None:
        self.output = output
        self.bytes_written = 0
        self.truncated = False
        self.reserve = len(
            (self.LIMIT_MESSAGE + "\n").encode("utf-8")
        )

    def _write(self, line: str) -> None:
        self.output.write(line + "\n")
        self.output.flush()

        # Prevent child output from beginning a workflow command.
        print(f"[flutter] {line}", flush=True)

    def write(self, line: str) -> None:
        if self.truncated:
            return

        size = len((line + "\n").encode("utf-8"))

        if (
            self.bytes_written + size
            > MAX_REPORT_BYTES - self.reserve
        ):
            self.truncated = True
            self._write(self.LIMIT_MESSAGE)
            return

        self._write(line)
        self.bytes_written += size


def terminate_process(process: subprocess.Popen[str]) -> None:
    """Terminate the process group on POSIX; direct child elsewhere."""

    if os.name == "posix":
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except OSError:
            if process.poll() is None:
                try:
                    process.terminate()
                except OSError:
                    pass

        deadline = time.monotonic() + TERMINATION_GRACE_SECONDS

        while time.monotonic() < deadline:
            try:
                os.killpg(process.pid, 0)
            except ProcessLookupError:
                break
            except OSError:
                break

            # Reap the direct child if it has exited.
            process.poll()
            time.sleep(0.1)

        try:
            os.killpg(process.pid, signal.SIGKILL)
        except OSError:
            pass

    elif process.poll() is None:
        try:
            process.terminate()
            process.wait(timeout=TERMINATION_GRACE_SECONDS)
        except subprocess.TimeoutExpired:
            try:
                process.kill()
            except OSError:
                pass
        except OSError:
            pass

    try:
        process.wait(timeout=TERMINATION_GRACE_SECONDS)
    except (OSError, subprocess.TimeoutExpired):
        pass


def read_output(
    stream: TextIO,
    events: queue.Queue[tuple[str, str]],
) -> None:
    """Read bounded lines on a daemon thread.

    An oversized line causes subsequent diagnostics to be suppressed.
    This avoids exposing fragments of a secret or PEM block whose
    beginning could have been discarded.
    """

    try:
        while True:
            raw_line = stream.readline(MAX_LINE_CHARACTERS + 1)

            if not raw_line:
                break

            if len(raw_line) > MAX_LINE_CHARACTERS:
                events.put(("oversized", ""))

                # Drain this line without retaining it in memory.
                while raw_line and not raw_line.endswith("\n"):
                    raw_line = stream.readline(
                        MAX_LINE_CHARACTERS + 1
                    )

                continue

            events.put(("line", raw_line.rstrip("\r\n")))

    except Exception:
        events.put(("reader_error", ""))

    finally:
        events.put(("eof", ""))


def run_build(args: list[str], output: TextIO) -> int:
    command = ["flutter", "build", *args]

    try:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            start_new_session=(os.name == "posix"),
        )

    except FileNotFoundError:
        raise RuntimeError(
            "Flutter executable was not found. "
            "Install Flutter or add it to PATH."
        ) from None

    except OSError:
        raise RuntimeError(
            "Could not start the Flutter build."
        ) from None

    if process.stdout is None:
        terminate_process(process)
        raise RuntimeError(
            "Could not capture Flutter output."
        )

    events: queue.Queue[tuple[str, str]] = queue.Queue(
        maxsize=OUTPUT_QUEUE_SIZE
    )

    reader = threading.Thread(
        target=read_output,
        args=(process.stdout, events),
        name="flutter-output-reader",
        daemon=True,
    )

    redactor = Redactor()
    writer = ReportWriter(output)

    deadline = time.monotonic() + BUILD_TIMEOUT_SECONDS
    output_suppressed = False
    reached_eof = False
    completed = False

    try:
        reader.start()

        while True:
            remaining = deadline - time.monotonic()

            if remaining <= 0:
                raise BuildTimedOut()

            if reached_eof:
                if process.poll() is not None:
                    completed = True
                    return process.returncode

                time.sleep(min(0.1, remaining))
                continue

            try:
                event, value = events.get(
                    timeout=min(0.25, remaining)
                )
            except queue.Empty:
                continue

            if event == "eof":
                reached_eof = True

            elif event == "reader_error":
                raise RuntimeError(
                    "Could not read Flutter build output."
                )

            elif event == "oversized":
                if not output_suppressed:
                    output_suppressed = True
                    writer.write(
                        "[OUTPUT OMITTED: oversized line detected; "
                        "remaining child diagnostics are suppressed]"
                    )

            elif event == "line" and not output_suppressed:
                writer.write(redactor.redact(value))

    finally:
        if not completed:
            terminate_process(process)

        # Avoid closing a TextIO object while its reader thread
        # may still hold the underlying read lock.
        if reader.ident is not None:
            reader.join(timeout=1)

        if not reader.is_alive():
            process.stdout.close()


def emit_error_annotations(log_path: Path) -> int:
    count = 0
    omitted = False

    try:
        with log_path.open(
            "r",
            encoding="utf-8",
            errors="replace",
        ) as report:
            for raw_line in report:
                line = raw_line.rstrip("\r\n")

                if not ERROR_PATTERN.search(line):
                    continue

                if count >= MAX_ANNOTATIONS:
                    omitted = True
                    break

                emit_annotation(
                    "error",
                    line[:MAX_ANNOTATION_LENGTH],
                )
                count += 1

    except OSError:
        emit_annotation(
            "warning",
            "Could not read the build report for annotations.",
        )

    if omitted:
        emit_annotation(
            "warning",
            "Additional errors were omitted from annotations. "
            "See the build report.",
        )

    return count


def handle_signal(signum: int, _frame: object) -> None:
    raise BuildInterrupted(signum)


def main() -> int:
    args = sys.argv[1:]

    try:
        target = validate_arguments(args)
    except ValueError as error:
        emit_annotation("error", str(error))
        print(
            "Usage: python3 tool/build_android.py "
            "<apk|appbundle> [Flutter build options]",
            file=sys.stderr,
            flush=True,
        )
        return 2

    log_path: Path | None = None
    previous_handlers: dict[int, object] = {}

    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.getsignal(signum)
            signal.signal(signum, handle_signal)

        label = build_label(target, args)
        log_path, output = create_report(label)

        print_build_header(target, args)

        with output:
            result = run_build(args, output)

        if result != 0:
            annotation_count = emit_error_annotations(log_path)

            emit_annotation(
                "error",
                f"Flutter build failed with exit code {result}. "
                f"Annotations emitted: {annotation_count}.",
            )

            return result if 0 < result < 256 else 1

        print(
            "Flutter Android build completed successfully.",
            flush=True,
        )
        return 0

    except BuildTimedOut:
        emit_annotation(
            "error",
            f"Flutter build exceeded the "
            f"{BUILD_TIMEOUT_SECONDS}-second timeout.",
        )
        return 124

    except BuildInterrupted as error:
        print(
            "Build interrupted; child-process termination attempted.",
            file=sys.stderr,
            flush=True,
        )
        return 128 + error.signum

    except KeyboardInterrupt:
        print(
            "Build interrupted by user.",
            file=sys.stderr,
            flush=True,
        )
        return 130

    except RuntimeError as error:
        # RuntimeError messages above are fixed wrapper messages.
        emit_annotation("error", str(error))
        return 1

    except OSError:
        # Do not expose raw OS errors, paths, or command arguments.
        emit_annotation(
            "error",
            "An operating-system error prevented build execution "
            "or report writing.",
        )
        return 1

    finally:
        for signum, previous_handler in previous_handlers.items():
            signal.signal(signum, previous_handler)

        if log_path is not None:
            print(
                f"Build report: {log_path.as_posix()}",
                flush=True,
            )


if __name__ == "__main__":
    raise SystemExit(main())
