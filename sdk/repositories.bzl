"""Repository rule for downloading a hermetic Android SDK."""

load(
    "//private:utils.bzl",
    "ANDROID_PLATFORMS",
    "archive_attrs",
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

ANDROID_SDK_LICENSE_ENV = "ACCEPTED_ANDROID_SDK_LICENSE_VERSION"

_SYSTEM_IMAGE_ARCHES = [
    "arm64-v8a",
    "armeabi-v7a",
    "x86",
    "x86_64",
]

SDK_TAG = tag_class(attrs = {
    "version": attr.string(
        doc = "Known SDK bundle version or custom SDK version identifier.",
        mandatory = True,
    ),
    "api_level": attr.string(
        doc = "Android API level to expose. Overrides the known bundle default.",
    ),
    "build_tools_version": attr.string(
        doc = "Android build-tools version.",
        mandatory = True,
    ),
    "build_tools_directory": attr.string(
        doc = "Directory name under build-tools/. Defaults to build_tools_version.",
    ),
    "build_tools_urls": attr.string_dict(
        doc = "Custom build-tools archive URLs keyed by supported platforms from linux, darwin, and windows.",
    ),
    "build_tools_sha256s": attr.string_dict(
        doc = "Custom build-tools archive SHA-256 values keyed by the same platforms as build_tools_urls.",
    ),
    "build_tools_strip_prefixes": attr.string_dict(
        doc = "Custom build-tools strip prefixes keyed by the same platforms as build_tools_urls.",
    ),
    "platform_tools_urls": attr.string_dict(
        doc = "Custom platform-tools archive URLs keyed by supported platforms from linux, darwin, and windows.",
    ),
    "platform_tools_sha256s": attr.string_dict(
        doc = "Custom platform-tools archive SHA-256 values keyed by the same platforms as platform_tools_urls.",
    ),
    "platforms_url": attr.string(
        doc = "Custom Android platform archive URL.",
    ),
    "platforms_sha256": attr.string(
        doc = "Custom Android platform archive SHA-256.",
    ),
    "platforms_strip_prefix": attr.string(
        doc = "Custom Android platform archive strip prefix.",
    ),
})

EMULATOR_TAG = tag_class(attrs = {
    "version": attr.string(
        doc = "Known Android Emulator version to download and inject into @androidsdk.",
        mandatory = True,
    ),
})

SYSTEM_IMAGE_TAG = tag_class(attrs = {
    "version": attr.string(
        doc = "Known Android default system image version to download and inject into @androidsdk, for example 28.",
        mandatory = True,
    ),
    "arch": attr.string(
        doc = "Known Android default system image architecture to download and inject into @androidsdk, for example arm64-v8a.",
        mandatory = True,
        values = _SYSTEM_IMAGE_ARCHES,
    ),
})

def _custom_platform_archives(rctx, urls, sha256s, strip_prefixes, what):
    if not urls or not sha256s:
        fail("Custom {} archives for Android SDK version {} require both {}_urls and {}_sha256s.".format(
            what,
            repr(rctx.attr.version),
            what,
            what,
        ))
    check_known_platforms(urls, "{}_urls".format(what), what = what)
    platforms = sorted(urls.keys())
    check_matching_platforms(sha256s, "{}_sha256s".format(what), platforms, what = what)
    if strip_prefixes:
        check_matching_platforms(strip_prefixes, "{}_strip_prefixes".format(what), platforms, what = what)
    return urls, sha256s, strip_prefixes, platforms

def _custom_archive_attrs(rctx):
    return (
        rctx.attr.build_tools_urls or
        rctx.attr.build_tools_sha256s or
        rctx.attr.build_tools_strip_prefixes or
        rctx.attr.platform_tools_urls or
        rctx.attr.platform_tools_sha256s or
        rctx.attr.platforms_url or
        rctx.attr.platforms_sha256 or
        rctx.attr.platforms_strip_prefix
    )

def _common_platforms(*platform_groups):
    platforms = sorted(platform_groups[0])
    for platform_group in platform_groups[1:]:
        platforms = [platform for platform in platforms if platform in platform_group]
    if not platforms:
        fail("Android SDK component archives have no platforms in common: {}.".format(
            ", ".join(["[{}]".format(format_platforms(platform_group)) for platform_group in platform_groups]),
        ))
    return platforms

def _resolve_known_sdk(rctx, data, version, known):
    components = data["components"]
    api_level = rctx.attr.api_level or version
    build_tools_version = rctx.attr.build_tools_version

    if build_tools_version not in components["build_tools"]:
        fail("Unknown Android SDK build-tools version {} for SDK version {}. Set custom archive URLs/SHA-256 values to use it.".format(
            repr(build_tools_version),
            repr(rctx.attr.version),
        ))

    platform_tools_version = known["platform_tools_version"]
    if platform_tools_version not in components["platform_tools"]:
        fail("Unknown platform-tools version {} in SDK versions metadata.".format(repr(platform_tools_version)))

    build_tools = components["build_tools"][build_tools_version]
    build_tools_urls, build_tools_sha256s, build_tools_strip_prefixes = archive_attrs(build_tools["archives"], include_strip_prefixes = True)
    build_tools_platforms = sorted(build_tools_urls.keys())

    platform_tools = components["platform_tools"][platform_tools_version]
    platform_tools_urls, platform_tools_sha256s, platform_tools_strip_prefixes = archive_attrs(platform_tools["archives"], include_strip_prefixes = True)
    platform_tools_platforms = sorted(platform_tools_urls.keys())

    platform = known["platform"]

    return {
        "api_level": api_level,
        "build_tools_directory": rctx.attr.build_tools_directory or build_tools.get("directory", build_tools_version),
        "build_tools_sha256s": build_tools_sha256s,
        "build_tools_strip_prefixes": build_tools_strip_prefixes,
        "build_tools_urls": build_tools_urls,
        "build_tools_version": build_tools_version,
        "platform_tools_sha256s": platform_tools_sha256s,
        "platform_tools_strip_prefixes": platform_tools_strip_prefixes,
        "platform_tools_urls": platform_tools_urls,
        "platforms": _common_platforms(build_tools_platforms, platform_tools_platforms),
        "platforms_sha256": platform["sha256"],
        "platforms_strip_prefix": platform.get("strip_prefix", ""),
        "platforms_url": archive_url(platform),
    }

def _resolve_custom_sdk(rctx):
    version = rctx.attr.version
    if not rctx.attr.api_level:
        fail("Custom Android SDK archives for version {} require api_level.".format(repr(version)))
    if not rctx.attr.build_tools_version:
        fail("Custom Android SDK archives for version {} require build_tools_version.".format(repr(version)))
    if not rctx.attr.platforms_url or not rctx.attr.platforms_sha256:
        fail("Custom Android SDK archives for version {} require both platforms_url and platforms_sha256.".format(repr(version)))

    build_tools_urls, build_tools_sha256s, build_tools_strip_prefixes, build_tools_platforms = _custom_platform_archives(
        rctx,
        rctx.attr.build_tools_urls,
        rctx.attr.build_tools_sha256s,
        rctx.attr.build_tools_strip_prefixes,
        "build_tools",
    )
    platform_tools_urls, platform_tools_sha256s, platform_tools_strip_prefixes, platform_tools_platforms = _custom_platform_archives(
        rctx,
        rctx.attr.platform_tools_urls,
        rctx.attr.platform_tools_sha256s,
        {},
        "platform_tools",
    )

    return {
        "api_level": rctx.attr.api_level,
        "build_tools_directory": rctx.attr.build_tools_directory or rctx.attr.build_tools_version,
        "build_tools_sha256s": build_tools_sha256s,
        "build_tools_strip_prefixes": build_tools_strip_prefixes,
        "build_tools_urls": build_tools_urls,
        "build_tools_version": rctx.attr.build_tools_version,
        "platform_tools_sha256s": platform_tools_sha256s,
        "platform_tools_strip_prefixes": platform_tools_strip_prefixes,
        "platform_tools_urls": platform_tools_urls,
        "platforms": _common_platforms(build_tools_platforms, platform_tools_platforms),
        "platforms_sha256": rctx.attr.platforms_sha256,
        "platforms_strip_prefix": rctx.attr.platforms_strip_prefix,
        "platforms_url": rctx.attr.platforms_url,
    }

def _resolve_system_images(rctx, data):
    if not rctx.attr.system_images:
        return []

    system_image_components = data["components"].get("system_images", {})
    system_images = []
    for directory in rctx.attr.system_images:
        if directory not in system_image_components:
            fail("Unknown Android system image {}. Available system images: [{}].".format(
                repr(directory),
                ", ".join(sorted(system_image_components.keys())),
            ))
        archive = system_image_components[directory]
        system_images.append({
            "directory": directory,
            "sha256": archive["sha256"],
            "strip_prefix": archive.get("strip_prefix", ""),
            "url": archive_url(archive),
        })
    return system_images

def _resolve_emulator(rctx, sdk_platforms, *, require_common_platforms):
    if not rctx.attr.emulator_version:
        return None

    versions_json = json.decode(rctx.read(rctx.attr._versions_json))
    components = versions_json["components"]
    if rctx.attr.emulator_version not in components.get("emulator", {}):
        fail("Unknown Android Emulator version {}. Add it to sdk/versions.json to use it.".format(
            repr(rctx.attr.emulator_version),
        ))
    emulator = components["emulator"][rctx.attr.emulator_version]
    emulator_urls, emulator_sha256s, emulator_strip_prefixes = archive_attrs(emulator["archives"], include_strip_prefixes = True)
    emulator_platforms = sorted(emulator_urls.keys())

    platforms = [platform for platform in sdk_platforms if platform in emulator_platforms]
    if not platforms:
        if require_common_platforms:
            fail("Android Emulator archives have no platforms in common with resolved Android SDK platforms: [{}] vs [{}].".format(
                format_platforms(emulator_platforms),
                format_platforms(sdk_platforms),
            ))
        return None

    return {
        "emulator_sha256s": emulator_sha256s,
        "emulator_strip_prefixes": emulator_strip_prefixes,
        "emulator_urls": emulator_urls,
        "emulator_version": rctx.attr.emulator_version,
        "platforms": platforms,
    }

def _resolve_sdk(rctx):
    versions_json = json.decode(rctx.read(rctx.attr._versions_json))
    versions = versions_json["versions"]
    if rctx.attr.version in versions:
        if _custom_archive_attrs(rctx):
            return _resolve_custom_sdk(rctx)
        return _resolve_known_sdk(rctx, versions_json, rctx.attr.version, versions[rctx.attr.version])
    return _resolve_custom_sdk(rctx)

def _download_component(rctx, url, sha256, output, strip_prefix = ""):
    kwargs = {
        "output": output,
        "sha256": sha256,
        "url": url,
    }
    if strip_prefix:
        kwargs["stripPrefix"] = strip_prefix
    rctx.download_and_extract(**kwargs)

def _download_sdk_platform_tools(rctx, sdk):
    for platform in sdk["platforms"]:
        if platform not in sdk["build_tools_urls"] or platform not in sdk["build_tools_sha256s"]:
            fail("Missing build-tools archive for resolved platform {}.".format(platform))
        _download_component(
            rctx,
            url = sdk["build_tools_urls"][platform],
            sha256 = sdk["build_tools_sha256s"][platform],
            output = "build-tools/{}/{}".format(platform, sdk["build_tools_directory"]),
            strip_prefix = sdk["build_tools_strip_prefixes"].get(platform, ""),
        )

        if platform not in sdk["platform_tools_urls"] or platform not in sdk["platform_tools_sha256s"]:
            fail("Missing platform-tools archive for resolved platform {}.".format(platform))
        _download_component(
            rctx,
            url = sdk["platform_tools_urls"][platform],
            sha256 = sdk["platform_tools_sha256s"][platform],
            output = "platform-tools/{}".format(platform),
            strip_prefix = sdk["platform_tools_strip_prefixes"].get(platform, ""),
        )

def _download_emulator(rctx, emulator):
    if not emulator:
        return
    if len(emulator["platforms"]) != 1:
        fail("Expected exactly one emulator platform in a platform repository, got [{}].".format(format_platforms(emulator["platforms"])))

    platform = emulator["platforms"][0]
    if platform not in emulator["emulator_urls"] or platform not in emulator["emulator_sha256s"]:
        fail("Missing emulator archive for resolved platform {}.".format(platform))
    _download_component(
        rctx,
        url = emulator["emulator_urls"][platform],
        sha256 = emulator["emulator_sha256s"][platform],
        output = "emulator",
        strip_prefix = emulator["emulator_strip_prefixes"].get(platform, ""),
    )

def _download_system_images(rctx, system_images):
    if not system_images:
        return
    for system_image in system_images:
        _download_component(
            rctx,
            url = system_image["url"],
            sha256 = system_image["sha256"],
            output = "system-images/{}".format(system_image["directory"]),
            strip_prefix = system_image["strip_prefix"],
        )

def _runner_script_content(rctx, name, platform, build_tools_directory, executable_extension):
    tool = "{}{}".format(name, executable_extension)
    tool_path = "build-tools/{}/{}/{}".format(platform, build_tools_directory, tool)
    libs = "build-tools/{}/{}".format(platform, build_tools_directory)
    if platform == "darwin":
        exec_lines = """exec "${tool}" "$@"
"""
    else:
        exec_lines = """exec env \\
  LD_LIBRARY_PATH="${{repo}}/{libs}/lib64:${{repo}}/{libs}/lib:${{LD_LIBRARY_PATH:-}}" \\
  "${{tool}}" "$@"
""".format(libs = libs)

    # buildifier: disable=external-path
    return """#!/usr/bin/env bash
set -eu
repo="${{RUNFILES_DIR:-${{0}}.runfiles}}/{repo_name}"
if [[ ! -d "${{repo}}" ]]; then
  repo="$(pwd)/external/{repo_name}"
fi
tool="${{repo}}/{tool_path}"
{exec_lines}
""".format(
        exec_lines = exec_lines,
        repo_name = rctx.name,
        tool_path = tool_path,
    )

def _script_runner(name, platform, build_tools_directory):
    executable_extension = ANDROID_PLATFORMS[platform]["executable_extension"]
    tool_path = "build-tools/{}/{}/{}{}".format(platform, build_tools_directory, name, executable_extension)
    return """sh_binary(
    name = "{name}_binary",
    srcs = ["tools/{name}_{platform}.sh"],
    data = [
        "{tool_path}",
        ":build_tools_libs",
    ],
)
""".format(
        name = name,
        platform = platform,
        tool_path = tool_path,
    )

def _platform_files(platform, sdk):
    build_tools_directory = sdk["build_tools_directory"]
    build_tools_major_version = int(sdk["build_tools_version"].split(".")[0])
    executable_extension = ANDROID_PLATFORMS[platform]["executable_extension"]
    base_srcs = [
        "build-tools/{platform}/{build_tools_directory}/lib/apksigner.jar",
        "build-tools/{platform}/{build_tools_directory}/lib/d8.jar",
        ":build_tools_libs",
        "@androidsdk//:platforms/android-{api_level}/android.jar",
        "@androidsdk//:platforms/android-{api_level}/core-for-system-modules.jar",
        "@androidsdk//:platforms/android-{api_level}/framework.aidl",
    ]
    if build_tools_major_version <= 30:
        base_srcs = [
            "build-tools/{platform}/{build_tools_directory}/lib/dx.jar",
            "build-tools/{platform}/{build_tools_directory}/mainDexClasses.rules",
        ] + base_srcs

    srcs = base_srcs + [
        "build-tools/{platform}/{build_tools_directory}/aapt{executable_extension}",
        "build-tools/{platform}/{build_tools_directory}/aapt2{executable_extension}",
        "build-tools/{platform}/{build_tools_directory}/aidl{executable_extension}",
        "build-tools/{platform}/{build_tools_directory}/dexdump{executable_extension}",
        "build-tools/{platform}/{build_tools_directory}/zipalign{executable_extension}",
        "platform-tools/{platform}/adb{executable_extension}",
    ]
    return """filegroup(
    name = "files",
    srcs = [
{srcs}
    ],
)
""".format(
        srcs = "\n".join([
            "        \"{}\",".format(src.format(
                api_level = sdk["api_level"],
                build_tools_directory = build_tools_directory,
                executable_extension = executable_extension,
                platform = platform,
            ))
            for src in srcs
        ]),
    )

def _platform_rules_for(platform, sdk):
    build_tools_directory = sdk["build_tools_directory"]
    blocks = []

    blocks.append("""filegroup(
    name = "build_tools_libs",
    srcs = glob([
        "build-tools/{platform}/{build_tools_directory}/lib/**",
        "build-tools/{platform}/{build_tools_directory}/lib64/**",
    ]),
)
""".format(
        build_tools_directory = build_tools_directory,
        platform = platform,
    ))

    blocks.append(_platform_files(platform, sdk))

    blocks.extend([
        _script_runner("aapt", platform, build_tools_directory),
        _script_runner("aapt2", platform, build_tools_directory),
        _script_runner("aidl", platform, build_tools_directory),
        _script_runner("zipalign", platform, build_tools_directory),
    ])

    blocks.append("""java_binary(
    name = "apksigner",
    main_class = "com.android.apksigner.ApkSignerTool",
    runtime_deps = ["build-tools/{platform}/{build_tools_directory}/lib/apksigner.jar"],
)
""".format(
        build_tools_directory = build_tools_directory,
        platform = platform,
    ))

    return "\n".join(blocks)

def _optional_java_imports(api_level):
    major = int(api_level.split(".")[0])
    blocks = []
    if major >= 23:
        blocks.append("""java_import(
    name = "org_apache_http_legacy-{api_level}",
    jars = ["platforms/android-{api_level}/optional/org.apache.http.legacy.jar"],
)

alias(
    name = "org_apache_http_legacy",
    actual = ":org_apache_http_legacy-{api_level}",
)
""".format(api_level = api_level))
    if major >= 28:
        blocks.append("""java_import(
    name = "legacy_test-{api_level}",
    jars = [
        "platforms/android-{api_level}/optional/android.test.base.jar",
        "platforms/android-{api_level}/optional/android.test.mock.jar",
        "platforms/android-{api_level}/optional/android.test.runner.jar",
    ],
    neverlink = True,
)
""".format(api_level = api_level))
    if major >= 29:
        blocks.append("""java_import(
    name = "android_car-{api_level}",
    jars = ["platforms/android-{api_level}/optional/android.car.jar"],
    neverlink = True,
)

alias(
    name = "android_car",
    actual = ":android_car-{api_level}",
)
""".format(api_level = api_level))
    return "\n".join(blocks)

def _platform_rules(sdk):
    return "\n".join([_platform_rules_for(platform, sdk) for platform in sdk["platforms"]])

def _tool_alias_label(platform, build_tools_directory, tool):
    if platform == "windows":
        return "build-tools/windows/{}/{}.exe".format(build_tools_directory, tool)
    if tool == "dexdump":
        return "build-tools/{}/{}/{}".format(platform, build_tools_directory, tool)
    if tool in ["aapt", "aapt2", "aidl", "zipalign"]:
        return ":{}_binary".format(tool)
    return ":{}_{}".format(tool, platform)

def _adb_alias_label(platform):
    if platform == "windows":
        return "platform-tools/windows/adb.exe"
    return "platform-tools/{}/adb".format(platform)

def _emulator_tool_label(platform, tool):
    return "emulator/{}{}".format(tool, ANDROID_PLATFORMS[platform]["executable_extension"])

def _emulator_qemu_i386_label(platform):
    extension = ANDROID_PLATFORMS[platform]["executable_extension"]
    qemu_platform = {
        "linux": "linux-x86_64",
        "windows": "windows-x86_64",
    }[platform]
    return "emulator/qemu/{}/qemu-system-i386{}".format(qemu_platform, extension)

def _plain_alias(name, actual, tags = None):
    lines = [
        "alias(",
        "    name = \"{}\",".format(name),
        "    actual = \"{}\",".format(actual),
    ]
    if tags:
        lines.append("    tags = [{}],".format(", ".join(["\"{}\"".format(tag) for tag in tags])))
    lines.append(")")
    return "\n".join(lines)

def _plain_filegroup(name, srcs_expr, tags = None):
    lines = [
        "filegroup(",
        "    name = \"{}\",".format(name),
        "    srcs = {},".format(srcs_expr),
    ]
    if tags:
        lines.append("    tags = [{}],".format(", ".join(["\"{}\"".format(tag) for tag in tags])))
    lines.append(")")
    return "\n".join(lines)

def _glob_filegroup(name, patterns, tags = None):
    lines = [
        "filegroup(",
        "    name = \"{}\",".format(name),
        "    srcs = glob({}, allow_empty = True),".format(repr(patterns)),
    ]
    if tags:
        lines.append("    tags = [{}],".format(", ".join(["\"{}\"".format(tag) for tag in tags])))
    lines.append(")")
    return "\n".join(lines)

def _qemu2_x86_srcs_expr(platform):
    emulator = _emulator_tool_label(platform, "emulator")
    if platform == "darwin":
        return repr([
            emulator,
            "emulator/qemu/darwin-aarch64/qemu-system-aarch64",
        ])
    return repr([
        emulator,
        _emulator_qemu_i386_label(platform),
    ])

def _qemu2_srcs_expr(platform):
    return "[\"{}\"] + glob([\"emulator/qemu/**\"], allow_empty = True)".format(_emulator_tool_label(platform, "emulator"))

def _platform_emulator_aliases(emulator):
    if not emulator:
        return ""
    if len(emulator["platforms"]) != 1:
        fail("Expected exactly one emulator platform for direct aliases, got [{}].".format(format_platforms(emulator["platforms"])))

    platform = emulator["platforms"][0]
    blocks = []
    for name in ["emulator", "emulator_arm", "emulator_x86"]:
        blocks.append(_plain_alias(
            name,
            _emulator_tool_label(platform, "emulator"),
            tags = ["manual"],
        ))
    blocks.extend([
        _plain_alias(
            "mksd",
            _emulator_tool_label(platform, "mksdcard"),
            tags = ["manual"],
        ),
        _glob_filegroup(
            "emulator_x86_bios",
            ["emulator/lib/pc-bios/*"],
            tags = ["manual"],
        ),
        _glob_filegroup(
            "emulator_shared_libs",
            ["emulator/lib64/**"],
            tags = ["manual"],
        ),
        _plain_filegroup(
            "qemu2_x86",
            _qemu2_x86_srcs_expr(platform),
            tags = ["manual"],
        ),
        _plain_filegroup(
            "qemu2",
            _qemu2_srcs_expr(platform),
            tags = ["manual"],
        ),
    ])
    return "\n\n".join(blocks)

def _platform_direct_aliases(platform, build_tools_directory):
    aliases = [
        _plain_alias(
            "aapt",
            _tool_alias_label(platform, build_tools_directory, "aapt"),
            tags = ["manual"],
        ),
        _plain_alias(
            "aapt2",
            _tool_alias_label(platform, build_tools_directory, "aapt2"),
            tags = ["manual"],
        ),
        _plain_alias(
            "aidl",
            _tool_alias_label(platform, build_tools_directory, "aidl"),
            tags = ["manual"],
        ),
        _plain_alias(
            "adb",
            _adb_alias_label(platform),
            tags = ["manual"],
        ),
        _plain_alias(
            "platform-tools/adb",
            _adb_alias_label(platform),
            tags = ["manual"],
        ),
        _plain_alias(
            "dexdump",
            _tool_alias_label(platform, build_tools_directory, "dexdump"),
            tags = ["manual"],
        ),
        _plain_alias(
            "main_dex_classes",
            "build-tools/{}/{}/mainDexClasses.rules".format(platform, build_tools_directory),
            tags = ["manual"],
        ),
        _plain_alias(
            "zipalign",
            _tool_alias_label(platform, build_tools_directory, "zipalign"),
            tags = ["manual"],
        ),
    ]
    return aliases

def _platform_aliases(sdk):
    platforms = sdk["platforms"]
    build_tools_directory = sdk["build_tools_directory"]
    if len(platforms) != 1:
        fail("Expected exactly one platform for Android SDK platform aliases, got [{}].".format(format_platforms(platforms)))
    return "\n\n".join(_platform_direct_aliases(platforms[0], build_tools_directory))

def _sdk_for_platform(sdk, platform):
    if platform not in sdk["platforms"]:
        fail("Android SDK archives are not available for platform {}. Available platforms: [{}].".format(
            repr(platform),
            format_platforms(sdk["platforms"]),
        ))
    platform_sdk = dict(sdk)
    platform_sdk["platforms"] = [platform]
    return platform_sdk

def _platform_redirect_alias_for_platforms(rctx, platforms, name):
    return select_alias(name, [
        (platform_condition(platform), external_label(platform_repository(rctx, platform, "SDK"), name))
        for platform in platforms
    ], tags = ["manual"])

def _platform_redirect_alias(rctx, sdk, name):
    return _platform_redirect_alias_for_platforms(rctx, sdk["platforms"], name)

def _platform_redirect_aliases(rctx, sdk):
    blocks = [
        _platform_redirect_alias(rctx, sdk, "aapt"),
        _platform_redirect_alias(rctx, sdk, "aapt_binary"),
        _platform_redirect_alias(rctx, sdk, "aapt2"),
        _platform_redirect_alias(rctx, sdk, "aapt2_binary"),
        _platform_redirect_alias(rctx, sdk, "aidl"),
        _platform_redirect_alias(rctx, sdk, "aidl_binary"),
        _platform_redirect_alias(rctx, sdk, "adb"),
        _platform_redirect_alias(rctx, sdk, "platform-tools/adb"),
        _platform_redirect_alias(rctx, sdk, "apksigner"),
        _platform_redirect_alias(rctx, sdk, "build_tools_libs"),
        _platform_redirect_alias(rctx, sdk, "dexdump"),
        _platform_redirect_alias(rctx, sdk, "files"),
        _platform_redirect_alias(rctx, sdk, "main_dex_classes"),
        _platform_redirect_alias(rctx, sdk, "zipalign"),
        _platform_redirect_alias(rctx, sdk, "zipalign_binary"),
    ]
    return "\n\n".join(blocks)

def _emulator_redirect_aliases(rctx, emulator):
    if not emulator:
        return ""
    blocks = [
        _platform_redirect_alias_for_platforms(rctx, emulator["platforms"], "emulator"),
        _platform_redirect_alias_for_platforms(rctx, emulator["platforms"], "emulator_arm"),
        _platform_redirect_alias_for_platforms(rctx, emulator["platforms"], "emulator_x86"),
        _platform_redirect_alias_for_platforms(rctx, emulator["platforms"], "emulator_shared_libs"),
        _platform_redirect_alias_for_platforms(rctx, emulator["platforms"], "emulator_x86_bios"),
        _platform_redirect_alias_for_platforms(rctx, emulator["platforms"], "mksd"),
        _platform_redirect_alias_for_platforms(rctx, emulator["platforms"], "qemu2"),
        _platform_redirect_alias_for_platforms(rctx, emulator["platforms"], "qemu2_x86"),
    ]
    return "\n\n".join(blocks)

def _system_image_dirs(system_images):
    return [
        "system-images/{}".format(system_image["directory"])
        for system_image in system_images
    ]

_SYSTEM_IMAGE_TAGS = {
    "android-tv": "tv",
    "android-wear": "wear",
    "default": "android",
    "google_apis": "google",
    "google_apis_playstore": "playstore",
}

_RULES_ANDROID_SYSTEM_IMAGE_ARCHES = {
    "armeabi-v7a": "arm",
    "x86": "x86",
}

def _system_image_target_name(directory):
    parts = directory.split("/")
    api = parts[0].split("-", 1)[1]
    tag = _SYSTEM_IMAGE_TAGS.get(parts[1])
    if not tag:
        fail("Unsupported Android system image tag directory {}.".format(repr(parts[1])))
    return "emulator_images_{}_{}_{}".format(tag, api, parts[2])

def _extra_system_image_filegroups(system_images):
    if not system_images:
        return ""
    blocks = []
    for system_image in system_images:
        directory = system_image["directory"]
        arch = directory.split("/")[-1]
        if arch in _RULES_ANDROID_SYSTEM_IMAGE_ARCHES:
            continue
        name = _system_image_target_name(directory)
        path = "system-images/{}".format(directory)
        blocks.extend([
            """filegroup(
    name = "{name}",
    srcs = glob(["{path}/**"]),
)""".format(
                name = name,
                path = path,
            ),
            """filegroup(
    name = "{name}_qemu2_extra",
    srcs = glob(["{path}/kernel-ranchu"], allow_empty = True),
)""".format(
                name = name,
                path = path,
            ),
        ])
    return "\n\n".join(blocks)

def _system_image_filegroups(system_images):
    if not system_images:
        return ""
    return """create_system_images_filegroups(
    system_image_dirs = {},
)

{}

exports_files(
    glob(["system-images/**"], allow_empty = True),
)
""".format(
        repr(_system_image_dirs(system_images)),
        _extra_system_image_filegroups(system_images),
    )

def _platform_redirect_rules_for(platform):
    blocks = []

    for constraint_name, constraints in ANDROID_PLATFORMS[platform]["constraints"]:
        local_name = constraint_name if platform == "darwin" else platform
        blocks.append("""toolchain(
    name = "sdk_{local_name}_toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":sdk",
    toolchain_type = ":sdk_toolchain_type",
)

""".format(
            constraints = repr(constraints),
            local_name = local_name,
        ))

    return "\n".join(blocks)

def _platform_redirect_rules(sdk):
    return "\n".join([_platform_redirect_rules_for(platform) for platform in sdk["platforms"]])

def _write_runner_scripts(rctx, sdk):
    for platform in sdk["platforms"]:
        build_tools_directory = sdk["build_tools_directory"]
        executable_extension = ANDROID_PLATFORMS[platform]["executable_extension"]
        for tool in ["aapt", "aapt2", "aidl", "zipalign"]:
            rctx.file(
                "tools/{}_{}.sh".format(tool, platform),
                _runner_script_content(rctx, tool, platform, build_tools_directory, executable_extension),
                executable = True,
            )

def _hermetic_android_sdk_platform_repository_impl(rctx):
    if not rctx.attr.version:
        fail("hermetic_android_sdk_platform_repository requires version.")
    if not rctx.attr.build_tools_version:
        fail("hermetic_android_sdk_platform_repository requires build_tools_version.")

    require_license(rctx, ANDROID_SDK_LICENSE_ENV, "SDK")
    sdk = _sdk_for_platform(_resolve_sdk(rctx), rctx.attr.platform)
    emulator = _resolve_emulator(rctx, sdk["platforms"], require_common_platforms = False)
    _download_sdk_platform_tools(rctx, sdk)
    _download_emulator(rctx, emulator)
    _write_runner_scripts(rctx, sdk)

    rctx.template(
        "BUILD.bazel",
        Label("//sdk:BUILD.androidsdk.tpl"),
        substitutions = {
            "%{emulator_aliases}": _platform_emulator_aliases(emulator),
            "%{platform_aliases}": _platform_aliases(sdk),
            "%{platform_rules}": _platform_rules(sdk),
        },
    )

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

hermetic_android_sdk_platform_repository = repository_rule(
    implementation = _hermetic_android_sdk_platform_repository_impl,
    attrs = {
        "api_level": attr.string(),
        "build_tools_directory": attr.string(),
        "build_tools_sha256s": attr.string_dict(),
        "build_tools_strip_prefixes": attr.string_dict(),
        "build_tools_urls": attr.string_dict(),
        "build_tools_version": attr.string(mandatory = True),
        "emulator_version": attr.string(),
        "platform_tools_sha256s": attr.string_dict(),
        "platform_tools_urls": attr.string_dict(),
        "platforms_sha256": attr.string(),
        "platforms_strip_prefix": attr.string(),
        "platforms_url": attr.string(),
        "system_images": attr.string_list(),
        "platform": attr.string(mandatory = True, values = sorted(ANDROID_PLATFORMS.keys())),
        "version": attr.string(mandatory = True),
        "_versions_json": attr.label(
            default = Label("//sdk:versions.json"),
            allow_single_file = True,
        ),
    },
    environ = [ANDROID_SDK_LICENSE_ENV],
)

def _hermetic_android_sdk_repository_impl(rctx):
    if not rctx.attr.version:
        fail("hermetic_android_sdk_repository requires version.")
    if not rctx.attr.build_tools_version:
        fail("hermetic_android_sdk_repository requires build_tools_version.")

    require_license(rctx, ANDROID_SDK_LICENSE_ENV, "SDK")
    sdk = _resolve_sdk(rctx)
    emulator = _resolve_emulator(rctx, sdk["platforms"], require_common_platforms = True)
    versions_json = json.decode(rctx.read(rctx.attr._versions_json))
    system_images = _resolve_system_images(rctx, versions_json)
    _download_system_images(rctx, system_images)
    _download_component(
        rctx,
        url = sdk["platforms_url"],
        sha256 = sdk["platforms_sha256"],
        output = "platforms",
        strip_prefix = sdk["platforms_strip_prefix"],
    )

    rctx.symlink(Label("@rules_android//rules/android_sdk_repository:helper.bzl"), "helper.bzl")
    rctx.template(
        "BUILD.bazel",
        Label("//sdk:BUILD.sdkredirect.tpl"),
        substitutions = {
            "%{api_level}": sdk["api_level"],
            "%{build_tools_directory}": sdk["build_tools_directory"],
            "%{build_tools_version}": sdk["build_tools_version"],
            "%{emulator_aliases}": _emulator_redirect_aliases(rctx, emulator),
            "%{platform_aliases}": _platform_redirect_aliases(rctx, sdk),
            "%{platform_rules}": _platform_redirect_rules(sdk),
            "%{optional_java_imports}": _optional_java_imports(sdk["api_level"]),
            "%{system_image_filegroups}": _system_image_filegroups(system_images),
        },
    )

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

hermetic_android_sdk_repository = repository_rule(
    implementation = _hermetic_android_sdk_repository_impl,
    attrs = {
        "api_level": attr.string(),
        "build_tools_directory": attr.string(),
        "build_tools_sha256s": attr.string_dict(),
        "build_tools_strip_prefixes": attr.string_dict(),
        "build_tools_urls": attr.string_dict(),
        "build_tools_version": attr.string(mandatory = True),
        "emulator_version": attr.string(),
        "platform_repositories": attr.string_dict(mandatory = True),
        "platform_tools_sha256s": attr.string_dict(),
        "platform_tools_urls": attr.string_dict(),
        "platforms_sha256": attr.string(),
        "platforms_strip_prefix": attr.string(),
        "platforms_url": attr.string(),
        "system_images": attr.string_list(),
        "version": attr.string(mandatory = True),
        "_versions_json": attr.label(
            default = Label("//sdk:versions.json"),
            allow_single_file = True,
        ),
    },
    environ = [ANDROID_SDK_LICENSE_ENV],
)
