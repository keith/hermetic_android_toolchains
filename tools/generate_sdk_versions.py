#!/usr/bin/env python3
"""Generate sdk/versions.json from Google's Android SDK manifests."""

import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile


_ROOT = Path(__file__).resolve().parents[1]
_OUTPUT = _ROOT / "sdk" / "versions.json"
_BASE_URL = "https://dl.google.com/android/repository/"
_REPOSITORY_URL = _BASE_URL + "repository2-3.xml"

_ARCHIVE_PLATFORMS = ("darwin", "linux", "windows")
_MANIFEST_PLATFORMS = {"linux": "linux", "macosx": "darwin", "windows": "windows"}
_MIN_API = 24  # Chosen at random

_PLATFORM_RE = re.compile(r"^platforms;android-(\d+(?:\.\d+)?)$")
_BUILD_TOOLS_RE = re.compile(r"^build-tools;(\d+(?:\.\d+)*)$")
_FINAL_RE = re.compile(r"^\d+(?:\.\d+)*$")


def _fetch_xml(url):
    with urllib.request.urlopen(url) as response:
        return ET.fromstring(response.read())


def _stable_channel(root):
    for channel in root.findall("channel"):
        if (channel.text or "").strip().lower() == "stable":
            return channel.attrib["id"]
    raise ValueError("manifest does not define a stable channel")


def _revision(pkg):
    rev = pkg.find("revision")
    return tuple(int(rev.findtext(part) or 0) for part in ("major", "minor", "micro", "preview"))


def _revision_name(rev):
    major, minor, micro, preview = rev
    version = "{}.{}.{}".format(major, minor, micro)
    return "{}-rc{}".format(version, preview) if preview else version


def _version_key(version):
    return tuple(int(part) for part in re.findall(r"\d+", version))


def _is_supported_version(version, min_api):
    return _FINAL_RE.fullmatch(version) and _version_key(version)[0] >= min_api


def _parse_packages(root):
    stable = _stable_channel(root)
    packages = []
    for pkg in root.findall("remotePackage"):
        channel_ref = pkg.find("channelRef")
        if channel_ref is None or channel_ref.attrib.get("ref") != stable:
            continue

        archives = []
        for archive in pkg.findall("./archives/archive"):
            complete = archive.find("complete")
            checksum = complete.find("checksum") if complete is not None else None
            url = complete.findtext("url") if complete is not None else None
            if not url or checksum is None or not checksum.text:
                raise ValueError("archive for {} is missing url or checksum".format(pkg.attrib["path"]))
            if checksum.attrib.get("type", "sha1") != "sha1":
                raise ValueError("unsupported checksum type for {}".format(pkg.attrib["path"]))

            manifest_platform = archive.findtext("host-os")
            archives.append({
                "file": url,
                "platform": _MANIFEST_PLATFORMS.get(manifest_platform) if manifest_platform else None,
                "sha1": checksum.text,
                "url": _BASE_URL + url,
            })

        packages.append({
            "archives": archives,
            "path": pkg.attrib["path"],
            "revision": _revision(pkg),
        })
    return packages


def _latest_by_path(packages):
    latest = {}
    for pkg in packages:
        old = latest.get(pkg["path"])
        if old is None or pkg["revision"] > old["revision"]:
            latest[pkg["path"]] = pkg
    return latest


def _single_archive(pkg):
    if len(pkg["archives"]) != 1 or pkg["archives"][0]["platform"] is not None:
        raise ValueError("expected one platform-independent archive for {}".format(pkg["path"]))
    return pkg["archives"][0]


def _platform_archive(pkg, platform):
    candidates = [archive for archive in pkg["archives"] if archive["platform"] == platform]
    if not candidates:
        raise ValueError("missing {} archive for {}".format(platform, pkg["path"]))
    if platform == "darwin":
        return sorted(candidates, key=lambda archive: ("x64" not in archive["file"], archive["file"]))[0]
    return sorted(candidates, key=lambda archive: archive["file"])[0]


def _zip_prefix(path):
    with zipfile.ZipFile(path) as archive:
        prefixes = {
            name.split("/", 1)[0]
            for name in archive.namelist()
            if "/" in name and not name.startswith("__MACOSX/")
        }
    return prefixes.pop() if len(prefixes) == 1 else ""


def _collect_archive_metadata(value, metadata):
    if isinstance(value, dict):
        if value.get("file") and value.get("sha256"):
            entry = {"sha256": value["sha256"]}
            if "strip_prefix" in value:
                entry["strip_prefix"] = value["strip_prefix"]
            metadata.setdefault(value["file"], entry)
        for child in value.values():
            _collect_archive_metadata(child, metadata)
    elif isinstance(value, list):
        for child in value:
            _collect_archive_metadata(child, metadata)


def _load_existing(path):
    if not path.exists():
        return {}, {}

    with path.open() as f:
        data = json.load(f)

    metadata = {}
    _collect_archive_metadata(data, metadata)
    return metadata, data.get("components", {})


def _hashes(path):
    sha1 = hashlib.sha1()
    sha256 = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            sha1.update(chunk)
            sha256.update(chunk)
    return sha1.hexdigest(), sha256.hexdigest()


def _download_metadata(archive, infer_prefix):
    print("Downloading {}".format(archive["url"]), file=sys.stderr)
    with tempfile.NamedTemporaryFile() as f:
        with urllib.request.urlopen(archive["url"]) as response:
            for chunk in iter(lambda: response.read(1024 * 1024), b""):
                f.write(chunk)
        f.flush()

        sha1, sha256 = _hashes(Path(f.name))
        if sha1 != archive["sha1"]:
            raise ValueError("SHA-1 mismatch for {}".format(archive["file"]))
        return {
            "sha256": sha256,
            "strip_prefix": _zip_prefix(Path(f.name)) if infer_prefix else "",
        }


def _archive_json(archive, metadata, infer_prefix):
    cached = metadata.get(archive["file"])
    if cached is None or (infer_prefix and "strip_prefix" not in cached):
        cached = _download_metadata(archive, infer_prefix)
        metadata[archive["file"]] = cached

    result = {"file": archive["file"], "sha256": cached["sha256"]}
    if cached.get("strip_prefix"):
        result["strip_prefix"] = cached["strip_prefix"]
    return result


def _platform_archives_json(pkg, metadata):
    return {
        platform: _archive_json(_platform_archive(pkg, platform), metadata, infer_prefix=True)
        for platform in _ARCHIVE_PLATFORMS
    }


def _matching_versions(packages, pattern, min_api):
    versions = {}
    for pkg in packages.values():
        match = pattern.match(pkg["path"])
        if match and _is_supported_version(match.group(1), min_api):
            versions[match.group(1)] = pkg
    return dict(sorted(versions.items(), key=lambda item: _version_key(item[0])))


def _merge_build_tools(existing_components, version, pkg, metadata):
    build_tools = dict(existing_components.get("build_tools", {}))
    build_tools[version] = {
        "directory": version,
        "archives": _platform_archives_json(pkg, metadata),
    }
    return dict(sorted(build_tools.items(), key=lambda item: _version_key(item[0])))


def _generate():
    metadata, existing_components = _load_existing(_OUTPUT)
    repo_packages = _parse_packages(_fetch_xml(_REPOSITORY_URL))
    repo = _latest_by_path(repo_packages)

    platforms = _matching_versions(repo, _PLATFORM_RE, _MIN_API)
    build_tools = _matching_versions(repo, _BUILD_TOOLS_RE, _MIN_API)

    build_tools_version = max(build_tools, key=_version_key)
    platform_tools_pkg = repo["platform-tools"]
    platform_tools_version = _revision_name(platform_tools_pkg["revision"])

    components = {
        "build_tools": _merge_build_tools(
            existing_components,
            build_tools_version,
            build_tools[build_tools_version],
            metadata,
        ),
        "platform_tools": {
            platform_tools_version: {
                "archives": _platform_archives_json(platform_tools_pkg, metadata),
            },
        },
    }

    versions = {}
    for version, pkg in platforms.items():
        versions[version] = {
            "platform_tools_version": platform_tools_version,
            "platform": _archive_json(_single_archive(pkg), metadata, infer_prefix=False),
        }

    return {"components": components, "versions": versions}


def _main():
    versions = _generate()
    with _OUTPUT.open("w") as f:
        json.dump(versions, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    _main()
