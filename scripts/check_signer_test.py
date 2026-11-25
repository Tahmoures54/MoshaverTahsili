#!/usr/bin/env python3
"""Regression tests for APK signature output parsing."""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest

from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("check_signer.py")
SPEC = importlib.util.spec_from_file_location("check_signer", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
check_signer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_signer)


class CheckSignerTests(unittest.TestCase):
    def test_normalizes_colon_separated_sha256(self) -> None:
        digest = ":".join(["ab"] * 32)
        self.assertEqual(check_signer.normalize_sha256(digest), "AB" * 32)

    def test_accepts_contiguous_sha256(self) -> None:
        self.assertEqual(check_signer.normalize_sha256("cd" * 32), "CD" * 32)

    def test_extracts_colon_separated_apksigner_digest(self) -> None:
        digest = " : ".join(["ef"] * 32)
        output = (
            "Verifies\r\n"
            "  Signer #1 certificate DN: CN=Android Debug, O=Android, C=US  \r\n"
            f"  Signer #1 certificate SHA-256 digest: {digest}  \r\n"
        )

        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "candidate.apk"
            apk.write_bytes(b"test apk")
            completed = subprocess.CompletedProcess(
                args=["apksigner", "verify"],
                returncode=0,
                stdout=b"",
                stderr=output.encode(),
            )

            with patch.object(check_signer.subprocess, "run", return_value=completed):
                fingerprint, is_debug = check_signer.verify_apk(apk, "apksigner")

        self.assertEqual(fingerprint, "EF" * 32)
        self.assertTrue(is_debug)


    def test_accepts_alternate_build_tools_certificate_labels(self) -> None:
        digest = "12" * 32
        output = (
            "Verifies\n"
            "  Signer #1 DN: CN=CI Validation,O=Temporary Build,C=US\n"
            f"  Signer #1 SHA-256 digest: {digest}\n"
        )

        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "candidate.apk"
            apk.write_bytes(b"test apk")
            completed = subprocess.CompletedProcess(
                args=["apksigner", "verify"],
                returncode=0,
                stdout=output.encode(),
                stderr=b"",
            )

            with patch.object(check_signer.subprocess, "run", return_value=completed):
                fingerprint, is_debug = check_signer.verify_apk(apk, "apksigner")

        self.assertEqual(fingerprint, digest.upper())
        self.assertFalse(is_debug)


    def test_strips_terminal_formatting_and_nonbreaking_spaces(self) -> None:
        digest = "34" * 32
        output = (
            "\x1b[32mVerifies\x1b[0m\r\n"
            f"\x1b[32mSigner #1 certificate DN:\x1b[0m CN=Release\u00a0\r\n"
            f"Signer #1 certificate SHA-256 digest: {digest}\r\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "candidate.apk"
            apk.write_bytes(b"test apk")
            completed = subprocess.CompletedProcess(
                args=["apksigner", "verify"],
                returncode=0,
                stdout=output.encode(),
                stderr=b"",
            )
            with patch.object(check_signer.subprocess, "run", return_value=completed):
                fingerprint, is_debug = check_signer.verify_apk(apk, "apksigner")
        self.assertEqual(fingerprint, digest.upper())
        self.assertFalse(is_debug)


    def test_accepts_sha256_label_without_digest_suffix(self) -> None:
        digest = "a7" * 32
        output = (
            "Verifies\n"
            "Signer #1 certificate DN: CN=CI Validation,O=Temporary Build,C=US\n"
            f"Signer #1 certificate SHA-256: {digest}\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "candidate.apk"
            apk.write_bytes(b"test apk")
            completed = subprocess.CompletedProcess(
                args=["apksigner", "verify"],
                returncode=0,
                stdout=output.encode(),
                stderr=b"",
            )
            with patch.object(check_signer.subprocess, "run", return_value=completed):
                fingerprint, is_debug = check_signer.verify_apk(apk, "apksigner")
        self.assertEqual(fingerprint, digest.upper())
        self.assertFalse(is_debug)

    def test_parses_split_signer_header_and_certificate_details(self) -> None:
        apk_digest = "9a" * 32
        stamp_digest = "bc" * 32
        output = (
            "Verifies\n"
            "Signer #1:\n"
            "  Signer #1 certificate DN: CN=Release,O=App,C=US\n"
            f"  Certificate SHA-256 digest: {apk_digest}\n"
            "Source Stamp Signer certificate DN: CN=Stamp,O=App,C=US\n"
            f"Source Stamp certificate SHA-256 digest: {stamp_digest}\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "candidate.apk"
            apk.write_bytes(b"test apk")
            completed = subprocess.CompletedProcess(
                args=["apksigner", "verify"],
                returncode=0,
                stdout=output.encode(),
                stderr=b"",
            )
            with patch.object(check_signer.subprocess, "run", return_value=completed):
                fingerprint, is_debug = check_signer.verify_apk(apk, "apksigner")
        self.assertEqual(fingerprint, apk_digest.upper())
        self.assertFalse(is_debug)

    def test_ignores_source_stamp_certificate(self) -> None:
        apk_digest = "56" * 32
        stamp_digest = "78" * 32
        output = (
            "Verifies\n"
            "Signer #1 certificate DN: CN=Release,O=App,C=US\n"
            f"Signer #1 certificate SHA-256 digest: {apk_digest}\n"
            "Source Stamp Signer certificate DN: CN=Source Stamp,O=App,C=US\n"
            f"Source Stamp Signer certificate SHA-256 digest: {stamp_digest}\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "candidate.apk"
            apk.write_bytes(b"test apk")
            completed = subprocess.CompletedProcess(
                args=["apksigner", "verify"],
                returncode=0,
                stdout=output.encode(),
                stderr=b"",
            )
            with patch.object(check_signer.subprocess, "run", return_value=completed):
                fingerprint, is_debug = check_signer.verify_apk(apk, "apksigner")
        self.assertEqual(fingerprint, apk_digest.upper())
        self.assertFalse(is_debug)


    def test_parses_scheme_labelled_v3_certificate_and_ignores_public_key_digest(self) -> None:
        certificate_digest = "d1" * 32
        public_key_digest = "e2" * 32
        output = (
            "Verifies\n"
            "V3.0 Signer: certificate DN: CN=CI Validation,O=Temporary Build,C=US\n"
            f"V3.0 Signer: certificate SHA-256 digest: {certificate_digest}\n"
            f"V3.0 Signer: public key SHA-256 digest: {public_key_digest}\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "candidate.apk"
            apk.write_bytes(b"test apk")
            completed = subprocess.CompletedProcess(
                args=["apksigner", "verify"],
                returncode=0,
                stdout=output.encode(),
                stderr=b"",
            )
            with patch.object(check_signer.subprocess, "run", return_value=completed):
                fingerprint, is_debug = check_signer.verify_apk(apk, "apksigner")
        self.assertEqual(fingerprint, certificate_digest.upper())
        self.assertFalse(is_debug)

if __name__ == "__main__":
    unittest.main()
