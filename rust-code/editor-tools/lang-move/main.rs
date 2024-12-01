extern crate lang_move_lib;
extern crate serde_json;

use lang_move_lib::edit;
use lang_move_lib::types::Input;
use std::io::{self, BufRead};

fn main() {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let input_result = serde_json::from_str::<Input>(&line.unwrap()).ok();
        let result = input_result.as_ref().and_then(|input| edit(input));
        if let Some(result) = result {
            println!("{}", result);
        }
    }
}
