package com.example.hermetic;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public final class MainActivity extends Activity {
  @Override
  public void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    System.loadLibrary("jni");

    TextView textView = new TextView(this);
    textView.setText(getString(R.string.jni_result_prefix) + Jni.add(20, 22));
    setContentView(textView);
  }
}
