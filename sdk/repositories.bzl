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

_PLATFORMS = ANDROID_PLATFORMS

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

def _download_sdk(rctx, sdk):
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

    _download_component(
        rctx,
        url = sdk["platforms_url"],
        sha256 = sdk["platforms_sha256"],
        output = "platforms",
        strip_prefix = sdk["platforms_strip_prefix"],
    )

def _runner_script_content(rctx, name, platform, build_tools_directory, executable_extension):
    tool = "{}{}".format(name, executable_extension)
    tool_path = "build-tools/{}/{}/{}".format(platform, build_tools_directory, tool)
    libs = "build-tools/{}/{}".format(platform, build_tools_directory)

    # buildifier: disable=external-path
    return """#!/usr/bin/env bash
set -eu
repo="${{RUNFILES_DIR:-${{0}}.runfiles}}/{repo_name}"
if [[ ! -d "${{repo}}" ]]; then
  repo="$(pwd)/external/{repo_name}"
fi
tool="${{repo}}/{tool_path}"
exec env \\
  LD_LIBRARY_PATH="${{repo}}/{libs}/lib64:${{repo}}/{libs}/lib:${{LD_LIBRARY_PATH:-}}" \\
  DYLD_LIBRARY_PATH="${{repo}}/{libs}/lib64:${{repo}}/{libs}/lib:${{DYLD_LIBRARY_PATH:-}}" \\
  "${{tool}}" "$@"
""".format(
        libs = libs,
        repo_name = rctx.name,
        tool_path = tool_path,
    )

def _script_runner(name, platform, build_tools_directory):
    tool_path = "build-tools/{}/{}/{}".format(platform, build_tools_directory, name)
    return """sh_binary(
    name = "{name}_{platform}",
    srcs = ["tools/{name}_{platform}.sh"],
    data = [
        "{tool_path}",
        ":build_tools_libs_{platform}",
    ],
)
""".format(
        platform = platform,
        name = name,
        tool_path = tool_path,
    )

def _platform_tool(platform, build_tools_directory, tool):
    if platform == "windows":
        return "\"build-tools/windows/{}/{}.exe\"".format(build_tools_directory, tool)
    return "\":{}_{}\"".format(tool, platform)

def _platform_rules_for(platform, sdk):
    build_tools_directory = sdk["build_tools_directory"]
    executable_extension = _PLATFORMS[platform]["executable_extension"]
    blocks = []

    blocks.append("""filegroup(
    name = "build_tools_libs_{platform}",
    srcs = glob([
        "build-tools/{platform}/{build_tools_directory}/lib/**",
        "build-tools/{platform}/{build_tools_directory}/lib64/**",
    ], allow_empty = True),
)
""".format(
        build_tools_directory = build_tools_directory,
        platform = platform,
    ))

    if platform != "windows":
        for tool in ["aapt", "aapt2", "aidl", "dexdump", "zipalign"]:
            blocks.append(_script_runner(tool, platform, build_tools_directory))

    blocks.append("""java_binary(
    name = "apksigner_{platform}",
    main_class = "com.android.apksigner.ApkSignerTool",
    runtime_deps = ["build-tools/{platform}/{build_tools_directory}/lib/apksigner.jar"],
)
""".format(
        build_tools_directory = build_tools_directory,
        platform = platform,
    ))

    sdk_name = "sdk_{}".format(platform)
    adb = "\"platform-tools/{}/adb{}\"".format(platform, executable_extension)
    blocks.append("""android_sdk(
    name = "{sdk_name}",
    aapt = {aapt},
    aapt2 = {aapt2},
    adb = {adb},
    aidl = {aidl},
    android_jar = "platforms/android-{api_level}/android.jar",
    apksigner = ":apksigner_{platform}",
    build_tools_version = "{build_tools_version}",
    dexdump = {dexdump},
    dx = ":d8_compat_dx",
    framework_aidl = "platforms/android-{api_level}/framework.aidl",
    legacy_main_dex_list_generator = ":generate_main_dex_list",
    main_dex_classes = "build-tools/{platform}/{build_tools_directory}/mainDexClasses.rules",
    main_dex_list_creator = ":main_dex_list_creator",
    proguard = "@remote_java_tools//:proguard",
    source_properties = "platforms/android-{api_level}/source.properties",
    tags = ["__ANDROID_RULES_MIGRATION__"],
    zipalign = {zipalign},
)

android_toolchain(
    name = "android_default_{platform}",
    aapt2 = {aapt2},
    adb = {adb},
    android_archive_jar_optimization_inputs_validator = ":fail",
    android_archive_packages_validator = ":fail",
    apk_to_bundle_tool = ":fail",
    centralize_r_class_tool = ":fail",
    desugar_globals_jar = ":fail",
    merge_baseline_profiles_tool = ":fail",
    object_method_rewriter = ":fail",
    profgen = ":fail",
    proto_map_generator = ":fail",
    translation_merger = ":fail",
)
""".format(
        aapt = _platform_tool(platform, build_tools_directory, "aapt"),
        aapt2 = _platform_tool(platform, build_tools_directory, "aapt2"),
        adb = adb,
        aidl = _platform_tool(platform, build_tools_directory, "aidl"),
        api_level = sdk["api_level"],
        build_tools_directory = build_tools_directory,
        build_tools_version = sdk["build_tools_version"],
        dexdump = _platform_tool(platform, build_tools_directory, "dexdump"),
        platform = platform,
        sdk_name = sdk_name,
        zipalign = _platform_tool(platform, build_tools_directory, "zipalign"),
    ))

    for constraint_name, constraints in _PLATFORMS[platform]["constraints"]:
        local_name = constraint_name if platform == "darwin" else platform
        blocks.append("""toolchain(
    name = "sdk_{local_name}_toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":{sdk_name}",
    toolchain_type = ":sdk_toolchain_type",
)

toolchain(
    name = "rules_android_sdk_{local_name}_toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":{sdk_name}",
    toolchain_type = "@rules_android//toolchains/android_sdk:toolchain_type",
)

toolchain(
    name = "android_default_{local_name}_toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":android_default_{platform}",
    toolchain_type = "@rules_android//toolchains/android:toolchain_type",
)
""".format(
            constraints = repr(constraints),
            platform = platform,
            local_name = local_name,
            sdk_name = sdk_name,
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

alias(
    name = "legacy_test",
    actual = ":legacy_test-{api_level}",
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
    return ":{}_{}".format(tool, platform)

def _adb_alias_label(platform):
    if platform == "windows":
        return "platform-tools/windows/adb.exe"
    return "platform-tools/{}/adb".format(platform)

def _platform_select_alias(name, platforms, linux, darwin, windows):
    entries = []
    if "linux" in platforms:
        entries.append((platform_condition("linux"), linux))
    if "darwin" in platforms:
        entries.append((platform_condition("darwin"), darwin))
    if "windows" in platforms:
        entries.append((platform_condition("windows"), windows))
    return select_alias(name, entries, tags = ["manual"])

def _platform_aliases(sdk):
    platforms = sdk["platforms"]
    build_tools_directory = sdk["build_tools_directory"]
    blocks = [
        _platform_select_alias(
            "aapt",
            platforms,
            _tool_alias_label("linux", build_tools_directory, "aapt"),
            _tool_alias_label("darwin", build_tools_directory, "aapt"),
            _tool_alias_label("windows", build_tools_directory, "aapt"),
        ),
        _platform_select_alias(
            "aapt2",
            platforms,
            _tool_alias_label("linux", build_tools_directory, "aapt2"),
            _tool_alias_label("darwin", build_tools_directory, "aapt2"),
            _tool_alias_label("windows", build_tools_directory, "aapt2"),
        ),
        _platform_select_alias(
            "aapt2_binary",
            platforms,
            _tool_alias_label("linux", build_tools_directory, "aapt2"),
            _tool_alias_label("darwin", build_tools_directory, "aapt2"),
            _tool_alias_label("windows", build_tools_directory, "aapt2"),
        ),
        _platform_select_alias(
            "aidl",
            platforms,
            _tool_alias_label("linux", build_tools_directory, "aidl"),
            _tool_alias_label("darwin", build_tools_directory, "aidl"),
            _tool_alias_label("windows", build_tools_directory, "aidl"),
        ),
        _platform_select_alias(
            "adb",
            platforms,
            _adb_alias_label("linux"),
            _adb_alias_label("darwin"),
            _adb_alias_label("windows"),
        ),
        _platform_select_alias(
            "platform-tools/adb",
            platforms,
            _adb_alias_label("linux"),
            _adb_alias_label("darwin"),
            _adb_alias_label("windows"),
        ),
        _platform_select_alias(
            "apksigner",
            platforms,
            ":apksigner_linux",
            ":apksigner_darwin",
            ":apksigner_windows",
        ),
        _platform_select_alias(
            "dexdump",
            platforms,
            _tool_alias_label("linux", build_tools_directory, "dexdump"),
            _tool_alias_label("darwin", build_tools_directory, "dexdump"),
            _tool_alias_label("windows", build_tools_directory, "dexdump"),
        ),
        _platform_select_alias(
            "main_dex_classes",
            platforms,
            "build-tools/linux/{}/mainDexClasses.rules".format(build_tools_directory),
            "build-tools/darwin/{}/mainDexClasses.rules".format(build_tools_directory),
            "build-tools/windows/{}/mainDexClasses.rules".format(build_tools_directory),
        ),
        _platform_select_alias(
            "zipalign",
            platforms,
            _tool_alias_label("linux", build_tools_directory, "zipalign"),
            _tool_alias_label("darwin", build_tools_directory, "zipalign"),
            _tool_alias_label("windows", build_tools_directory, "zipalign"),
        ),
        _platform_select_alias(
            "zipalign_binary",
            platforms,
            _tool_alias_label("linux", build_tools_directory, "zipalign"),
            _tool_alias_label("darwin", build_tools_directory, "zipalign"),
            _tool_alias_label("windows", build_tools_directory, "zipalign"),
        ),
    ]
    return "\n\n".join(blocks)

def _sdk_for_platform(sdk, platform):
    if platform not in sdk["platforms"]:
        fail("Android SDK archives are not available for platform {}. Available platforms: [{}].".format(
            repr(platform),
            format_platforms(sdk["platforms"]),
        ))
    platform_sdk = dict(sdk)
    platform_sdk["platforms"] = [platform]
    return platform_sdk

def _platform_redirect_alias(rctx, sdk, name, target):
    return select_alias(name, [
        (platform_condition(platform), external_label(platform_repository(rctx, platform, "SDK"), target))
        for platform in sdk["platforms"]
    ], tags = ["manual"])

def _platform_redirect_aliases(rctx, sdk):
    blocks = [
        _platform_redirect_alias(rctx, sdk, "aapt", "aapt"),
        _platform_redirect_alias(rctx, sdk, "aapt2", "aapt2"),
        _platform_redirect_alias(rctx, sdk, "aapt2_binary", "aapt2_binary"),
        _platform_redirect_alias(rctx, sdk, "aidl", "aidl"),
        _platform_redirect_alias(rctx, sdk, "adb", "adb"),
        _platform_redirect_alias(rctx, sdk, "platform-tools/adb", "platform-tools/adb"),
        _platform_redirect_alias(rctx, sdk, "apksigner", "apksigner"),
        _platform_redirect_alias(rctx, sdk, "dexdump", "dexdump"),
        _platform_redirect_alias(rctx, sdk, "main_dex_classes", "main_dex_classes"),
        _platform_redirect_alias(rctx, sdk, "zipalign", "zipalign"),
        _platform_redirect_alias(rctx, sdk, "zipalign_binary", "zipalign_binary"),
    ]
    return "\n\n".join(blocks)

def _platform_redirect_rules_for(rctx, platform, sdk):
    repository = platform_repository(rctx, platform, "SDK")
    sdk_name = "sdk_{}".format(platform)
    build_tools_version = sdk["build_tools_version"]
    blocks = []

    blocks.append("""android_sdk(
    name = "{sdk_name}",
    aapt = "@{repository}//:aapt",
    aapt2 = "@{repository}//:aapt2",
    adb = "@{repository}//:adb",
    aidl = "@{repository}//:aidl",
    android_jar = "platforms/android-{api_level}/android.jar",
    apksigner = "@{repository}//:apksigner",
    build_tools_version = "{build_tools_version}",
    dexdump = "@{repository}//:dexdump",
    dx = ":d8_compat_dx",
    framework_aidl = "platforms/android-{api_level}/framework.aidl",
    legacy_main_dex_list_generator = ":generate_main_dex_list",
    main_dex_classes = "@{repository}//:main_dex_classes",
    main_dex_list_creator = ":main_dex_list_creator",
    proguard = "@remote_java_tools//:proguard",
    source_properties = "platforms/android-{api_level}/source.properties",
    tags = ["__ANDROID_RULES_MIGRATION__"],
    zipalign = "@{repository}//:zipalign",
)

android_toolchain(
    name = "android_default_{platform}",
    aapt2 = "@{repository}//:aapt2",
    adb = "@{repository}//:adb",
    android_archive_jar_optimization_inputs_validator = ":fail",
    android_archive_packages_validator = ":fail",
    apk_to_bundle_tool = ":fail",
    centralize_r_class_tool = ":fail",
    desugar_globals_jar = ":fail",
    merge_baseline_profiles_tool = ":fail",
    object_method_rewriter = ":fail",
    profgen = ":fail",
    proto_map_generator = ":fail",
    translation_merger = ":fail",
)
""".format(
        api_level = sdk["api_level"],
        build_tools_version = build_tools_version,
        platform = platform,
        repository = repository,
        sdk_name = sdk_name,
    ))

    for constraint_name, constraints in _PLATFORMS[platform]["constraints"]:
        local_name = constraint_name if platform == "darwin" else platform
        blocks.append("""toolchain(
    name = "sdk_{local_name}_toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":{sdk_name}",
    toolchain_type = ":sdk_toolchain_type",
)

toolchain(
    name = "rules_android_sdk_{local_name}_toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":{sdk_name}",
    toolchain_type = "@rules_android//toolchains/android_sdk:toolchain_type",
)

toolchain(
    name = "android_default_{local_name}_toolchain",
    exec_compatible_with = {constraints},
    toolchain = ":android_default_{platform}",
    toolchain_type = "@rules_android//toolchains/android:toolchain_type",
)
""".format(
            constraints = repr(constraints),
            platform = platform,
            local_name = local_name,
            sdk_name = sdk_name,
        ))

    return "\n".join(blocks)

def _platform_redirect_rules(rctx, sdk):
    return "\n".join([_platform_redirect_rules_for(rctx, platform, sdk) for platform in sdk["platforms"]])

def _write_runner_scripts(rctx, sdk):
    for platform in sdk["platforms"]:
        if platform == "windows":
            continue
        build_tools_directory = sdk["build_tools_directory"]
        executable_extension = _PLATFORMS[platform]["executable_extension"]
        for tool in ["aapt", "aapt2", "aidl", "dexdump", "zipalign"]:
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
    _download_sdk(rctx, sdk)
    _write_runner_scripts(rctx, sdk)

    rctx.symlink(Label("@rules_android//rules/android_sdk_repository:helper.bzl"), "helper.bzl")
    rctx.template(
        "BUILD.bazel",
        Label("//sdk:BUILD.androidsdk.tpl"),
        substitutions = {
            "%{api_level}": sdk["api_level"],
            "%{build_tools_directory}": sdk["build_tools_directory"],
            "%{build_tools_version}": sdk["build_tools_version"],
            "%{platform_aliases}": _platform_aliases(sdk),
            "%{platform_rules}": _platform_rules(sdk),
            "%{optional_java_imports}": _optional_java_imports(sdk["api_level"]),
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
        "platform_tools_sha256s": attr.string_dict(),
        "platform_tools_urls": attr.string_dict(),
        "platforms_sha256": attr.string(),
        "platforms_strip_prefix": attr.string(),
        "platforms_url": attr.string(),
        "platform": attr.string(mandatory = True, values = sorted(_PLATFORMS.keys())),
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
        Label("//sdk:BUILD.androidsdk.tpl"),
        substitutions = {
            "%{api_level}": sdk["api_level"],
            "%{build_tools_directory}": sdk["build_tools_directory"],
            "%{build_tools_version}": sdk["build_tools_version"],
            "%{platform_aliases}": _platform_redirect_aliases(rctx, sdk),
            "%{platform_rules}": _platform_redirect_rules(rctx, sdk),
            "%{optional_java_imports}": _optional_java_imports(sdk["api_level"]),
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
        "platform_repositories": attr.string_dict(mandatory = True),
        "platform_tools_sha256s": attr.string_dict(),
        "platform_tools_urls": attr.string_dict(),
        "platforms_sha256": attr.string(),
        "platforms_strip_prefix": attr.string(),
        "platforms_url": attr.string(),
        "version": attr.string(mandatory = True),
        "_versions_json": attr.label(
            default = Label("//sdk:versions.json"),
            allow_single_file = True,
        ),
    },
    environ = [ANDROID_SDK_LICENSE_ENV],
)
