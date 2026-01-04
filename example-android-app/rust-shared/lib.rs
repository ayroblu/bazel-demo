extern crate bindings_lib;
extern crate example_lib;
extern crate http_shared_lib;
extern crate jotai_logs_lib;

uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn dummy() {}
