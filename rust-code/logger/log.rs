use chrono::Local;

#[macro_export]
macro_rules! log {
    ($($arg:tt)*) => {
        $crate::log::log_info(
            format!("{}:{}: {}", module_path!(), line!(), format_args!($($arg)*))
        )
    };
}
#[macro_export]
macro_rules! elog {
    ($($arg:tt)*) => {
        $crate::log::log_error(format!($($arg)*));
    };
}

pub fn log_info(message: String) {
    println!("{} I: {}", Local::now().format("%T%.3f"), message);
}
pub fn log_error(message: String) {
    eprintln!("{} E: {}", Local::now().format("%T%.3f"), message);
}
