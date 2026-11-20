#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import hashlib
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from check_appicon_md5 import EXPECTED_MD5, ICON_REL, main  # noqa: E402


class AppIconMd5Tests(unittest.TestCase):
    def test_shipping_icon_matches_expected_md5(self):
        root = Path(__file__).resolve().parents[1]
        path = root / ICON_REL
        self.assertTrue(path.is_file(), f"missing {ICON_REL}")
        digest = hashlib.md5(path.read_bytes()).hexdigest()
        self.assertEqual(digest, EXPECTED_MD5)

    def test_main_exits_zero(self):
        self.assertEqual(main(), 0)


if __name__ == "__main__":
    unittest.main()
