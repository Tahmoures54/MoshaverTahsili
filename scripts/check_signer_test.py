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
        digest = ":".join(["ef"] * 32)
        output = (
            "Verifies\n"
            "Signer #1 certificate DN: CN=Android Debug, O=Android, C=US\n"
            f"Signer #1 certificate SHA-256 digest: {digest}\n"
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

        self.assertEqual(fingerprint, "EF" * 32)
        self.assertTrue(is_debug)


if __name__ == "__main__":
    unittest.main()
