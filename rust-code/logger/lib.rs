#[cfg(not(target_os = "android"))]
pub mod log;

#[cfg(target_os = "android")]
pub mod android;
