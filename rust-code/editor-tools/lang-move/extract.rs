use crate::types::MoveAction;
use tree_sitter::Node;

pub(crate) fn get_node<'a>(
    node: &Node<'a>,
    action: &MoveAction,
) -> Option<Option<(Node<'a>, Node<'a>)>> {
    match action {
        MoveAction::Prev => node
            .prev_named_sibling()
            .map(|prev| Some((*node, prev)))
            .or_else(|| node.next_named_sibling().map(|_| None)),
        MoveAction::Next => node
            .next_named_sibling()
            .map(|next| Some((*node, next)))
            .or_else(|| node.prev_named_sibling().map(|_| None)),
    }
}
