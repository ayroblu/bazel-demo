pub fn indent_string(s: String, indent_level: usize) -> String {
    let indent = "    ".repeat(indent_level);
    s.lines()
        .map(|line| format!("{}{}", indent, line))
        .collect::<Vec<String>>()
        .join("\n")
}
