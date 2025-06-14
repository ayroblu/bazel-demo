use crate::types::Action;
use tree_sitter::Node;
use tree_sitter_utils::fn_get_ancestor_node;

pub(crate) fn get_node<'a>(node: Node<'a>, action: &'a Action) -> Option<Node<'a>> {
    match action {
        Action::Ternary => get_if_statement(node),
        Action::Condition => get_ternary_expression(node).and_then(|node| {
            let parent = node.parent();
            if parent.is_some_and(|node| {
                matches!(
                    node.kind(),
                    // TS
                    "return_statement" |
                    // Swift
                    "control_transfer_statement"
                )
            }) {
                parent
            } else {
                Some(node)
            }
        }),
        Action::Resolve => get_condition(node),
    }
}

fn_get_ancestor_node!(get_if_statement, if_statement);
fn_get_ancestor_node!(get_ternary_expression, ternary_expression);
fn_get_ancestor_node!(get_condition, if_statement, ternary_expression);
