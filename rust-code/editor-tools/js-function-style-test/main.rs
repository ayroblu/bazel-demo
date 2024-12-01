use assert_cmd::Command;
use js_function_style_lib::ConvertAction;
use js_function_style_lib::Input;
use serde_json;

#[test]
fn it_converts_example_function_to_block() {
    // bazel implementation detail
    // cwd: _main/rust-code/editor-tools/js-function-style-test/test-632671733
    let mut cmd = Command::cargo_bin("../../js-function-style/js-function-style").unwrap();
    let input_text = serde_json::to_string(&Input {
        source: A.to_string(),
        line: 0,
        column: 0,
        action: ConvertAction::ArrowBlock,
    })
    .unwrap();
    cmd.write_stdin(input_text)
        .assert()
        .success()
        .stdout(format!("{}\n", A_BLOCK));
}

const A: &str = "function a(v: string) {
    console.log('a', v);
}";
const A_BLOCK: &str = "const a = (v: string) => {
    console.log('a', v);
}";
