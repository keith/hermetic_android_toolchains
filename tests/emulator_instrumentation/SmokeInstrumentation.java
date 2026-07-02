package com.example.hermetic.emulator.test;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;

public final class SmokeInstrumentation extends Instrumentation {
  @Override
  public void onCreate(Bundle arguments) {
    super.onCreate(arguments);
    Bundle results = new Bundle();
    results.putString("hermetic_android_toolchains", "ok");
    finish(Activity.RESULT_OK, results);
  }
}
