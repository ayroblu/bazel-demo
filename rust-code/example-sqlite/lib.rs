pub mod db;
pub mod types;

pub use db::*;
pub use types::*;

pub fn get_saved() -> Option<Vec<String>> {
    Some(vec!["first".to_string()])
}
