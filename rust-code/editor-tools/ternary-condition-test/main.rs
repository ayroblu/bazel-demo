extern crate direct;

use assert_cmd::Command;
use direct::direct_path;
use serde_json;
use ternary_condition_lib::types::Action;
use ternary_condition_lib::types::Input;
use ternary_condition_lib::types::Lang;

#[test]
fn it_converts_example_condition_to_ternary_direct() {
    let mut cmd = Command::cargo_bin(direct_path()).unwrap();
    let input_text = serde_json::to_string(&Input {
        source: BEFORE.to_string(),
        line: 0,
        column: 0,
        action: Action::Ternary,
        lang: Lang::TypeScript,
    })
    .unwrap();
    cmd.write_stdin(input_text)
        .assert()
        .success()
        .stdout(format!("{}\n", EXPECTED));
}

const BEFORE: &str = "if (a === b) {
    return 1;
} else if (a === c) {
    return 2;
} else {
    return 3;
}";
const EXPECTED: &str = "return (a === b) ? 1 : (a === c) ? 2 : 3";
