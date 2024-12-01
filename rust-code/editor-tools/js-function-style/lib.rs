extern crate traverse_lib;

use traverse_lib::TraverseAction;
use tree_sitter::Node;
use tree_sitter::Parser;
use tree_sitter::TreeCursor;
use tree_sitter_typescript;
use utils::indent_string;

pub struct Input {
    pub source: String,
    pub line: usize,
    pub column: usize,
    pub action: ConvertAction,
}
pub enum ConvertAction {
    Function,
    ArrowBlock,
    ArrowInline,
}
pub fn edit(input: Input) -> Option<String> {
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
    let mut vec: Vec<Function> = Vec::new();

    traverse_with_cursor(cursor, &mut vec, source_bytes, &input);

    vec.pop()
}
fn convert(input: &Input, item: &Function) -> Option<String> {
    let source_bytes = input.source.as_bytes();
    match input.action {
        ConvertAction::Function => {
            let body = item
                .body
                .map_or_else(|| "".to_string(), |node| to_text(&node, source_bytes));
            let is_block = item
                .body
                .filter(|node| node.kind() == "statement_block")
                .is_some();
            let body_text = if is_block {
                body
            } else {
                format!("{{\n{};\n}}", indent_string(format!("return {}", body), 1))
            };
            Some(format!(
                "function {}{} {}",
                item.name
                    .as_ref()
                    .map_or_else(|| "".to_string(), |name| name.clone()),
                item.params
                    .map_or_else(|| "()".to_string(), |node| to_text(&node, source_bytes)),
                body_text
            ))
        }
        ConvertAction::ArrowBlock => {
            let body = item
                .body
                .map_or_else(|| "".to_string(), |node| to_text(&node, source_bytes));
            let is_block = item
                .body
                .filter(|node| node.kind() == "statement_block")
                .is_some();
            let body_text = if is_block {
                body
            } else {
                format!("{{\n{};\n}}", indent_string(format!("return {}", body), 1))
            };
            Some(format!(
                "const {} = {} => {}",
                item.name
                    .as_ref()
                    .map_or_else(|| "".to_string(), |name| name.clone()),
                item.params
                    .map_or_else(|| "()".to_string(), |node| to_text(&node, source_bytes)),
                body_text
            ))
        }
        ConvertAction::ArrowInline => {
            // conversion to inline is not perfect, you may return a value you weren't before
            let is_block = item
                .body
                .filter(|node| node.kind() == "statement_block")
                .is_some();
            let is_multi = item
                .body
                .map(|node| {
                    let mut cursor = node.walk();
                    node.named_children(&mut cursor).count()
                })
                .filter(|count| *count > 1)
                .is_some();
            if is_multi || !is_block {
                return None;
            }
            let body_text = item
                .body
                .and_then(|node| node.named_child(0))
                .and_then(|node| node.named_child(0))
                .map_or_else(|| "".to_string(), |node| to_text(&node, source_bytes));
            Some(format!(
                "const {} = {} => {}",
                item.name
                    .as_ref()
                    .map_or_else(|| "".to_string(), |name| name.clone()),
                item.params
                    .map_or_else(|| "()".to_string(), |node| to_text(&node, source_bytes)),
                body_text
            ))
        }
    }
}

fn traverse_with_cursor<'a>(
    cursor: &mut TreeCursor<'a>,
    vec: &mut Vec<Function<'a>>,
    source_bytes: &'a [u8],
    input: &'a Input,
) -> bool {
    let node = cursor.node();
    let (action, value) = if node.is_named() {
        on_node(node, source_bytes, input)
    } else {
        (TraverseAction::Next, None)
    };
    if let Some(value) = value {
        vec.push(value);
    }
    match action {
        TraverseAction::Continue => {
            if cursor.goto_first_child() {
                let mut is_more = traverse_with_cursor(cursor, vec, source_bytes, input);
                if is_more && cursor.goto_next_sibling() {
                    is_more = traverse_with_cursor(cursor, vec, source_bytes, input);
                }
                cursor.goto_parent();
                is_more
            } else if cursor.goto_next_sibling() {
                traverse_with_cursor(cursor, vec, source_bytes, input)
            } else {
                true
            }
        }
        TraverseAction::Next => {
            if cursor.goto_next_sibling() {
                traverse_with_cursor(cursor, vec, source_bytes, input)
            } else {
                true
            }
        }
        TraverseAction::Exit => false,
    }
}

fn on_node<'a>(
    node: Node<'a>,
    source_bytes: &'a [u8],
    input: &'a Input,
) -> (TraverseAction, Option<Function<'a>>) {
    let sr = node.start_position().row;
    let sc = node.start_position().column;
    let er = node.end_position().row;
    let ec = node.end_position().column;

    let node_text = to_text(&node, source_bytes);
    println!("- {} =\n{}", node.to_sexp(), indent_string(node_text, 1));

    let is_before = sr < input.line || (sr == input.line && sc <= input.column);
    let is_after = (er > input.line) || (er == input.line && ec >= input.column);
    if is_before && is_after {
        let func = get_function(node, source_bytes);
        (TraverseAction::Continue, func)
    } else if is_before {
        (TraverseAction::Next, None)
    } else {
        (TraverseAction::Exit, None)
    }
}

fn to_text(node: &Node, source_bytes: &[u8]) -> String {
    node.utf8_text(source_bytes)
        .map_or_else(|s| s.to_string(), |s| s.to_string())
}

#[derive(Debug, Clone)]
enum FunctionKind {
    Function,    // function f() {}
    ArrowBlock,  // const f = () => {}
    ArrowInline, // const f = () => body
    Method,      // { f(){} }
    Property,    // { f: () => {} }
}
#[derive(Debug, Clone)]
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
        // (function_declaration
        //   name: (identifier)
        //   parameters: (formal_parameters)
        //   body: (statement_block (expression_statement (call_expression function: (member_expression object: (identifier) property: (property_identifier)) arguments: (arguments (string (string_fragment))))))
        // )
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
        // (lexical_declaration
        //  (variable_declarator
        //      name: (identifier)
        //      value: (arrow_function
        //          parameters: (formal_parameters)
        //          body: (statement_block
        //              (expression_statement (call_expression function: (member_expression object: (identifier) property: (property_identifier)) arguments: (arguments (string (string_fragment)))))
        //              (expression_statement (call_expression function: (member_expression object: (identifier) property: (property_identifier)) arguments: (arguments (string (string_fragment)))))
        //          )
        //      )
        //  )
        // )
        node.named_child(0)
            .filter(|node| node.kind() == "variable_declarator")
            .and_then(|node| node.child_by_field_name("value"))
            .filter(|node| node.kind() == "arrow_function")
            .map(|child_node| {
                let body = child_node.child_by_field_name("body");
                Function {
                    name: node
                        .named_child(0)
                        .and_then(|node| node.child_by_field_name("name"))
                        .map(|node| to_text(&node, source_bytes)),
                    node,
                    kind: body
                        .filter(|body| body.kind() == "statement_block")
                        .map_or_else(|| FunctionKind::ArrowInline, |_| FunctionKind::ArrowBlock),
                    body,
                    params: child_node.child_by_field_name("parameters"),
                }
            })
    } else {
        None
    }
}

fn replace(input: &Input, node: &Node, text: String) -> String {
    let mut source = input.source.clone();
    source.replace_range(node.start_byte()..node.end_byte(), &text);
    source
}
