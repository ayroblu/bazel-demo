extern crate direct;

use assert_cmd::Command;
use direct::direct_path;
use lang_move_lib::types::Input;
use lang_move_lib::types::Lang;
use lang_move_lib::types::MoveAction;
use serde_json;

#[test]
fn it_converts_example_function_to_block_direct() {
    let mut cmd = Command::cargo_bin(direct_path()).unwrap();
    let input_text = serde_json::to_string(&Input {
        source: PARAM.to_string(),
        line: 0,
        column: 13,
        action: MoveAction::Next,
        lang: Lang::TypeScript,
    })
    .unwrap();
    cmd.write_stdin(input_text)
        .assert()
        .success()
        .stdout(format!("{}\n", PARAM_SWAP));
}

const PARAM: &str = "console.log('first', 'second')";
const PARAM_SWAP: &str = "console.log('second', 'first')";
