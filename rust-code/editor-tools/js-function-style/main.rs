extern crate traverse_lib;

use traverse_lib::traverse_with_cursor;
use traverse_lib::TraverseAction;
use tree_sitter::Node;
use tree_sitter::Parser;
use tree_sitter_typescript;

fn main() {
    // Take in a json object via stdin
    // Parse, and query at cursor position
    parse(Input {
        source: EXAMPLE.to_string(),
        line: 2,
        column: 5,
        action: ConvertAction::ArrowBlock,
    });
}

const EXAMPLE: &str = "
function a() {
    console.log('a');
}
const b = () => {
    console.log('b');
}
const c = () => console.log('c')
";
struct Input {
    source: String,
    line: usize,
    column: usize,
    action: ConvertAction,
}
enum ConvertAction {
    Function,
    ArrowBlock,
    ArrowInline,
}
fn parse(input: Input) {
    let mut parser = Parser::new();
    parser
        .set_language(&tree_sitter_typescript::LANGUAGE_TSX.into())
        .expect("Error loading Rust grammar");
    let tree = parser.parse(&input.source, None).unwrap();
    let root_node = tree.root_node();
    let mut cursor = root_node.walk();
    // let source_bytes = input.source.as_bytes();
    traverse_with_cursor(&mut cursor, &|node: Node| {
        let sr = node.start_position().row;
        let sc = node.start_position().column;
        let er = node.end_position().row;
        let ec = node.end_position().column;

        // let node_text = node
        //     .utf8_text(source_bytes)
        //     .map_or_else(|s| s.to_string(), |s| s.to_string());
        // println!("- {} =\n{}", node.to_sexp(), indent_string(node_text, 1));

        let is_before = sr < input.line || (sr == input.line && sc <= input.column);
        let is_after = (er > input.line) || (er == input.line && ec >= input.column);
        if is_before && is_after {
            TraverseAction::Continue
        } else if is_before {
            TraverseAction::Next
        } else {
            TraverseAction::Exit
        }
    });
}

// fn indent_string(s: String, indent_level: usize) -> String {
//     let indent = "    ".repeat(indent_level);
//     s.lines()
//         .map(|line| format!("{}{}", indent, line))
//         .collect::<Vec<String>>()
//         .join("\n")
// }
