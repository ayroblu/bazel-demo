package com.example.bazel.js

import android.app.Application
import android.util.Log
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.javascriptengine.JavaScriptConsoleCallback
import androidx.javascriptengine.JavaScriptIsolate
import androidx.javascriptengine.JavaScriptSandbox
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.launch

class JsEngineViewModel(application: Application) : AndroidViewModel(application) {
  private var jsSandbox by mutableStateOf<JavaScriptSandbox?>(null)

  init {
    if (JavaScriptSandbox.isSupported()) {
      Log.i("Bazel", "Start js sandbox")
      val jsSandboxFuture = JavaScriptSandbox.createConnectedInstanceAsync(getApplication())
      viewModelScope.launch {
        jsSandbox = jsSandboxFuture.await()
        Log.i("Bazel", "Allocate js sandbox")
      }
    }
  }

  suspend fun run(): String? {
    val jsSandbox = jsSandbox ?: return null
    val jsIsolate: JavaScriptIsolate = jsSandbox.createIsolate()
    jsIsolate.setConsoleCallback { consoleCallback(it) }
    val setupCode =
        """async function run() {
            console.log(1+1);
            // setTimeout(() => {});
            return "hi"
        }"""
    return runCatching {
          jsIsolate.evaluateJavaScriptAsync(setupCode).await()
          val result = jsIsolate.evaluateJavaScriptAsync("run()").await()
          Log.i("Bazel", result)
          return result
        }
        .onFailure { err -> Log.e("BazelJsError", err.message.toString()) }
        .getOrDefault(null)
  }
}

@Composable
fun JsEngineButton() {
  val jsEngineVm = viewModel<JsEngineViewModel>()
  var name by remember { mutableStateOf("Click me!") }
  val lifecycleOwner = LocalLifecycleOwner.current
  Button(
      onClick = {
        lifecycleOwner.lifecycleScope.launch { name = jsEngineVm.run() ?: return@launch }
      }
  ) {
    Text(text = name)
  }
}

fun consoleCallback(message: JavaScriptConsoleCallback.ConsoleMessage) {
  Log.i("BazelJs", message.message)
  Log.v("BazelJs", "(${message.level}) ${message.source}:${message.line}:${message.column}")
  Log.v("BazelJs", "  ${message.trace ?: return}")
}
