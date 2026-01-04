mod effect;
pub use effect::*;

#[cfg(not(target_os = "android"))]
pub mod log;
#[cfg(not(target_os = "android"))]
pub use log::*;

#[cfg(target_os = "android")]
pub mod android;
#[cfg(target_os = "android")]
pub use android::*;
