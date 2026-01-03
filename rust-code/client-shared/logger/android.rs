use crate::run_effects;
use std::ffi::CString;
use std::time::SystemTime;

#[macro_export]
macro_rules! log {
    ($($arg:tt)*) => {
        $crate::android::log_info(&format!($($arg)*));
    };
}

#[macro_export]
macro_rules! elog {
    ($($arg:tt)*) => {
        $crate::android::log_error(&format!($($arg)*));
    };
}

#[derive(Copy, Clone)]
#[repr(i32)]
pub enum LogLevel {
    // Verbose = 2,
    // Debug = 3,
    Info = 4,
    // Warn = 5,
    Error = 6,
    // Fatal = 7,
}
impl std::fmt::Display for LogLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            Self::Info => "I",
            Self::Error => "E",
        };
        write!(f, "{}", s)
    }
}

unsafe extern "C" {
    fn __android_log_print(prio: i32, tag: *const i8, fmt: *const i8, ...) -> i32;
    // fn getpid() -> i32;
}

pub fn log_info(message: &str) {
    log(LogLevel::Info, message);
}

pub fn log_error(message: &str) {
    log(LogLevel::Error, message);
}

fn log(level: LogLevel, message: &str) {
    log_android(&level, message);
    run_effects(SystemTime::now(), &level.to_string(), message);
}
fn log_android(level: &LogLevel, message: &str) {
    // TODO: maybe inject tag or something
    let tag = CString::new("BazelRust").unwrap();
    let fmt = CString::new("%s").unwrap();
    let msg = CString::new(message).unwrap();

    unsafe {
        __android_log_print(
            *level as i32,
            tag.as_ptr() as *const i8,
            fmt.as_ptr() as *const i8,
            msg.as_ptr() as *const i8,
        );
    }
}

// pub struct SingleLog {
//     last_id: Option<i64>,
// }
// impl SingleLog {
//     pub fn new() -> Self {
//         Self { last_id: None }
//     }
//     pub fn log(&mut self, message: &str) {
//         let level = LogLevel::Info;
//         let key = &level.to_string();
//         let now = SystemTime::now();
//         log_android(level, message);
//         let last_id = insert_log(key, message, now);
//         self.last_id.map(|id| delete_log_by_id(id));
//         self.last_id = last_id.ok().and_then(|v| v);
//     }
//     pub fn elog(&mut self, message: &str) {
//         let level = LogLevel::Error;
//         let key = &level.to_string();
//         let now = SystemTime::now();
//         log_android(level, message);
//         let last_id = insert_log(key, message, now);
//         self.last_id.map(|id| delete_log_by_id(id));
//         self.last_id = last_id.ok().and_then(|v| v);
//     }
// }
