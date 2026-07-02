#!/usr/bin/env bash

set -euo pipefail

adb="%(adb)s"
aapt2="%(aapt2)s"
emulator="%(emulator)s"
mksd="%(mksd)s"
test_host_apk="%(test_host_apk)s"
instrumentation_apk="%(instrumentation_apk)s"
instrumentation_runner="%(instrumentation_runner)s"
system_image_source_properties="%(system_image_source_properties)s"
device_id=""
emulator_port="5554"

while [[ $# -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --device_id=*)
      device_id="${arg##*=}"
      ;;
    --emulator_port=*)
      emulator_port="${arg##*=}"
      ;;
    --instrumentation_apk=*)
      instrumentation_apk="${arg##*=}"
      ;;
    --test_host_apk=*)
      test_host_apk="${arg##*=}"
      ;;
  esac
  shift
done

resolve_runfile() {
  local path="$1"
  if [[ -z "$path" ]]; then
    return 1
  elif [[ -e "$path" ]]; then
    printf '%s\n' "$path"
  elif [[ -n "${RUNFILES_DIR:-}" && -e "${RUNFILES_DIR}/$path" ]]; then
    printf '%s\n' "${RUNFILES_DIR}/$path"
  elif [[ -n "${TEST_SRCDIR:-}" && -n "${TEST_WORKSPACE:-}" && -e "${TEST_SRCDIR}/${TEST_WORKSPACE}/$path" ]]; then
    printf '%s\n' "${TEST_SRCDIR}/${TEST_WORKSPACE}/$path"
  elif [[ -n "${TEST_SRCDIR:-}" && -e "${TEST_SRCDIR}/$path" ]]; then
    printf '%s\n' "${TEST_SRCDIR}/$path"
  else
    echo "missing runfile: $path" >&2
    exit 1
  fi
}

adb="$(resolve_runfile "$adb")"
aapt2="$(resolve_runfile "$aapt2")"
emulator="$(resolve_runfile "$emulator")"
mksd="$(resolve_runfile "$mksd")"
instrumentation_apk="$(resolve_runfile "$instrumentation_apk")"
system_image_source_properties="$(resolve_runfile "$system_image_source_properties")"
if [[ -n "$test_host_apk" ]]; then
  test_host_apk="$(resolve_runfile "$test_host_apk")"
fi

system_image_dir="$(cd "$(dirname "$system_image_source_properties")" && pwd)"
test_tmpdir="${TEST_TMPDIR:-$(mktemp -d)}"
adb_server_port="${ADB_SERVER_PORT:-5038}"
emulator_pid=""
adb_cmd=()

print_emulator_log() {
  if [[ -f "${test_tmpdir}/emulator.log" ]]; then
    tail -200 "${test_tmpdir}/emulator.log" >&2
  fi
}

cleanup() {
  set +e
  if ((${#adb_cmd[@]} == 0)); then
    return
  fi
  if [[ -n "${instrumentation_app_id:-}" ]]; then
    "${adb_cmd[@]}" shell am force-stop "$instrumentation_app_id" >/dev/null 2>&1
    "${adb_cmd[@]}" shell pm uninstall --user all "$instrumentation_app_id" >/dev/null 2>&1
    "${adb_cmd[@]}" uninstall "$instrumentation_app_id" >/dev/null 2>&1
  fi
  if [[ -n "${test_host_app_id:-}" ]]; then
    "${adb_cmd[@]}" shell am force-stop "$test_host_app_id" >/dev/null 2>&1
    "${adb_cmd[@]}" shell pm uninstall --user all "$test_host_app_id" >/dev/null 2>&1
    "${adb_cmd[@]}" uninstall "$test_host_app_id" >/dev/null 2>&1
  fi
  if [[ -n "$emulator_pid" ]]; then
    "${adb_cmd[@]}" emu kill >/dev/null 2>&1
    wait "$emulator_pid" >/dev/null 2>&1
  fi
  env ADB_SERVER_PORT="$adb_server_port" "$adb" kill-server >/dev/null 2>&1
}
trap cleanup EXIT

source_property() {
  sed -n "s/^$1=//p" "$system_image_source_properties" | head -1
}

if [[ -z "$device_id" ]]; then
  device_id="emulator-${emulator_port}"
  sdcard="${test_tmpdir}/sdcard.img"
  "$mksd" 64M "$sdcard" >/dev/null
  system_image_abi="$(source_property "SystemImage.Abi")"
  api_level="$(source_property "AndroidVersion.ApiLevel")"
  tag_id="$(source_property "SystemImage.TagId")"
  tag_display="$(source_property "SystemImage.TagDisplay")"
  case "$system_image_abi" in
    arm64-v8a)
      cpu_arch="arm64"
      ;;
    armeabi-v7a)
      cpu_arch="arm"
      ;;
    *)
      cpu_arch="$system_image_abi"
      ;;
  esac

  avd_name="hermetic-emulator-test"
  avd_home="${test_tmpdir}/avd"
  avd_dir="${avd_home}/${avd_name}.avd"
  mkdir -p "$avd_dir"
  cat >"${avd_home}/${avd_name}.ini" <<EOF
avd.ini.encoding=UTF-8
path=$avd_dir
path.rel=avd/${avd_name}.avd
target=android-${api_level}
EOF
  cat >"${avd_dir}/config.ini" <<EOF
AvdId=$avd_name
PlayStore.enabled=false
abi.type=$system_image_abi
avd.ini.displayname=$avd_name
disk.dataPartition.size=2048M
hw.cpu.arch=$cpu_arch
hw.cpu.ncore=2
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader_indirect
hw.keyboard=yes
hw.lcd.density=420
hw.lcd.height=1920
hw.lcd.width=1080
hw.ramSize=2048
image.sysdir.1=${system_image_dir}/
runtime.network.latency=none
runtime.network.speed=full
sdcard.path=$sdcard
skin.dynamic=yes
tag.display=$tag_display
tag.id=$tag_id
target=android-${api_level}
EOF

  env \
    ADB_SERVER_PORT="$adb_server_port" \
    ANDROID_AVD_HOME="$avd_home" \
    ANDROID_SDK_HOME="${test_tmpdir}/sdk-home" \
    "$emulator" \
      -avd "$avd_name" \
      -port "$emulator_port" \
      -no-window \
      -no-audio \
      -no-boot-anim \
      -no-snapshot \
      -no-snapshot-save \
      -wipe-data \
      -gpu swiftshader_indirect \
      >"${test_tmpdir}/emulator.log" 2>&1 &
  emulator_pid="$!"
fi

adb_cmd=(env ADB_SERVER_PORT="$adb_server_port" "$adb" -s "$device_id")

device_connected=false
for _ in $(seq 1 90); do
  if "${adb_cmd[@]}" get-state >/dev/null 2>&1; then
    device_connected=true
    break
  fi
  if [[ -n "$emulator_pid" ]] && ! kill -0 "$emulator_pid" >/dev/null 2>&1; then
    echo "Emulator exited before adb connected." >&2
    print_emulator_log
    exit 1
  fi
  sleep 1
done
if [[ "$device_connected" != true ]]; then
  echo "Emulator did not connect to adb." >&2
  print_emulator_log
  exit 1
fi

boot_completed=false
for _ in $(seq 1 180); do
  if [[ "$("${adb_cmd[@]}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    boot_completed=true
    break
  fi
  sleep 1
done
if [[ "$boot_completed" != true ]]; then
  echo "Emulator did not finish booting." >&2
  print_emulator_log
  exit 1
fi

have_test_host_apk=false
if [[ -n "$test_host_apk" && -f "$test_host_apk" ]]; then
  have_test_host_apk=true
  test_host_app_id="$("$aapt2" dump packagename "$test_host_apk")"
fi
instrumentation_app_id="$("$aapt2" dump packagename "$instrumentation_apk")"

if [[ "$have_test_host_apk" == true ]]; then
  "${adb_cmd[@]}" install -r -t -g "$test_host_apk"
  "${adb_cmd[@]}" install -r -t -g "$instrumentation_apk"
else
  "${adb_cmd[@]}" install -r -t -g "$instrumentation_apk"
fi

"${adb_cmd[@]}" logcat -c
set +e
output="$("${adb_cmd[@]}" shell am instrument -r -w "${instrumentation_app_id}/${instrumentation_runner}" 2>&1)"
instrumentation_status=$?
set -e
log_output="$("${adb_cmd[@]}" logcat -d)"

if [[ "$instrumentation_status" -ne 0 ]]; then
  echo "$output"
  echo "$log_output"
  exit "$instrumentation_status"
fi
if echo "$output" | grep -q "FAILURES"; then
  echo "$output"
  exit 1
fi
if echo "$log_output" | grep "Fatal signal" | grep -v -q "Fatal signal 31"; then
  echo "$log_output"
  exit 1
fi
