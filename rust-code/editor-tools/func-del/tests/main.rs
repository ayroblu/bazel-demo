extern crate direct;

use assert_cmd::Command;
use direct::direct_path;
use func_del_lib::types::Action;
use func_del_lib::types::Input;
use serde_json;

#[test]
fn it_removes_first_surrounding_func() {
    #[allow(deprecated)]
    let mut cmd = Command::cargo_bin(direct_path()).unwrap();
    let input_text = serde_json::to_string(&Input {
        source: BEFORE.to_string(),
        line: 0,
        column: 0,
        action: Action::FuncDel,
    })
    .unwrap();
    cmd.write_stdin(input_text)
        .assert()
        .success()
        .stdout(format!("{}\n", EXPECTED));
}

const BEFORE: &str = "first {
    second(
        third<>(value)
    )
}";
const EXPECTED: &str = "second(
        third<>(value)
    )";
