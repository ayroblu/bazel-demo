package com.example.bazel

import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.bazel.ui.theme.AppTheme
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.*
import okhttp3.RequestBody.Companion.toRequestBody
import uniffi.example.checkNetwork
import uniffi.example.printAndAdd
import uniffi.example_rusqlite.getSaved
import uniffi.http_shared.HttpProvider
import uniffi.http_shared.HttpRequest
import uniffi.http_shared.HttpResponse
import uniffi.http_shared.setHttpProvider

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    Log.v("Bazel", "Hello, Android")
    actionBar?.hide()
    setContent { AppTheme { MainApp() } }
    setHttpProvider(OkHttpProvider())
    Log.v("Bazel", "Finish init")
  }
}

@Preview(name = "Light Mode")
@Preview(uiMode = Configuration.UI_MODE_NIGHT_YES, showBackground = true, name = "Dark Mode")
@Composable
fun MainApp() {
  var result by remember { mutableStateOf<String?>(null) }

  LaunchedEffect(Unit) {
    Log.v("Bazel", "checking network")
    result = checkNetwork()
    Log.v("Bazel", "got result")
  }

  Surface(modifier = Modifier.fillMaxSize()) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
      Text("from rust: 1 + 2 = " + printAndAdd(1, 2))
      Log.v("Bazel", "render")
      JsEngineButton()
      Log.v("Bazel", "render2")
      val jsViewModel = viewModel<JsViewModel>()
      Button(onClick = { jsViewModel.handleClick() }) { Text(text = jsViewModel.name) }
      val saved = getSaved()
      Text(text = "rusqlite: " + saved?.joinToString(", ") ?: "No data saved")
      result?.let { ip -> Text(text = "ip: $ip") }
    }
  }
}

class OkHttpProvider(private val client: OkHttpClient = OkHttpClient()) : HttpProvider {

  override suspend fun sendRequest(request: HttpRequest): HttpResponse {
    Log.v("Bazel", "New request")
    val okhttpRequest =
        Request.Builder()
            .url(request.url)
            .method(request.method.name, request.body?.toRequestBody())
            .apply { request.headers?.forEach { (name, value) -> addHeader(name, value) } }
            .build()

    return suspendCancellableCoroutine { continuation ->
      val call = client.newCall(okhttpRequest)

      continuation.invokeOnCancellation { call.cancel() }

      call.enqueue(
          object : Callback {
            override fun onResponse(call: Call, response: Response) {
              response.use {
                val httpResponse =
                    HttpResponse(
                        statusCode = response.code.toUShort(),
                        headers = response.headers.toMap(),
                        body = response.body?.bytes() ?: byteArrayOf(),
                    )
                continuation.resume(httpResponse)
              }
            }

            override fun onFailure(call: Call, e: IOException) {
              if (continuation.isCancelled) return
              continuation.resumeWithException(e)
            }
          }
      )
    }
  }
}
