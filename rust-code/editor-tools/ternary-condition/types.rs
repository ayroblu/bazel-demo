use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct Input {
    pub source: String,
    pub line: usize,
    pub column: usize,
    pub lang: Lang,
    pub action: Action,
}
#[derive(Serialize, Deserialize)]
pub enum Action {
    Ternary,
    Condition,
}
#[derive(Serialize, Deserialize)]
pub enum Lang {
    TypeScript,
}
