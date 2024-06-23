package examples.android.lib

import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import androidx.activity.ComponentActivity

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    Log.v("Bazel", "Hello, Android")
    setContent { Greeting("world") }
  }
}

@Preview @Composable fun Greeting(name: String) = Text(text = "Hello $name!")
