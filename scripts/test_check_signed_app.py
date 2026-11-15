#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""Unit tests for check_signed_app.py."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import check_signed_app as csa


class CheckSignedAppTests(unittest.TestCase):
    def test_ok_without_encryption_key(self) -> None:
        info = {
            "CFBundleIdentifier": "com.cinderandcrown.magpie",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "3.1",
        }
        entitlements = {
            "application-identifier": "GDNRT9DJ58.com.cinderandcrown.magpie",
            "com.apple.developer.team-identifier": "GDNRT9DJ58",
        }
        self.assertEqual(
            csa.problems(info, entitlements, "GDNRT9DJ58", "com.cinderandcrown.magpie", "0.1.0", "3.1"),
            [],
        )

    def test_require_export_compliance(self) -> None:
        info = {
            "CFBundleIdentifier": "com.cinderandcrown.magpie",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
        }
        entitlements = {
            "application-identifier": "GDNRT9DJ58.com.cinderandcrown.magpie",
            "com.apple.developer.team-identifier": "GDNRT9DJ58",
        }
        found = csa.problems(
            info, entitlements, "GDNRT9DJ58", "com.cinderandcrown.magpie", "0.1.0", "1",
            require_export_compliance=True,
        )
        self.assertTrue(any("ITSAppUsesNonExemptEncryption" in p for p in found))

    def test_rejects_dev_signature_and_wrong_bundle(self) -> None:
        info = {
            "CFBundleIdentifier": "com.wrong",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
        }
        entitlements = {
            "application-identifier": "TEAM.com.wrong",
            "com.apple.developer.team-identifier": "TEAM",
            "get-task-allow": True,
        }
        found = csa.problems(info, entitlements, "GDNRT9DJ58", "com.cinderandcrown.magpie", "0.1.0", "1")
        self.assertGreaterEqual(len(found), 3)

    def test_cli_ok(self) -> None:
        import plistlib

        with tempfile.TemporaryDirectory() as tmp:
            info_path = Path(tmp) / "Info.plist"
            ent_path = Path(tmp) / "ent.plist"
            info_path.write_bytes(
                plistlib.dumps(
                    {
                        "CFBundleIdentifier": "com.cinderandcrown.magpie",
                        "CFBundleShortVersionString": "0.1.0",
                        "CFBundleVersion": "1.1",
                    }
                )
            )
            ent_path.write_bytes(
                plistlib.dumps(
                    {
                        "application-identifier": "GDNRT9DJ58.com.cinderandcrown.magpie",
                        "com.apple.developer.team-identifier": "GDNRT9DJ58",
                    }
                )
            )
            code = csa.main(
                [
                    "--info", str(info_path),
                    "--entitlements", str(ent_path),
                    "--team", "GDNRT9DJ58",
                    "--bundle-id", "com.cinderandcrown.magpie",
                    "--version", "0.1.0",
                    "--build", "1.1",
                ]
            )
            self.assertEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
