package examples.android.lib

import android.app.Application
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.javascriptengine.JavaScriptConsoleCallback.ConsoleMessage
import androidx.javascriptengine.JavaScriptIsolate
import androidx.javascriptengine.JavaScriptSandbox
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.launch

class JsViewModel(application: Application) : AndroidViewModel(application) {
    var jsSandbox by mutableStateOf<JavaScriptSandbox?>(null)
        private set

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
        val funcs = """async function run() {
            console.log(1+1);
            // setTimeout(() => {});
            return "hi"
        }"""
//        val code = "throw new Error('internal')"
        return runCatching {
            jsIsolate.evaluateJavaScriptAsync(funcs).await()
            val result = jsIsolate.evaluateJavaScriptAsync("run()").await()
            Log.i("Bazel", result)
            return result
        }.onFailure { err ->
            Log.e("BazelJsError", err.message.toString())
        }.getOrDefault(null)
    }
}

fun consoleCallback(message: ConsoleMessage) {
    Log.i("BazelJs", message.message)
    Log.v("BazelJs", "(${message.level}) ${message.source}:${message.line}:${message.column}")
    Log.v("BazelJs", "  ${message.trace ?: return}")
}
