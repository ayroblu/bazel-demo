package com.example.bazel

import android.app.Application
import android.util.Log
import android.webkit.WebView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import com.example.bazel.genjsapp.IApp
import com.example.bazel.genjsapp.JsDispatcher
import com.example.bazel.genjsapp.JsReceiver
import com.example.bazel.genjsapp.MyParams
import com.example.bazel.jswebview.WebViewThread

class JsViewModel(application: Application) : AndroidViewModel(application) {
    var name by mutableStateOf("Other button")
    private val jsAppWrapper: JsAppWrapper = JsAppWrapper(this)

    fun handleClick() {
        name = "pre click"
        Log.v("BazelJs2", "handleClick")
        jsAppWrapper.data["name"] = "Run once!"
        jsAppWrapper.jsDispatcher.click("Run once!")
    }
}

class JsApp(
    private val jsViewModel: JsViewModel,
    private val data: HashMap<String, String>
) : IApp {
    override fun emit(newName: String) {
        jsViewModel.name = newName
    }

    override fun getName(): String {
        return jsViewModel.name
    }

    override fun getData(key: String): String? {
        return data[key]
    }

    override fun setData(key: String, value: Int) {
        Log.v("BazelJs2", "setData: $key: $value")
        data[key] = value.toString()
    }

    override fun emitObject(params: MyParams) {
        Log.v("BazelJs2", "emitObject: $params")
    }
}

class JsAppWrapper(private val jsViewModel: JsViewModel) {
    private val webViewThread = WebViewThread(jsViewModel.getApplication()) {
        setupWebView(it)
    }

    val data = HashMap<String, String>()
    val jsDispatcher = JsDispatcher(webViewThread, data)

    private fun setupWebView(webView: WebView) {
        val jsApp = JsApp(jsViewModel, data)
        val jsReceiver = JsReceiver(jsApp)
        webView.addJavascriptInterface(jsReceiver, jsApp.appName)
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

