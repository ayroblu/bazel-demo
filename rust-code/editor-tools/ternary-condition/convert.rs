extern crate serde;

use crate::types::Action;
use crate::types::Input;
use tree_sitter::Node;
use tree_sitter_utils::strip_semi;
use tree_sitter_utils::to_text;
use utils::indent_string;

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
        Action::Resolve => None,
    }
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
