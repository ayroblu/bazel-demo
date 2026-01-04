package com.example.bazel.js

import android.webkit.JavascriptInterface
import android.webkit.WebView
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

interface IApp {
  val appName: String
    get() = "_androidApp"

  fun emit(newName: String)

  fun getName(): String

  fun getData(key: String): String?

  fun setData(key: String, value: Int)

  fun emitObject(params: MyParams)
}

@Serializable data class MyParams(val name: String, val age: Int)

val jsonParser = Json {
  isLenient = true
  ignoreUnknownKeys = true
  allowStructuredMapKeys = true
}

class JsReceiver(private val iJsReceiver: IApp) {
  @JavascriptInterface
  fun emit(newName: String) {
    return iJsReceiver.emit(newName)
  }

  @JavascriptInterface
  fun getName(): String {
    return iJsReceiver.getName()
  }

  @JavascriptInterface
  fun getData(key: String): String? {
    return iJsReceiver.getData(key)
  }

  @JavascriptInterface
  fun setData(key: String, value: Int) {
    return iJsReceiver.setData(key, value)
  }

  @JavascriptInterface
  fun emitObject(myParams: String) {
    val data = jsonParser.decodeFromString<MyParams>(myParams)
    return iJsReceiver.emitObject(data)
  }
}

class JsDispatcher(
    private val webViewThread: WebViewThread,
    private val data: HashMap<String, String>,
) {
  fun setup(webView: WebView) {
    webView.evaluateJavascript(setupScript) {}
  }

  fun click(name: String) {
    data[name.hashCode().toString()] = name
    webViewThread.postCommand("click(${name.hashCode()})")
  }
}

private const val setupScript =
    """
var androidApp = {
    emit: (name) => _androidApp.emit(name),
    getName: () => _androidApp.getName(),
    getData: (key) => _androidApp.getData(key),
    setData: (key, value) => _androidApp.setData(key, value),
    emitObject: (params) => _androidApp.emitObject(JSON.stringify(params)),
}
function click(code) {
    var data = androidApp.getData(code);
    return _click(data);
}
function _click(name, options) {
    console.log("logging", name, options)
    androidApp.setData("example", 3.14159265)
    androidApp.emitObject({name: "John", age: 25})
    androidApp.emit(name)
    console.log("name", androidApp.getName());
    setTimeout(() => {
        if (androidApp.getName() === "Run once!") {
            androidApp.emit("Run twice!")
        }
    }, 2000);
}
console.log("evaluated");
"""
