use crate::types::MoveAction;
use tree_sitter::Node;

const DELIMITERS: [&str; 3] = [",", "||", "&&"];
pub(crate) fn get_node<'a>(
    node: &Node<'a>,
    action: &MoveAction,
) -> Option<Option<(Node<'a>, Node<'a>)>> {
    if node
        .prev_sibling()
        .is_some_and(|node| DELIMITERS.contains(&node.kind()))
        || node
            .next_sibling()
            .is_some_and(|node| DELIMITERS.contains(&node.kind()))
    {
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
    } else {
        None
    }
}
