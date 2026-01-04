package com.example.bazel.js

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient

fun handleConsole(consoleMessage: ConsoleMessage) {
  when (consoleMessage.messageLevel()) {
    ConsoleMessage.MessageLevel.DEBUG -> Log.d("BazelWebView", consoleMessage.message())

    ConsoleMessage.MessageLevel.ERROR -> Log.e("BazelWebView", consoleMessage.message())

    ConsoleMessage.MessageLevel.WARNING -> Log.w("BazelWebView", consoleMessage.message())

    else -> Log.i("BazelWebView", consoleMessage.message())
  }
  Log.v("BazelWebView", "${consoleMessage.sourceId()}:${consoleMessage.lineNumber()}")
}

class WebViewThread(private val context: Context, private val onWebView: (WebView) -> Unit) :
    Thread() {
  private lateinit var handler: Handler
  private lateinit var webViewHelper: WebViewHelper

  init {
    start()
    Log.i("BazelWebView", "started")
  }

  override fun run() {
    Looper.prepare()

    webViewHelper = WebViewHelper(context)
    onWebView(webViewHelper.webView)

    handler =
        Handler(Looper.myLooper()!!) { message ->
          when (message.what) {
            1 -> {
              val data = message.obj as String
              Log.v("BazelJs2", "Command received: $data")
              webViewHelper.run(data)
            }

            else -> {
              Log.v("BazelJs2", "Unknown command")
            }
          }
          true
        }

    Looper.loop()
  }

  fun postCommand(command: String) {
    if (::handler.isInitialized) {
      val message =
          Message.obtain().apply {
            what = 1
            obj = command
          }
      handler.sendMessage(message)
    } else {
      Log.v("BazelJs2", "Handler is not initialized yet")
    }
  }

  // fun stopLooper() {
  //     if (::handler.isInitialized) {
  //         handler.looper.quit() // Stop the Looper
  //     }
  // }
}

@SuppressLint("SetJavaScriptEnabled")
class WebViewHelper(context: Context) {
  val webView: WebView

  init {
    val webViewClient = WebViewClient()
    val newWebView = WebView(context)

    newWebView.webViewClient = webViewClient
    newWebView.settings.javaScriptEnabled = true
    newWebView.webChromeClient =
        object : WebChromeClient() {
          @Suppress("NAME_SHADOWING")
          override fun onConsoleMessage(consoleMessage: ConsoleMessage?): Boolean {
            val consoleMessage = consoleMessage ?: return true
            handleConsole(consoleMessage)
            return true
          }
        }
    webView = newWebView
  }

  fun run(js: String) {
    webView.evaluateJavascript(js) {}
  }
}
