package examples.android.lib

import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.javascriptengine.JavaScriptIsolate
import androidx.javascriptengine.JavaScriptSandbox
import com.google.common.util.concurrent.ListenableFuture
import examples.android.lib.ui.theme.AppTheme


class MainActivity : ComponentActivity() {
    var jsSandboxFuture: ListenableFuture<JavaScriptSandbox> =
        JavaScriptSandbox.createConnectedInstanceAsync(this)
    var jsIsolate: JavaScriptIsolate = jsSandbox.createIsolate()
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    Log.v("Bazel", "Hello, Android")
    actionBar?.hide()
    setContent { AppTheme { MainApp() } }
  }
}

@Preview(name = "Light Mode")
@Preview(uiMode = Configuration.UI_MODE_NIGHT_YES, showBackground = true, name = "Dark Mode")
@Composable
fun MainApp() =
    Surface(modifier = Modifier.fillMaxSize()) {
      Column(
          horizontalAlignment = Alignment.CenterHorizontally,
          verticalArrangement = Arrangement.Center) {
            Text(text = "Hello world!")
          }
    }
