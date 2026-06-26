package com.example.sdkonly;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public final class MainActivity extends Activity {
  @Override
  public void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);

    TextView textView = new TextView(this);
    textView.setText("SDK-only Android app");
    setContentView(textView);
  }
}
