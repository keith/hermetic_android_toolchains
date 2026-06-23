#!/bin/bash

set -euo pipefail

readonly new_version=$1

cat <<EOF
### MODULE.bazel Snippet

\`\`\`starlark
bazel_dep(name = "hermetic_android_toolchains", version = "$new_version", dev_dependency = True)
bazel_dep(name = "rules_android", version = "0.7.3", dev_dependency = True)
bazel_dep(name = "rules_android_ndk", version = "0.1.5", dev_dependency = True)

android = use_extension("@hermetic_android_toolchains//:extensions.bzl", "android", dev_dependency = True)
android.sdk(
    build_tools_version = "37.0.0",
    version = "37.0",
)
android.ndk(version = "r29")
use_repo(android, "androidsdk", "androidndk")

# Make @rules_android's @androidsdk labels resolve to the hermetic SDK.
rules_android_sdk = use_extension("@rules_android//rules/android_sdk_repository:rule.bzl", "android_sdk_repository_extension", dev_dependency = True)

override_repo(rules_android_sdk, "androidsdk")

# Make @rules_android_ndk's @androidndk labels resolve to the hermetic SDK.
rules_android_ndk = use_extension("@rules_android_ndk//:extension.bzl", "android_ndk_repository_extension", dev_dependency = True)

override_repo(rules_android_ndk, "androidndk")

register_toolchains("@androidndk//:all", "@androidsdk//:all", dev_dependency = True)
\`\`\`

Setup docs: https://github.com/keith/hermetic_android_toolchains#usage
EOF
