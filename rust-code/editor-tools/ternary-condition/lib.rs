extern crate serde;
extern crate tree_sitter_utils;

mod convert;
mod extract;
pub mod types;

use convert::convert;
use extract::get_node;
use tree_sitter::Node;
use tree_sitter::Parser;
use tree_sitter::TreeCursor;
use tree_sitter_typescript;
use tree_sitter_utils::replace;
use tree_sitter_utils::traverse_with_cursor;
use types::Input;
use types::Lang;

pub fn edit(input: &Input) -> Option<String> {
    let mut parser = Parser::new();
    match input.lang {
        Lang::TypeScript => parser
            .set_language(&tree_sitter_typescript::LANGUAGE_TSX.into())
            .expect("Error loading TypeScript grammar"),
        Lang::Swift => parser
            .set_language(&tree_sitter_swift::LANGUAGE.into())
            .expect("Error loading Swift grammar"),
        // Rust and Scala only have normal "if" statements
        Lang::Rust => parser
            .set_language(&tree_sitter_rust::LANGUAGE.into())
            .expect("Error loading Rust grammar"),
        Lang::Scala => parser
            .set_language(&tree_sitter_scala::LANGUAGE.into())
            .expect("Error loading Scala grammar"),
        Lang::Go => parser
            .set_language(&tree_sitter_go::LANGUAGE.into())
            .expect("Error loading Go grammar"),
    }
    let tree = parser.parse(&input.source, None).unwrap();
    #[cfg(debug_assertions)]
    {
        // Useful for debugging and adding new languages
        eprintln!("{}", tree.root_node());
    }
    let mut cursor = tree.root_node().walk();

    extract(&input, &mut cursor).and_then(|item| {
        let new_text = convert(&input, &item, false)?;
        Some(replace(&input.source, &item, new_text))
    })
}

fn extract<'a>(input: &'a Input, cursor: &mut TreeCursor<'a>) -> Option<Node<'a>> {
    let mut vec: Vec<Node> = Vec::new();

    traverse_with_cursor(cursor, &mut vec, input.line, input.column);

    vec.iter()
        .rev()
        .find_map(|node| get_node(*node, &input.action))
}
