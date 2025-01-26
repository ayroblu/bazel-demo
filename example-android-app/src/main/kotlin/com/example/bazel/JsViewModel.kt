package com.example.bazel

import android.app.Application
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel

class JsViewModel(application: Application) : AndroidViewModel(application) {
    private val looperThread = LooperThread(getApplication()) {
        setupWebview(it)
    }

    var name by mutableStateOf("Other button")

    init {
        looperThread.start()
    }

    fun run() {
        name = "pre run"

        looperThread.postCommand("""
            console.log("logging")
            app.emit("Run once!")
            setTimeout(() => {
                app.emit("Run twice!")
            }, 2000);
        """)
    }

    fun setupWebview(webView: WebView) {
        class Emitter {
            @JavascriptInterface
            fun emit(newName: String) {
                Log.i("BazelJs2", "emit $newName")
                name = newName
            }
        }
        webView.addJavascriptInterface(Emitter(), "app")
        webView.evaluateJavascript("app.toString()", {
            if (it != "null") {
                Log.i("BazelJs2", "app found: $it")
            }
        })
    }
}

