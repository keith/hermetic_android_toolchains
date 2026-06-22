#!/usr/bin/env python3
"""Generate ndk/versions.json from Google's Android SDK manifest."""

import base64
import json
from pathlib import Path
import re
import urllib.request
import xml.etree.ElementTree as ET


_ROOT = Path(__file__).resolve().parents[1]
_OUTPUT = _ROOT / "ndk" / "versions.json"
_BASE_URL = "https://dl.google.com/android/repository/"
_REPOSITORY_URL = _BASE_URL + "repository2-4.xml"

_ARCHIVE_PLATFORMS = ("darwin", "linux", "windows")
_MANIFEST_PLATFORMS = {"linux": "linux", "macosx": "darwin", "windows": "windows"}
_CHANNELS = ("stable", "beta")

_NDK_PATH_RE = re.compile(r"^ndk;(\d+\.\d+\.\d+)$")
_NDK_ARCHIVE_RE = re.compile(
    r"^android-ndk-(r\d+(?:[a-z]|-(?:beta|rc)\d+)?)-(darwin|linux|windows)\.zip$"
)
_NDK_VERSION_RE = re.compile(r"^r(\d+)(?:(-(?:beta|rc))(\d+)|([a-z]))?$")
_MIN_PACKAGE_VERSION = (25, 0, 0)


def _fetch_xml(url):
    with urllib.request.urlopen(url) as response:
        return ET.fromstring(response.read())


def _channel_ids(root):
    channels = {
        (channel.text or "").strip().lower(): channel.attrib["id"]
        for channel in root.findall("channel")
    }
    missing = [channel for channel in _CHANNELS if channel not in channels]
    if missing:
        raise ValueError(
            "manifest does not define channels {}".format(", ".join(missing))
        )
    return {channels[channel] for channel in _CHANNELS}


def _revision(pkg):
    rev = pkg.find("revision")
    return tuple(
        int(rev.findtext(part) or 0) for part in ("major", "minor", "micro", "preview")
    )


def _version_stage(stage, number):
    if stage == "-beta":
        return -2000 + number
    if stage == "-rc":
        return -1000 + number
    return 0


def _version_suffix_key(suffix):
    return ord(suffix) - ord("a") + 1 if suffix else 0


def _version_key(version):
    match = _NDK_VERSION_RE.fullmatch(version)
    if not match:
        raise ValueError("unsupported NDK version {}".format(repr(version)))
    if match.group(2):
        return int(match.group(1)), _version_stage(match.group(2), int(match.group(3)))
    return int(match.group(1)), _version_suffix_key(match.group(4))


def _package_version_key(version):
    return tuple(int(part) for part in version.split("."))


def _archive_release(file_name):
    match = _NDK_ARCHIVE_RE.fullmatch(file_name)
    return match.group(1) if match else None


def _parse_packages(root):
    channels = _channel_ids(root)
    packages = {}
    aliases = {}
    for pkg in root.findall("remotePackage"):
        path_match = _NDK_PATH_RE.fullmatch(pkg.attrib["path"])
        if pkg.attrib.get("obsolete") == "true" or not path_match:
            continue
        version = path_match.group(1)
        channel_ref = pkg.find("channelRef")
        channel = channel_ref.attrib.get("ref") if channel_ref is not None else None
        if channel not in channels:
            continue

        revision = _revision(pkg)
        releases = set()
        archives = []
        for archive in pkg.findall("./archives/archive"):
            complete = archive.find("complete")
            checksum = complete.find("checksum") if complete is not None else None
            file_name = complete.findtext("url") if complete is not None else None
            release = _archive_release(file_name or "")
            if not release:
                archives = []
                break
            if checksum is None or not checksum.text:
                raise ValueError(
                    "archive for {} is missing checksum".format(pkg.attrib["path"])
                )
            if checksum.attrib.get("type", "sha1") != "sha1":
                raise ValueError(
                    "unsupported checksum type for {}".format(pkg.attrib["path"])
                )

            manifest_platform = archive.findtext("host-os")
            platform = _MANIFEST_PLATFORMS.get(manifest_platform)
            if platform is None:
                raise ValueError(
                    "unsupported archive platform for {}".format(pkg.attrib["path"])
                )
            releases.add(release)
            archives.append(
                {
                    "file": file_name,
                    "platform": platform,
                    "sha1": checksum.text,
                    "url": _BASE_URL + file_name,
                }
            )

        if not archives:
            continue
        if len(releases) != 1:
            raise ValueError(
                "archives for {} contain mixed releases".format(pkg.attrib["path"])
            )

        release = releases.pop()
        if _package_version_key(version) < _MIN_PACKAGE_VERSION:
            continue

        old = packages.get(version)
        if old is None or revision > old["revision"]:
            packages[version] = {
                "alias": release,
                "archives": archives,
                "revision": revision,
            }
            aliases[release] = version
    return packages, aliases


def _platform_archive(pkg, platform):
    candidates = [
        archive for archive in pkg["archives"] if archive["platform"] == platform
    ]
    if len(candidates) != 1:
        raise ValueError("expected one {} archive for NDK".format(platform))
    return candidates[0]


def _integrity(algorithm, hexdigest):
    digest = bytes.fromhex(hexdigest)
    return "{}-{}".format(algorithm, base64.b64encode(digest).decode("ascii"))


def _archive_json(archive):
    return {
        "file": archive["file"],
        "sha1": archive["sha1"],
        "integrity": _integrity("sha1", archive["sha1"]),
    }


def _archives_json(pkg):
    return {
        platform: _archive_json(_platform_archive(pkg, platform))
        for platform in _ARCHIVE_PLATFORMS
    }


def _selected_versions(existing_versions, manifest_versions):
    return {
        version
        for version in set(existing_versions) | set(manifest_versions)
        if _NDK_PATH_RE.fullmatch("ndk;{}".format(version))
        and _package_version_key(version) >= _MIN_PACKAGE_VERSION
    }


def _generate():
    manifest_versions, aliases = _parse_packages(_fetch_xml(_REPOSITORY_URL))
    versions = {}

    for version in _selected_versions({}, manifest_versions):
        alias = manifest_versions[version]["alias"]
        versions[version] = {
            "strip_prefix": "android-ndk-{}".format(alias),
            "archives": _archives_json(manifest_versions[version]),
        }

    aliases = {
        alias: version
        for alias, version in aliases.items()
        if version in versions and _NDK_VERSION_RE.fullmatch(alias)
    }
    return {
        "aliases": dict(
            sorted(aliases.items(), key=lambda item: _version_key(item[0]))
        ),
        "versions": dict(
            sorted(versions.items(), key=lambda item: _package_version_key(item[0]))
        ),
    }


def _main():
    versions = _generate()
    with _OUTPUT.open("w") as f:
        json.dump(versions, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    _main()
