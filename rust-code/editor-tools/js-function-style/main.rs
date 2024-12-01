extern crate js_function_style_lib;
extern crate serde_json;

use js_function_style_lib::edit;
use js_function_style_lib::Input;
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
