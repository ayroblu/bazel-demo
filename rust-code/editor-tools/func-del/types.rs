use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct Input {
    pub source: String,
    pub line: usize,
    pub column: usize,
    pub action: Action,
}
#[derive(Serialize, Deserialize)]
pub enum Action {
    FuncDel,
}
