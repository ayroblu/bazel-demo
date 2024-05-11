extern crate traverse_lib;

use tree_sitter::Parser;
use tree_sitter_python;
use tree_sitter_scala;
use tree_sitter_typescript;

fn main() {
    scala();
    python();
    tsx();
    traverse_lib::traverse();
    println!("hello world");
}

fn scala() {
    let mut parser = Parser::new();
    parser
        .set_language(&tree_sitter_scala::language())
        .expect("Error loading Rust grammar");
    let source_code = "val a = 1L";
    let tree = parser.parse(source_code, None).unwrap();
    let root_node = tree.root_node();
    println!("{}", root_node.to_sexp());
}
fn python() {
    let mut parser = Parser::new();
    parser
        .set_language(&tree_sitter_python::language())
        .expect("Error loading Rust grammar");
    let source_code = "scala_binary(sources = [\"*.scala\"])";
    let tree = parser.parse(source_code, None).unwrap();
    let root_node = tree.root_node();
    println!("{}", root_node.to_sexp());
}
fn tsx() {
    let mut parser = Parser::new();
    parser
        .set_language(&tree_sitter_typescript::language_tsx())
        .expect("Error loading Rust grammar");
    let source_code = "let a = 1;";
    let tree = parser.parse(source_code, None).unwrap();
    let root_node = tree.root_node();
    println!("{}", root_node.to_sexp());
}
