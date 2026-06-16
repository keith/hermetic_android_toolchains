# hermetic_android_toolchains

This repo contains hermetic bazel toolchains for the Android SDK and
NDK. This makes bazel automatically download the tools as needed, and
doesn't require that your developers have them installed globally. This
also ensures you will have the exact same version across all your
developers and CI.

## Usage

Add this to your `MODULE.bazel`:

```starlark
bazel_dep(name = "hermetic_android_toolchains", version = "0.0.0")
bazel_dep(name = "rules_android", version = "0.7.3")

android = use_extension("@hermetic_android_toolchains//:extensions.bzl", "android")
android.sdk(version = "35")
android.ndk(version = "r25c")
use_repo(android, "androidsdk", "androidndk")

# Make @rules_android's @androidsdk labels resolve to the hermetic SDK.
rules_android_sdk = use_extension("@rules_android//rules/android_sdk_repository:rule.bzl", "android_sdk_repository_extension")
override_repo(rules_android_sdk, "androidsdk")

register_toolchains("@androidndk//:all", "@androidsdk//:all")
```

Once you have reviewed and accepted the SDK and NDK licenses, add this
to your `.bazelrc` for the versions of the licenses you accepted:

```
common --repo_env=ACCEPTED_ANDROID_SDK_LICENSE_VERSION=35
common --repo_env=ACCEPTED_ANDROID_NDK_LICENSE_VERSION=r25c
```

Use `android.ndk(api_level = ...)` to specify a different API level for
the NDK.

## Specifying versions

This repo includes metadata for many Android SDK and NDK versions so you
can specify a well known version in your `MODULE.bazel` file. When there
is a new version that isn't yet supported by this repo, please submit a
PR updating the `versions.json` files with the correct shas.

Until the version you want to use is merged here you can specify the
full details of a SDK / NDK in your `MODULE.bazel`:

```bzl
android.sdk(
    version = "35",
    api_level = "35",
    build_tools_version = "35.0.0",
    build_tools_directory = "35.0.0",
    build_tools_urls = {
        "linux": "https://mirror.example/build-tools-linux.zip",
        "darwin": "https://mirror.example/build-tools-darwin.zip",
        "windows": "https://mirror.example/build-tools-windows.zip",
    },
    build_tools_sha256s = {
        "linux": "...",
        "darwin": "...",
        "windows": "...",
    },
    platform_tools_urls = {
        "linux": "https://mirror.example/platform-tools-linux.zip",
        "darwin": "https://mirror.example/platform-tools-darwin.zip",
        "windows": "https://mirror.example/platform-tools-windows.zip",
    },
    platform_tools_sha256s = {
        "linux": "...",
        "darwin": "...",
        "windows": "...",
    },
    platforms_url = "https://mirror.example/platform-35.zip",
    platforms_sha256 = "...",
)

android.ndk(
    version = "r27d",
    urls = {
        "linux": "https://mirror.example/android-ndk-r27d-linux.zip",
        "darwin": "https://mirror.example/android-ndk-r27d-darwin.zip",
        "windows": "https://mirror.example/android-ndk-r27d-windows.zip",
    },
    sha256s = {
        "linux": "...",
        "darwin": "...",
        "windows": "...",
    },
    strip_prefix = "android-ndk-r27d",
)
```
