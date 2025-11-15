use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct Input {
    pub source: String,
    pub line: usize,
    pub column: usize,
    pub lang: Lang,
    pub action: MoveAction,
}
#[derive(Serialize, Deserialize)]
pub enum MoveAction {
    Prev,
    Next,
}
#[derive(Serialize, Deserialize)]
pub enum Lang {
    Go,
    Python,
    Rust,
    Scala,
    Swift,
    TypeScript,
}
