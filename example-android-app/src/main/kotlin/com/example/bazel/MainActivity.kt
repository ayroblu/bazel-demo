package com.example.bazel

import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.bazel.ui.theme.AppTheme
import uniffi.example.printAndAdd
// import uniffi.example_rusqlite.getSaved

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.v("Bazel", "Hello, Android")
        actionBar?.hide()
        setContent { AppTheme { MainApp() } }
        Log.v("Bazel", "Finish init")
    }
}

@Preview(name = "Light Mode")
@Preview(uiMode = Configuration.UI_MODE_NIGHT_YES, showBackground = true, name = "Dark Mode")
@Composable
fun MainApp() {
    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text("1 + 2 = " + printAndAdd(1, 2))
            Log.v("Bazel", "render")
            JsEngineButton()
            Log.v("Bazel", "render2")
            val jsViewModel = viewModel<JsViewModel>()
            Button(onClick = {
                jsViewModel.handleClick()
            }) {
                Text(text = jsViewModel.name)
            }
            // val saved = getSaved()
            // Text(text = saved?.joinToString(", ") ?: "No data saved")
        }
    }
}
