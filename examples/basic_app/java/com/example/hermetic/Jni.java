package com.example.hermetic;

public final class Jni {
  private Jni() {}

  public static native int add(int left, int right);
}
