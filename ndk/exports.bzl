"""Rules for exposing Android NDK source exports."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_EXPORTS_TOOLCHAIN_TYPE = Label("//ndk:exports_toolchain_type")

def _ndk_exports_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        cc_exports = {
            "cpufeatures": ctx.attr.cpufeatures[CcInfo],
            "native_app_glue": ctx.attr.native_app_glue[CcInfo],
        },
        file_exports = {
            "android_native_app_glue_header": ctx.file.android_native_app_glue_header,
        },
    )]

ndk_exports_toolchain = rule(
    implementation = _ndk_exports_toolchain_impl,
    attrs = {
        "android_native_app_glue_header": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "cpufeatures": attr.label(
            mandatory = True,
            providers = [CcInfo],
        ),
        "native_app_glue": attr.label(
            mandatory = True,
            providers = [CcInfo],
        ),
    },
)

def _ndk_cc_export_impl(ctx):
    toolchain = ctx.toolchains[_EXPORTS_TOOLCHAIN_TYPE]
    return [toolchain.cc_exports[ctx.attr.export]]

ndk_cc_export = rule(
    implementation = _ndk_cc_export_impl,
    attrs = {
        "export": attr.string(
            mandatory = True,
            values = [
                "cpufeatures",
                "native_app_glue",
            ],
        ),
    },
    toolchains = [_EXPORTS_TOOLCHAIN_TYPE],
)

def _ndk_file_export_impl(ctx):
    toolchain = ctx.toolchains[_EXPORTS_TOOLCHAIN_TYPE]
    return [DefaultInfo(files = depset([toolchain.file_exports[ctx.attr.export]]))]

ndk_file_export = rule(
    implementation = _ndk_file_export_impl,
    attrs = {
        "export": attr.string(
            mandatory = True,
            values = ["android_native_app_glue_header"],
        ),
    },
    toolchains = [_EXPORTS_TOOLCHAIN_TYPE],
)
