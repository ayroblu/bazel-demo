extern crate serde;

use crate::helpers::to_text;
use crate::types::ConvertAction;
use crate::types::Function;
use crate::types::Input;
use utils::indent_string;

pub(crate) fn convert(input: &Input, item: &Function) -> Option<String> {
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
                "function {}{}{} {}",
                item.name
                    .as_ref()
                    .map_or_else(|| "".to_string(), |name| name.clone()),
                item.params
                    .map_or_else(|| "()".to_string(), |node| to_text(&node, source_bytes)),
                item.return_type
                    .map_or_else(|| "".to_string(), |node| to_text(&node, source_bytes)),
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
            let params = item
                .params
                .map_or_else(|| "()".to_string(), |node| to_text(&node, source_bytes));
            let return_type = item
                .return_type
                .map_or_else(|| "".to_string(), |node| to_text(&node, source_bytes));
            Some(item.name.as_ref().map_or_else(
                || format!("{}{} => {}", params, return_type, body_text),
                |name| {
                    format!(
                        "const {} = {}{} => {}",
                        name, params, return_type, body_text
                    )
                },
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
            let params = item
                .params
                .map_or_else(|| "()".to_string(), |node| to_text(&node, source_bytes));
            let return_type = item
                .return_type
                .map_or_else(|| "".to_string(), |node| to_text(&node, source_bytes));
            Some(item.name.as_ref().map_or_else(
                || format!("{}{} => {}", params, return_type, body_text),
                |name| {
                    format!(
                        "const {} = {}{} => {}",
                        name, params, return_type, body_text
                    )
                },
            ))
        }
    }
}
