use std::ffi::CString;

#[macro_export]
macro_rules! log {
    ($($arg:tt)*) => {
        $crate::android::log_info(format!($($arg)*));
    };
}

#[macro_export]
macro_rules! elog {
    ($($arg:tt)*) => {
        $crate::android::log_error(format!($($arg)*));
    };
}

#[repr(i32)]
pub enum LogLevel {
    // Verbose = 2,
    // Debug = 3,
    Info = 4,
    // Warn = 5,
    Error = 6,
    // Fatal = 7,
}

unsafe extern "C" {
    fn __android_log_print(prio: i32, tag: *const i8, fmt: *const i8, ...) -> i32;
    // fn getpid() -> i32;
}

pub fn log_info(message: String) {
    log(LogLevel::Info, message);
}

pub fn log_error(message: String) {
    log(LogLevel::Error, message);
}

fn log(level: LogLevel, message: String) {
    // TODO: maybe inject tag or something
    let tag = CString::new("BazelRust").unwrap();
    let fmt = CString::new("%s").unwrap();
    let msg = CString::new(message).unwrap();

    unsafe {
        __android_log_print(
            level as i32,
            tag.as_ptr() as *const i8,
            fmt.as_ptr() as *const i8,
            msg.as_ptr() as *const i8,
        );
    }
}
