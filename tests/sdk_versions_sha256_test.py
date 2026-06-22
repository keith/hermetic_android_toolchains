#!/usr/bin/env python3
"""Validates checksums for Android SDK archives listed in sdk/versions.json."""

import concurrent.futures
import hashlib
import json
import re
import sys
import urllib.error
import urllib.request
import unittest


ANDROID_REPOSITORY_URL = "https://dl.google.com/android/repository/"
CHUNK_SIZE = 1024 * 1024
SDK_SHA256_TEST_JOBS = 4
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
TIMEOUT_SECONDS = 60


def archive_url(archive):
    if "url" in archive:
        return archive["url"]
    return ANDROID_REPOSITORY_URL + archive["file"]


def collect_archives(metadata):
    archives = []

    for component_name, versions in sorted(metadata["components"].items()):
        for version, component in sorted(versions.items()):
            for platform, archive in sorted(component["archives"].items()):
                archives.append(
                    (
                        "{} {} {}".format(component_name, version, platform),
                        archive_url(archive),
                        archive["sha256"],
                    )
                )

    for version, sdk in sorted(metadata["versions"].items()):
        platform = sdk["platform"]
        archives.append(
            (
                "platform {}".format(version),
                archive_url(platform),
                platform["sha256"],
            )
        )

    return archives


def deduplicate_archives(archives):
    by_url = {}
    for label, url, sha256 in archives:
        previous = by_url.get(url)
        if previous and previous[1] != sha256:
            raise AssertionError(
                "Conflicting sha256 values for {}: {} has {}, {} has {}".format(
                    url,
                    previous[0],
                    previous[1],
                    label,
                    sha256,
                )
            )
        if not previous:
            by_url[url] = (label, sha256)
    return [(label, url, sha256) for url, (label, sha256) in sorted(by_url.items())]


def download_sha256(url):
    digest = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=TIMEOUT_SECONDS) as response:
        while True:
            chunk = response.read(CHUNK_SIZE)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def validate_archive(label, url, expected_sha256):
    print("downloading {} from {}".format(label, url), file=sys.stderr)
    actual_sha256 = download_sha256(url)
    if actual_sha256 != expected_sha256:
        return "{}: expected {}, got {} ({})".format(
            label,
            expected_sha256,
            actual_sha256,
            url,
        )
    print("validated {} sha256 {}".format(label, expected_sha256), file=sys.stderr)
    return None


class SdkVersionsSha256Test(unittest.TestCase):
    def test_archives_match_recorded_sha256s(self):
        with open(sys.argv[1], encoding="utf-8") as versions_json:
            metadata = json.load(versions_json)

        archives = deduplicate_archives(collect_archives(metadata))
        for label, url, sha256 in archives:
            with self.subTest(archive=label):
                self.assertRegex(sha256, SHA256_PATTERN)
                self.assertTrue(url.startswith("https://"), url)

        print(
            "Validating {} Android SDK archive sha256 values with {} workers.".format(
                len(archives),
                SDK_SHA256_TEST_JOBS,
            ),
            file=sys.stderr,
        )

        failures = []
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=SDK_SHA256_TEST_JOBS,
        ) as executor:
            future_to_archive = {
                executor.submit(validate_archive, label, url, sha256): (label, url)
                for label, url, sha256 in archives
            }
            for future in concurrent.futures.as_completed(future_to_archive):
                label, url = future_to_archive[future]
                try:
                    failure = future.result()
                except (OSError, urllib.error.URLError) as error:
                    failure = "{}: failed to download {}: {}".format(label, url, error)
                if failure:
                    failures.append(failure)

        if failures:
            self.fail("\n".join(sorted(failures)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: sdk_versions_sha256_test.py <sdk/versions.json>")
    unittest.main(argv=[sys.argv[0]])
