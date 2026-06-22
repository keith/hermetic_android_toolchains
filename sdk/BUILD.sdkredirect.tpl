"""Generated Android SDK redirect repository."""

load(
    ":helper.bzl",
    "string_flag",
)
load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")
load("@rules_android//rules:rules.bzl", "android_sdk")
load("@rules_java//java:defs.bzl", "java_binary", "java_import")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//visibility:public"])

exports_files([
    "platforms/android-%{api_level}/android.jar",
    "platforms/android-%{api_level}/core-for-system-modules.jar",
    "platforms/android-%{api_level}/framework.aidl",
])

toolchain_type(name = "sdk_toolchain_type")

config_feature_flag(
    name = "true",
    allowed_values = [
        "true",
        "false",
    ],
    default_value = "true",
    visibility = ["//visibility:private"],
)

config_setting(
    name = "always_true",
    flag_values = {":true": "true"},
    visibility = ["//visibility:private"],
)

config_setting(
    name = "dx_standalone_dexer",
    values = {"define": "android_standalone_dexing_tool=dx_compat_dx"},
)

bool_flag(
    name = "allow_proguard",
    build_setting_default = True,
)

config_setting(
    name = "disallow_proguard",
    flag_values = {":allow_proguard": "false"},
)

config_setting(
    name = "api_%{api_level}_enabled",
    flag_values = {
        ":api_level": "%{api_level}",
    },
)

string_flag(
    name = "api_level",
    build_setting_default = "%{api_level}",
    values = ["%{api_level}"],
    visibility = ["//visibility:public"],
)

alias(
    name = "has_androidsdk",
    actual = ":always_true",
)

%{optional_java_imports}

java_import(
    name = "core-for-system-modules-jar",
    jars = ["platforms/android-%{api_level}/core-for-system-modules.jar"],
)

java_binary(
    name = "d8_compat_dx",
    main_class = "com.google.devtools.build.android.r8.CompatDx",
    runtime_deps = [
        "@rules_android//src/tools/java/com/google/devtools/build/android/r8",
    ],
)

java_binary(
    name = "generate_main_dex_list",
    jvm_flags = [
        "-XX:+TieredCompilation",
        "-XX:TieredStopAtLevel=1",
        "-Xms8g",
        "-Xmx8g",
    ],
    main_class = "com.android.tools.r8.GenerateMainDexList",
    runtime_deps = [
        "@rules_android//src/tools/java/com/google/devtools/build/android/r8",
    ],
)

genrule(
    name = "main_dex_list_creator_source",
    outs = ["main_dex_list_creator.sh"],
    cmd = "\n".join([
        "cat > $@ <<'EOF'",
        "#!/usr/bin/env bash",
        "echo main_dex_list_creator should not be used anymore.",
        "exit 1",
        "EOF",
    ]),
    executable = True,
)

sh_binary(
    name = "main_dex_list_creator",
    srcs = [":main_dex_list_creator_source"],
)

genrule(
    name = "generate_fail_sh",
    outs = ["fail.sh"],
    cmd = "printf '#!/usr/bin/env bash\\nexit 1\\n' > $@",
    executable = True,
)

sh_binary(
    name = "bash_fail",
    srcs = [":generate_fail_sh"],
)

genrule(
    name = "generate_fail_cmd",
    outs = ["fail.cmd"],
    cmd = "echo @exit /b 1 > $@",
    executable = True,
)

sh_binary(
    name = "windows_fail.cmd",
    srcs = [":generate_fail_cmd"],
)

alias(
    name = "fail",
    actual = select({
        "@platforms//os:windows": ":windows_fail.cmd",
        "//conditions:default": ":bash_fail",
    }),
)

%{platform_rules}

%{platform_aliases}

android_sdk(
    name = "sdk",
    aapt = select({
        "@platforms//os:windows": ":aapt",
        "//conditions:default": ":aapt_binary",
    }),
    aapt2 = ":aapt2",
    adb = select({
        "@platforms//os:windows": ":adb",
        "//conditions:default": ":platform-tools/adb",
    }),
    aidl = select({
        "@platforms//os:windows": ":aidl",
        "//conditions:default": ":aidl_binary",
    }),
    android_jar = "platforms/android-%{api_level}/android.jar",
    apksigner = ":apksigner",
    build_tools_version = "%{build_tools_version}",
    dexdump = ":dexdump",
    dx = select({
        ":dx_standalone_dexer": ":fail",
        "//conditions:default": ":d8_compat_dx",
    }),
    framework_aidl = "platforms/android-%{api_level}/framework.aidl",
    legacy_main_dex_list_generator = ":generate_main_dex_list",
    main_dex_classes = ":main_dex_classes",
    main_dex_list_creator = ":main_dex_list_creator",
    proguard = select({
        ":disallow_proguard": ":fail",
        "//conditions:default": "@remote_java_tools//:proguard",
    }),
    source_properties = "platforms/android-%{api_level}/source.properties",
    tags = [
        "__ANDROID_RULES_MIGRATION__",
        "manual",
    ],
    zipalign = ":zipalign",
)

# Exists for backwards compatibility with MODULE.bazel register_toolchains copied from rules_android
toolchain(
    name = "sdk-toolchain",
    tags = ["manual"],
    target_compatible_with = ["@platforms//:incompatible"],
    toolchain = ":fail",
    toolchain_type = ":sdk_toolchain_type",
)
