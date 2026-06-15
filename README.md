# hermetic_android_toolchain

This repo contains hermetic bazel toolchains for the Android SDK and
NDK. This makes bazel automatically download the tools as needed, and
doesn't require that your developers have them installed globally. This
also ensures you will have the exact same version across all your
developers and CI.
