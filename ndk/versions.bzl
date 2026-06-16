"""Known Android NDK archive metadata."""

visibility("//:__subpackages__")

# TODO: When rules_android_ndk releases, import their default
DEFAULT_API_LEVEL = 31
DEFAULT_NDK_VERSION = "r25c"
NDK_VERSIONS = Label("//ndk:versions.json")
