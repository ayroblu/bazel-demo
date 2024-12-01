extern crate lib;

use lib::edit;
use lib::ConvertAction;
use lib::Input;

fn main() {
    // Take in a json object via stdin
    // Parse, and query at cursor position
    let result = edit(Input {
        source: EXAMPLE.to_string(),
        line: 5,
        column: 5,
        action: ConvertAction::Function,
    });
    if let Some(result) = result {
        println!("Something!");
    }
}

const EXAMPLE: &str = "
function a() {
    console.log('a');
}
const b = () => {
    console.log('b');
    console.log('b2');
}
const c = () => console.log('c')
const d = function() {
    console.log('b');
}
";
