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
_SYSTEM_IMAGES_REPOSITORY_URL = _BASE_URL + "sys-img/android/sys-img2-3.xml"
_SYSTEM_IMAGES_FILE_PREFIX = "sys-img/android/"

_ARCHIVE_PLATFORMS = ("darwin", "linux", "windows")
_MANIFEST_PLATFORMS = {"linux": "linux", "macosx": "darwin", "windows": "windows"}
_MIN_API = 24  # Chosen at random

_PLATFORM_RE = re.compile(r"^platforms;android-(\d+(?:\.\d+)?)$")
_BUILD_TOOLS_RE = re.compile(r"^build-tools;(\d+(?:\.\d+)*)$")
_FINAL_RE = re.compile(r"^\d+(?:\.\d+)*$")
_SYSTEM_IMAGE_RE = re.compile(
    r"^system-images;android-(\d+(?:\.\d+)?);([^;]+);([^;]+)$"
)


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
    return tuple(
        int(rev.findtext(part) or 0) for part in ("major", "minor", "micro", "preview")
    )


def _revision_name(rev):
    major, minor, micro, preview = rev
    version = "{}.{}.{}".format(major, minor, micro)
    return "{}-rc{}".format(version, preview) if preview else version


def _version_key(version):
    return tuple(int(part) for part in re.findall(r"\d+", version))


def _is_supported_version(version, min_api):
    return _FINAL_RE.fullmatch(version) and _version_key(version)[0] >= min_api


def _parse_packages(root, file_prefix=""):
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
                raise ValueError(
                    "archive for {} is missing url or checksum".format(
                        pkg.attrib["path"]
                    )
                )
            if checksum.attrib.get("type", "sha1") != "sha1":
                raise ValueError(
                    "unsupported checksum type for {}".format(pkg.attrib["path"])
                )

            manifest_platform = archive.findtext("host-os")
            file_name = file_prefix + url
            archives.append(
                {
                    "file": file_name,
                    "platform": _MANIFEST_PLATFORMS.get(manifest_platform)
                    if manifest_platform
                    else None,
                    "sha1": checksum.text,
                    "url": _BASE_URL + file_name,
                }
            )

        packages.append(
            {
                "archives": archives,
                "path": pkg.attrib["path"],
                "revision": _revision(pkg),
            }
        )
    return packages


def _latest_by_path(packages):
    latest = {}
    for pkg in packages:
        old = latest.get(pkg["path"])
        if old is None or pkg["revision"] > old["revision"]:
            latest[pkg["path"]] = pkg
    return latest


def _by_path(packages):
    by_path = {}
    for pkg in packages:
        by_path.setdefault(pkg["path"], []).append(pkg)
    for path in by_path:
        by_path[path] = sorted(by_path[path], key=lambda pkg: pkg["revision"])
    return by_path


def _single_archive(pkg):
    if len(pkg["archives"]) != 1 or pkg["archives"][0]["platform"] is not None:
        raise ValueError(
            "expected one platform-independent archive for {}".format(pkg["path"])
        )
    return pkg["archives"][0]


def _platform_archive(pkg, platform):
    candidates = [
        archive for archive in pkg["archives"] if archive["platform"] == platform
    ]
    if not candidates:
        raise ValueError("missing {} archive for {}".format(platform, pkg["path"]))
    if platform == "darwin":
        return sorted(
            candidates,
            key=lambda archive: ("aarch64" not in archive["file"], archive["file"]),
        )[0]
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
        platform: _archive_json(
            _platform_archive(pkg, platform), metadata, infer_prefix=True
        )
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


def _merge_emulator(existing_components, emulator_packages, metadata):
    existing = dict(existing_components.get("emulator", {}))
    packages_by_version = {
        _revision_name(pkg["revision"]): pkg for pkg in emulator_packages
    }

    emulator = {}
    for version, pkg in packages_by_version.items():
        emulator[version] = {"archives": _platform_archives_json(pkg, metadata)}
    for version, component in existing.items():
        emulator.setdefault(version, component)
    return dict(sorted(emulator.items(), key=lambda item: _version_key(item[0])))


def _system_image_directory(path):
    match = _SYSTEM_IMAGE_RE.fullmatch(path)
    if not match:
        raise ValueError("unsupported system image path {}".format(path))
    return "android-{}/{}".format(match.group(1), "/".join(match.groups()[1:]))


def _is_supported_system_image(pkg):
    match = _SYSTEM_IMAGE_RE.fullmatch(pkg["path"])
    if not match:
        return False
    api_level, tag, _arch = match.groups()
    if tag != "default" or not _is_supported_version(api_level, _MIN_API):
        return False
    return len(pkg["archives"]) == 1 and pkg["archives"][0]["platform"] is None


def _generate_system_images(existing_components, system_image_packages, metadata):
    system_images = {}
    for path, pkg in system_image_packages.items():
        if not _is_supported_system_image(pkg):
            continue
        directory = _system_image_directory(path)
        system_images[directory] = _archive_json(
            _single_archive(pkg),
            metadata,
            infer_prefix=True,
        )
    for directory, archive in existing_components.get("system_images", {}).items():
        system_images.setdefault(directory, archive)
    return dict(sorted(system_images.items(), key=lambda item: item[0]))


def _generate():
    metadata, existing_components = _load_existing(_OUTPUT)
    repo_packages = _parse_packages(_fetch_xml(_REPOSITORY_URL))
    repo = _latest_by_path(repo_packages)
    repo_by_path = _by_path(repo_packages)
    system_image_packages = _latest_by_path(
        _parse_packages(
            _fetch_xml(_SYSTEM_IMAGES_REPOSITORY_URL),
            file_prefix=_SYSTEM_IMAGES_FILE_PREFIX,
        )
    )

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
        "emulator": _merge_emulator(
            existing_components,
            repo_by_path.get("emulator", []),
            metadata,
        ),
        "platform_tools": {
            platform_tools_version: {
                "archives": _platform_archives_json(platform_tools_pkg, metadata),
            },
        },
        "system_images": _generate_system_images(
            existing_components,
            system_image_packages,
            metadata,
        ),
    }

    versions = {}
    for version, pkg in platforms.items():
        versions[version] = {
            "platform_tools_version": platform_tools_version,
            "platform": _archive_json(
                _single_archive(pkg), metadata, infer_prefix=False
            ),
        }

    return {"components": components, "versions": versions}


def _main():
    versions = _generate()
    with _OUTPUT.open("w") as f:
        json.dump(versions, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    _main()
