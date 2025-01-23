package examples.android.lib

import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.Message
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
    private val looperThread = LooperThread(this, getApplication())

    init {
        looperThread.start()
    }

    fun run2() {
        name = "pre run"

        looperThread.postCommand("Hello, Looper!")
    }

    var name by mutableStateOf("Other button")
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

class LooperThread(val jsViewModel: JsViewModel, val context: Context) : Thread() {
    private lateinit var handler: Handler
    private lateinit var webViewHelper: WebViewHelper

    override fun run() {
        Looper.prepare()

        webViewHelper = WebViewHelper(jsViewModel)
        webViewHelper.initWebView(context)

        handler = Handler(Looper.myLooper()!!) { message ->
            when (message.what) {
                1 -> {
                    webViewHelper.run()
                    val data = message.obj as String
                    println("Command received: $data")
                }
                else -> {
                    println("Unknown command")
                }
            }
            true
        }

        Looper.loop()
    }

    fun postCommand(command: String) {
        if (::handler.isInitialized) {
            val message = Message.obtain().apply {
                what = 1
                obj = command
            }
            handler.sendMessage(message)
        } else {
            println("Handler is not initialized yet")
        }
    }

    fun stopLooper() {
        if (::handler.isInitialized) {
            handler.looper.quit() // Stop the Looper
        }
    }
}

class WebViewHelper(val jsViewModel: JsViewModel) {
    private var webView: WebView? = null

    @SuppressLint("SetJavaScriptEnabled")
    fun initWebView(context: Context) {
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
                jsViewModel.name = newName
            }
        }
        Log.i("BazelJs2", "setupWebView")
        newWebView.addJavascriptInterface(Emitter(), "app")
        newWebView.evaluateJavascript("app.toString()", {
            if (it != "null") {
                Log.i("BazelJs2", "app found: $it")
                webView = newWebView
            }
        })
    }

    fun run() {
        Log.i("Bazel", "pre run")
        jsViewModel.name = "pre run"
        webView?.evaluateJavascript("""
            console.log("logging")
            app.emit("Run once!")
            setTimeout(() => {
                app.emit("Run twice!")
            }, 2000);
        """, {})
    }
}
