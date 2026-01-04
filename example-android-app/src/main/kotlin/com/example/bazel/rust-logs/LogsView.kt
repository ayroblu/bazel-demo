package com.example.bazel.rust_logs

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import uniffi.jotai_logs.ClosureCallback
import uniffi.jotai_logs.DeleteLogsAtom
import uniffi.jotai_logs.Log
import uniffi.jotai_logs.LogAtom
import uniffi.jotai_logs.RustJotaiStore

val LocalRustJotaiStore =
    staticCompositionLocalOf<RustJotaiStore> {
      error("No RustJotaiStore provided! Check your MainActivity.")
    }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogsView() {
  val store = LocalRustJotaiStore.current

  val logAtom = remember { LogAtom(store) }
  val deleteLogsAtom = remember { DeleteLogsAtom(store) }

  var logItems by remember { mutableStateOf(logAtom.get()) }
  val listState = rememberLazyListState()

  DisposableEffect(Unit) {
    val cleanup =
        logAtom.sub(
            object : ClosureCallback {
              override fun notif() {
                logItems = logAtom.get()
              }
            }
        )

    onDispose { cleanup.dispose() }
  }

  Scaffold(
      topBar = {
        TopAppBar(
            title = { Text("Logs") },
            actions = {
              if (logItems.isNotEmpty()) {
                IconButton(onClick = { deleteLogsAtom.set() }) {
                  Icon(Icons.Default.Delete, contentDescription = "Delete")
                }
              }
            },
        )
      }
  ) { innerPadding ->
    if (logItems.isEmpty()) {
      Box(
          modifier = Modifier.fillMaxSize().padding(innerPadding),
          contentAlignment = Alignment.Center,
      ) {
        Text("No items")
      }
    } else {
      LazyColumn(state = listState, modifier = Modifier.fillMaxSize().padding(innerPadding)) {
        itemsIndexed(logItems) { index, logItem ->
          val currentLog = logItems[index]
          if (index > 0) {
            val previousLog = logItems[index - 1]

            val secondsBetween =
                abs(currentLog.createdAt.epochSecond - previousLog.createdAt.epochSecond)

            if (secondsBetween > 60) {
              TimeSeparator()
            }
          }

          LogItemRow(logItem)
        }
      }
    }
  }
}

@Composable
fun TimeSeparator() {
  Row(
      modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
      horizontalArrangement = Arrangement.Center,
      verticalAlignment = Alignment.CenterVertically,
  ) {
    HorizontalDivider(modifier = Modifier.width(20.dp), thickness = 1.dp, color = Color.Gray)
  }
}

@Composable
fun LogItemRow(logItem: Log) {
  Box(
      modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
      contentAlignment = Alignment.BottomEnd,
  ) {
    Column(modifier = Modifier.fillMaxWidth()) {
      Text(text = logItem.text, modifier = Modifier.padding(bottom = 4.dp))
    }

    Text(
        text = logItem.createdAt.formatTimeWithMillis(),
        style = MaterialTheme.typography.labelSmall,
        color = Color.Gray,
    )
  }
}

private val logFormatter =
    DateTimeFormatter.ofPattern("HH:mm:ss.SSS").withZone(ZoneId.systemDefault())

fun Instant.formatTimeWithMillis(): String {
  return logFormatter.format(this)
}
