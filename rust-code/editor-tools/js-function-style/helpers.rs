use crate::types::Input;
use tree_sitter::Node;

pub(crate) fn to_text(node: &Node, source_bytes: &[u8]) -> String {
    node.utf8_text(source_bytes)
        .map_or_else(|s| s.to_string(), |s| s.to_string())
}

pub(crate) fn replace(input: &Input, node: &Node, text: String) -> String {
    let mut source = input.source.clone();
    source.replace_range(node.start_byte()..node.end_byte(), &text);
    source
}