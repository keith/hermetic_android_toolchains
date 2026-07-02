"""Module extension for Android SDK and NDK repositories."""

load(
    "//ndk:repositories.bzl",
    "ANDROID_NDK_LICENSE_ENV",
    "NDK_TAG",
    "hermetic_android_ndk_platform_repository",
    "hermetic_android_ndk_repository",
)
load("//private:utils.bzl", "ANDROID_PLATFORMS")
load(
    "//sdk:repositories.bzl",
    "ANDROID_SDK_LICENSE_ENV",
    "EMULATOR_TAG",
    "SDK_TAG",
    "SYSTEM_IMAGE_TAG",
    "hermetic_android_sdk_platform_repository",
    "hermetic_android_sdk_repository",
)

def _root_tags(module_ctx, tag_name):
    root_tags = []
    for module in module_ctx.modules:
        tags = getattr(module.tags, tag_name)
        if module.is_root and tags:
            root_tags.extend(tags)
    return root_tags

def _single_root_tag(module_ctx, tag_name):
    root_tags = _root_tags(module_ctx, tag_name)

    if len(root_tags) > 1:
        fail("Expected at most one root android.{}(...) tag, found {}.".format(tag_name, len(root_tags)))

    return root_tags[0] if root_tags else None

def _sdk_kwargs(tag):
    if not tag:
        fail("Expected a root android.sdk(...) tag with version and build_tools_version.")
    if not tag.version:
        fail("android.sdk(...) requires version.")
    if not tag.build_tools_version:
        fail("android.sdk(...) requires build_tools_version.")

    return {
        "api_level": tag.api_level,
        "build_tools_directory": tag.build_tools_directory,
        "build_tools_sha256s": tag.build_tools_sha256s,
        "build_tools_strip_prefixes": tag.build_tools_strip_prefixes,
        "build_tools_urls": tag.build_tools_urls,
        "build_tools_version": tag.build_tools_version,
        "platform_tools_sha256s": tag.platform_tools_sha256s,
        "platform_tools_urls": tag.platform_tools_urls,
        "platforms_sha256": tag.platforms_sha256,
        "platforms_strip_prefix": tag.platforms_strip_prefix,
        "platforms_url": tag.platforms_url,
        "version": tag.version,
    }

def _emulator_kwargs(tag):
    if not tag:
        return {}
    return {"emulator_version": tag.version}

def _system_image_directory(tag):
    version = tag.version
    if not version.startswith("android-"):
        version = "android-{}".format(version)
    return "{}/default/{}".format(version, tag.arch)

def _system_images_kwargs(tags):
    directories = {}
    for tag in tags:
        directory = _system_image_directory(tag)
        directories[directory] = True
    return {"system_images": sorted(directories.keys())}

def _ndk_kwargs(tag):
    if not tag:
        return None
    if not tag.version:
        fail("android.ndk(...) requires version.")

    return {
        "api_level": tag.api_level,
        "sha256s": tag.sha256s,
        "strip_prefix": tag.strip_prefix,
        "urls": tag.urls,
        "version": tag.version,
    }

def _android_impl(module_ctx):
    sdk = _sdk_kwargs(_single_root_tag(module_ctx, "sdk"))
    emulator = _emulator_kwargs(_single_root_tag(module_ctx, "emulator"))
    system_images = _system_images_kwargs(_root_tags(module_ctx, "system_image"))
    kwargs = sdk | emulator | system_images
    root_module_direct_dev_deps = ["androidsdk"]

    sdk_platform_repositories = {}
    for platform in sorted(ANDROID_PLATFORMS.keys()):
        name = "androidsdk_{}".format(platform)
        hermetic_android_sdk_platform_repository(
            name = name,
            platform = platform,
            **kwargs
        )
        sdk_platform_repositories[platform] = name
    hermetic_android_sdk_repository(
        name = "androidsdk",
        platform_repositories = sdk_platform_repositories,
        **kwargs
    )

    ndk = _ndk_kwargs(_single_root_tag(module_ctx, "ndk"))
    if ndk:
        ndk_platform_repositories = {}
        for platform in sorted(ANDROID_PLATFORMS.keys()):
            name = "androidndk_{}".format(platform)
            hermetic_android_ndk_platform_repository(
                name = name,
                platform = platform,
                **ndk
            )
            ndk_platform_repositories[platform] = name
        hermetic_android_ndk_repository(
            name = "androidndk",
            platform_repositories = ndk_platform_repositories,
            **ndk
        )
        root_module_direct_dev_deps.append("androidndk")

    return module_ctx.extension_metadata(
        reproducible = True,
        root_module_direct_deps = [],
        root_module_direct_dev_deps = root_module_direct_dev_deps,
    )

android = module_extension(
    implementation = _android_impl,
    environ = [
        ANDROID_NDK_LICENSE_ENV,
        ANDROID_SDK_LICENSE_ENV,
    ],
    tag_classes = {
        "emulator": EMULATOR_TAG,
        "ndk": NDK_TAG,
        "sdk": SDK_TAG,
        "system_image": SYSTEM_IMAGE_TAG,
    },
)
