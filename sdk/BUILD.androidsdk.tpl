"""Generated Android SDK repository."""

load(
    ":helper.bzl",
    "create_system_images_filegroups",
    "string_flag",
)
load("@rules_android//rules:rules.bzl", "android_sdk")
load("@rules_android//toolchains/android:toolchain.bzl", "android_toolchain")
load("@rules_java//java:defs.bzl", "java_binary", "java_import")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//visibility:public"])

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
    flag_values = {
        ":true": "true",
    },
    visibility = ["//visibility:private"],
)

config_setting(
    name = "linux_x86_64_exec",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    visibility = ["//visibility:private"],
)

config_setting(
    name = "darwin_exec",
    constraint_values = [
        "@platforms//os:macos",
    ],
    visibility = ["//visibility:private"],
)

config_setting(
    name = "windows_x86_64_exec",
    constraint_values = [
        "@platforms//os:windows",
        "@platforms//cpu:x86_64",
    ],
    visibility = ["//visibility:private"],
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
        ":windows_x86_64_exec": ":windows_fail.cmd",
        "//conditions:default": ":bash_fail",
    }),
)

%{platform_rules}

%{platform_aliases}

android_sdk(
    name = "sdk",
    aapt = ":aapt",
    aapt2 = ":aapt2",
    adb = ":adb",
    aidl = ":aidl",
    android_jar = "platforms/android-%{api_level}/android.jar",
    apksigner = ":apksigner",
    build_tools_version = "%{build_tools_version}",
    dexdump = ":dexdump",
    dx = ":d8_compat_dx",
    framework_aidl = "platforms/android-%{api_level}/framework.aidl",
    legacy_main_dex_list_generator = ":generate_main_dex_list",
    main_dex_classes = ":main_dex_classes",
    main_dex_list_creator = ":main_dex_list_creator",
    proguard = "@remote_java_tools//:proguard",
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

filegroup(
    name = "files",
    srcs = [
        "platforms/android-%{api_level}/android.jar",
        "platforms/android-%{api_level}/core-for-system-modules.jar",
        "platforms/android-%{api_level}/framework.aidl",
    ],
)

filegroup(
    name = "sdk_path",
    srcs = ["."],
)

%{emulator_aliases}

create_system_images_filegroups(
    system_image_dirs = %{system_image_dirs},
)

exports_files(
    glob(["system-images/**"], allow_empty = True),
)
