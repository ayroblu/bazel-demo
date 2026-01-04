package com.example.bazel

import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.List
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.example.bazel.http.OkHttpProvider
import com.example.bazel.rust_logs.LocalRustJotaiStore
import com.example.bazel.rust_logs.LogsView
import com.example.bazel.ui.theme.AppTheme
import java.io.File
import uniffi.example.checkNetwork
import uniffi.example.printAndAdd
import uniffi.example_rusqlite.getSaved
import uniffi.http_shared.setHttpProvider
import uniffi.jotai_logs.DeleteOldLogsAtom
import uniffi.jotai_logs.createStore
import uniffi.jotai_logs.initEffects
import uniffi.jotai_logs.initLogDb

class MainActivity : ComponentActivity() {
  private val store = createStore()
  private lateinit var deleteOldLogsAtom: DeleteOldLogsAtom

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    Log.v("Bazel", "Hello, Android")
    actionBar?.hide()

    initEffects(store)
    deleteOldLogsAtom = DeleteOldLogsAtom(store)
    setHttpProvider(OkHttpProvider())
    onLaunch(this)

    setContent {
      CompositionLocalProvider(LocalRustJotaiStore provides store) { AppTheme { MainApp() } }
    }
    Log.v("Bazel", "Finish init")
  }
}

fun onLaunch(context: Context) {
  val logDir = File(context.filesDir, "logs")
  if (!logDir.exists()) {
    logDir.mkdirs()
  }
  val file = File(logDir, "logs.sqlite")

  initLogDb(path = file.absolutePath)
}

@Preview(name = "Light Mode")
@Preview(uiMode = Configuration.UI_MODE_NIGHT_YES, showBackground = true, name = "Dark Mode")
@Composable
fun MainApp() {
  val store = LocalRustJotaiStore.current
  val deleteOldLogsAtom = remember { DeleteOldLogsAtom(store) }

  LaunchedEffect(Unit) { deleteOldLogsAtom.set() }

  val navController = rememberNavController()

  Scaffold(bottomBar = { BottomNavigationBar(navController) }) { innerPadding ->
    NavHost(
        navController = navController,
        startDestination = "home",
        modifier = Modifier.padding(innerPadding),
    ) {
      composable("home") { HomeTabView() }
      composable("todo") { JotaiExampleView() }
      composable("more_todo") { DragExampleView() }
      composable("logs") { LogsView() }
    }
  }
}

@Composable
fun BottomNavigationBar(navController: NavHostController) {
  val navBackStackEntry by navController.currentBackStackEntryAsState()
  val currentRoute = navBackStackEntry?.destination?.route

  NavigationBar {
    val items =
        listOf(
            NavigationItem("Home", "home", Icons.Default.Home),
            NavigationItem("Todo", "todo", Icons.Default.List),
            NavigationItem("More todo", "more_todo", Icons.Default.Info),
            NavigationItem("Logs", "logs", Icons.Default.Info),
        )

    items.forEach { item ->
      NavigationBarItem(
          selected = currentRoute == item.route,
          onClick = {
            navController.navigate(item.route) {
              popUpTo(navController.graph.startDestinationId)
              launchSingleTop = true
            }
          },
          icon = { Icon(item.icon, contentDescription = item.label) },
          label = { Text(item.label) },
      )
    }
  }
}

data class NavigationItem(
    val label: String,
    val route: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
)

@Composable
fun HomeTabView() {
  var result by remember { mutableStateOf<String?>(null) }

  LaunchedEffect(Unit) {
    Log.v("Bazel", "checking network")
    result = checkNetwork()
    Log.v("Bazel", "got result")
  }

  Surface(modifier = Modifier.fillMaxSize()) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
      Text("from rust: 1 + 2 = " + printAndAdd(1, 2))
      Log.v("Bazel", "render")
      JsEngineButton()
      Log.v("Bazel", "render2")
      val jsViewModel = viewModel<JsViewModel>()
      Button(onClick = { jsViewModel.handleClick() }) { Text(text = jsViewModel.name) }
      val saved = getSaved()
      Text(text = "rusqlite: " + saved?.joinToString(", ") ?: "No data saved")
      result?.let { ip -> Text(text = "ip: $ip") }
    }
  }
}

@Composable
fun JotaiExampleView() {
  Surface(modifier = Modifier.fillMaxSize()) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
      Text("JotaiExampleView")
      Log.v("Bazel", "JotaiExampleView")
    }
  }
}

@Composable
fun DragExampleView() {
  Surface(modifier = Modifier.fillMaxSize()) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
      Text("DragExampleView")
      Log.v("Bazel", "DragExampleView")
    }
  }
}
