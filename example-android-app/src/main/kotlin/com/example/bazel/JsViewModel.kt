package com.example.bazel

import android.app.Application
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import com.example.bazel.genjsapp.IApp
import com.example.bazel.genjsapp.JsDispatcher
import com.example.bazel.jswebview.WebViewThread

class JsViewModel(application: Application) : AndroidViewModel(application) {
    var name by mutableStateOf("Other button")
    private val jsAppWrapper: JsAppWrapper = JsAppWrapper(this)

    fun handleClick() {
        name = "pre click"
        Log.v("BazelJs2", "handleClick")
        jsAppWrapper.data.set("name", "Run once!");
        jsAppWrapper.jsDispatcher.click()
    }
}

class JsAppWrapper(private val jsViewModel: JsViewModel) {
    private val webViewThread = WebViewThread(jsViewModel.getApplication()) {
        setupWebView(it)
    }

    val data = HashMap<String, String>()
    val jsDispatcher = JsDispatcher(webViewThread)

    private fun setupWebView(webView: WebView) {
        val jsApp = JsApp(jsViewModel, data)
        webView.addJavascriptInterface(jsApp, jsApp.appName)
        Log.v("BazelJs2", "Added App: ${jsApp.appName}")
        webView.evaluateJavascript("${jsApp.appName}.toString()") {
            if (it != "null") {
                Log.i("BazelJs2", "app found")
            } else {
                Log.i("BazelJs2", "app not found")
            }
        }
        jsDispatcher.setup(webView)
    }
}

class JsApp(private val jsViewModel: JsViewModel, private val data: HashMap<String, String>): IApp {
    @JavascriptInterface
    override fun emit(newName: String) {
        Log.i("BazelJs2", "emit $newName")
        jsViewModel.name = newName
    }
    @JavascriptInterface
    override fun getName(): String {
        return jsViewModel.name
    }
    @JavascriptInterface
    override fun getData(key: String): String? {
        return data[key]
    }
    @JavascriptInterface
    override fun setData(key: String, value: String) {
        Log.v("BazelJs2", value)
        data[key] = value
    }
}