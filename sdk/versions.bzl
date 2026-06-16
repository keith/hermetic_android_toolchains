"""Known Android SDK bundle metadata."""

visibility("//:__subpackages__")

DEFAULT_SDK_VERSION = "35"
SDK_VERSIONS = Label("//sdk:versions.json")
