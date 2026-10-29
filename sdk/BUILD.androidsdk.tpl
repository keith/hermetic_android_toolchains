"""Generated Android SDK platform repository."""

load("@rules_java//java:defs.bzl", "java_binary")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//visibility:public"])

# Resolve this file's physical parent to obtain a standard Android SDK layout.
filegroup(
    name = "sdk_root",
    srcs = ["sdk/.root"],
)

# Exposes only the downloaded host tools, excluding generated Bazel runners.
filegroup(
    name = "host_tools_files",
    srcs = glob([
        "build-tools/**",
        "emulator/**",
        "platform-tools/**",
    ], allow_empty = True),
    visibility = ["//visibility:public"],
)

%{platform_rules}

%{platform_aliases}

%{emulator_aliases}
