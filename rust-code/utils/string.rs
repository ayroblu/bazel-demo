pub fn indent_string(s: String, indent_level: usize) -> String {
    let indent = " ".repeat(4).repeat(indent_level);
    s.lines()
        .map(|line| format!("{}{}", indent, line))
        .collect::<Vec<String>>()
        .join("\n")
}
pub fn indent_str(s: String, count: usize, whitespace_type: &WhitespaceType) -> String {
    let indent = match whitespace_type {
        WhitespaceType::Tabs => "\t".repeat(count),
        WhitespaceType::Spaces => " ".repeat(count),
    };
    s.lines()
        .map(|line| format!("{}{}", indent, line))
        .collect::<Vec<String>>()
        .join("\n")
}
pub enum WhitespaceType {
    Tabs,
    Spaces,
}
