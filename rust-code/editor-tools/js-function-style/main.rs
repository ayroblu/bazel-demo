use tree_sitter::Parser;
use tree_sitter_typescript;

fn main() {
    // Take in a json object via stdin
    // Parse, and query at cursor position
    parse(Input {
        source: EXAMPLE.to_string(),
        line: 2,
        column: 5,
    });
}

const EXAMPLE: &str = "
function a() {
    console.log('a');
}
const b = () => {
    console.log('b');
}
const c = () => console.log('c')
";
struct Input {
    source: String,
    line: i32,
    column: i32,
}
fn parse(input: Input) {
    let mut parser = Parser::new();
    parser
        .set_language(&tree_sitter_typescript::LANGUAGE_TSX.into())
        .expect("Error loading Rust grammar");
    let tree = parser.parse(&input.source, None).unwrap();
    let root_node = tree.root_node();
    println!("{}", root_node.to_sexp());
}
