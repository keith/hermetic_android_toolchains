#include <jni.h>

#include "jni_dep.h"

extern "C" JNIEXPORT jint JNICALL
Java_com_example_hermetic_Jni_add(JNIEnv *, jclass, jint left, jint right) {
  return add_from_dep(left, right);
}
