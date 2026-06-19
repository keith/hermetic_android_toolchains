"""Repository rule for downloading a hermetic Android NDK."""

load("//ndk:versions.bzl", "DEFAULT_API_LEVEL", "NDK_VERSIONS")

ANDROID_NDK_LICENSE_ENV = "ACCEPTED_ANDROID_NDK_LICENSE_VERSION"

NDK_TAG = tag_class(attrs = {
    "version": attr.string(
        doc = "Known NDK version.",
        mandatory = True,
    ),
    "api_level": attr.int(
        doc = "Minimum Android API level for the NDK C/C++ toolchains. Defaults to {}.".format(DEFAULT_API_LEVEL),
    ),
    "urls": attr.string_dict(
        doc = "Custom NDK archive URLs keyed by supported platforms from linux, darwin, and windows.",
    ),
    "sha256s": attr.string_dict(
        doc = "Custom NDK archive SHA-256 values keyed by the same platforms as urls.",
    ),
    "strip_prefix": attr.string(
        doc = "Custom NDK archive strip prefix. Defaults to android-ndk-<version>.",
    ),
})

_PLATFORMS = {
    "darwin": {
        "clang_directory": "toolchains/llvm/prebuilt/darwin-x86_64",
        "constraints": [
            ("darwin", ["@platforms//os:macos"]),
        ],
        "executable_extension": "",
    },
    "linux": {
        "clang_directory": "toolchains/llvm/prebuilt/linux-x86_64",
        "constraints": [
            ("linux", ["@platforms//os:linux", "@platforms//cpu:x86_64"]),
        ],
        "executable_extension": "",
    },
    "windows": {
        "clang_directory": "toolchains/llvm/prebuilt/windows-x86_64",
        "constraints": [
            ("windows", ["@platforms//os:windows", "@platforms//cpu:x86_64"]),
        ],
        "executable_extension": ".exe",
    },
}

NDK_PLATFORMS = sorted(_PLATFORMS.keys())

def _require_license(rctx):
    value = rctx.getenv(ANDROID_NDK_LICENSE_ENV)
    if value != rctx.attr.version:
        fail("""\
Before using the hermetic Android NDK toolchain you must read and accept the license for the current version. Once you have done so, add this in your '.bazelrc':

common --repo_env={}={}

Current {} value was {}.""".format(
            ANDROID_NDK_LICENSE_ENV,
            rctx.attr.version,
            ANDROID_NDK_LICENSE_ENV,
            value or "unset",
        ))

def _archive_url(archive):
    if archive.get("url"):
        return archive["url"]
    return "https://dl.google.com/android/repository/{}".format(archive["file"])

def _archive_attrs(archives):
    urls = {}
    sha256s = {}
    for platform, archive in archives.items():
        urls[platform] = _archive_url(archive)
        sha256s[platform] = archive["sha256"]
    return urls, sha256s

def _format_platforms(platforms):
    return ", ".join(sorted(platforms))

def _check_known_platforms(values, attr_name):
    keys = sorted(values.keys())
    unknown = [platform for platform in keys if platform not in _PLATFORMS]
    if unknown:
        fail("{} contains unsupported platforms: [{}]. Expected keys from [{}].".format(
            attr_name,
            _format_platforms(unknown),
            _format_platforms(_PLATFORMS.keys()),
        ))

def _check_matching_platforms(values, attr_name, platforms):
    keys = sorted(values.keys())
    expected = sorted(platforms)
    if keys != expected:
        fail("{} must use the same platforms as urls: got [{}], expected [{}].".format(
            attr_name,
            _format_platforms(keys),
            _format_platforms(expected),
        ))

def _custom_archives(rctx):
    if not rctx.attr.urls or not rctx.attr.sha256s:
        fail("Custom Android NDK archives for version {} require both urls and sha256s.".format(repr(rctx.attr.version)))
    if not rctx.attr.strip_prefix:
        fail("Custom Android NDK archives for version {} require strip_prefix.".format(repr(rctx.attr.version)))
    _check_known_platforms(rctx.attr.urls, "urls")
    platforms = sorted(rctx.attr.urls.keys())
    _check_matching_platforms(rctx.attr.sha256s, "sha256s", platforms)
    return {
        "platforms": platforms,
        "sha256s": rctx.attr.sha256s,
        "strip_prefix": rctx.attr.strip_prefix,
        "urls": rctx.attr.urls,
    }

def _resolve_ndk(rctx):
    versions_json = json.decode(rctx.read(rctx.attr._versions_json))
    api_level = rctx.attr.api_level or DEFAULT_API_LEVEL
    custom_archives = rctx.attr.urls or rctx.attr.sha256s or rctx.attr.strip_prefix
    versions = versions_json["versions"]
    if custom_archives:
        ndk = _custom_archives(rctx)
    elif rctx.attr.version in versions:
        known = versions[rctx.attr.version]
        urls, sha256s = _archive_attrs(known["archives"])
        ndk = {
            "platforms": sorted(urls.keys()),
            "sha256s": sha256s,
            "strip_prefix": known.get("strip_prefix", "android-ndk-{}".format(rctx.attr.version)),
            "urls": urls,
        }
    else:
        fail("Unknown Android NDK version {}. Set custom urls, sha256s, and strip_prefix.".format(repr(rctx.attr.version)))
    ndk["api_level"] = api_level
    return ndk

def _download_ndk(rctx, ndk):
    for platform in ndk["platforms"]:
        if platform not in ndk["urls"] or platform not in ndk["sha256s"]:
            fail("Missing NDK archive for resolved platform {}.".format(platform))
        rctx.download_and_extract(
            url = ndk["urls"][platform],
            sha256 = ndk["sha256s"][platform],
            stripPrefix = ndk["strip_prefix"],
        )

def _clang_resource_dir(rctx, clang_directory):
    for parent in ["lib/clang", "lib64/clang"]:
        clang_lib = rctx.path("{}/{}".format(clang_directory, parent))
        if not clang_lib.exists:
            continue
        versions = sorted([path.basename for path in clang_lib.readdir()])
        if not versions:
            fail("Could not find clang resource directory under {}.".format(clang_lib))
        if len(versions) > 1:
            fail("Expected one clang resource directory under {}, found {}.".format(clang_lib, versions))
        return "{}/{}".format(parent, versions[0])
    fail("Could not find clang resource directory under {}.".format(clang_directory))

def _platform_toolchains(platforms):
    toolchains = []
    for platform in platforms:
        clang_directory = _PLATFORMS[platform]["clang_directory"]
        for name, constraints in _PLATFORMS[platform]["constraints"]:
            toolchains.append((name, clang_directory, constraints))
    return repr(toolchains)

def _ndk_for_platform(ndk, platform):
    if platform not in ndk["platforms"]:
        fail("Android NDK archives are not available for platform {}. Available platforms: [{}].".format(
            repr(platform),
            _format_platforms(ndk["platforms"]),
        ))
    platform_ndk = dict(ndk)
    platform_ndk["platforms"] = [platform]
    return platform_ndk

def _platform_condition(platform):
    if platform == "linux":
        return ":linux_x86_64_exec"
    if platform == "darwin":
        return ":darwin_exec"
    if platform == "windows":
        return ":windows_x86_64_exec"
    fail("Unsupported platform {}.".format(repr(platform)))

def _external_label(repository, target):
    return "@{}//:{}".format(repository, target)

def _platform_repository(rctx, platform):
    if platform not in rctx.attr.platform_repositories:
        fail("Missing platform repository for Android NDK platform {}. Got [{}].".format(
            repr(platform),
            _format_platforms(rctx.attr.platform_repositories.keys()),
        ))
    return rctx.attr.platform_repositories[platform]

def _select_alias(name, entries):
    lines = [
        "alias(",
        "    name = \"{}\",".format(name),
        "    actual = select({",
    ]
    for condition, actual in entries:
        lines.append("        \"{}\": \"{}\",".format(condition, actual))
    lines.extend([
        "    }),",
        ")",
    ])
    return "\n".join(lines)

def _facade_ndk_select_alias(rctx, ndk, name, target):
    return _select_alias(name, [
        (_platform_condition(platform), _external_label(_platform_repository(rctx, platform), target))
        for platform in ndk["platforms"]
    ])

def _facade_platform_toolchains(rctx, ndk):
    toolchains = []
    for platform in ndk["platforms"]:
        repository = _platform_repository(rctx, platform)
        clang_directory = _PLATFORMS[platform]["clang_directory"]
        toolchain_pattern = "@{}//{}:cc_toolchain_{{}}".format(repository, clang_directory)
        for name, constraints in _PLATFORMS[platform]["constraints"]:
            toolchains.append((name, toolchain_pattern, constraints))
    return repr(toolchains)

def _facade_toolchain_suite_alias(rctx, ndk):
    return _select_alias("toolchain", [
        (
            _platform_condition(platform),
            "@{}//{}:cc_toolchain_suite".format(
                _platform_repository(rctx, platform),
                _PLATFORMS[platform]["clang_directory"],
            ),
        )
        for platform in ndk["platforms"]
    ])

def _facade_build_file_content(rctx, ndk):
    aliases = [
        _facade_toolchain_suite_alias(rctx, ndk),
        _facade_ndk_select_alias(rctx, ndk, "cpufeatures", "cpufeatures"),
        _facade_ndk_select_alias(rctx, ndk, "native_app_glue", "native_app_glue"),
        _facade_ndk_select_alias(rctx, ndk, "sources/android/native_app_glue/android_native_app_glue.h", "sources/android/native_app_glue/android_native_app_glue.h"),
    ]
    return """\"\"\"Generated Android NDK facade repository.\"\"\"

load("//:platform_toolchains.bzl", "PLATFORM_TOOLCHAINS")
load("//:target_systems.bzl", "CPU_CONSTRAINT", "TARGET_SYSTEM_NAMES")

package(default_visibility = ["//visibility:public"])

[
    toolchain(
        name = "toolchain_{{}}_{{}}".format(platform_name, target_system_name),
        exec_compatible_with = exec_compatible_with,
        target_compatible_with = [
            "@platforms//os:android",
            CPU_CONSTRAINT[target_system_name],
        ],
        toolchain = toolchain_pattern.format(target_system_name),
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )
    for platform_name, toolchain_pattern, exec_compatible_with in PLATFORM_TOOLCHAINS
    for target_system_name in TARGET_SYSTEM_NAMES
]

{aliases}
""".format(aliases = "\n\n".join(aliases))

def _generate_platform_build_files(rctx, ndk):
    repository_name = rctx.attr._rules_android_ndk_build.workspace_name
    for platform in ndk["platforms"]:
        clang_directory = _PLATFORMS[platform]["clang_directory"]
        sysroot_directory = "{}/sysroot".format(clang_directory)
        executable_extension = _PLATFORMS[platform]["executable_extension"]
        clang_resource_directory = _clang_resource_dir(rctx, clang_directory)

        rctx.template(
            "{}/BUILD.bazel".format(clang_directory),
            rctx.attr._template_ndk_clang,
            {
                "{api_level}": str(ndk["api_level"]),
                "{clang_resource_directory}": clang_resource_directory,
                "{executable_extension}": executable_extension,
                "{repository_name}": repository_name,
                "{sysroot_directory}": sysroot_directory,
            },
        )

        rctx.template(
            "{}/BUILD.bazel".format(sysroot_directory),
            rctx.attr._template_ndk_sysroot,
            {
                "{api_level}": str(ndk["api_level"]),
            },
        )

def _hermetic_android_ndk_platform_repository_impl(rctx):
    if not rctx.attr.version:
        fail("hermetic_android_ndk_platform_repository requires version.")

    _require_license(rctx)
    ndk = _ndk_for_platform(_resolve_ndk(rctx), rctx.attr.platform)
    _download_ndk(rctx, ndk)

    rctx.file("ndk/.keep", "")
    rctx.symlink(rctx.path("sources"), "ndk/sources")
    rctx.file(
        "platform_toolchains.bzl",
        "PLATFORM_TOOLCHAINS = {}\n".format(_platform_toolchains(ndk["platforms"])),
    )
    rctx.symlink(Label("//ndk:BUILD.androidndk.bazel"), "BUILD.bazel")
    rctx.template(
        "target_systems.bzl",
        rctx.attr._template_target_systems,
        {},
    )
    _generate_platform_build_files(rctx, ndk)

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

hermetic_android_ndk_platform_repository = repository_rule(
    implementation = _hermetic_android_ndk_platform_repository_impl,
    attrs = {
        "api_level": attr.int(),
        "platform": attr.string(mandatory = True, values = NDK_PLATFORMS),
        "sha256s": attr.string_dict(),
        "strip_prefix": attr.string(),
        "urls": attr.string_dict(),
        "version": attr.string(mandatory = True),
        "_rules_android_ndk_build": attr.label(
            default = Label("@rules_android_ndk//:BUILD"),
            allow_single_file = True,
        ),
        "_template_ndk_clang": attr.label(
            default = Label("@rules_android_ndk//:BUILD.ndk_clang.tpl"),
            allow_single_file = True,
        ),
        "_template_ndk_sysroot": attr.label(
            default = Label("@rules_android_ndk//:BUILD.ndk_sysroot.tpl"),
            allow_single_file = True,
        ),
        "_template_target_systems": attr.label(
            default = Label("@rules_android_ndk//:target_systems.bzl.tpl"),
            allow_single_file = True,
        ),
        "_versions_json": attr.label(
            default = NDK_VERSIONS,
            allow_single_file = True,
        ),
    },
    environ = [ANDROID_NDK_LICENSE_ENV],
)

def _hermetic_android_ndk_repository_impl(rctx):
    if not rctx.attr.version:
        fail("hermetic_android_ndk_repository requires version.")

    _require_license(rctx)
    ndk = _resolve_ndk(rctx)

    rctx.file(
        "platform_toolchains.bzl",
        "PLATFORM_TOOLCHAINS = {}\n".format(_facade_platform_toolchains(rctx, ndk)),
    )
    rctx.file("BUILD.bazel", _facade_build_file_content(rctx, ndk))
    rctx.template(
        "target_systems.bzl",
        rctx.attr._template_target_systems,
        {},
    )

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

hermetic_android_ndk_repository = repository_rule(
    implementation = _hermetic_android_ndk_repository_impl,
    attrs = {
        "api_level": attr.int(),
        "platform_repositories": attr.string_dict(mandatory = True),
        "sha256s": attr.string_dict(),
        "strip_prefix": attr.string(),
        "urls": attr.string_dict(),
        "version": attr.string(mandatory = True),
        "_template_target_systems": attr.label(
            default = Label("@rules_android_ndk//:target_systems.bzl.tpl"),
            allow_single_file = True,
        ),
        "_versions_json": attr.label(
            default = NDK_VERSIONS,
            allow_single_file = True,
        ),
    },
    environ = [ANDROID_NDK_LICENSE_ENV],
)
