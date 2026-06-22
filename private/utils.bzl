"""Shared helpers for Android SDK and NDK repository rules."""

ANDROID_PLATFORMS = {
    "darwin": {
        "constraints": [
            ("darwin", ["@platforms//os:macos"]),
        ],
        "executable_extension": "",
    },
    "linux": {
        "constraints": [
            ("linux", ["@platforms//os:linux", "@platforms//cpu:x86_64"]),
        ],
        "executable_extension": "",
    },
    "windows": {
        "constraints": [
            ("windows", ["@platforms//os:windows", "@platforms//cpu:x86_64"]),
        ],
        "executable_extension": ".exe",
    },
}

_PLATFORM_CONDITIONS = {
    "darwin": ":darwin_exec",
    "linux": ":linux_x86_64_exec",
    "windows": ":windows_x86_64_exec",
}

def require_license(rctx, license_env, component):
    """Fails unless the repository rule's version has been accepted."""
    value = rctx.getenv(license_env)
    if value != rctx.attr.version:
        fail("""\
Before using the hermetic Android {} toolchain you must read and accept the license for the current version. Once you have done so, add this in your '.bazelrc':

common --repo_env={}={}

Current {} value was {}.""".format(
            component,
            license_env,
            rctx.attr.version,
            license_env,
            value or "unset",
        ))

def archive_url(archive):
    """Returns a download URL from an archive metadata entry."""
    if archive.get("url"):
        return archive["url"]
    return "https://dl.google.com/android/repository/{}".format(archive["file"])

def archive_attrs(archives, include_strip_prefixes = False):
    """Splits archive metadata into URL, SHA-256, and optional strip-prefix maps.

    Args:
      archives: Archive metadata keyed by platform.
      include_strip_prefixes: Whether to return a strip-prefix map.

    Returns:
      A tuple of URL and SHA-256 maps, plus strip prefixes when requested.
    """
    urls = {}
    sha256s = {}
    strip_prefixes = {}
    for platform, archive in archives.items():
        urls[platform] = archive_url(archive)
        sha256s[platform] = archive["sha256"]
        if include_strip_prefixes and archive.get("strip_prefix"):
            strip_prefixes[platform] = archive["strip_prefix"]
    if include_strip_prefixes:
        return urls, sha256s, strip_prefixes
    return urls, sha256s

def format_platforms(platforms):
    """Formats platform names for diagnostics."""
    return ", ".join(sorted(platforms))

def check_known_platforms(values, attr_name, valid_platforms, what = ""):
    """Fails if an attribute map contains unsupported platform keys.

    Args:
      values: Attribute map keyed by platform.
      attr_name: Attribute name to use in diagnostics.
      valid_platforms: Supported platform names.
      what: Optional component name to use in diagnostics.
    """
    keys = sorted(values.keys())
    unknown = [platform for platform in keys if platform not in valid_platforms]
    if unknown:
        if what:
            fail("{} contains unsupported platforms for {}: [{}]. Expected keys from [{}].".format(
                attr_name,
                what,
                format_platforms(unknown),
                format_platforms(valid_platforms),
            ))
        fail("{} contains unsupported platforms: [{}]. Expected keys from [{}].".format(
            attr_name,
            format_platforms(unknown),
            format_platforms(valid_platforms),
        ))

def check_matching_platforms(values, attr_name, platforms, what = "", expected_attr_name = "urls"):
    """Fails if an attribute map's platform keys differ from expected platforms.

    Args:
      values: Attribute map keyed by platform.
      attr_name: Attribute name to use in diagnostics.
      platforms: Expected platform names.
      what: Optional component name to use in diagnostics.
      expected_attr_name: Attribute name that defines the expected platforms.
    """
    keys = sorted(values.keys())
    expected = sorted(platforms)
    if keys != expected:
        if what:
            fail("{} must use the same platforms as {}_urls for {}: got [{}], expected [{}].".format(
                attr_name,
                what,
                what,
                format_platforms(keys),
                format_platforms(expected),
            ))
        fail("{} must use the same platforms as {}: got [{}], expected [{}].".format(
            attr_name,
            expected_attr_name,
            format_platforms(keys),
            format_platforms(expected),
        ))

def platform_condition(platform):
    """Returns the config_setting label for an Android host platform."""
    if platform in _PLATFORM_CONDITIONS:
        return _PLATFORM_CONDITIONS[platform]
    fail("Unsupported platform {}.".format(repr(platform)))

def external_label(repository, target):
    """Returns a root target label in an external repository."""
    return "@{}//:{}".format(repository, target)

def platform_repository(rctx, platform, component):
    """Returns the configured platform repository name for a facade repository."""
    if platform not in rctx.attr.platform_repositories:
        fail("Missing platform repository for Android {} platform {}. Got [{}].".format(
            component,
            repr(platform),
            format_platforms(rctx.attr.platform_repositories.keys()),
        ))
    return rctx.attr.platform_repositories[platform]

def _string_list(values):
    return "[{}]".format(", ".join(["\"{}\"".format(value) for value in values]))

def select_alias(name, entries, tags = None):
    """Returns an alias rule string backed by a select expression.

    Args:
      name: Alias rule name.
      entries: Pairs of condition labels and selected target labels.
      tags: Optional tags for the generated alias rule.

    Returns:
      A BUILD-file fragment defining the alias.
    """
    lines = [
        "alias(",
        "    name = \"{}\",".format(name),
        "    actual = select({",
    ]
    for condition, actual in entries:
        lines.append("        \"{}\": \"{}\",".format(condition, actual))
    lines.extend([
        "    }),",
    ])
    if tags:
        lines.append("    tags = {},".format(_string_list(tags)))
    lines.append(")")
    return "\n".join(lines)
