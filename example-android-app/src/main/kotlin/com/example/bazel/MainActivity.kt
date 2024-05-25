package examples.android.lib

import androidx.appcompat.app.AlertDialog
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.LinearLayout.LayoutParams
import androidx.appcompat.app.AppCompatActivity
import android.util.Log;
import android.widget.TextView;

class MainActivity : AppCompatActivity() {

  override fun onCreate(savedInstanceState: Bundle?) {
    // super.onCreate(savedInstanceState)
    // val parent = LinearLayout(this).apply {
    //   orientation = LinearLayout.VERTICAL
    // }.also { it.addView(Button(this).apply { text = "Foo!" }) }
    // setContentView(parent, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

    super.onCreate(savedInstanceState);
    Log.v("Bazel", "Hello, Android");

    setContentView(R.layout.activity_main);

    val clickMeButton: Button = findViewById(R.id.clickMeButton);
    val helloBazelTextView: TextView = findViewById(R.id.helloBazelTextView);

    // val greeter: Greeter = new Greeter();
    val text = "Hello Bazel! \uD83D\uDC4B\uD83C\uDF31"; // Unicode for 👋🌱

    // // Bazel supports Java 8 language features like lambdas!
    clickMeButton.setOnClickListener { helloBazelTextView.setText(text) };
  }
}
