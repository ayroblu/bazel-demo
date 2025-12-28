use chrono::{DateTime, Local};
use log_db::delete_log_by_id;
use log_db::insert_log;
use std::time::SystemTime;

#[macro_export]
macro_rules! log {
    ($($arg:tt)*) => {
        $crate::log::log_info(
            &format!("{}:{} - {}", module_path!(), line!(), format_args!($($arg)*))
        )
    };
}
#[macro_export]
macro_rules! elog {
    ($($arg:tt)*) => {
        $crate::log::log_error(
            &format!("{}:{} - {}", module_path!(), line!(), format_args!($($arg)*))
        )
    };
}

pub fn log_info(message: &str) {
    let key = "I";
    let now = SystemTime::now();
    let now_str = DateTime::<Local>::from(now).format("%T%.3f");
    println!("{} {}: {}", now_str, key, &message);
    let _ = insert_log(key, message, now);
}
pub fn log_error(message: &str) {
    let key = "E";
    let now = SystemTime::now();
    let now_str = DateTime::<Local>::from(now).format("%T%.3f");
    eprintln!("{} {}: {}", now_str, key, &message);
    let _ = insert_log(key, message, now);
}

pub struct SingleLog {
    last_id: Option<i64>,
}
impl SingleLog {
    pub fn new() -> Self {
        Self { last_id: None }
    }
    pub fn log(&mut self, message: &str) {
        let key = "I";
        let now = SystemTime::now();
        let now_str = DateTime::<Local>::from(now).format("%T%.3f");
        println!("{} {}: {}", now_str, key, &message);
        let last_id = insert_log(key, message, now);
        self.last_id.map(|id| delete_log_by_id(id));
        self.last_id = last_id.ok().and_then(|v| v);
    }
    pub fn elog(&mut self, message: &str) {
        let key = "E";
        let now = SystemTime::now();
        let now_str = DateTime::<Local>::from(now).format("%T%.3f");
        eprintln!("{} {}: {}", now_str, key, &message);
        let last_id = insert_log(key, message, now);
        self.last_id.map(|id| delete_log_by_id(id));
        self.last_id = last_id.ok().and_then(|v| v);
    }
}
