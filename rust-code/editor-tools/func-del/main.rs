extern crate func_del_lib;
extern crate serde_json;

use func_del_lib::edit;
use func_del_lib::types::Input;
use std::io::{self, BufRead};

fn main() {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let input_result = serde_json::from_str::<Input>(&line.unwrap()).ok();
        let result = input_result.as_ref().and_then(|input| edit(input));
        eprintln!("result {:?}", result);
        if let Some(result) = result {
            println!("{}", result);
        }
    }
}
