"""Generated Android SDK platform repository."""

load("@rules_java//java:defs.bzl", "java_binary")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//visibility:public"])

%{platform_rules}

%{platform_aliases}
