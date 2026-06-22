#include "jni_dep.h"

#include "sources/android/cpufeatures/cpu-features.h"
#include "sources/android/native_app_glue/android_native_app_glue.h"

int add_from_dep(int left, int right) {
  static_cast<void>(android_getCpuCount);
  static_cast<void>(app_dummy);

  return left + right;
}
