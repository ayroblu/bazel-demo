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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.bazel.ui.theme.AppTheme
import uniffi.example.printAndAdd
import uniffi.example.checkNetwork
import uniffi.http_shared.setHttpProvider
import uniffi.http_shared.HttpRequest
import uniffi.http_shared.HttpResponse
import uniffi.example_rusqlite.getSaved
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.v("Bazel", "Hello, Android")
        actionBar?.hide()
        setContent { AppTheme { MainApp() } }
        setHttpProvider(object : HttpProvider {
            override suspend fun sendRequest(request: HttpRequest): HttpResponse {
                return withContext(Dispatchers.IO) {
                    val builder = Request.Builder().url(request.url)

                    request.headers?.forEach { (name, value) ->
                        builder.addHeader(name, value)
                    }

                    val contentType = request.headers?.get("Content-Type")?.toMediaTypeOrNull()

                    val methodStr = request.method.name

                    if (request.method == HttpMethod.GET || request.method == HttpMethod.HEAD) {
                        builder.method(methodStr, null)
                    } else {
                        val requestBody = (request.body ?: byteArrayOf()).toRequestBody(contentType)
                        builder.method(methodStr, requestBody)
                    }

                    client.newCall(builder.build()).execute().use { response ->
                        HttpResponse(
                            status = response.code,
                            body = response.body?.bytes() ?: byteArrayOf()
                        )
                    }
                }
            }
        })
        Log.v("Bazel", "Finish init")
    }
}

@Preview(name = "Light Mode")
@Preview(uiMode = Configuration.UI_MODE_NIGHT_YES, showBackground = true, name = "Dark Mode")
@Composable
fun MainApp() {
    var result by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        result = checkNetwork()
    }

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text("from rust: 1 + 2 = " + printAndAdd(1, 2))
            Log.v("Bazel", "render")
            JsEngineButton()
            Log.v("Bazel", "render2")
            val jsViewModel = viewModel<JsViewModel>()
            Button(onClick = {
                jsViewModel.handleClick()
            }) {
                Text(text = jsViewModel.name)
            }
            val saved = getSaved()
            Text(text = "rusqlite: " + saved?.joinToString(", ") ?: "No data saved")
            result?.let { ip ->
                Text(text = "ip: $ip")
            }
        }
    }
}
