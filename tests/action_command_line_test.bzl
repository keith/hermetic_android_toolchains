"""Analysis test helpers for action command lines."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "unittest")

def _action_command_line_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    matching_actions = [
        action
        for action in analysistest.target_actions(env)
        if action.mnemonic == ctx.attr.mnemonic
    ]
    if ctx.attr.argv_filter:
        matching_actions = [
            action
            for action in matching_actions
            if ctx.attr.argv_filter in " ".join(action.argv)
        ]

    if not matching_actions:
        actual_mnemonics = collections.uniq([
            action.mnemonic
            for action in analysistest.target_actions(env)
        ])
        unittest.fail(
            env,
            "Target {} registered no {} action. It had {}.".format(
                target_under_test.label,
                ctx.attr.mnemonic,
                actual_mnemonics,
            ),
        )
        return analysistest.end(env)

    if len(matching_actions) != 1:
        unittest.fail(
            env,
            "Expected one {} action for {}, found {}.".format(
                ctx.attr.mnemonic,
                target_under_test.label,
                len(matching_actions),
            ),
        )
        return analysistest.end(env)

    argv = " ".join(matching_actions[0].argv) + " "
    remaining = argv
    for expected in ctx.attr.expected_argv:
        index = remaining.find(expected)
        if index == -1:
            unittest.fail(
                env,
                "Expected {} action for {} to contain {} in order. Full argv: {}".format(
                    ctx.attr.mnemonic,
                    target_under_test.label,
                    repr(expected),
                    argv,
                ),
            )
        else:
            remaining = remaining[index + len(expected):]

    for not_expected in ctx.attr.not_expected_argv:
        if not_expected in argv:
            unittest.fail(
                env,
                "Expected {} action for {} to omit {}. Full argv: {}".format(
                    ctx.attr.mnemonic,
                    target_under_test.label,
                    repr(not_expected),
                    argv,
                ),
            )

    return analysistest.end(env)

action_command_line_test = analysistest.make(
    _action_command_line_test_impl,
    attrs = {
        "argv_filter": attr.string(),
        "expected_argv": attr.string_list(),
        "mnemonic": attr.string(mandatory = True),
        "not_expected_argv": attr.string_list(),
    },
    config_settings = {
        # buildifier: disable=canonical-repository
        "//command_line_option:platforms": "@@rules_android+//:x86_64",
    },
)
