
#!/usr/bin/env python3
"""Verify APK signature and enforce release certificate policy."""

from __future__ import annotations

import os
import re
import sys

from pathlib import Path


REPORT_ARGUMENTS = 1

DEBUG_CERTIFICATE_MARKER = "CN=Android Debug"

SHA256_PATTERN = re.compile(
    r"(?im)^\s*Signer\s+#\d+\s+certificate\s+SHA-256\s+digest:\s*"
    r"([0-9a-fA-F:]{64,95})\s*$"
)

VERIFICATION_MARKERS = (
    "Verifies",
    "Verified using v1 scheme",
    "Verified using v2 scheme",
    "Verified using v3 scheme",
    "Verified using v4 scheme",
)


def normalize_sha256(value: str) -> str:
    """Normalize SHA-256 fingerprint to 64 uppercase hexadecimal characters."""

    normalized = value.replace(":", "").replace(" ", "").strip().upper()

    if not re.fullmatch(r"[0-9A-F]{64}", normalized):
        raise ValueError("Invalid SHA-256 certificate fingerprint.")

    return normalized


def read_report(path: Path) -> str:
    """Read apksigner output safely."""

    if not path.exists() or not path.is_file():
        raise ValueError(f"Signature report not found: {path}")

    try:
        report = path.read_text(
            encoding="utf-8",
            errors="replace",
        )
    except OSError as error:
        raise ValueError(
            f"Could not read signature report: {error}"
        ) from error

    if not report.strip():
        raise ValueError("Signature verification report is empty.")

    return report


def verify_report(report: str) -> tuple[bool, str]:
    """Check successful signature verification and identify certificate."""

    verified = any(
        marker in report
        for marker in VERIFICATION_MARKERS
    )

    if not verified:
        raise ValueError(
            "APK signature verification did not succeed."
        )

    is_debug = DEBUG_CERTIFICATE_MARKER in report

    matches = SHA256_PATTERN.findall(report)

    if len(matches) > 1:
        fingerprints = {
            normalize_sha256(item)
            for item in matches
        }

        if len(fingerprints) > 1:
            raise ValueError(
                "Multiple different signer certificate fingerprints found."
            )

    fingerprint = (
        normalize_sha256(matches[0])
        if matches
        else ""
    )

    return is_debug, fingerprint


def main() -> int:
    if len(sys.argv) != REPORT_ARGUMENTS + 1:
        print(
            "Usage: python3 tool/verify_apk_signature.py "
            "<apksigner-report>",
            file=sys.stderr,
        )
        return 2

    report_path = Path(sys.argv[1])

    production_ready = (
        os.environ.get("PRODUCTION_READY", "").strip().lower()
        == "true"
    )

    expected_fingerprint_raw = os.environ.get(
        "EXPECTED_RELEASE_CERT_SHA256",
        "",
    ).strip()

    try:
        report = read_report(report_path)
        is_debug, fingerprint = verify_report(report)

        if production_ready and is_debug:
            raise ValueError(
                "A production build must not use the Android debug certificate."
            )

        if production_ready and not expected_fingerprint_raw:
            raise ValueError(
                "EXPECTED_RELEASE_CERT_SHA256 is required for production verification."
            )

        if expected_fingerprint_raw:
            expected_fingerprint = normalize_sha256(
                expected_fingerprint_raw
            )

            if not fingerprint:
                raise ValueError(
                    "Could not extract signer SHA-256 fingerprint."
                )

            if fingerprint != expected_fingerprint:
                raise ValueError(
                    "APK signer certificate does not match the expected release certificate."
                )

        certificate_type = (
            "DEBUG TEST BUILD"
            if is_debug
            else "private release certificate"
        )

        print("APK signature verification: PASSED")
        print(f"Certificate type: {certificate_type}")

        if fingerprint:
            print(f"Certificate SHA-256: {fingerprint}")
        else:
            print(
                "Certificate SHA-256: unavailable in supplied report"
            )

        if production_ready:
            print("Production certificate policy: PASSED")
        else:
            print(
                "Production certificate policy: NOT ENFORCED"
            )

        return 0

    except (ValueError, OSError) as error:
        print(f"::error::{error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
