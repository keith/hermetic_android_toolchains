"""Android instrumentation test rule backed by the hermetic emulator."""

load("@rules_android//providers:providers.bzl", "AndroidInstrumentationInfo", "ApkInfo")

def _single_file_with_basename(files, basename, owner):
    matches = [file for file in files if file.basename == basename]
    if len(matches) != 1:
        fail("Expected exactly one {} file named {}, got {}.".format(owner, basename, matches))
    return matches[0]

def _android_emulator_instrumentation_test_impl(ctx):
    test_host_apk = None
    if AndroidInstrumentationInfo in ctx.attr.test_app:
        test_host_apk = ctx.attr.test_app[AndroidInstrumentationInfo].target

    instrumentation_apk = ctx.attr.test_app[ApkInfo]
    if not instrumentation_apk:
        fail("The 'test_app' attribute must provide an ApkInfo provider.")

    adb = ctx.executable._adb
    aapt2 = ctx.files._aapt2[0]
    emulator = ctx.executable._emulator
    mksd = ctx.executable._mksd
    system_image_source_properties = _single_file_with_basename(
        ctx.files.system_image,
        "source.properties",
        str(ctx.attr.system_image.label),
    )

    runfiles = [
        adb,
        aapt2,
        emulator,
        mksd,
        instrumentation_apk.signed_apk,
        system_image_source_properties,
    ]
    runfiles.extend(ctx.files._emulator_shared_libs)
    runfiles.extend(ctx.files._emulator_x86_bios)
    runfiles.extend(ctx.files._qemu2)
    runfiles.extend(ctx.files.system_image)
    runfiles.extend(ctx.files.system_image_qemu2_extra)
    if test_host_apk:
        runfiles.append(test_host_apk.signed_apk)

    substitutions = {
        "%(aapt2)s": aapt2.short_path,
        "%(adb)s": adb.short_path,
        "%(emulator)s": emulator.short_path,
        "%(instrumentation_apk)s": instrumentation_apk.signed_apk.short_path,
        "%(instrumentation_runner)s": ctx.attr.instrumentation_runner,
        "%(mksd)s": mksd.short_path,
        "%(system_image_source_properties)s": system_image_source_properties.short_path,
        "%(test_host_apk)s": test_host_apk.signed_apk.short_path if test_host_apk else "",
    }

    instrumentation_script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        output = instrumentation_script,
        template = ctx.file._instrumentation_test_template,
        substitutions = substitutions,
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = instrumentation_script,
            runfiles = ctx.runfiles(
                files = runfiles,
                transitive_files = ctx.attr._aapt2[DefaultInfo].default_runfiles.files,
            ),
        ),
    ]

android_emulator_instrumentation_test = rule(
    implementation = _android_emulator_instrumentation_test_impl,
    attrs = {
        "instrumentation_runner": attr.string(
            default = "com.example.hermetic.emulator.test.SmokeInstrumentation",
            doc = "Fully qualified instrumentation runner class to pass to am instrument.",
        ),
        "test_app": attr.label(
            mandatory = True,
            providers = [ApkInfo],
            doc = "The Android instrumentation application to run.",
        ),
        "system_image": attr.label(
            allow_files = True,
            mandatory = True,
            doc = "The Android system image filegroup to boot.",
        ),
        "system_image_qemu2_extra": attr.label(
            allow_files = True,
            mandatory = True,
            doc = "Additional QEMU files needed by the Android system image.",
        ),
        "_aapt2": attr.label(
            allow_files = True,
            cfg = "exec",
            default = "@androidsdk//:aapt2",
        ),
        "_adb": attr.label(
            allow_files = True,
            cfg = "exec",
            default = "@androidsdk//:platform-tools/adb",
            executable = True,
        ),
        "_emulator": attr.label(
            allow_files = True,
            cfg = "exec",
            default = "@androidsdk//:emulator",
            executable = True,
        ),
        "_emulator_shared_libs": attr.label(
            allow_files = True,
            cfg = "exec",
            default = "@androidsdk//:emulator_shared_libs",
        ),
        "_emulator_x86_bios": attr.label(
            allow_files = True,
            cfg = "exec",
            default = "@androidsdk//:emulator_x86_bios",
        ),
        "_instrumentation_test_template": attr.label(
            allow_single_file = True,
            default = "android_emulator_instrumentation_test.template.sh",
        ),
        "_mksd": attr.label(
            allow_files = True,
            cfg = "exec",
            default = "@androidsdk//:mksd",
            executable = True,
        ),
        "_qemu2": attr.label(
            allow_files = True,
            cfg = "exec",
            default = "@androidsdk//:qemu2",
        ),
    },
    test = True,
    doc = "Runs an Android instrumentation APK on the hermetic Android emulator.",
)
