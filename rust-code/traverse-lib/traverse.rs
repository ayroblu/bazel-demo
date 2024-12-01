use tree_sitter::Node;
use tree_sitter::TreeCursor;

pub enum TraverseAction {
    Continue,
    Next,
    Exit,
}
// pub fn traverse_with_cursor<'a, F, T>(
//     cursor: &mut TreeCursor<'a>,
//     vec: &mut Vec<T>,
//     on_node: &F,
// ) -> bool
// where
//     F: Fn(Node<'a>) -> (TraverseAction, Option<T>),
// {
pub fn traverse_with_cursor<T>(
    cursor: &mut TreeCursor,
    vec: &mut Vec<T>,
    on_node: &impl Fn(Node) -> (TraverseAction, Option<T>),
) -> bool {
    let node = cursor.node();
    let (action, value) = if node.is_named() {
        on_node(node)
    } else {
        (TraverseAction::Next, None)
    };
    if let Some(value) = value {
        vec.push(value);
    }
    match action {
        TraverseAction::Continue => {
            if cursor.goto_first_child() {
                let mut is_more = traverse_with_cursor(cursor, vec, on_node);
                if is_more && cursor.goto_next_sibling() {
                    is_more = traverse_with_cursor(cursor, vec, on_node);
                }
                cursor.goto_parent();
                is_more
            } else if cursor.goto_next_sibling() {
                traverse_with_cursor(cursor, vec, on_node)
            } else {
                true
            }
        }
        TraverseAction::Next => {
            if cursor.goto_next_sibling() {
                traverse_with_cursor(cursor, vec, on_node)
            } else {
                true
            }
        }
        TraverseAction::Exit => false,
    }
}
