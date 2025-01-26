package com.example.bazel.genjsapp

import android.webkit.WebView
import com.example.bazel.jswebview.WebViewThread

interface IApp {
    val appName: String
        get() = "androidApp"

    fun emit(newName: String)
    fun getName(): String
    fun getData(key: String): String?
    fun setData(key: String, value: String)
}

class JsDispatcher(private val webViewThread: WebViewThread) {
    fun setup(webView: WebView) {
        webView.evaluateJavascript(setupScript) {}
    }
    private fun run(name: String) {
        webViewThread.postCommand("$name()")
    }
    fun click() {
        run("click")
    }
}

private const val setupScript = """
function click() {
    console.log("logging")
    androidApp.setData("example", JSON.stringify(["item"]))
    androidApp.emit(androidApp.getData("name"))
    console.log("name", androidApp.getName());
    setTimeout(() => {
        if (androidApp.getName() === "Run once!") {
            androidApp.emit("Run twice!")
        }
    }, 2000);
}
console.log("evaluated");
"""
