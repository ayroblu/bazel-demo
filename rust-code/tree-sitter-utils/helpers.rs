use std::ops::Range;

use tree_sitter::Node;

pub fn to_text(node: &Node, source_bytes: &[u8]) -> String {
    node.utf8_text(source_bytes)
        .map_or_else(|s| s.to_string(), |s| s.to_string())
}

pub fn replace(source_in: &String, node: &Node, text: String) -> String {
    let mut source = source_in.clone();
    source.replace_range(node.start_byte()..node.end_byte(), &text);
    source
}

pub fn swap(source_in: &String, node: &Node, next: &Node) -> String {
    let mut source = source_in.clone();
    let source_bytes = source.as_bytes();
    let node_text = to_text(node, source_bytes);
    let next_text = to_text(next, source_bytes);
    let diff: isize = if node.start_byte() < next.start_byte() {
        node_text.len() as isize - next_text.len() as isize
    } else {
        0
    };
    source.replace_range(node.start_byte()..node.end_byte(), &next_text);
    let range: Range<usize> = ((next.start_byte() as isize - diff) as usize)
        ..((next.end_byte() as isize - diff) as usize);
    source.replace_range(range, &node_text);
    source
}

pub fn strip_semi(text: String) -> String {
    if text.ends_with(";") {
        text[..text.len() - 1].to_string()
    } else {
        text
    }
}

#[macro_export]
macro_rules! fn_get_ancestor_node {
    ($name:ident, $($kind:ident),+ ) => {
        fn $name(node: Node) -> Option<Node> {
            if matches!(node.kind(), $(stringify!($kind))|+) {
                return Some(node);
            }
            return node.parent().and_then($name);
        }
    };
}
