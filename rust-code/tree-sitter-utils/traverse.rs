use tree_sitter::Node;
use tree_sitter::TreeCursor;

pub fn traverse_with_cursor<'a>(
    cursor: &mut TreeCursor<'a>,
    vec: &mut Vec<Node<'a>>,
    line: usize,
    column: usize,
) -> bool {
    let node = cursor.node();
    let (action, value) = if node.is_named() {
        on_node(&node, line, column)
    } else {
        (TraverseAction::Next, None)
    };
    if let Some(value) = value {
        vec.push(value);
    }
    match action {
        TraverseAction::Continue => {
            if cursor.goto_first_child() {
                let mut is_more = traverse_with_cursor(cursor, vec, line, column);
                if is_more && cursor.goto_next_sibling() {
                    is_more = traverse_with_cursor(cursor, vec, line, column);
                }
                cursor.goto_parent();
                is_more
            } else if cursor.goto_next_sibling() {
                traverse_with_cursor(cursor, vec, line, column)
            } else {
                true
            }
        }
        TraverseAction::Next => {
            if cursor.goto_next_sibling() {
                traverse_with_cursor(cursor, vec, line, column)
            } else {
                true
            }
        }
        TraverseAction::Exit => false,
    }
}

fn on_node<'a>(node: &Node<'a>, line: usize, column: usize) -> (TraverseAction, Option<Node<'a>>) {
    let sr = node.start_position().row;
    let sc = node.start_position().column;
    let er = node.end_position().row;
    let ec = node.end_position().column;

    // let node_text = to_text(&node, source_bytes);
    // println!("- {} =\n{}", node.to_sexp(), indent_string(node_text, 1));

    let is_before = sr < line || (sr == line && sc <= column);
    let is_after = (er > line) || (er == line && ec >= column);
    if is_before && is_after {
        (TraverseAction::Continue, Some(*node))
    } else if is_before {
        (TraverseAction::Next, None)
    } else {
        (TraverseAction::Exit, None)
    }
}

pub enum TraverseAction {
    Continue,
    Next,
    Exit,
}
