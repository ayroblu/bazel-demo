extern crate traverse_lib;

use std::sync::Arc;
use std::sync::Mutex;

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
        line: 5,
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
const d = function() {
    console.log('b');
}
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
    let source_bytes = input.source.as_bytes();
    let mut vec: Vec<Function> = Vec::new();
    // let vec: Arc<Mutex<Vec<Option<Function>>>> = Arc::new(Mutex::new(Vec::new()));
    let f = |node: Node| {
        let sr = node.start_position().row;
        let sc = node.start_position().column;
        let er = node.end_position().row;
        let ec = node.end_position().column;

        let node_text = node
            .utf8_text(source_bytes)
            .map_or_else(|s| s.to_string(), |s| s.to_string());
        println!("- {} =\n{}", node.to_sexp(), indent_string(node_text, 1));

        let is_before = sr < input.line || (sr == input.line && sc <= input.column);
        let is_after = (er > input.line) || (er == input.line && ec >= input.column);
        if is_before && is_after {
            let node2 = node.clone();
            let _func = get_function(node2, source_bytes);
            (TraverseAction::Continue, None)
        } else if is_before {
            (TraverseAction::Next, None)
        } else {
            (TraverseAction::Exit, None)
        }
    };
    traverse_with_cursor(&mut cursor, &mut vec, &f);
}

fn to_text(node: &Node, source_bytes: &[u8]) -> String {
    node.utf8_text(source_bytes)
        .map_or_else(|s| s.to_string(), |s| s.to_string())
}

enum FunctionKind {
    Function,    // function f() {}
    ArrowBlock,  // const f = () => {}
    ArrowInline, // const f = () => body
    Method,      // { f(){} }
    Property,    // { f: () => {} }
}
struct Function<'a> {
    name: Option<String>,
    node: Node<'a>,
    kind: FunctionKind,
    body: Option<Node<'a>>,
    params: Option<Node<'a>>,
}
fn get_function<'a>(node: Node<'a>, source_bytes: &'a [u8]) -> Option<Function<'a>> {
    let kind = node.kind();
    if kind == "function_declaration" {
        // (function_declaration name: (identifier) parameters: (formal_parameters) body: (statement_block (expression_statement (call_expression function: (member_expression object: (identifier) property: (property_identifier)) arguments: (arguments (string (string_fragment)))))))
        Some(Function {
            name: node
                .child_by_field_name("name")
                .map(|node| to_text(&node, source_bytes)),
            node,
            kind: FunctionKind::Function,
            body: node.child_by_field_name("body"),
            params: node.child_by_field_name("parameters"),
        })
    } else if kind == "lexical_declaration" {
        // (lexical_declaration (variable_declarator name: (identifier) value: (arrow_function parameters: (formal_parameters) body: (statement_block (expression_statement (call_expression function: (member_expression object: (identifier) property: (property_identifier)) arguments: (arguments (string (string_fragment)))))))))
        node.child(0)
            .filter(|node| node.kind() == "variable_declarator")
            .and_then(|node| node.child_by_field_name("value"))
            .filter(|node| node.kind() == "arrow_function")
            .map(|child_node| {
                let body = child_node.child_by_field_name("body");
                Function {
                    name: node
                        .child(0)
                        .and_then(|node| node.child_by_field_name("name"))
                        .map(|node| to_text(&node, source_bytes)),
                    node,
                    kind: body
                        .filter(|body| body.kind() == "statement_block")
                        .map_or_else(|| FunctionKind::ArrowBlock, |_| FunctionKind::ArrowInline),
                    body,
                    params: node.child_by_field_name("parameters"),
                }
            })
    } else {
        None
    }
}

fn indent_string(s: String, indent_level: usize) -> String {
    let indent = "    ".repeat(indent_level);
    s.lines()
        .map(|line| format!("{}{}", indent, line))
        .collect::<Vec<String>>()
        .join("\n")
}
