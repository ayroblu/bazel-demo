extern crate serde;
extern crate tree_sitter_utils;

mod convert;
mod extract;
pub mod types;

use convert::convert;
use extract::get_function;
use tree_sitter::Node;
use tree_sitter::Parser;
use tree_sitter::TreeCursor;
use tree_sitter_typescript;
use tree_sitter_utils::replace;
use tree_sitter_utils::traverse_with_cursor;
use types::Function;
use types::Input;

pub fn edit(input: &Input) -> Option<String> {
    let mut parser = Parser::new();
    parser
        .set_language(&tree_sitter_typescript::LANGUAGE_TSX.into())
        .expect("Error loading Rust grammar");
    let tree = parser.parse(&input.source, None).unwrap();
    let mut cursor = tree.root_node().walk();

    extract(&input, &mut cursor).and_then(|item| {
        let new_text = convert(&input, &item)?;
        Some(replace(&input.source, &item.node, new_text))
    })
}
fn extract<'a>(input: &'a Input, cursor: &mut TreeCursor<'a>) -> Option<Function<'a>> {
    let source_bytes = input.source.as_bytes();
    let mut vec: Vec<Node> = Vec::new();

    traverse_with_cursor(cursor, &mut vec, input.line, input.column);

    vec.iter()
        .rev()
        .find_map(|node| get_function(node, source_bytes))
}
