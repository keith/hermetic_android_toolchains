"""Build ThinLTO artifacts for every Android ABI using the host's NDK."""

def _android_thin_lto_impl(_settings, _attr):
    return {
        abi: {
            "//command_line_option:compilation_mode": "opt",
            "//command_line_option:features": ["thin_lto"],
            "//command_line_option:platforms": [str(Label("@rules_android//:" + abi))],
        }
        for abi in ["armeabi-v7a", "arm64-v8a", "x86", "x86_64"]
    }

_android_thin_lto = transition(
    implementation = _android_thin_lto_impl,
    inputs = [],
    outputs = [
        "//command_line_option:compilation_mode",
        "//command_line_option:features",
        "//command_line_option:platforms",
    ],
)

def _thin_lto_artifacts_impl(ctx):
    return [DefaultInfo(files = depset(transitive = [
        target[DefaultInfo].files
        for targets in ctx.split_attr.targets.values()
        for target in targets
    ]))]

thin_lto_artifacts = rule(
    implementation = _thin_lto_artifacts_impl,
    attrs = {
        "targets": attr.label_list(cfg = _android_thin_lto),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
