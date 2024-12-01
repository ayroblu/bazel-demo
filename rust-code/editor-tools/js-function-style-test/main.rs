extern crate direct;
extern crate runfile;

use assert_cmd::Command;
use js_function_style_lib::types::ConvertAction;
use js_function_style_lib::types::Input;
use serde_json;
use runfile::runfile_path;
use direct::direct_path;

#[test]
fn it_converts_example_function_to_block() {
    let mut cmd = Command::cargo_bin(runfile_path()).unwrap();
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

#[test]
fn it_converts_example_function_to_block_direct() {
    let mut cmd = Command::cargo_bin(direct_path()).unwrap();
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
