use serde::{Deserialize, Serialize};
use tree_sitter::Node;

#[derive(Serialize, Deserialize)]
pub struct Input {
    pub source: String,
    pub line: usize,
    pub column: usize,
    pub action: ConvertAction,
}
#[derive(Serialize, Deserialize)]
pub enum ConvertAction {
    Function,
    ArrowBlock,
    ArrowInline,
}

#[derive(Debug, Clone)]
pub(crate) enum FunctionKind {
    Function,    // function f() {}
    ArrowBlock,  // const f = () => {}
    ArrowInline, // const f = () => body
    Method,      // { f(){} }
    Property,    // { f: () => {} }
}
#[derive(Debug, Clone)]
pub(crate) struct Function<'a> {
    pub(crate) name: Option<String>,
    pub(crate) node: Node<'a>,
    pub(crate) kind: FunctionKind,
    pub(crate) body: Option<Node<'a>>,
    pub(crate) params: Option<Node<'a>>,
    pub(crate) return_type: Option<Node<'a>>,
}
