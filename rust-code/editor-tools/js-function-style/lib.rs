extern crate serde;
extern crate traverse_lib;

pub mod types;
mod extract;
mod helpers;
mod convert;

use tree_sitter::Node;
use tree_sitter::Parser;
use tree_sitter::TreeCursor;
use tree_sitter_typescript;
use types::Function;
use types::Input;
use convert::convert;
use traverse_lib::traverse_with_cursor;
use helpers::replace;
use extract::get_function;

pub fn edit(input: &Input) -> Option<String> {
    let mut parser = Parser::new();
    parser
        .set_language(&tree_sitter_typescript::LANGUAGE_TSX.into())
        .expect("Error loading Rust grammar");
    let tree = parser.parse(&input.source, None).unwrap();
    let mut cursor = tree.root_node().walk();

    extract(&input, &mut cursor).and_then(|item| {
        let new_text = convert(&input, &item)?;
        Some(replace(&input, &item.node, new_text))
    })
}
fn extract<'a>(input: &'a Input, cursor: &mut TreeCursor<'a>) -> Option<Function<'a>> {
    let source_bytes = input.source.as_bytes();
    let mut vec: Vec<Node> = Vec::new();

    traverse_with_cursor(cursor, &mut vec, input.line, input.column);

    vec.iter().rev().find_map(|node| get_function(node, source_bytes))
}
