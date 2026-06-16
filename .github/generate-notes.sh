#!/bin/bash

set -euo pipefail

readonly new_version=$1

cat <<EOF
Setup docs: https://github.com/keith/hermetic_android_toolchains#usage

### MODULE.bazel Snippet

\`\`\`bzl
bazel_dep(name = "hermetic_android_toolchains", version = "$new_version")

android = use_extension("@hermetic_android_toolchains//:extensions.bzl", "android")
android.sdk(version = "35")
android.ndk(version = "r25c")
use_repo(android, "androidsdk", "androidndk")

# Make @rules_android's @androidsdk labels resolve to the hermetic SDK.
rules_android_sdk = use_extension("@rules_android//rules/android_sdk_repository:rule.bzl", "android_sdk_repository_extension")
override_repo(rules_android_sdk, "androidsdk")

register_toolchains("@androidndk//:all", "@androidsdk//:all")
\`\`\`
EOF
