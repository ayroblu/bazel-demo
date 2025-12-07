extern crate serde;

use crate::types::Action;
use crate::types::Input;
use crate::types::Lang;
use tree_sitter::Node;
use tree_sitter_utils::strip_semi;
use tree_sitter_utils::to_text;
use utils::indent_str;
use utils::indent_string;
use utils::WhitespaceType;

pub(crate) fn convert(input: &Input, item: &Node, is_else: bool) -> Option<String> {
    let source_bytes = input.source.as_bytes();
    match input.action {
        Action::Ternary => {
            let is_return = item
                .child_by_field_name("consequence")
                .and_then(|node| match node.kind() {
                    "statement_block" => node.named_child(0),
                    _ => Some(node),
                })
                .is_some_and(|node| {
                    matches!(
                        node.kind(),
                        // TS
                        "return_statement" |
                        // Swift
                        "control_transfer_statement"
                    )
                });
            let condition = item
                .child_by_field_name("condition")
                .map(|node| to_text(&node, source_bytes))
                .unwrap_or_else(|| "undefined".to_string());
            let consequence = item
                .child_by_field_name("consequence")
                .and_then(|node| match node.kind() {
                    "statement_block" => to_block_text(&node, source_bytes, is_return),
                    _ => handle_return(node, is_return).map(|node| to_text(&node, source_bytes)),
                })
                .unwrap_or_else(|| "undefined".to_string());
            let alternative = item
                .child_by_field_name("alternative")
                .and_then(|node| match node.kind() {
                    "else_clause" => node.named_child(0),
                    _ => None,
                })
                .and_then(|node| match node.kind() {
                    "statement_block" => to_block_text(&node, source_bytes, is_return),
                    "if_statement" => convert(input, &node, true),
                    _ => handle_return(node, is_return).map(|node| to_text(&node, source_bytes)),
                })
                .unwrap_or_else(|| "undefined".to_string());
            let return_prefix = if is_return && !is_else { "return " } else { "" };
            Some(format!(
                "{}{} ? {} : {}",
                return_prefix, condition, consequence, alternative,
            ))
        }
        Action::Condition => {
            let is_return = item.kind() == "return_statement";
            let node = if is_return {
                &item.named_child(0).unwrap()
            } else {
                item
            };
            let condition = node
                .child_by_field_name("condition")
                .map(|node| {
                    let text = to_text(&node, source_bytes);
                    match node.kind() {
                        "parenthesized_expression" => text,
                        _ => format!("({})", text),
                    }
                })
                .unwrap_or_else(|| "undefined".to_string());
            let consequence = node
                .child_by_field_name("consequence")
                .map(|node| to_text(&node, source_bytes))
                .unwrap_or_else(|| "undefined".to_string());
            let alternative = node
                .child_by_field_name("alternative")
                .and_then(|node| match node.kind() {
                    "ternary_expression" => convert(input, &node, true),
                    // I think this is syntactically correct to not have the block, but add the
                    // block for consistency
                    _ => Some(format!(
                        "{{\n    return {};\n}}",
                        to_text(&node, source_bytes)
                    )),
                })
                .unwrap_or_else(|| "undefined".to_string());
            if is_return || is_else {
                Some(format!(
                    "if {} {{\n    return {};\n}} else {}",
                    condition, consequence, alternative,
                ))
            } else {
                Some(format!(
                    "if {} {{\n{}\n}} else {{\n{}\n}}",
                    condition,
                    indent_string(consequence, 1),
                    indent_string(alternative, 1),
                ))
            }
        }
        Action::ResolveTrue => {
            let node = item;
            let consequence = get_child_resolve_true_text(input, node, source_bytes);
            Some(consequence)
        }
        Action::ResolveFalse => {
            let node = item;
            let alternative = get_child_resolve_false_text(input, node, source_bytes);
            Some(alternative)
        }
    }
}

fn get_child_resolve_true_text(input: &Input, node: &Node, source_bytes: &[u8]) -> String {
    match input.lang {
        Lang::TypeScript => get_ts_child_text("consequence", node, source_bytes)
            .unwrap_or_else(|| "undefined".to_string()),
        Lang::Rust => {
            get_rust_child_text("consequence", node, source_bytes).unwrap_or_else(|| "".to_string())
        }
        Lang::Swift => get_swift_child_text("consequence", node, source_bytes)
            .unwrap_or_else(|| "".to_string()),
        Lang::Scala => get_scala_child_text("consequence", node, source_bytes)
            .unwrap_or_else(|| "".to_string()),
        Lang::Go => {
            get_go_child_text("consequence", node, source_bytes).unwrap_or_else(|| "".to_string())
        }
    }
}
fn get_child_resolve_false_text(input: &Input, node: &Node, source_bytes: &[u8]) -> String {
    match input.lang {
        Lang::TypeScript => get_ts_child_text("alternative", node, source_bytes)
            .unwrap_or_else(|| "undefined".to_string()),
        Lang::Rust => get_rust_child_text("alternative", node, source_bytes)
            .unwrap_or_else(|| "undefined".to_string()),
        Lang::Swift => get_swift_child_text("alternative", node, source_bytes)
            .unwrap_or_else(|| "undefined".to_string()),
        Lang::Scala => get_scala_child_text("alternative", node, source_bytes)
            .unwrap_or_else(|| "undefined".to_string()),
        Lang::Go => get_go_child_text("alternative", node, source_bytes)
            .unwrap_or_else(|| "undefined".to_string()),
    }
}
#[macro_export]
macro_rules! fn_child_text {
    ($name:ident, $($else_kind:literal)|+, $($block_kind:literal)|+ ) => {
        fn $name(
            name: &str,
            node: &Node,
            source_bytes: &[u8],
        ) -> Option<String> {
            node.child_by_field_name(name)
                .and_then(|node| {
                    let (count, is_tabs) = count_spaces_from_newline(&node, source_bytes);
                    let whitespace_type = match is_tabs {
                        true => WhitespaceType::Tabs,
                        false => WhitespaceType::Spaces,
                    };
                    Some(node)
                        // and_then + map for (else_clause (statement_block (item))
                        .and_then(|node| match node.kind() {
                            $($else_kind)|+ => node.named_child(0),
                            _ => Some(node),
                        })
                        .map(|node| match node.kind() {
                            $($block_kind)|+ => node.named_children(&mut node.walk()).collect(),
                            _ => vec![node],
                        })
                        .map(|nodes| nodes.iter()
                            .enumerate()
                            .map(|(i, node)| {
                                let text = to_text(node, source_bytes);
                                if i == 0 {
                                    text // no indent for the first one
                                } else {
                                    indent_str(text, count, &whitespace_type)
                                }
                            })
                            .collect::<Vec<String>>().join("\n"))
                })
        }
    };
}
fn_child_text!(get_ts_child_text, "else_clause", "statement_block");
fn_child_text!(get_rust_child_text, "else_clause", "block");
fn_child_text!(get_swift_child_text, "else_clause", "block");
fn_child_text!(get_scala_child_text, "N/A", "block");
fn_child_text!(get_go_child_text, "N/A", "block");

fn count_spaces_from_newline(node: &Node, source_bytes: &[u8]) -> (usize, bool) {
    let mut pos = node.start_byte();
    let mut count_spaces = 0;
    let mut count_tabs = 0;
    while pos > 0 {
        pos -= 1;
        match source_bytes[pos] {
            b' ' => {
                count_spaces += 1;
                continue;
            }
            b'\t' => {
                count_tabs += 1;
                continue;
            }
            b'\n' => {
                if count_tabs > 0 {
                    return (count_tabs, true);
                } else {
                    return (count_spaces, false);
                }
            }
            _ => {
                count_tabs = 0;
                count_spaces = 0;
            }
        }
    }
    (0, false)
}

fn to_block_text(node: &Node, source_bytes: &[u8], skip_return: bool) -> Option<String> {
    if node.named_children(&mut node.walk()).count() > 1 {
        Some(format!("(() => {})()", to_text(&node, source_bytes)))
    } else {
        node.named_child(0)
            .and_then(|node| handle_return(node, skip_return))
            .map(|node| strip_semi(to_text(&node, source_bytes)))
    }
}

fn handle_return<'a>(node: Node<'a>, skip_return: bool) -> Option<Node<'a>> {
    if node.kind() == "return_statement" && skip_return {
        node.named_child(0)
    } else {
        Some(node)
    }
}
