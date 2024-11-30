use tree_sitter::Node;
use tree_sitter::TreeCursor;

pub enum TraverseAction {
    Continue,
    Next,
    Exit,
}
pub fn traverse_with_cursor(
    cursor: &mut TreeCursor,
    on_node: &impl Fn(Node) -> TraverseAction,
) -> bool {
    let node = cursor.node();
    let action = if node.is_named() {
        on_node(node)
    } else {
        TraverseAction::Next
    };
    match action {
        TraverseAction::Continue => {
            if cursor.goto_first_child() {
                let mut is_more = traverse_with_cursor(cursor, on_node);
                if is_more && cursor.goto_next_sibling() {
                    is_more = traverse_with_cursor(cursor, on_node);
                }
                cursor.goto_parent();
                is_more
            } else if cursor.goto_next_sibling() {
                traverse_with_cursor(cursor, on_node)
            } else {
                true
            }
        }
        TraverseAction::Next => {
            if cursor.goto_next_sibling() {
                traverse_with_cursor(cursor, on_node)
            } else {
                true
            }
        }
        TraverseAction::Exit => false,
    }
}
