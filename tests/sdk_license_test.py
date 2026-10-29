"""Check exported acceptance markers and the SDK layout used by Gradle."""

from pathlib import Path
import sys
import unittest


_SOURCE, _EXPORTED, _SDK_ROOT = [Path(arg) for arg in sys.argv[1:]]
del sys.argv[1:]


class SdkLicenseTest(unittest.TestCase):
    def test_sdk_layout_and_packaging_expose_the_generated_hashes(self):
        expected = _SOURCE.read_text()
        self.assertEqual(_EXPORTED.read_text(), expected)
        sdk_root = _SDK_ROOT.resolve().parent
        self.assertEqual(
            (sdk_root / "licenses" / "android-sdk-license").read_text(), expected
        )
        self.assertIn(
            "24333f8a63b6825ea9c5514f83c2829b004d1fee", expected.splitlines()
        )


if __name__ == "__main__":
    unittest.main()
