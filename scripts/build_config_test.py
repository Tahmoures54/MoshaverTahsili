#!/usr/bin/env python3
"""Regression tests for production release configuration completeness."""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import unittest

from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("build_config.py")
SPEC = importlib.util.spec_from_file_location("build_config", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
build_config = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = build_config
SPEC.loader.exec_module(build_config)


class BuildConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.pubspec = Path(self.directory.name) / "pubspec.yaml"
        self.pubspec.write_text(
            "name: test_app\nversion: 1.2.3+45\n",
            encoding="utf-8",
        )
        self.environment = {
            "RELEASE_KEYSTORE_BASE64": "dGVzdA==",
            "RELEASE_KEYSTORE_PASSWORD": "test-store-password",
            "RELEASE_KEY_ALIAS": "upload",
            "RELEASE_KEY_PASSWORD": "test-key-password",
            "BAZAAR_RSA_PUBLIC_KEY": "test-public-key",
            "EXPECTED_RELEASE_CERT_SHA256": "ab" * 32,
            "AI_API_KEY": "test-ai-key",
            "BAZAAR_CATALOG_CONFIRMED": "true",
        }

    def inspect(self, environment: dict[str, str]):
        with (
            patch.object(build_config, "PUBSPEC_PATH", self.pubspec),
            patch.dict(os.environ, environment, clear=True),
        ):
            return build_config.inspect_configuration()

    def test_complete_configuration_requires_certificate_pin(self) -> None:
        config = self.inspect(self.environment)
        self.assertTrue(config.production_ready)
        self.assertIn(
            "EXPECTED_RELEASE_CERT_SHA256",
            config.present_required,
        )

    def test_missing_certificate_pin_blocks_production_readiness(self) -> None:
        environment = dict(self.environment)
        environment.pop("EXPECTED_RELEASE_CERT_SHA256")
        config = self.inspect(environment)

        self.assertFalse(config.production_ready)
        self.assertIn(
            "EXPECTED_RELEASE_CERT_SHA256",
            config.missing_required,
        )
        self.assertIn(
            "EXPECTED_RELEASE_CERT_SHA256",
            build_config.generate_summary(config),
        )


if __name__ == "__main__":
    unittest.main()
