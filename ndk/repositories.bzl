"""Repository rule for downloading a hermetic Android NDK."""

load(
    "//private:utils.bzl",
    "ANDROID_PLATFORMS",
    "archive_url",
    "check_known_platforms",
    "check_matching_platforms",
    "external_label",
    "format_platforms",
    "platform_condition",
    "platform_repository",
    "require_license",
    "select_alias",
)

ANDROID_NDK_LICENSE_ENV = "ACCEPTED_ANDROID_NDK_LICENSE_VERSION"

# TODO: When rules_android_ndk releases, import their default
_DEFAULT_API_LEVEL = 31

NDK_TAG = tag_class(attrs = {
    "version": attr.string(
        doc = "Known NDK version.",
        mandatory = True,
    ),
    "api_level": attr.int(
        doc = "Minimum Android API level for the NDK C/C++ toolchains. Defaults to {}.".format(_DEFAULT_API_LEVEL),
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

_CLANG_DIRECTORIES = {
    "darwin": "toolchains/llvm/prebuilt/darwin-x86_64",
    "linux": "toolchains/llvm/prebuilt/linux-x86_64",
    "windows": "toolchains/llvm/prebuilt/windows-x86_64",
}

def _platforms():
    platforms = {}
    for platform, metadata in ANDROID_PLATFORMS.items():
        platform_metadata = dict(metadata)
        platform_metadata["clang_directory"] = _CLANG_DIRECTORIES[platform]
        platforms[platform] = platform_metadata
    return platforms

_PLATFORMS = _platforms()

def _custom_archives(rctx):
    if not rctx.attr.urls or not rctx.attr.sha256s:
        fail("Custom Android NDK archives for version {} require both urls and sha256s.".format(repr(rctx.attr.version)))
    if not rctx.attr.strip_prefix:
        fail("Custom Android NDK archives for version {} require strip_prefix.".format(repr(rctx.attr.version)))
    check_known_platforms(rctx.attr.urls, "urls")
    platforms = sorted(rctx.attr.urls.keys())
    check_matching_platforms(rctx.attr.sha256s, "sha256s", platforms)
    return {
        "integrities": {},
        "platforms": platforms,
        "sha256s": rctx.attr.sha256s,
        "strip_prefix": rctx.attr.strip_prefix,
        "urls": rctx.attr.urls,
    }

def _known_archive_attrs(archives):
    urls = {}
    sha256s = {}
    integrities = {}
    for platform, archive in archives.items():
        urls[platform] = archive_url(archive)
        if archive.get("integrity"):
            integrities[platform] = archive["integrity"]
        elif archive.get("sha256"):
            sha256s[platform] = archive["sha256"]
        else:
            fail("Missing checksum for NDK archive {}.".format(archive.get("file", platform)))
    return urls, sha256s, integrities

def _resolve_ndk(rctx):
    versions_json = json.decode(rctx.read(rctx.attr._versions_json))
    api_level = rctx.attr.api_level or _DEFAULT_API_LEVEL
    custom_archives = rctx.attr.urls or rctx.attr.sha256s or rctx.attr.strip_prefix
    versions = versions_json["versions"]
    aliases = versions_json.get("aliases", {})
    if custom_archives:
        ndk = _custom_archives(rctx)
    elif rctx.attr.version in versions or rctx.attr.version in aliases:
        version = aliases.get(rctx.attr.version, rctx.attr.version)
        if version not in versions:
            fail("Android NDK alias {} resolves to unknown version {}.".format(repr(rctx.attr.version), repr(version)))
        known = versions[version]
        urls, sha256s, integrities = _known_archive_attrs(known["archives"])
        ndk = {
            "integrities": integrities,
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
        if platform not in ndk["urls"]:
            fail("Missing NDK archive for resolved platform {}.".format(platform))
        kwargs = {
            "url": ndk["urls"][platform],
            "stripPrefix": ndk["strip_prefix"],
        }
        if platform in ndk.get("integrities", {}):
            kwargs["integrity"] = ndk["integrities"][platform]
        elif platform in ndk["sha256s"]:
            kwargs["sha256"] = ndk["sha256s"][platform]
        else:
            fail("Missing NDK archive checksum for resolved platform {}.".format(platform))
        rctx.download_and_extract(**kwargs)

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
            format_platforms(ndk["platforms"]),
        ))
    platform_ndk = dict(ndk)
    platform_ndk["platforms"] = [platform]
    return platform_ndk

def _platform_redirect_alias(rctx, ndk, name, target):
    return select_alias(name, [
        (platform_condition(platform), external_label(platform_repository(rctx, platform, "NDK"), target))
        for platform in ndk["platforms"]
    ])

def _platform_redirect_toolchains(rctx, ndk):
    toolchains = []
    for platform in ndk["platforms"]:
        repository = platform_repository(rctx, platform, "NDK")
        clang_directory = _PLATFORMS[platform]["clang_directory"]
        toolchain_pattern = "@{}//{}:cc_toolchain_{{}}".format(repository, clang_directory)
        for name, constraints in _PLATFORMS[platform]["constraints"]:
            toolchains.append((name, toolchain_pattern, constraints))
    return repr(toolchains)

def _platform_redirect_toolchain_suite_alias(rctx, ndk):
    return select_alias("toolchain", [
        (
            platform_condition(platform),
            "@{}//{}:cc_toolchain_suite".format(
                platform_repository(rctx, platform, "NDK"),
                _PLATFORMS[platform]["clang_directory"],
            ),
        )
        for platform in ndk["platforms"]
    ])

def _platform_redirect_build_file_content(rctx, ndk):
    aliases = [
        _platform_redirect_toolchain_suite_alias(rctx, ndk),
        _platform_redirect_alias(rctx, ndk, "cpufeatures", "cpufeatures"),
        _platform_redirect_alias(rctx, ndk, "native_app_glue", "native_app_glue"),
        _platform_redirect_alias(rctx, ndk, "sources/android/native_app_glue/android_native_app_glue.h", "sources/android/native_app_glue/android_native_app_glue.h"),
    ]
    return """\"\"\"Generated Android NDK platform redirect repository.\"\"\"

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

    require_license(rctx, ANDROID_NDK_LICENSE_ENV, "NDK")
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
        "platform": attr.string(mandatory = True, values = sorted(_PLATFORMS.keys())),
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
            default = Label("//ndk:versions.json"),
            allow_single_file = True,
        ),
    },
    environ = [ANDROID_NDK_LICENSE_ENV],
)

def _hermetic_android_ndk_repository_impl(rctx):
    if not rctx.attr.version:
        fail("hermetic_android_ndk_repository requires version.")

    require_license(rctx, ANDROID_NDK_LICENSE_ENV, "NDK")
    ndk = _resolve_ndk(rctx)

    rctx.file(
        "platform_toolchains.bzl",
        "PLATFORM_TOOLCHAINS = {}\n".format(_platform_redirect_toolchains(rctx, ndk)),
    )
    rctx.file("BUILD.bazel", _platform_redirect_build_file_content(rctx, ndk))
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
            default = Label("//ndk:versions.json"),
            allow_single_file = True,
        ),
    },
    environ = [ANDROID_NDK_LICENSE_ENV],
)
