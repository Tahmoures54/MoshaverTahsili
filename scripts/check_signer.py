#!/usr/bin/env python3
"""Verify an APK with apksigner and enforce certificate pinning.

Requires Python 3.10 or newer and Android SDK apksigner.

Usage:
    python3 tool/verify_apk_signature.py <artifact.apk>
    python3 tool/verify_apk_signature.py <artifact.apk> \
        --apksigner /path/to/android-sdk/build-tools/35.0.0/apksigner

Environment:
    PRODUCTION_READY:
        Empty or "false": production certificate policy is not required.
        "true": require EXPECTED_RELEASE_CERT_SHA256 and reject a
                recognizable Android debug certificate.

    EXPECTED_RELEASE_CERT_SHA256:
        Optional outside production, required in production.
        When provided, the APK certificate must match it.

Exit codes:
    0: Signature verification and applicable certificate policy passed.
    1: Verification or certificate policy failed.
    2: Invalid arguments/configuration or tool execution failure.

This verifies one APK, not an AAB or a complete split-APK installation.
Use a trusted SDK installation and immutable build artifacts in CI.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys

from pathlib import Path


VERIFY_TIMEOUT_SECONDS = 120

SHA256_PATTERN = re.compile(
    r"^[ \t]*Signer #[ \t]*(?P<signer>[1-9][0-9]*)[ \t]+"
    r"certificate SHA-256 digest:[ \t]*"
    r"(?P<fingerprint>[^\r\n]+?)[ \t]*$",
    re.MULTILINE | re.IGNORECASE,
)

DN_PATTERN = re.compile(
    r"^[ \t]*Signer #[ \t]*(?P<signer>[1-9][0-9]*)[ \t]+"
    r"certificate DN:[ \t]*(?P<dn>[^\r\n]*)[ \t]*$",
    re.MULTILINE | re.IGNORECASE,
)

DEBUG_CN_PATTERN = re.compile(
    r"(?:^|,)\s*CN\s*=\s*Android Debug\s*(?:,|$)",
    re.IGNORECASE,
)


class ConfigurationError(Exception):
    """Invalid local configuration or unavailable verification tool."""


class VerificationError(Exception):
    """APK verification or certificate policy failed."""


def emit_error(message: str) -> None:
    """Messages are fixed strings; raw tool output is never echoed."""
    print(f"::error::{message}", file=sys.stderr)


def normalize_sha256(value: str) -> str:
    """Accept plain hex or 32 colon-separated hexadecimal octets."""

    value = re.sub(r"[:\s]", "", value.strip())

    if re.fullmatch(r"[0-9a-fA-F]{64}", value):
        return value.upper()

    raise ConfigurationError(
        "EXPECTED_RELEASE_CERT_SHA256 must contain a valid "
        "SHA-256 certificate fingerprint."
    )


def read_policy() -> tuple[bool, str | None]:
    raw_production = os.environ.get(
        "PRODUCTION_READY", ""
    ).strip().lower()

    # Fail closed on typos instead of silently disabling production policy.
    if raw_production not in {"", "false", "true"}:
        raise ConfigurationError(
            "PRODUCTION_READY must be empty, false, or true."
        )

    production = raw_production == "true"

    raw_expected = os.environ.get(
        "EXPECTED_RELEASE_CERT_SHA256", ""
    ).strip()

    if production and not raw_expected:
        raise ConfigurationError(
            "EXPECTED_RELEASE_CERT_SHA256 is required "
            "when PRODUCTION_READY=true."
        )

    expected = (
        normalize_sha256(raw_expected)
        if raw_expected
        else None
    )

    return production, expected


def resolve_apksigner(value: str) -> str:
    executable = shutil.which(value)

    if executable is None:
        raise ConfigurationError(
            "apksigner was not found or is not executable. "
            "Provide a trusted executable using --apksigner."
        )

    return str(Path(executable).resolve())


def verify_apk(apk: Path, executable: str) -> tuple[str, bool]:
    """Run apksigner and extract the verified single signer's certificate."""

    try:
        apk = apk.resolve(strict=True)

        if not apk.is_file() or apk.suffix.lower() != ".apk":
            raise ConfigurationError(
                "Input must be an existing APK file."
            )

        before = apk.stat()

    except OSError:
        raise ConfigurationError(
            "Could not access the APK file."
        ) from None

    environment = os.environ.copy()
    environment["LC_ALL"] = "C"
    environment["LANG"] = "C"

    try:
        completed = subprocess.run(
            [
                executable,
                "verify",
                "--verbose",
                "--print-certs",
                str(apk),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=VERIFY_TIMEOUT_SECONDS,
            check=False,
            env=environment,
        )

    except subprocess.TimeoutExpired:
        raise ConfigurationError(
            "apksigner verification timed out."
        ) from None

    except OSError:
        raise ConfigurationError(
            "Could not execute apksigner."
        ) from None

    try:
        after = apk.stat()
    except OSError:
        raise VerificationError(
            "APK became unavailable during verification."
        ) from None

    # Best-effort mutation detection; not a substitute for immutable inputs.
    before_signature = (
        before.st_dev,
        before.st_ino,
        before.st_size,
        before.st_mtime_ns,
        before.st_ctime_ns,
    )
    after_signature = (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
        after.st_ctime_ns,
    )

    if before_signature != after_signature:
        raise VerificationError(
            "APK changed during signature verification."
        )

    # Verification success comes from the process exit status,
    # never from a success-looking substring.
    if completed.returncode != 0:
        raise VerificationError(
            "apksigner rejected the APK signature. "
            "Run the trusted tool directly for detailed diagnostics."
        )

    try:
        stdout = completed.stdout.decode("utf-8", errors="strict")
        stderr = completed.stderr.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        raise VerificationError(
            "apksigner returned unsupported output encoding."
        ) from None

    # Android SDK builds may write certificate details to either stream.
    # Parse both while retaining the process exit code as the trust signal.
    output = f"{stdout}\n{stderr}"
    output = output.replace("\r\n", "\n").replace("\r", "\n")

    # Parse only normalized hexadecimal fingerprints. Ignore unrelated
    # certificate digest lines (for example SHA-1 and MD5).
    fingerprints: list[tuple[str, str]] = []
    for match in SHA256_PATTERN.finditer(output):
        try:
            normalized = normalize_sha256(match.group("fingerprint"))
        except ConfigurationError:
            continue
        fingerprints.append((match.group("signer"), normalized))

    # Repeated identical records are harmless; different signers or
    # fingerprints require a separate explicit multi-signer policy.
    unique_fingerprints = set(fingerprints)
    if len(unique_fingerprints) != 1:
        raise VerificationError(
            "Expected one unique signer certificate SHA-256 record; "
            f"found {len(unique_fingerprints)}."
        )

    signer, fingerprint = next(iter(unique_fingerprints))
    if signer != "1":
        raise VerificationError(
            "Unexpected signer identifier in apksigner output."
        )

    distinguished_names = list(DN_PATTERN.finditer(output))
    unique_names = {
        (match.group("signer"), match.group("dn"))
        for match in distinguished_names
    }
    if len(unique_names) != 1:
        raise VerificationError(
            "Expected one unique signer certificate DN; "
            f"found {len(unique_names)}."
        )

    signer_name, distinguished_name = next(iter(unique_names))
    if signer_name != "1":
        raise VerificationError(
            "Unexpected signer identifier in certificate DN."
        )

    # A DN marker is only a heuristic; pinning is the identity check.
    is_debug = bool(DEBUG_CN_PATTERN.search(distinguished_name))

    return fingerprint, is_debug


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Verify an APK signature and apply "
            "an optional release certificate pin."
        )
    )
    parser.add_argument("apk", type=Path)
    parser.add_argument(
        "--apksigner",
        default="apksigner",
        help="Trusted apksigner executable path or command name.",
    )

    arguments = parser.parse_args()

    try:
        production, expected = read_policy()
        executable = resolve_apksigner(arguments.apksigner)

        fingerprint, is_debug = verify_apk(
            arguments.apk,
            executable,
        )

        if production and is_debug:
            raise VerificationError(
                "Production policy rejects the recognizable "
                "Android debug certificate."
            )

        if expected is not None and fingerprint != expected:
            raise VerificationError(
                "APK signer certificate does not match "
                "EXPECTED_RELEASE_CERT_SHA256."
            )

    except ConfigurationError as error:
        emit_error(str(error))
        return 2

    except VerificationError as error:
        emit_error(str(error))
        return 1

    print("APK signature verification: PASSED")
    print(f"Certificate SHA-256: {fingerprint}")
    print(
        "Recognizable Android debug certificate: "
        f"{str(is_debug).lower()}"
    )
    print(
        "Certificate pin check: "
        + ("PASSED" if expected is not None else "NOT CONFIGURED")
    )
    print(
        "Production certificate policy: "
        + ("PASSED" if production else "NOT REQUIRED")
    )
    print(
        "Signature verification does not prove installation, "
        "runtime behavior, store acceptance, or payment functionality."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
