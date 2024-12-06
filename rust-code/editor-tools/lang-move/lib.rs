extern crate serde;
extern crate tree_sitter_utils;

mod extract;
pub mod types;

use extract::get_node;
use tree_sitter::Node;
use tree_sitter::Parser;
use tree_sitter::TreeCursor;
use tree_sitter_typescript;
use tree_sitter_utils::swap;
use tree_sitter_utils::traverse_with_cursor;
use types::Input;
use types::Lang;

pub fn edit(input: &Input) -> Option<String> {
    let mut parser = Parser::new();
    match input.lang {
        Lang::TypeScript => parser
            .set_language(&tree_sitter_typescript::LANGUAGE_TSX.into())
            .expect("Error loading Rust grammar"),
        Lang::Rust => parser
            .set_language(&tree_sitter_rust::LANGUAGE.into())
            .expect("Error loading Rust grammar"),
    }
    let tree = parser.parse(&input.source, None).unwrap();
    let mut cursor = tree.root_node().walk();

    extract(input, &mut cursor)
        .flatten()
        .map(|(node, next)| swap(&input.source, &node, &next))
}

fn extract<'a>(
    input: &'a Input,
    cursor: &mut TreeCursor<'a>,
) -> Option<Option<(Node<'a>, Node<'a>)>> {
    let mut vec: Vec<Node> = Vec::new();

    traverse_with_cursor(cursor, &mut vec, input.line, input.column);

    vec.iter()
        .rev()
        .find_map(|node| get_node(node, &input.action))
}
