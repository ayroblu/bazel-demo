package com.example.bazel.http

import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.*
import okhttp3.RequestBody.Companion.toRequestBody
import uniffi.http_shared.HttpProvider
import uniffi.http_shared.HttpRequest
import uniffi.http_shared.HttpResponse

class OkHttpProvider(private val client: OkHttpClient = OkHttpClient()) : HttpProvider {
  override suspend fun sendRequest(request: HttpRequest): HttpResponse {
    // Log.v("Bazel", "New request")
    val okhttpRequest =
        Request.Builder()
            .url(request.url)
            .method(request.method.name, request.body?.toRequestBody())
            .apply { request.headers?.forEach { (name, value) -> addHeader(name, value) } }
            .build()

    return suspendCancellableCoroutine { continuation ->
      val call = client.newCall(okhttpRequest)

      continuation.invokeOnCancellation { call.cancel() }

      call.enqueue(
          object : Callback {
            override fun onResponse(call: Call, response: Response) {
              response.use {
                val httpResponse =
                    HttpResponse(
                        statusCode = response.code.toUShort(),
                        headers = response.headers.toMap(),
                        body = response.body?.bytes() ?: byteArrayOf(),
                    )
                continuation.resume(httpResponse)
              }
            }

            override fun onFailure(call: Call, e: IOException) {
              if (continuation.isCancelled) return
              continuation.resumeWithException(e)
            }
          }
      )
    }
  }
}
