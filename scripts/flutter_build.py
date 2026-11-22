
#!/usr/bin/env python3
"""Run Flutter Android builds with redacted, uploadable diagnostics."""

from __future__ import annotations

import os
import re
import signal
import subprocess
import sys

from pathlib import Path
from typing import TextIO


REPORT_DIRECTORY = Path("build/reports/android")

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

SUPPORTED_TARGETS = {
    "apk",
    "appbundle",
}

ERROR_PATTERN = re.compile(
    r"^\s*(?:"
    r"e:|"
    r"error:|"
    r"FAILURE:|"
    r"What went wrong|"
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

PRIVATE_KEY_PATTERN = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----"
)

MAX_ANNOTATIONS = 30
MAX_ANNOTATION_LENGTH = 900


def load_secrets() -> list[str]:
    """Load known sensitive environment values without printing them."""

    values = []

    for name in SECRET_ENVIRONMENT_VARIABLES:
        value = os.environ.get(name, "")

        # Very short values can cause excessive false-positive redaction.
        # Known credentials are expected to be longer than this threshold.
        if value and len(value) >= 4:
            values.append(value)

    return sorted(set(values), key=len, reverse=True)


SECRETS = load_secrets()


def redact(line: str) -> str:
    """Redact known secrets and common credential patterns."""

    for secret in SECRETS:
        line = line.replace(secret, "[REDACTED]")

    line = BEARER_PATTERN.sub(
        "Bearer [REDACTED]",
        line,
    )

    line = CREDENTIAL_PATTERN.sub(
        lambda match: match.group(1) + "[REDACTED]",
        line,
    )

    if PRIVATE_KEY_PATTERN.search(line):
        return "[REDACTED: PRIVATE KEY CONTENT]"

    return line


def github_escape_message(value: str) -> str:
    """Escape a message used in a GitHub Actions workflow command."""

    return (
        value
        .replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )


def validate_arguments(args: list[str]) -> str:
    """Validate the Flutter build target."""

    if not args:
        raise ValueError(
            "Missing Flutter build target. Use apk or appbundle."
        )

    target = args[0].strip().lower()

    if target not in SUPPORTED_TARGETS:
        raise ValueError(
            "Unsupported build target. Supported targets: apk, appbundle."
        )

    return target


def build_label(target: str, args: list[str]) -> str:
    """Create a predictable report filename matching the requested ABI."""

    if "--split-per-abi" in args:
        return f"{target}-split"

    platform = None
    for index, argument in enumerate(args):
        if argument == "--target-platform" and index + 1 < len(args):
            platform = args[index + 1]
            break
        if argument.startswith("--target-platform="):
            platform = argument.split("=", 1)[1]
            break

    if platform:
        suffix = platform.replace("android-", "").replace("android_", "")
        return f"{target}-{suffix}"

    if target == "apk":
        return "apk-universal"

    return "appbundle"


def prepare_report_directory() -> None:
    try:
        REPORT_DIRECTORY.mkdir(
            parents=True,
            exist_ok=True,
        )
    except OSError as error:
        raise RuntimeError(
            f"Could not create report directory: {error}"
        ) from error


def print_build_header(target: str, args: list[str]) -> None:
    """Print safe build metadata without exposing argument values."""

    options = []

    if "--release" in args:
        options.append("release")

    if "--debug" in args:
        options.append("debug")

    if "--profile" in args:
        options.append("profile")

    if "--split-per-abi" in args:
        options.append("split-per-abi")

    if "--obfuscate" in args:
        options.append("obfuscate")

    description = ", ".join(options) if options else "default options"

    print(
        f"Running Flutter Android build: {target} ({description})",
        flush=True,
    )


def write_log_line(output: TextIO, line: str) -> None:
    output.write(line + "\n")
    output.flush()


def terminate_process(process: subprocess.Popen[str]) -> None:
    """Stop a running child process and wait for it."""

    if process.poll() is not None:
        return

    try:
        process.terminate()
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    except OSError:
        try:
            process.kill()
            process.wait()
        except OSError:
            pass


def run_build(
    args: list[str],
    output: TextIO,
) -> int:
    """Run Flutter and stream redacted output to console and report."""

    command = [
        "flutter",
        "build",
        *args,
    ]

    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
    except FileNotFoundError as error:
        raise RuntimeError(
            "Flutter executable was not found. "
            "Install Flutter or add it to PATH."
        ) from error
    except OSError as error:
        raise RuntimeError(
            f"Could not start Flutter build: {error}"
        ) from error

    if process.stdout is None:
        terminate_process(process)
        raise RuntimeError(
            "Could not capture Flutter build output."
        )

    try:
        for raw_line in process.stdout:
            line = redact(raw_line.rstrip("\r\n"))

            print(line, flush=True)
            write_log_line(output, line)

        return process.wait()

    except KeyboardInterrupt:
        terminate_process(process)
        raise

    except BaseException:
        terminate_process(process)
        raise

    finally:
        process.stdout.close()


def emit_error_annotations(log_path: Path) -> int:
    """Emit a limited number of safely escaped GitHub error annotations."""

    count = 0

    try:
        with log_path.open(
            "r",
            encoding="utf-8",
            errors="replace",
        ) as report:
            for line in report:
                line = line.rstrip("\r\n")

                if not ERROR_PATTERN.search(line):
                    continue

                if count >= MAX_ANNOTATIONS:
                    break

                message = line[:MAX_ANNOTATION_LENGTH]

                print(
                    "::error::" + github_escape_message(message),
                    flush=True,
                )

                count += 1

    except OSError as error:
        print(
            "::warning::Could not read build report: "
            + github_escape_message(str(error)),
            flush=True,
        )

    if count == MAX_ANNOTATIONS:
        print(
            "::warning::Additional build errors were omitted from annotations. "
            "See the uploaded build report.",
            flush=True,
        )

    return count


def main() -> int:
    args = sys.argv[1:]

    try:
        target = validate_arguments(args)
        prepare_report_directory()

        label = build_label(target, args)
        log_path = REPORT_DIRECTORY / f"build-{label}.txt"

        print_build_header(target, args)

        with log_path.open(
            "w",
            encoding="utf-8",
            newline="\n",
        ) as output:
            result = run_build(args, output)

        print(
            f"Build report saved: {log_path.as_posix()}",
            flush=True,
        )

        if result != 0:
            annotation_count = emit_error_annotations(log_path)

            print(
                f"Flutter build failed with exit code {result}. "
                f"Annotations emitted: {annotation_count}.",
                file=sys.stderr,
                flush=True,
            )

            return result if 0 < result < 256 else 1

        print(
            "Flutter Android build completed successfully.",
            flush=True,
        )

        return 0

    except KeyboardInterrupt:
        print(
            "Build interrupted by user.",
            file=sys.stderr,
            flush=True,
        )
        return 130

    except (ValueError, RuntimeError, OSError) as error:
        message = redact(str(error))

        print(
            "::error::" + github_escape_message(message),
            file=sys.stderr,
            flush=True,
        )

        return 1


if __name__ == "__main__":
    raise SystemExit(main())
