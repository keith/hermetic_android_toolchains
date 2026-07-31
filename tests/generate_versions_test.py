#!/usr/bin/env python3
"""Tests that version metadata updates are additive."""

import copy
import unittest
from unittest import mock

from tools import generate_ndk_versions
from tools import generate_sdk_versions


def _archives(prefix, *, sha1=None):
    return [
        {
            "file": "{}-{}.zip".format(prefix, platform),
            "platform": platform,
            "sha1": sha1,
            "url": "https://example.com/{}-{}.zip".format(prefix, platform),
        }
        for platform in ("darwin", "linux", "windows")
    ]


class GenerateSdkVersionsTest(unittest.TestCase):
    def test_generate_preserves_existing_values_and_adds_new_values(self):
        existing = {
            "components": {
                "build_tools": {"38.0.0": {"existing": "build-tools"}},
                "emulator": {"2.0.0": {"existing": "emulator"}},
                "platform_tools": {"1.0.0": {"existing": "platform-tools"}},
                "system_images": {"old/image": {"existing": "system-image"}},
            },
            "versions": {
                "24": {
                    "platform_tools_version": "1.0.0",
                    "platform": {"existing": "platform"},
                }
            },
        }
        repo_packages = [
            {
                "path": "platforms;android-24",
                "revision": (24, 0, 1, 0),
                "archives": [
                    {
                        "file": "changed-platform-24.zip",
                        "platform": None,
                        "sha1": None,
                        "url": "https://example.com/changed-platform-24.zip",
                    }
                ],
            },
            {
                "path": "platforms;android-25",
                "revision": (25, 0, 0, 0),
                "archives": [
                    {
                        "file": "platform-25.zip",
                        "platform": None,
                        "sha1": None,
                        "url": "https://example.com/platform-25.zip",
                    }
                ],
            },
            {
                "path": "build-tools;38.0.0",
                "revision": (38, 0, 0, 0),
                "archives": _archives("changed-build-tools"),
            },
            {
                "path": "platform-tools",
                "revision": (2, 0, 0, 0),
                "archives": _archives("platform-tools-2"),
            },
            {
                "path": "emulator",
                "revision": (2, 0, 0, 0),
                "archives": _archives("changed-emulator-2"),
            },
            {
                "path": "emulator",
                "revision": (3, 0, 0, 0),
                "archives": _archives("emulator-3"),
            },
        ]

        def archive_json(archive, _metadata, infer_prefix):
            result = {"file": archive["file"], "sha256": "new"}
            if infer_prefix:
                result["strip_prefix"] = "new"
            return result

        with (
            mock.patch.object(
                generate_sdk_versions,
                "_load_existing",
                return_value=({}, copy.deepcopy(existing)),
            ),
            mock.patch.object(generate_sdk_versions, "_fetch_xml", return_value=None),
            mock.patch.object(
                generate_sdk_versions,
                "_parse_packages",
                side_effect=[repo_packages, []],
            ),
            mock.patch.object(
                generate_sdk_versions,
                "_archive_json",
                side_effect=archive_json,
            ),
        ):
            actual = generate_sdk_versions._generate()

        self.assertEqual(
            actual["components"]["build_tools"]["38.0.0"],
            existing["components"]["build_tools"]["38.0.0"],
        )
        self.assertEqual(
            actual["components"]["emulator"]["2.0.0"],
            existing["components"]["emulator"]["2.0.0"],
        )
        self.assertEqual(
            actual["components"]["platform_tools"]["1.0.0"],
            existing["components"]["platform_tools"]["1.0.0"],
        )
        self.assertEqual(
            actual["components"]["system_images"],
            existing["components"]["system_images"],
        )
        self.assertEqual(actual["versions"]["24"], existing["versions"]["24"])
        self.assertIn("3.0.0", actual["components"]["emulator"])
        self.assertIn("2.0.0", actual["components"]["platform_tools"])
        self.assertIn("25", actual["versions"])


class GenerateNdkVersionsTest(unittest.TestCase):
    def test_generate_preserves_retired_versions_and_changed_aliases(self):
        existing = {
            "aliases": {"r25": "25.0.1"},
            "versions": {
                "25.0.1": {
                    "strip_prefix": "existing",
                    "archives": {"linux": {"existing": "archive"}},
                }
            },
        }
        sha1 = "00" * 20
        manifest_versions = {
            "25.0.9": {
                "alias": "r25",
                "archives": _archives("changed-r25", sha1=sha1),
            },
            "26.0.2": {
                "alias": "r26",
                "archives": _archives("r26", sha1=sha1),
            },
        }
        aliases = {"r25": "25.0.9", "r26": "26.0.2"}

        with (
            mock.patch.object(
                generate_ndk_versions,
                "_load_existing",
                return_value=copy.deepcopy(existing),
            ),
            mock.patch.object(generate_ndk_versions, "_fetch_xml", return_value=None),
            mock.patch.object(
                generate_ndk_versions,
                "_parse_packages",
                return_value=(manifest_versions, aliases),
            ),
        ):
            actual = generate_ndk_versions._generate()

        self.assertEqual(actual["aliases"]["r25"], "25.0.1")
        self.assertEqual(actual["versions"]["25.0.1"], existing["versions"]["25.0.1"])
        self.assertEqual(actual["aliases"]["r26"], "26.0.2")
        self.assertIn("25.0.9", actual["versions"])
        self.assertIn("26.0.2", actual["versions"])


if __name__ == "__main__":
    unittest.main()
