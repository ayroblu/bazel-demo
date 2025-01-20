package examples.android.lib

import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

class JsViewModel(application: Application) : AndroidViewModel(application) {
    private var webView by mutableStateOf<WebView?>(null)

    @SuppressLint("SetJavaScriptEnabled")
    suspend fun initWebView(context: Context) = coroutineScope {
        launch {
            val webViewClient = WebViewClient()
            val newWebView = WebView(context)

            newWebView.webViewClient = webViewClient
            newWebView.settings.javaScriptEnabled = true
            newWebView.webChromeClient = object : WebChromeClient() {
                @Suppress("NAME_SHADOWING")
                override fun onConsoleMessage(consoleMessage: ConsoleMessage?): Boolean {
                    val consoleMessage = consoleMessage ?: return true
                    handleConsole(consoleMessage)
                    return true
                }
            }
            class Emitter {
                @JavascriptInterface
                fun emit(newName: String) {
                    Log.i("BazelJs2", "emit $newName")
                    name = newName
                }
            }
            Log.i("BazelJs2", "setupWebView")
            newWebView.addJavascriptInterface(Emitter(), "app")
            newWebView.evaluateJavascript("app.toString()", {
                webView = newWebView
            })
        }
    }

    fun run2() {
        name = "pre run"
        Log.i("Bazel", "pre run")
        webView?.evaluateJavascript("""
            console.log("logging")
            app.emit("Run once!")
            setTimeout(() => {
                app.emit("Run twice!")
            }, 2000);
        """, {})
    }

    var name by mutableStateOf<String>("Other button")
}

fun handleConsole(consoleMessage: ConsoleMessage) {
    when (consoleMessage.messageLevel()) {
        ConsoleMessage.MessageLevel.DEBUG ->
            Log.d("BazelWebView", consoleMessage.message())

        ConsoleMessage.MessageLevel.ERROR ->
            Log.e("BazelWebView", consoleMessage.message())

        ConsoleMessage.MessageLevel.WARNING ->
            Log.w("BazelWebView", consoleMessage.message())

        else ->
            Log.i("BazelWebView", consoleMessage.message())
    }
    Log.v("BazelWebView", "${consoleMessage.sourceId()}:${consoleMessage.lineNumber()}")
}
